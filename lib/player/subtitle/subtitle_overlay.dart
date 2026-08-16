import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/player_settings.dart';
import '../../utils/subtitle_fonts.dart';
import 'subtitle_cue.dart';
import 'subtitle_parser.dart';

/// 外挂字幕叠加层
/// 通过 CustomPaint + ValueNotifier 渲染当前时间点的字幕
/// 复用 Phase 1 的 PlayerSettings 字幕样式
class SubtitleOverlay extends StatefulWidget {
  final List<SubtitleCue> cues;
  final Duration Function() currentPosition;
  final PlayerSettings settings;
  final double screenWidth;
  final double screenHeight;

  const SubtitleOverlay({
    super.key,
    required this.cues,
    required this.currentPosition,
    required this.settings,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  State<SubtitleOverlay> createState() => _SubtitleOverlayState();
}

class _SubtitleOverlayState extends State<SubtitleOverlay> {
  final ValueNotifier<SubtitleCue?> _currentCueNotifier = ValueNotifier<SubtitleCue?>(null);
  int _lastCueIndex = -1;

  @override
  void initState() {
    super.initState();
    _updateCurrentCue();
  }

  @override
  void didUpdateWidget(SubtitleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cues != widget.cues) {
      _lastCueIndex = -1;
    }
    _updateCurrentCue();
  }

  /// 更新当前字幕
  /// 调用方需在播放位置变化时调用此方法（通过 setState 或 ValueNotifier 触发重建）
  /// 使用二分查找（cues 按 start 升序），与 ExternalSubtitleManager.getCueAt 一致，
  /// 大字幕文件下 O(log n) 替代线性扫描。
  void _updateCurrentCue() {
    final position = widget.currentPosition();
    final cues = widget.cues;
    SubtitleCue? found;
    int newIdx = -1;
    if (cues.isNotEmpty) {
      int left = 0;
      int right = cues.length - 1;
      while (left <= right) {
        final mid = (left + right) ~/ 2;
        final cue = cues[mid];
        if (cue.contains(position)) {
          found = cue;
          newIdx = mid;
          break;
        }
        if (position < cue.start) {
          right = mid - 1;
        } else {
          left = mid + 1;
        }
      }
    }
    if (newIdx != _lastCueIndex) {
      _lastCueIndex = newIdx;
      _currentCueNotifier.value = found;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 幂等注册自定义字体（已注册则直接返回），确保 Exo 外挂字幕用上用户字体
    SubtitleFonts.ensureLoaded();
    return ValueListenableBuilder<SubtitleCue?>(
      valueListenable: _currentCueNotifier,
      builder: (context, cue, _) {
        if (cue == null) return const SizedBox.shrink();
        // 注意：此前的 Positioned 不是 Stack 直接子级（父级是 Positioned.fill →
        // IgnorePointer → ValueListenableBuilder），release 下定位参数静默失效、
        // 字幕被 Center 渲染到画面正中。改 Align + 底部 Padding 后位置回归底部、
        // subtitleBottomMargin 边距设置生效。
        return Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: widget.screenHeight * widget.settings.subtitleBottomMargin,
            ),
            child: _buildSubtitleText(cue.text),
          ),
        );
      },
    );
  }

  /// 字体解析：自定义字体文件优先，其次样式表字体，缺省系统字体
  String? _resolveFontFamily(PlayerSettings s) {
    if (SubtitleFonts.savedPath != null && SubtitleFonts.savedPath!.isNotEmpty) {
      return SubtitleFonts.fontFamily;
    }
    return s.subtitleFontFamily == 'system' ? null : s.subtitleFontFamily;
  }

  /// 构建字幕文本 Widget
  /// 支持多行（换行符分割）、描边、阴影、背景
  Widget _buildSubtitleText(String text) {
    final s = widget.settings;
    final fontSize = _calculateFontSize();

    // 支持多行
    final lines = text.split('\n');

    return Container(
      constraints: BoxConstraints(maxWidth: widget.screenWidth * 0.9),
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 4,
      ),
      decoration: s.subtitleBackgroundOpacity > 0
          ? BoxDecoration(
              color: Colors.black.withValues(alpha: s.subtitleBackgroundOpacity),
              borderRadius: BorderRadius.circular(4),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: lines.map((line) {
          return Stack(
            children: [
              // 描边层
              if (s.subtitleBorderWidth > 0)
                Text(
                  line,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: s.subtitleBold ? FontWeight.bold : FontWeight.normal,
                    fontFamily: _resolveFontFamily(s),
                    fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = s.subtitleBorderWidth
                      ..color = Color(s.subtitleBorderColor),
                  ),
                  textAlign: TextAlign.center,
                ),
              // 阴影层
              if (s.subtitleShadowOffset > 0)
                Text(
                  line,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: s.subtitleBold ? FontWeight.bold : FontWeight.normal,
                    fontFamily: _resolveFontFamily(s),
                    fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
                    color: Colors.transparent,
                    shadows: [
                      Shadow(
                        color: Color(s.subtitleShadowColor),
                        offset: Offset(s.subtitleShadowOffset, s.subtitleShadowOffset),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              // 主文字层
              Text(
                line,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: s.subtitleBold ? FontWeight.bold : FontWeight.normal,
                  fontFamily: _resolveFontFamily(s),
                  fontFamilyFallback: const ['Noto Sans CJK SC', 'sans-serif'],
                  color: Color(s.subtitleColor),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// 根据屏幕高度和字号倍数计算实际字号
  /// 基准 6%：5.33% 偏小、8.5% 偏大、7% 仍偏大（三次实机反馈），
  /// 最终取 6%（1080p 横屏 ≈65px，清晰且不遮画面）
  double _calculateFontSize() {
    const baseRatio = 0.06;
    return widget.screenHeight * baseRatio * widget.settings.subtitleFontSizeScale;
  }

  @override
  void dispose() {
    _currentCueNotifier.dispose();
    super.dispose();
  }
}

/// 外挂字幕管理器
/// 负责加载字幕文件、管理 cue 列表、驱动字幕更新
class ExternalSubtitleManager {
  List<SubtitleCue> _cues = [];
  bool _loaded = false;
  String? _error;

  List<SubtitleCue> get cues => _cues;
  bool get isLoaded => _loaded;
  String? get error => _error;

  /// 从文件路径加载字幕
  Future<void> loadFromFile(String path) async {
    _loaded = false;
    _error = null;
    _cues = [];
    try {
      _cues = await SubtitleParser.parseFile(path);
      _loaded = _cues.isNotEmpty;
      if (!_loaded) {
        _error = '字幕文件为空或解析失败';
      }
    } catch (e) {
      _error = '加载字幕失败: $e';
    }
  }

  /// 从字符串加载字幕
  void loadFromContent(String content) {
    _loaded = false;
    _error = null;
    _cues = [];
    try {
      _cues = SubtitleParser.parseContent(content);
      _loaded = _cues.isNotEmpty;
      if (!_loaded) {
        _error = '字幕内容为空或解析失败';
      }
    } catch (e) {
      _error = '解析字幕失败: $e';
    }
  }

  /// 获取指定时间点的字幕（二分查找优化）
  SubtitleCue? getCueAt(Duration position) {
    if (_cues.isEmpty) return null;
    // 二分查找
    int left = 0;
    int right = _cues.length - 1;
    while (left <= right) {
      final mid = (left + right) ~/ 2;
      final cue = _cues[mid];
      if (cue.contains(position)) return cue;
      if (position < cue.start) {
        right = mid - 1;
      } else {
        left = mid + 1;
      }
    }
    return null;
  }

  void clear() {
    _cues = [];
    _loaded = false;
    _error = null;
  }
}
