import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart';
import '../core/player_engine.dart';
import '../../models/player_settings.dart';
import '../../utils/app_log.dart';

/// MPV 播放器引擎实现（基于 media_kit / libmpv）
/// 优势：格式兼容性最强、支持杜比视界/HDR、本地文件播放最佳
class MpvEngine implements PlayerEngine {
  late mk.Player _player;
  late VideoController _videoController;

  final StreamController<PlayerState> _stateController = StreamController<PlayerState>.broadcast();
  PlayerState _state = const PlayerState(engineType: PlayerEngineType.mpv);

  StreamSubscription? _playingSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferSub;
  StreamSubscription? _errorSub;

  double _videoScale = 1.0;
  PlayerSettings _subtitleSettings = PlayerSettings.defaults;
  final ValueNotifier<BoxFit> _fitModeNotifier = ValueNotifier(BoxFit.contain);
  final ValueNotifier<Size> _videoSizeNotifier = ValueNotifier(const Size(0, 0));

  @override
  PlayerEngineType get engineType => PlayerEngineType.mpv;

  @override
  Stream<PlayerState> get stateStream => _stateController.stream;

  @override
  PlayerState get currentState => _state;

  @override
  Widget buildVideoWidget() {
    return ClipRect(
      child: ValueListenableBuilder<BoxFit>(
        valueListenable: _fitModeNotifier,
        builder: (context, fit, child) {
          return FittedBox(
            fit: fit,
            child: child,
          );
        },
        child: ValueListenableBuilder<Size>(
          valueListenable: _videoSizeNotifier,
          builder: (context, size, child) {
            return SizedBox(
              width: size.width > 0 ? size.width : 1920,
              height: size.height > 0 ? size.height : 1080,
              child: child,
            );
          },
          // 禁用 media_kit 自带控件（红色进度条、播放状态提示等）
          // 完全由 Flutter UI 控制
          child: Video(
            controller: _videoController,
            controls: null,
          ),
        ),
      ),
    );
  }

  MpvEngine() {
    _init();
  }

