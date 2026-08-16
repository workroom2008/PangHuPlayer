import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../services/danmaku_service.dart';
import '../../theme/app_theme.dart';
import 'danmaku_models.dart';

import '../../utils/app_log.dart';
/// 弹幕控制器
///
/// 类似 AkDanmaku 的 DanmakuPlayer，负责弹幕的激活、轨道分配、滚动位移、
/// 过期回收等核心逻辑，与 UI 解耦。PlayerScreen 只需在合适时机调用
/// init / setData / start / pause / seekTo / updateActive / updateConfig 等接口。
///
/// 通过 [TickerProvider]（通常是 TickerProviderStateMixin）驱动逐帧更新，
/// 内部维护对象池与扫描游标以降低分配开销。
class DanmakuController {
  DanmakuController(this._tickerProvider);

  final TickerProvider _tickerProvider;

  // ===== 弹幕数据与活动状态 =====
  List<Danmaku> _danmakuList = [];
  final List<ActiveDanmaku> _activeDanmaku = [];
  final List<ActiveDanmaku> _danmakuPool = []; // 对象池
  final Map<String, ActiveDanmaku> _trackLastDanmaku = {}; // 每条轨道末尾弹幕（key: "type_trackIdx"）
  final Set<String> _activeDanmakuIds = {}; // 已激活弹幕 ID 集合，O(1) 查找
  // DanmakuFlameMaster 式文本缓存：相同 text+字号+粗体+颜色 共享已 layout 的
  // TextPainter（layout 是最大开销，密集弹幕时避免对重复文本反复测量）
  final Map<String, TextPainter> _textCache = {};
  static const int _textCacheMax = 300;
  // 活动弹幕文本集合（mergeDuplicates 用 O(1) 判重，替代逐条 any 扫描）
  final Set<String> _activeTexts = {};
  // 是否存在移动中的滚动弹幕（全是顶部/底部静态弹幕时跳过逐帧重绘，降功耗）
  bool _hasMovingDanmaku = false;

  // ── 弹幕热力图：弹幕密度分桶缓存（DanmakuFlameMaster 分桶思想）──
  // setData 时一次性预计算归一化密度数组，渲染时 O(1) 查桶，绝不逐帧重算
  static const int _heatmapBucketMs = 10000; // 每桶 10 秒
  List<double> _heatmapDensity = const [];
  int _danmakuScanIndex = 0; // _danmakuList 扫描游标（前提：列表按 time 升序）

  int _frameCount = 0;
  int _tickCount = 0;
  int _timeoutDroppedCount = 0;  // 超时丢弃计数
  int _totalActivatedCount = 0;  // 总激活计数
  // ===== 渲染配置 =====
  DanmakuRenderConfig _config = DanmakuRenderConfig.defaults();
  double _screenWidth = 0;
  double _screenHeight = 0;
  Ticker? _ticker;
  final ValueNotifier<int> _tickNotifier = ValueNotifier<int>(0);

  // ===== 运行时状态 =====
  int _lastDanmakuUpdateMs = 0;
  int _currentMs = 0;
  int _lastElapsedMs = 0;  // Ticker 上次 elapsed（ms），用于计算实际帧间隔
  int _clockScanAccumMs = 0;  // 时钟自推进后累计的扫描间隔（ms），约每 300ms 扫描一次
  bool _isPlaying = false;
  bool _isSeeking = false;
  bool _enabled = true;
  // 样式变化检测（避免每帧重建 TextPainter）
  double _lastAppliedFontSizeScale = 1.0;
  double _lastAppliedOpacity = 1.0;
  bool _lastAppliedBold = false;

  // ===== 对外暴露的接口 =====

  /// 帧通知，UI 通过 ValueListenableBuilder 监听后重建 DanmakuRenderer
  ValueListenable<int> get tickNotifier => _tickNotifier;

  /// 当前活动弹幕列表（只读视图）
  List<ActiveDanmaku> get activeDanmaku => _activeDanmaku;