  void _init() {
    _player = mk.Player();
    _videoController = VideoController(_player);

    Future.microtask(() async {
      final platform = _player.platform;
      if (platform != null) {
        try {
          // 视频解码：Android TV 上 mediacodec-copy 最稳定（Surface 直通，避免 auto-safe 选错路径）
          await (platform as dynamic).setProperty('hwdec', 'mediacodec-copy');
          // 帧同步：匹配显示器刷新率，减少 judder
          await (platform as dynamic).setProperty('video-sync', 'display-resample');
          // 增大 demuxer 缓冲，减少网络波动导致的卡顿
          await (platform as dynamic).setProperty('demuxer-max-bytes', '128MiB');
          await (platform as dynamic).setProperty('demuxer-max-back-bytes', '32MiB');
          // 音频解码配置：强制使用 FFmpeg 软件解码，支持 TrueHD/DTS-HD 等高端格式
          await (platform as dynamic).setProperty('ad', 'lavc');
          await (platform as dynamic).setProperty('audio-spdif', '');
          // HDR 配置：auto 模式自动检测显示器 HDR 能力
          // - HDR 显示器：直通 HDR10/HLG 信号（tone-mapping=auto）
          // - SDR 显示器：自动 tone-mapping 到 BT.2390
          await (platform as dynamic).setProperty('tone-mapping', 'auto');
          await (platform as dynamic).setProperty('hdr-compute-peak', 'yes');
          // 不强制 target-prim/target-trc，让 mpv 根据显示器能力自动选择
          // 如需 SDR 输出可设置: target-prim=bt.709, target-trc=srgb
          await (platform as dynamic).setProperty('target-prim', 'auto');
          await (platform as dynamic).setProperty('target-trc', 'auto');
          // GPU 上下文：Android 上优先 vulkan，回退 opengl
          await (platform as dynamic).setProperty('gpu-context', 'auto');
          // 10bit 色深输出
          await (platform as dynamic).setProperty('dither-depth', 'auto');
          // 禁用 MPV 自带 OSD 层（进度条、播放状态等由 Flutter UI 控制）
          await (platform as dynamic).setProperty('osd-level', '0');
          await (platform as dynamic).setProperty('osd-bar', 'no');
          await (platform as dynamic).setProperty('osd-playing-msg', '');
          // 默认字幕字号（200 ≈ 视频高度 20%），避免 4K 视频字幕过小
          await (platform as dynamic).setProperty('sub-font-size', '200');
          await (platform as dynamic).setProperty('sub-ass-override', 'force');
          await (platform as dynamic).setProperty('osd-paused-msg', '');
          // 字幕配置：使用默认样式，运行时由 applySubtitleStyle() 动态调整
          await applySubtitleStyle(PlayerSettings.defaults);
          // 确保字幕可见（默认开启）
          await (platform as dynamic).setProperty('sub-visibility', 'yes');
          // ASS/SSA 特效字幕：按原始位置定位
          await (platform as dynamic).setProperty('sub-use-margins', 'no');
          await (platform as dynamic).setProperty('sub-ass-vsfilter-aspect-compat', 'no');
          // ── 网络流媒体缓存优化（解决 HTTP 流播放掉帧/卡顿）──
          await (platform as dynamic).setProperty('cache', 'yes');
          // 解复用器最大缓存 512MB（高码率 4K 需要更大缓冲）
          await (platform as dynamic).setProperty('demuxer-max-bytes', '536870912');
          // 解复用器向后缓存 128MB（用于回退/seek）
          await (platform as dynamic).setProperty('demuxer-max-back-bytes', '134217728');
          // 预读 60 秒数据
          await (platform as dynamic).setProperty('demuxer-readahead-secs', '60');
          // 缓冲暂停策略：缓冲低于 3 秒时暂停等待（平衡起播速度与流畅度）
          await (platform as dynamic).setProperty('cache-pause', 'yes');
          await (platform as dynamic).setProperty('cache-pause-wait', '3');
          // 网络超时设置
          await (platform as dynamic).setProperty('stream-lavf-o', 'timeout=10000000');
          AppLog.i('MpvEngine', 'MPV 配置完成 (HDR auto + 10bit + 网络缓存优化)');
        } catch (e) {
          AppLog.e('MpvEngine', 'MPV 配置失败: $e');
        }
      }
    });

    _playingSub = _player.stream.playing.listen((playing) {
      _updateState(_state.copyWith(isPlaying: playing));
    });

    _positionSub = _player.stream.position.listen((pos) {
      _updateState(_state.copyWith(position: pos));
    });

    _durationSub = _player.stream.duration.listen((dur) {
      _updateState(_state.copyWith(duration: dur));
    });

    _bufferSub = _player.stream.buffer.listen((buf) {
      _updateState(_state.copyWith(buffer: buf));
    });

    _errorSub = _player.stream.error.listen((err) {
      AppLog.e('MpvEngine', '播放错误: $err');
      _updateState(_state.copyWith(error: err.toString()));
    });

    // 监听视频轨道变化，检测是否有视频流
    _player.stream.tracks.listen((tracks) {
      final videoCount = tracks.video.where((t) => t.id != 'no').length;
      final audioCount = tracks.audio.where((t) => t.id != 'no').length;
      AppLog.i('MpvEngine', '视频轨道数: $videoCount, 音频轨道数: $audioCount');
      if (videoCount == 0) {
        AppLog.w('MpvEngine', '未检测到视频轨道，可能无法显示画面');
      }
      // 更新视频尺寸
      final vw = _player.state.width;
      final vh = _player.state.height;
      if (vw != null && vw > 0 && vh != null && vh > 0) {
        _videoSizeNotifier.value = Size(vw.toDouble(), vh.toDouble());
      }
    });

    // 监听视频尺寸变化
    _player.stream.width.listen((width) {
      final w = width ?? 0;
      final h = _player.state.height ?? 0;
      if (w > 0 && h > 0) {
        _videoSizeNotifier.value = Size(w.toDouble(), h.toDouble());
        AppLog.i('MpvEngine', '视频尺寸: ${w}x$h');
      }
    });
  }