  /// 是否有活动弹幕（UI 据此决定是否渲染弹幕层）
  bool get hasActiveDanmaku => _activeDanmaku.isNotEmpty;

  /// 点击命中检测：返回点击位置（逻辑坐标）处可见的最近一条弹幕
  /// 位置公式与 DanmakuPainter 保持一致，避免「点得到处不是这条」的偏差
  ActiveDanmaku? hitTest(double x, double y) {
    final w = _screenWidth;
    final h = _screenHeight;
    if (w <= 0 || h <= 0) return null;
    final area = _config.displayArea.clamp(0.5, 1.0);
    final areaBottom = h * area;
    final areaTop = h - areaBottom;
    // 从后往前：越晚发送的弹幕越靠上层
    for (final d in _activeDanmaku.reversed) {
      final trackHeight = d.fontSize * AppTheme.danmakuTrackHeightRatio;
      double left;
      double top;
      switch (d.danmaku.type) {
        case DanmakuType.top:
          left = (w - d.width) / 2;
          top = 40 + d.track * trackHeight;
          if (top + trackHeight > areaBottom) continue;
          break;
        case DanmakuType.bottom:
          left = (w - d.width) / 2;
          top = h - 40 - (d.track + 1) * trackHeight;
          if (top < areaTop || top < h * 0.5) continue;
          break;
        case DanmakuType.scroll:
          left = d.offset;
          top = 40 + d.track * trackHeight;
          if (top + trackHeight > areaBottom) continue;
          break;
      }
      if (y >= top && y < top + trackHeight && x >= left && x < left + d.width) {
        return d;
      }
    }
    return null;
  }

  /// 统计：当前活动弹幕数
  int get activeCount => _activeDanmaku.length;

  /// 统计：超时丢弃计数
  int get timeoutDroppedCount => _timeoutDroppedCount;

  /// 统计：总激活计数
  int get totalActivatedCount => _totalActivatedCount;

  /// 初始化（设置屏幕尺寸、配置，并创建 Ticker）
  void init({
    required double screenWidth,
    required double screenHeight,
    required DanmakuRenderConfig config,
  }) {
    _screenWidth = screenWidth;
    _screenHeight = screenHeight;
    _config = config;
    _lastAppliedFontSizeScale = config.fontSize / AppTheme.danmakuDefaultFontSize;
    _lastAppliedOpacity = config.opacity;
    _lastAppliedBold = config.bold;
    // 提前创建 Ticker，start() 时直接启动
    _ticker ??= _tickerProvider.createTicker((elapsed) {
      if (!_isPlaying || _isSeeking || !_enabled) return;
      final ms = elapsed.inMilliseconds;
      final deltaMs = _lastElapsedMs > 0 ? ms - _lastElapsedMs : 16;
      _lastElapsedMs = ms;
      // 弹幕时钟自推进：持续播放时按帧推进，不依赖外部位置推送（防止时钟冻结、
      // 后续弹幕永不激活）。外部 updateActive 仍是权威同步，会纠正任何漂移。
      _currentMs += (deltaMs * _config.playbackSpeed).round();
      // 周期性扫描激活新弹幕（约每 300ms 时钟；updateActive 内部还有节流兜底）
      _clockScanAccumMs += (deltaMs * _config.playbackSpeed).round();
      if (_clockScanAccumMs >= 300) {
        _clockScanAccumMs = 0;
        updateActive(_currentMs);
      }
      _tickDanmaku(deltaMs);
    });
  }

  /// 设置弹幕数据列表（已按 time 排序）
  void setData(List<Danmaku> danmakuList) {
    _danmakuList = danmakuList;
    if (danmakuList.isNotEmpty) {
      AppLog.i('Danmaku', 'setData: ${danmakuList.length}条, first.time=${danmakuList.first.time}ms, last.time=${danmakuList.last.time}ms');
    }
    clearActive();
    _danmakuScanIndex = 0;
    _lastDanmakuUpdateMs = 0; // 重置节流，setData后立即允许updateActive
    _lastElapsedMs = 0; // 重置帧时间基准
    // 弹幕数据变化 → 重建热力分桶缓存（O(n) 一次，后续只读）
    _buildHeatmap();
  }

  // ===== 弹幕热力图（密度分桶缓存） =====

  /// 热力图密度数组（已归一化 0~1，按桶索引；桶宽 [heatmapBucketWidthMs]）
  List<double> get heatmapDensity => _heatmapDensity;

  /// 热力图桶宽（毫秒）
  int get heatmapBucketWidthMs => _heatmapBucketMs;

  /// O(1) 查询某时刻弹幕密度（0~1），无数据返回 0
  double heatmapDensityAt(int positionMs) {
    if (_heatmapDensity.isEmpty) return 0;
    final idx = positionMs ~/ _heatmapBucketMs;
    if (idx < 0 || idx >= _heatmapDensity.length) return 0;
    return _heatmapDensity[idx];
  }

  /// 预计算热力分桶：遍历弹幕列表统计每桶条数并归一化（O(n)，仅在 setData 时执行一次）
  void _buildHeatmap() {
    if (_danmakuList.isEmpty) {
      _heatmapDensity = const [];
      return;
    }
    final bucketCount = (_danmakuList.last.time ~/ _heatmapBucketMs) + 1;
    final counts = List<int>.filled(bucketCount, 0);
    var maxCount = 0;
    for (final d in _danmakuList) {
      final idx = d.time ~/ _heatmapBucketMs;
      if (idx >= 0 && idx < bucketCount) {
        counts[idx]++;
        if (counts[idx] > maxCount) maxCount = counts[idx];
      }
    }
    if (maxCount <= 0) {
      _heatmapDensity = const [];
      return;
    }
    // 归一化缓存：渲染侧只查表，永不在帧循环里重算
    _heatmapDensity = List<double>.generate(
      bucketCount,
      (i) => (counts[i] / maxCount).clamp(0.0, 1.0),
    );
  }

  /// 开始播放（启动 Ticker）
  void start() {
    _isPlaying = true;
    _lastElapsedMs = 0; // 重置帧时间基准
    _ticker ??= _tickerProvider.createTicker((elapsed) {
      if (!_isPlaying || _isSeeking || !_enabled) return;
      final ms = elapsed.inMilliseconds;
      final deltaMs = _lastElapsedMs > 0 ? ms - _lastElapsedMs : 16;
      _lastElapsedMs = ms;
      // 弹幕时钟自推进：持续播放时按帧推进，不依赖外部位置推送（防止时钟冻结、
      // 后续弹幕永不激活）。外部 updateActive 仍是权威同步，会纠正任何漂移。
      _currentMs += (deltaMs * _config.playbackSpeed).round();
      // 周期性扫描激活新弹幕（约每 300ms 时钟；updateActive 内部还有节流兜底）
      _clockScanAccumMs += (deltaMs * _config.playbackSpeed).round();
      if (_clockScanAccumMs >= 300) {
        _clockScanAccumMs = 0;
        updateActive(_currentMs);
      }
      _tickDanmaku(deltaMs);
    });
    _ticker!.start();
  }

  /// 暂停
  void pause() {
    _isPlaying = false;
    _ticker?.stop();
  }

  /// Seek 到指定位置（清理活动弹幕，重置游标）
  void seekTo(Duration position) {
    _currentMs = position.inMilliseconds;
    clearActive();
    _lastDanmakuUpdateMs = 0; // 重置节流，确保 seek 后立即允许 updateActive
    _lastElapsedMs = 0; // 重置帧时间基准

    // 二分查找：将游标定位到 position 附近（回看 5 秒范围内）
    // 无论前进还是后退 seek，都能正确定位，避免游标越界导致 active=0
    final targetMs = position.inMilliseconds;
    if (_danmakuList.isNotEmpty) {
      final lookbackMs = (targetMs - 5000).clamp(0, _danmakuList.last.time + 1);
      int lo = 0, hi = _danmakuList.length - 1;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (_danmakuList[mid].time < lookbackMs) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      _danmakuScanIndex = lo;
    } else {
      _danmakuScanIndex = 0;
    }

    _tickNotifier.value++;
  }