  void _updateState(PlayerState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  @override
  Future<void> open({
    required String url,
    Map<String, String>? httpHeaders,
    bool autoPlay = true,
  }) async {
    try {
      await _player.open(
        mk.Media(url, httpHeaders: httpHeaders ?? {}),
        play: autoPlay,
      );
    } catch (e) {
      AppLog.e('MpvEngine', '打开失败: $e');
      _updateState(_state.copyWith(error: e.toString()));
    }
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setRate(speed);
    _updateState(_state.copyWith(speed: speed));
  }

  @override
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume * 100);
    _updateState(_state.copyWith(volume: volume));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _playingSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _bufferSub?.cancel();
    await _errorSub?.cancel();
    await _player.dispose();
    await _stateController.close();
  }

  @override
  Future<List<Map<String, dynamic>>> getAudioTracks() async {
    try {
      final tracks = _player.state.tracks;
      // 过滤掉 'no'（禁用）轨道，避免索引错位导致无法正确切换
      return tracks.audio
          .where((t) => t.id != 'no')
          .map((t) => {
                'id': t.id,
                'title': t.title ?? '音轨 ${t.id}',
                'language': t.language ?? '',
                'codec': t.codec ?? '',
                'channels': t.channels ?? '',
                'bitrate': t.bitrate,
                'audiochannels': t.audiochannels,
                'samplerate': t.samplerate,
                'isDefault': t.isDefault ?? false,
              })
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 位图字幕编解码器集合（PGS/DVDsub/VobSub/DVB 等），这些格式是预渲染图片，
  /// 不支持字号/颜色等样式调整，且部分 MPV 构建可能缺少解码器
  static const _bitmapSubCodecs = {'pgs_sub', 'hdmv_pgs_subtitle', 'dvd_subtitle', 'dvb_subtitle', 'vobsub', 'subrip_bitmap'};

  @override
  Future<List<Map<String, dynamic>>> getSubtitleTracks() async {
    try {
      final tracks = _player.state.tracks;
      final filtered = tracks.subtitle
          .where((t) => t.id != 'no' && t.id != 'auto')
          .toList();
      AppLog.i('MpvEngine', '字幕轨道数: ${filtered.length}');
      for (var i = 0; i < filtered.length; i++) {
        final t = filtered[i];
        AppLog.i(
          'MpvEngine',
          '字幕轨道[$i]: id=${t.id}, title=${t.title ?? ''}, '
          'language=${t.language ?? ''}, codec=${t.codec ?? ''}, '
          'default=${t.isDefault ?? false}',
        );
      }
      return filtered.map((t) {
        final codec = t.codec ?? '';
        final isBitmap = _bitmapSubCodecs.contains(codec.toLowerCase());
        if (isBitmap) {
          AppLog.w('MpvEngine', '检测到字幕轨道 [${t.id}] 为位图格式 ($codec)，可能无法渲染');
        }
        return {
          'id': t.id,
          'title': t.title ?? '字幕 ${t.id}',
          'language': t.language ?? '',
          'codec': codec,
          'isDefault': t.isDefault ?? false,
          'isBitmap': isBitmap,
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> setAudioTrack(int index) async {
    try {
      // 与 getAudioTracks 保持一致的过滤，确保索引对齐
      final tracks = _player.state.tracks.audio.where((t) => t.id != 'no').toList();
      if (index >= 0 && index < tracks.length) {
        await _player.setAudioTrack(tracks[index]);
        AppLog.i('MpvEngine', '切换音轨: index=$index, id=${tracks[index].id}');
      }
    } catch (e) {
      AppLog.e('MpvEngine', '切换音轨失败: $e');
    }
  }

  @override
  Future<void> setSubtitleTrack(int index) async {
    try {
      // index == -1 表示关闭字幕
      if (index == -1) {
        await _player.setSubtitleTrack(mk.SubtitleTrack.no());
        AppLog.i('MpvEngine', '字幕已关闭');
        return;
      }
      // 与 getSubtitleTracks 保持一致的过滤，确保索引对齐
      final tracks = _player.state.tracks.subtitle.where((t) => t.id != 'no' && t.id != 'auto').toList();
      if (index >= 0 && index < tracks.length) {
        final track = tracks[index];
        AppLog.i(
          'MpvEngine',
          '准备切换字幕: index=$index, id=${track.id}, title=${track.title ?? ''}, '
          'language=${track.language ?? ''}, codec=${track.codec ?? ''}, '
          'default=${track.isDefault ?? false}',
        );
        await _player.setSubtitleTrack(track);
        AppLog.i('MpvEngine', '字幕切换完成: index=$index, id=${track.id}');

        // MPV 在媒体/字幕轨道加载时可能重置字幕渲染属性。
        // 选轨完成后重新应用用户样式，确保当前 SUBRIP/ASS 轨道字号生效。
        await applySubtitleStyle(_subtitleSettings);
        final platform = _player.platform;
        if (platform != null) {
          await (platform as dynamic).setProperty('sub-visibility', 'yes');
        }
        await _logSubtitleProperties(trackId: track.id, codec: track.codec ?? '');
      }
    } catch (e) {
      AppLog.e('MpvEngine', '切换字幕失败: $e');
    }
  }

  @override
  Future<void> applySubtitleStyle(PlayerSettings s) async {
    _subtitleSettings = s;
    final platform = _player.platform;
    if (platform == null) {
      AppLog.w('MpvEngine', '字幕样式未应用: platform=null');
      return;
    }
    try {
      const fontSize = 200;
      final marginY = (s.subtitleBottomMargin * 100).round();
      AppLog.i(
        'MpvEngine',
        '应用字幕样式: fontSize=$fontSize, scale=${s.subtitleFontSizeScale}, '
        'family=${s.subtitleFontFamily}, bold=${s.subtitleBold}, '
        'borderWidth=${s.subtitleBorderWidth}, marginY=$marginY, '
        'assOverride=${s.subtitleAssOverride ? 'force' : 'no'}',
      );
      // 字号：基准 200（MPV 归一化到 ~1000px 视频高度），通过 sub-scale 用户缩放
      // TV 观看距离远，需要更大字号；200 ≈ 视频高度 20%
      await (platform as dynamic).setProperty('sub-font-size', fontSize.toString());
      await (platform as dynamic).setProperty('sub-scale', s.subtitleFontSizeScale.toString());
      // 字幕延迟（秒，正=延后，负=提前），MPV 原生属性
      if (s.subtitleDelaySeconds != 0) {
        await (platform as dynamic).setProperty('sub-delay', s.subtitleDelaySeconds.toString());
      }
      // 底部边距：视频高度百分比转换为像素（假设视频高度 100 单位）
      await (platform as dynamic).setProperty('sub-margin-y', marginY.toString());
      // 文字颜色与描边
      await (platform as dynamic).setProperty('sub-color', _argbToMpvHex(s.subtitleColor));
      await (platform as dynamic).setProperty('sub-border-color', _argbToMpvHex(s.subtitleBorderColor));
      await (platform as dynamic).setProperty('sub-border-size', s.subtitleBorderWidth.toString());
      // 阴影
      await (platform as dynamic).setProperty('sub-shadow-offset', s.subtitleShadowOffset.toString());
      await (platform as dynamic).setProperty('sub-shadow-color', _argbToMpvHex(s.subtitleShadowColor));
      // 加粗
      await (platform as dynamic).setProperty('sub-bold', s.subtitleBold ? 'yes' : 'no');
      // 字体
      if (s.subtitleFontFamily != 'system') {
        await (platform as dynamic).setProperty('sub-font', s.subtitleFontFamily);
      }
      // ASS/SSA 特效字幕：强制使用 force 统一样式，确保 sub-font-size 对所有字幕类型生效
      // （'no' 模式下 ASS 文件内部样式会覆盖 sub-font-size，导致 TV 上字幕过小）
      await (platform as dynamic).setProperty(
        'sub-ass-override',
        s.subtitleAssOverride ? 'force' : 'no',
      );
      AppLog.i(
        'MpvEngine',
        '字幕样式应用完成: fontSize=$fontSize, scale=${s.subtitleFontSizeScale}, '
        'effectiveBase=${fontSize * s.subtitleFontSizeScale}',
      );
    } catch (e) {
      AppLog.e('MpvEngine', '应用字幕样式失败: $e');
    }
  }

  Future<void> _logSubtitleProperties({required String trackId, required String codec}) async {
    final platform = _player.platform;
    if (platform == null) return;
    try {
      final native = platform as dynamic;
      final fontSize = await native.getProperty('sub-font-size');
      final scale = await native.getProperty('sub-scale');
      final visibility = await native.getProperty('sub-visibility');
      final marginY = await native.getProperty('sub-margin-y');
      final assOverride = await native.getProperty('sub-ass-override');
      AppLog.i(
        'MpvEngine',
        '字幕样式回读: track=$trackId, codec=$codec, fontSize=$fontSize, '
        'scale=$scale, visibility=$visibility, marginY=$marginY, '
        'assOverride=$assOverride',
      );
    } catch (e) {
      // 某些 media_kit/libmpv 构建不暴露 getProperty；不影响样式设置。
      AppLog.w('MpvEngine', '字幕样式属性回读失败: $e');
    }
  }

  /// ARGB 整数转 MPV 十六进制字符串（#RRGGBBAA 或 #AARRGGBB）
  /// MPV 使用 #AARRGGBB 格式（AA 在前）
  String _argbToMpvHex(int argb) {
    final a = (argb >> 24) & 0xFF;
    final r = (argb >> 16) & 0xFF;
    final g = (argb >> 8) & 0xFF;
    final b = argb & 0xFF;
    return '#${a.toRadixString(16).padLeft(2, '0')}${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0').toUpperCase()}';
  }

  @override
  Future<bool> loadExternalSubtitle(String path) async {
    final platform = _player.platform;
    if (platform == null) return false;
    try {
      // libmpv sub-add 命令：加载外挂字幕文件
      // 参数：sub-add <filename> [flags] [title] [lang]
      final before = _player.state.tracks.subtitle.map((t) => t.id).toSet();
      await (platform as dynamic).setProperty('sub-files', path);
      AppLog.i('MpvEngine', '加载外挂字幕: $path');
      // sub-add 默认不会切换选中轨（sid=auto 时可能仍显示内嵌轨），
      // 需要显式选中刚添加的外挂轨，否则用户选的服务端字幕不会显示。
      // 轨道列表刷新是异步的，先立刻查一次，查不到则短延时后再查一次。
      List<mk.SubtitleTrack> added = _player.state.tracks.subtitle
          .where((t) => !before.contains(t.id))
          .toList();
      if (added.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 300));
        added = _player.state.tracks.subtitle
            .where((t) => !before.contains(t.id))
            .toList();
      }
      if (added.isNotEmpty) {
        await _player.setSubtitleTrack(added.last);
        AppLog.i('MpvEngine', '已选中外挂字幕轨: id=${added.last.id}');
      } else {
        AppLog.w('MpvEngine', '外挂字幕轨未出现在轨道列表，可能未选中');
      }
      return true;
    } catch (e) {
      AppLog.e('MpvEngine', '加载外挂字幕失败: $e');
      return false;
    }
  }

  @override
  dynamic get externalSubtitleManager => null; // MPV 字幕由原生层渲染，不需要 Flutter 层叠加

  @override
  double get videoScale => _videoScale;

  @override
  void setVideoScale(double scale) {
    _videoScale = scale.clamp(1.0, 2.0);
  }

  @override
  BoxFit get fitMode => _fitModeNotifier.value;

  @override
  ValueNotifier<BoxFit> get fitModeNotifier => _fitModeNotifier;

  @override
  void setFitMode(BoxFit mode) {
    _fitModeNotifier.value = mode;
  }

  // ===== Anime4K GLSL 着色器管理 =====

  /// 当前已加载的着色器文件路径列表
  final List<String> _loadedShaders = [];

  /// 加载 Anime4K 着色器（GLSL 文件路径列表）
  ///
  /// 通过 mpv 的 `glsl-shaders` 属性加载着色器链。
  /// 路径必须是设备上可访问的绝对路径。
  ///
  /// 常用 Anime4K 配置：
  /// - Mode A (高质量): Anime4K_Clamp_Highlights.glsl + Restore_CNN_M.glsl + Upscale_CNN_x2_M.glsl
  /// - Mode B (平衡):   Clamp_Highlights + Restore_CNN_S + Upscale_CNN_x2_S
  /// - Mode C (性能):   Clamp_Highlights + Upscale_Denoise_CNN_x2_S
  Future<bool> loadShaders(List<String> shaderPaths) async {
    try {
      final platform = _player.platform;
      if (platform == null) return false;

      // mpv 使用 : 分隔多个着色器路径（Linux/Android）
      final shaderString = shaderPaths.join(':');

      await (platform as dynamic).setProperty('glsl-shaders', shaderString);
      _loadedShaders
        ..clear()
        ..addAll(shaderPaths);

      AppLog.i('MpvEngine', 'Anime4K 着色器加载成功: ${shaderPaths.length} 个');
      return true;
    } catch (e) {
      AppLog.e('MpvEngine', 'Anime4K 着色器加载失败: $e');
      return false;
    }
  }

  /// 卸载所有着色器（恢复默认渲染）
  Future<void> clearShaders() async {
    try {
      final platform = _player.platform;
      if (platform == null) return;
      await (platform as dynamic).setProperty('glsl-shaders', '');
      _loadedShaders.clear();
      AppLog.i('MpvEngine', '着色器已清除');
    } catch (e) {
      AppLog.e('MpvEngine', '着色器清除失败: $e');
    }
  }

  /// 当前已加载的着色器列表
  List<String> get loadedShaders => List.unmodifiable(_loadedShaders);

  /// 是否有着色器在运行
  bool get hasShaders => _loadedShaders.isNotEmpty;

  /// 设置 mpv 自定义属性（高级用户接口）
  Future<void> setMpvProperty(String key, String value) async {
    try {
      final platform = _player.platform;
      if (platform == null) return;
      await (platform as dynamic).setProperty(key, value);
    } catch (e) {
      AppLog.e('MpvEngine', 'setProperty($key=$value) 失败: $e');
    }
  }

  @override
  Future<Uint8List?> captureFrame() async {
    // media_kit 暂不支持 libmpv 截图命令，能力表声明为不支持，UI 会降级提示
    return null;
  }

  @override
  PlayerEngineCapabilities get capabilities => const PlayerEngineCapabilities(
        supportsFrameCapture: false,
        supportsHardwareDecode: true,
        supportsExternalSubtitle: true,
        supportsTrackSwitching: true,
      );

  /// 获取原始 Player 实例（兼容旧代码）
  mk.Player get rawPlayer => _player;

  /// 获取原始 VideoController 实例
  VideoController get rawController => _videoController;
}