  /// 更新配置（字体大小、透明度、速度、显示开关、倍速等）
  void updateConfig(DanmakuRenderConfig config) {
    _config = config;
  }

  /// 更新屏幕尺寸
  void updateScreenSize(double width, double height) {
    _screenWidth = width;
    _screenHeight = height;
  }

  /// 发送单条弹幕（用户发送，立即加入活动列表）
  void send(Danmaku danmaku) {
    _addDanmakuToTrack(danmaku);
    _activeDanmakuIds.add(danmaku.id);
    _tickNotifier.value++;
  }

  /// 设置弹幕开关
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (_enabled && _isPlaying) {
      start();
    } else {
      _ticker?.stop();
    }
  }

  /// 设置是否正在拖拽进度条
  ///
  /// 开始拖拽时清理活动弹幕（与原实现一致），拖拽期间 Ticker 回调提前返回。
  void setSeeking(bool seeking) {
    _isSeeking = seeking;
    if (seeking) {
      clearActive();
    }
  }

  /// 更新活动弹幕（根据当前播放位置添加新弹幕到轨道）
  ///
  /// 利用 _danmakuList 已按 time 升序排列的特性，从游标处向后扫描。
  /// 节流 300ms，避免引擎频繁回调时重复扫描。
  void updateActive(int currentMs) {
    _currentMs = currentMs;
    if (_screenWidth == 0) { AppLog.w('Danmaku', 'updateActive: screenWidth=0, skip'); return; }
    if (_lastDanmakuUpdateMs > 0 && (currentMs - _lastDanmakuUpdateMs).abs() < 300) return;
    _lastDanmakuUpdateMs = currentMs;
    // 诊断日志：每 30 次打印一次
    if (_frameCount % 30 == 0) {
      AppLog.d('Danmaku', 'updateActive: ms=$currentMs, scanIdx=$_danmakuScanIndex/${_danmakuList.length}, active=${_activeDanmaku.length}, enabled=$_enabled, isPlaying=$_isPlaying, isSeeking=$_isSeeking');
    }
    _frameCount++;

    final display = _config;
    final syncOffsetMs = (display.syncDelay * 1000).round();

    // 滚动弹幕可见窗口（毫秒）：从右侧进入 → 完全离开左侧的时长
    // 用平均弹幕宽度 ~120px 估算
    final scrollVisibleMs = ((_screenWidth + 120) / (display.speed * 1000) * 1000).round();

    // 快进/快退优化：如果游标距当前位置很远，快进游标跳过已过期的弹幕
    if (_danmakuScanIndex < _danmakuList.length) {
      final gapMs = currentMs - _danmakuList[_danmakuScanIndex].time;
      if (gapMs > 10000) {
        // 快进游标：跳过所有已完全过期的弹幕
        while (_danmakuScanIndex < _danmakuList.length) {
          final d = _danmakuList[_danmakuScanIndex];
          final adjustedTime = d.time + syncOffsetMs;
          // 滚动弹幕：时间 + 可见窗口 < 当前时间 → 已过期
          // 顶部/底部弹幕：时间 + 5000 < 当前时间 → 已过期
          final expireMs = (d.type == DanmakuType.scroll)
              ? adjustedTime + scrollVisibleMs
              : adjustedTime + 5000;
          if (expireMs < currentMs) {
            _danmakuScanIndex++;
          } else {
            break;
          }
        }
        AppLog.d('Danmaku', 'seek fast-forward: scanIdx=$_danmakuScanIndex/${_danmakuList.length}');
      }
    }

    int activated = 0;
    while (_danmakuScanIndex < _danmakuList.length) {
      final danmaku = _danmakuList[_danmakuScanIndex];
      if (danmaku.time > currentMs + syncOffsetMs) break; // 后面的都还没到时间（含同步偏移）

      // 已激活则跳过
      if (_activeDanmakuIds.contains(danmaku.id)) {
        _danmakuScanIndex++;
        continue;
      }

      // 合并重复弹幕：O(1) 集合判重（DanmakuFlameMaster 同款，避免逐条 any 扫描）
      if (display.mergeDuplicates && _activeTexts.contains(danmaku.text)) {
        _danmakuScanIndex++;
        continue;
      }

      // 根据显示设置过滤弹幕类型
      if (danmaku.type == DanmakuType.top && !display.showTop) {
        _danmakuScanIndex++;
        continue;
      }
      if (danmaku.type == DanmakuType.bottom && !display.showBottom) {
        _danmakuScanIndex++;
        continue;
      }
      if (danmaku.type == DanmakuType.scroll && !display.showScroll) {
        _danmakuScanIndex++;
        continue;
      }

      // 顶部/底部弹幕：如果已超过其5秒显示窗口，跳过（避免激活即过期）
      if ((danmaku.type == DanmakuType.top || danmaku.type == DanmakuType.bottom)
          && currentMs > danmaku.time + syncOffsetMs + 5000) {
        _danmakuScanIndex++;
        continue;
      }

      // 滚动弹幕：如果已超过其可见窗口，跳过（避免 seek 后大量过期弹幕涌入）
      if (danmaku.type == DanmakuType.scroll
          && currentMs > danmaku.time + syncOffsetMs + scrollVisibleMs) {
        _danmakuScanIndex++;
        continue;
      }

      // 性能限制：活动弹幕数超过上限时停止激活（滚动弹幕）
      if (danmaku.type == DanmakuType.scroll && _activeDanmaku.length >= AppTheme.danmakuMaxActive) {
        break;
      }

      _addDanmakuToTrack(danmaku);
      _activeDanmakuIds.add(danmaku.id);
      activated++;
      _danmakuScanIndex++;
    }
    if (activated > 0) {
      AppLog.i('Danmaku', 'updateActive: 激活$activated条, currentMs=$currentMs, scanIdx=$_danmakuScanIndex/${_danmakuList.length}');
      // 激活了新弹幕时立即通知 UI 重建，不依赖 _tickDanmaku 的帧回调
      _tickNotifier.value++;
    }
  }

  /// 清理活动弹幕（保留对象池）
  void clearActive() {
    _activeDanmaku.clear();
    _trackLastDanmaku.clear();
    _activeDanmakuIds.clear();
    _activeTexts.clear();
    _hasMovingDanmaku = false;
  }

  /// 内部：Ticker 回调驱动的逐帧更新（移动、过期回收、样式同步）
  void _tickDanmaku(int deltaMs) {
    if (_screenWidth == 0 || _screenHeight == 0) {
      AppLog.w('Danmaku', '_tickDanmaku: screen=0x0, skip');
      return;
    }
    // 诊断日志：每 120 帧打印一次
    _tickCount++;
    if (_tickCount % 120 == 0) {
      AppLog.d('Danmaku', '_tickDanmaku: active=${_activeDanmaku.length}, currentMs=$_currentMs, scanIdx=$_danmakuScanIndex/${_danmakuList.length}, enabled=$_enabled, isPlaying=$_isPlaying, isSeeking=$_isSeeking');
    }
    final display = _config;
    final fontSizeScale = display.fontSize / AppTheme.danmakuDefaultFontSize;
    final opacity = display.opacity;

    // 字体大小、透明度或粗体变化时，更新已激活弹幕的样式
    final styleChanged = _lastAppliedFontSizeScale != fontSizeScale ||
        _lastAppliedOpacity != opacity ||
        _lastAppliedBold != display.bold;
    if (styleChanged) {
      _lastAppliedFontSizeScale = fontSizeScale;
      _lastAppliedOpacity = opacity;
      _lastAppliedBold = display.bold;
      // 样式变化：旧文本缓存全部失效，重建（避免共享 painter 携带旧样式）
      _textCache.clear();
      if (_activeDanmaku.isNotEmpty) {
        for (final d in _activeDanmaku) {
          final fontSize = (d.danmaku.fontSize?.toDouble() ?? AppTheme.danmakuDefaultFontSize) * fontSizeScale;
          final textColor = _parseColor(d.danmaku.color).withValues(alpha: opacity);
          d.painter = _cachedPainter(d.danmaku.text, fontSize, display.bold, textColor);
          d.fontSize = fontSize;
          d.width = d.painter.width;
          d.height = d.painter.height;
        }
      }
    }

    final currentMs = _currentMs;
    final dtMs = deltaMs.clamp(1, 50).toDouble(); // 限制 delta 范围，防止切后台回来时跳帧
    final pxPerMs = _screenWidth / (display.speed * 1000);
    final dx = pxPerMs * dtMs * display.playbackSpeed; // 倍速联动
    var removedAny = false;
    for (int i = _activeDanmaku.length - 1; i >= 0; i--) {
      final d = _activeDanmaku[i];
      // 根据显示设置过滤已激活弹幕
      if (d.danmaku.type == DanmakuType.top && !display.showTop) {
        _removeActive(i, d);
        removedAny = true;
        continue;
      }
      if (d.danmaku.type == DanmakuType.bottom && !display.showBottom) {
        _removeActive(i, d);
        removedAny = true;
        continue;
      }
      if (d.danmaku.type == DanmakuType.scroll && !display.showScroll) {
        _removeActive(i, d);
        removedAny = true;
        continue;
      }
      // 滚动弹幕：移动位置（从右向左）
      if (d.danmaku.type == DanmakuType.scroll) {
        d.offset -= dx;
        // 移出屏幕后回收
        if (d.offset < -d.width) {
          _removeActive(i, d);
          removedAny = true;
          final trackKey = 's_${d.track}';
          if (_trackLastDanmaku[trackKey] == d) {
            _trackLastDanmaku.remove(trackKey);
          }
          if (_danmakuPool.length < 200) {
            _danmakuPool.add(d);
          }
        }
      }
      // 顶部/底部弹幕：超时自动消失
      if (d.expireTimeMs > 0 && currentMs >= d.expireTimeMs) {
        _removeActive(i, d);
        removedAny = true;
        final prefix = d.danmaku.type == DanmakuType.top ? 't' : 'b';
        final expireTrackKey = '${prefix}_${d.track}';
        if (_trackLastDanmaku[expireTrackKey] == d) {
          _trackLastDanmaku.remove(expireTrackKey);
        }
        if (_danmakuPool.length < 200) {
          _danmakuPool.add(d);
        }
      }
    }
    // 智能重绘：有移动中的滚动弹幕才逐帧重绘；全是顶部/底部静态弹幕时
    // 只在激活/过期瞬间重绘（DanmakuFlameMaster 同款降功耗）
    if (_activeDanmaku.isNotEmpty && (_hasMovingDanmaku || removedAny)) {
      _tickNotifier.value++;
    }
  }

  /// 内部：将弹幕分配到轨道并加入活动列表
  void _addDanmakuToTrack(Danmaku danmaku) {
    final fontSizeScale = _config.fontSize / AppTheme.danmakuDefaultFontSize;
    final opacity = _config.opacity;
    final fontSize = (danmaku.fontSize?.toDouble() ?? AppTheme.danmakuDefaultFontSize) * fontSizeScale;
    final trackHeight = fontSize * AppTheme.danmakuTrackHeightRatio;

    // 从对象池取一个复用
    final d = _danmakuPool.isNotEmpty ? _danmakuPool.removeLast() : ActiveDanmaku.empty();

    final textColor = _parseColor(danmaku.color).withValues(alpha: opacity);
    // 共享 TextPainter：相同文本+样式复用已 layout 结果，避免重复测量
    d.painter = _cachedPainter(danmaku.text, fontSize, _config.bold, textColor);
    d
      ..danmaku = danmaku
      ..fontSize = fontSize
      ..width = d.painter.width
      ..height = d.painter.height
      ..offset = _screenWidth
      ..expireTimeMs = (danmaku.type == DanmakuType.top || danmaku.type == DanmakuType.bottom)
          ? danmaku.time + 5000 // 顶部/底部弹幕显示 5 秒后自动消失
          : 0;

    // 分配轨道
    final trackKey = _allocateTrack(d, trackHeight);
    if (trackKey == null) {
      // 无可用轨道：滚动弹幕超时 3 秒后丢弃
      if (danmaku.type == DanmakuType.scroll &&
          _activeDanmaku.length > _config.maxScrollLines * 2 &&
          _currentMs > danmaku.time + 3000) {
        _timeoutDroppedCount++;
        if (_danmakuPool.length < 200) _danmakuPool.add(d);
        return;
      }
      // 非滚动弹幕或超时未到：强制分配到备选轨道
      final prefix = _trackPrefix(danmaku.type);
      d.track = 0;
      _trackLastDanmaku['${prefix}_0'] = d;
    }
    _totalActivatedCount++;
    _activeTexts.add(danmaku.text);
    // 真正入列后再标记移动（轨道分配失败被丢弃的不会误标）
    if (danmaku.type == DanmakuType.scroll) _hasMovingDanmaku = true;
    _activeDanmaku.add(d);
  }

  /// 取（或创建）共享 TextPainter：layout 只做一次，后续同文本命中直接复用
  /// （DanmakuFlameMaster 测量缓存，layout 是弹幕渲染最大开销）
  TextPainter _cachedPainter(String text, double fontSize, bool bold, Color color) {
    final key = '${fontSize.toStringAsFixed(1)}|${bold ? 1 : 0}|${color.toARGB32().toRadixString(16)}|$text';
    final cached = _textCache[key];
    if (cached != null) return cached;
    if (_textCache.length >= _textCacheMax) _textCache.clear();
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: 0.6 * _config.opacity),
              blurRadius: AppTheme.danmakuShadowBlur,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    painter.layout();
    _textCache[key] = painter;
    return painter;
  }

  /// 移除活动弹幕并维护副作用集合（O(1) 判重集合 / 滚动标志）
  void _removeActive(int index, ActiveDanmaku d) {
    _activeDanmaku.removeAt(index);
    _activeDanmakuIds.remove(d.danmaku.id);
    _activeTexts.remove(d.danmaku.text);
    if (d.danmaku.type == DanmakuType.scroll && _hasMovingDanmaku) {
      // 最后一条滚动弹幕被回收时重扫确认（避免误留 true 导致空转重绘）
      var anyScroll = false;
      for (final a in _activeDanmaku) {
        if (a.danmaku.type == DanmakuType.scroll) {
          anyScroll = true;
          break;
        }
      }
      _hasMovingDanmaku = anyScroll;
    }
  }

  /// 轨道前缀（用于分离不同类型的轨道编号）
  String _trackPrefix(DanmakuType type) {
    switch (type) {
      case DanmakuType.scroll: return 's';
      case DanmakuType.top: return 't';
      case DanmakuType.bottom: return 'b';
    }
  }

  /// 内部：为弹幕分配轨道（返回轨道键，null 表示无可用轨道）
  ///
  /// 按弹幕类型使用独立的最大行数限制：
  /// - 滚动弹幕: maxScrollLines
  /// - 顶部弹幕: maxTopLines
  /// - 底部弹幕: maxBottomLines
  ///
  /// 碰撞检测（preventOverlap=true）：
  /// 滚动弹幕要求前一条完全进入屏幕 + 基于速度的安全间距后才分配同轨道。
  ///
  /// 超时丢弃：滚动弹幕等待超 3 秒仍无轨道则由调用方丢弃。
  String? _allocateTrack(ActiveDanmaku d, double trackHeight) {
    final danmaku = d.danmaku;
    final maxLines = (_screenHeight * 0.5 / trackHeight).floor();
    final prefix = _trackPrefix(danmaku.type);

    int typeMaxLines;
    switch (danmaku.type) {
      case DanmakuType.scroll:
        typeMaxLines = maxLines.clamp(1, _config.maxScrollLines);
        break;
      case DanmakuType.top:
        typeMaxLines = maxLines.clamp(1, _config.maxTopLines);
        break;
      case DanmakuType.bottom:
        typeMaxLines = maxLines.clamp(1, _config.maxBottomLines);
        break;
    }

    // 滚动弹幕的安全入口间距（基于速度：速度越快需要越大间距）
    final safeEntryMargin = danmaku.type == DanmakuType.scroll
        ? (_screenWidth / (_config.speed * 1000) * 300).clamp(d.width * 0.3, d.width * 0.8)
        : 0.0;

    // 轨道查找：优先空闲轨道，其次可复用轨道
    int? fallbackTrack;
    double minOffset = double.infinity;

    for (int i = 0; i < typeMaxLines; i++) {
      final key = '${prefix}_$i';
      final prev = _trackLastDanmaku[key];
      if (prev == null) {
        d.track = i;
        _trackLastDanmaku[key] = d;
        return key;
      }

      if (danmaku.type == DanmakuType.scroll) {
        if (_config.preventOverlap) {
          // 碰撞检测：前一条完全进入屏幕 + 安全间距
          if (prev.offset + prev.width + safeEntryMargin <= _screenWidth) {
            d.track = i;
            _trackLastDanmaku[key] = d;
            return key;
          }
        } else {
          // 无碰撞检测：前一条离开入口即可
          if (prev.offset < _screenWidth - d.width) {
            d.track = i;
            _trackLastDanmaku[key] = d;
            return key;
          }
        }
      } else {
        // 顶部/底部弹幕：前一条仍在显示中则占用
        if (_currentMs < prev.expireTimeMs) {
          // 仍占用，继续查找下一轨道
        } else {
          // 已过期，轨道可复用
          d.track = i;
          _trackLastDanmaku[key] = d;
          return key;
        }
      }

      // 记录最靠左/最空闲的轨道作为备选
      if (danmaku.type == DanmakuType.scroll && prev.offset < minOffset) {
        minOffset = prev.offset;
        fallbackTrack = i;
      }
    }

    // 所有轨道都被占用，返回备选轨道
    if (fallbackTrack != null) {
      d.track = fallbackTrack;
      _trackLastDanmaku['${prefix}_$fallbackTrack'] = d;
      return '${prefix}_$fallbackTrack';
    }

    return null; // 无可用轨道（顶部/底部弹幕满载时无备选）
  }

  /// 解析十六进制颜色字符串
  ///
  /// 支持 #RRGGBB 与 #AARRGGBB 两种格式，空串或非法格式返回白色。
  Color _parseColor(String color) {
    if (color.isEmpty) return Colors.white;
    if (color.startsWith('#')) {
      final hex = color.substring(1);
      if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
      if (hex.length == 8) return Color(int.parse(hex, radix: 16));
    }
    return Colors.white;
  }

  /// 释放资源
  ///
  /// 停止并销毁 Ticker，释放 ValueNotifier，清空活动弹幕与对象池。
  void dispose() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _tickNotifier.dispose();
    _activeDanmaku.clear();
    _danmakuPool.clear();
    _trackLastDanmaku.clear();
    _activeDanmakuIds.clear();
    _activeTexts.clear();
    _textCache.clear();
    _danmakuList = [];
  }
}
