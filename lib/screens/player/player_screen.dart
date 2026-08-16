import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../player/core/player_engine.dart';
import '../../player/core/player_manager.dart';
import '../../player/subtitle/subtitle_overlay.dart';
import '../../player/danmaku/danmaku_controller.dart';
import '../../player/danmaku/danmaku_renderer.dart';
import '../../player/danmaku/danmaku_models.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../services/danmaku_service.dart';
import '../../services/storage_service.dart';
import '../../database/database_service.dart';
import '../../services/http_client.dart';
import '../../providers/app_providers.dart';
import '../../utils/app_log.dart';
import '../../utils/animation_config.dart';
import '../../utils/chinese_converter.dart';
import '../../utils/track_titles.dart';
import 'package:crypto/crypto.dart';
import '../../widgets/online_subtitle_sheet.dart';
import '../../services/opensubtitles_service.dart';
import '../../widgets/double_tap_ripple.dart';
import '../../widgets/custom_progress_bar.dart';
import '../../widgets/skip_button.dart';
import '../../widgets/track_right_panel.dart';
import '../../widgets/tap_feedback.dart';
import '../../widgets/more_right_panel.dart';
import 'subtitle_style_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  static const routeName = '/player';

  final MediaItem media;
  final String streamUrl;
  final Map<String, String>? httpHeaders;
  final List<MediaItem>? episodes;
  final MediaServerService? service;
  final MediaServer? server;
  final int? resumePositionMs;

  const PlayerScreen({
    super.key,
    required this.media,
    required this.streamUrl,
    this.httpHeaders,
    this.episodes,
    this.service,
    this.server,
    this.resumePositionMs,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with TickerProviderStateMixin {
  PlayerEngine? _engine;
  PlayerEngineType _engineType = PlayerEngineType.mpv;
  StreamSubscription<PlayerState>? _stateSub;
  int _engineKey = 0; // 引擎切换时增加，强制视频 widget 重建

  bool _controlsVisible = true;
  bool _isPlaying = false;
  Timer? _progressTimer;
  Timer? _uiUpdateTimer;
  DateTime _lastStateTime = DateTime.now();
  int _lastReportedMs = 0;
  bool _playbackStartReported = false;
  bool _resumeApplied = false;
  bool _isBuffering = false;
  int _streamTick = 0;
  int _uiTick = 0;
  TapDownDetails? _doubleTapDetails;
  bool _showEpisodePanel = false;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  String _currentQuality = 'auto';   // 当前播放画质（播放器内可切换）
  // 当前实际播放的流地址：切集/切画质后 widget.streamUrl 已过时，
  // 服务端字幕下载需用它提取当前集的 MediaSourceId（否则会用上一集的
  // MediaSourceId 构造字幕 URL → 404 → "字幕下载失败"）。
  String _currentStreamUrl = '';
  bool _controlsLocked = false;      // 播放器锁定（防误触，Streama/CapyPlayer 同款）
  bool _danmakuEnabled = true;
  String? _initError;
  BoxFit _currentFitMode = BoxFit.contain;
  bool _isSeeking = false;

  final List<_FitModeOption> _fitModeOptions = [
    _FitModeOption(BoxFit.contain, '原始', Icons.aspect_ratio_rounded),
    _FitModeOption(BoxFit.cover, '填充', Icons.crop_square_rounded),
    _FitModeOption(BoxFit.fill, '拉伸', Icons.fit_screen_rounded),
    _FitModeOption(BoxFit.fitWidth, '适配宽度', Icons.align_horizontal_left_rounded),
    _FitModeOption(BoxFit.fitHeight, '适配高度', Icons.align_vertical_top_rounded),
  ];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  double _speed = 1.0;
  double _brightness = 1.0;
  double _volume = 1.0;
  // 画幅模式已替代简单缩放，_videoScale 不再使用

  Timer? _hideTimer;
  Timer? _brightnessHideTimer;
  Timer? _volumeHideTimer;

  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0, 4.0];
  int _currentSpeedIndex = 2;

  double _screenWidth = 0;
  double _screenHeight = 0;
  DanmakuDisplaySettings _cachedDisplay = const DanmakuDisplaySettings();
  late final DanmakuController _danmakuController;

  int _currentSubtitleIndex = -1;
  List<Map<String, dynamic>> _subtitleTracks = [];
  // 是否已自动启用过文件标记的默认字幕轨（每个播放会话只自动一次，
  // 防止重复触发下载；切集时重置以便新一集自动启用其默认轨）
  bool _autoDefaultSubtitleApplied = false;
  // 是否已后台预取过常用服务端字幕（默认/中文/英文）；切集时重置以便新一集预取
  bool _subtitlePrefetched = false;
  // 用户是否显式关闭过字幕：视频本身带硬字幕（烧录进画面）的片源，
  // 再叠加软字幕就是双层。用户关过一次后本会话记住，不再自动启用。
  bool _userDisabledSubtitles = false;
  // 去重后的完整字幕轨列表（过滤前），供"显示全部字幕"展开用
  List<Map<String, dynamic>> _fullSubtitleTracks = [];
  // 是否已展开显示全部字幕轨（默认只显示 中/英/默认轨）
  bool _showAllSubtitleTracks = false;
  // 位图字幕（PGS/SUP）提示是否已弹出（轨道轮询会多次进入此块，只提示一次）
  bool _bitmapWarned = false;
  int _currentAudioIndex = 0;
  List<Map<String, dynamic>> _audioTracks = [];

  // 外挂字幕状态（Phase 2）
  List<dynamic> _externalSubtitleCues = [];
  bool _externalSubtitleLoaded = false;
  // 服务端字幕下载中（Emby/NAS 首次按需提取内嵌字幕可能很慢，给用户可见反馈）
  bool _serverSubtitleLoading = false;

  bool _isDisposed = false;
  bool _cleanupDone = false;
  bool _tracksLoaded = false;
  bool _showedAudioError = false;
  bool _danmakuLoading = false; // 弹幕加载中标志位，防止重复请求

  // ── 当前播放集数跟踪（切集后 widget.media 已过时） ──
  int _currentEpisodeIndex = 0;
  MediaItem? _currentMedia;
  MediaItem get _activeMedia => _currentMedia ?? widget.media;

  /// 是否有可用的选集列表（上一集/下一集按钮据此显示）
  bool get _hasEpisodeList {
    final eps = widget.episodes;
    return eps != null && eps.isNotEmpty && _currentEpisodeIndex >= 0;
  }

  /// 左下角视频信息：分辨率 · 编码 · 码率 · 帧率（数据来自服务端 MediaStreams）
  String? get _videoMetadata {
    final tracks = _activeMedia.videoTracks;
    if (tracks == null || tracks.isEmpty) return null;
    final t = tracks.first;
    final w = t['Width'] as num?;
    final h = t['Height'] as num?;
    final codec = t['Codec']?.toString().toUpperCase();
    final bitrate = t['BitRate'] as num?;
    final fps = t['FrameRate'] as num?;
    final parts = <String>[];
    if (w != null && h != null && w > 0 && h > 0) parts.add('${w.toInt()}×${h.toInt()}');
    if (codec != null && codec.isNotEmpty && codec != 'UNKNOWN') parts.add(codec);
    if (bitrate != null && bitrate > 0) {
      final mbps = bitrate / 1000000;
      parts.add(mbps >= 10 ? '${mbps.round()} Mbps' : '${mbps.toStringAsFixed(1)} Mbps');
    }
    if (fps != null && fps > 0) parts.add('${fps.round()} fps');
    return parts.isEmpty ? null : parts.join(' · ');
  }

  // ── 跳过片头/片尾 ──
  IntroSkip? _introSkip;
  String? _skipButtonLabel;       // '跳过片头' / '跳过片尾' / null
  bool _skipIntroHandled = false; // 本次播放是否已自动跳过片头

  // ── 双击涟漪 ──
  Offset _ripplePosition = Offset.zero;
  bool _rippleIsLeft = true;
  bool _ripplePlayPause = false; // 中间双击=播放/暂停涟漪（非 seek 圆弧）
  IconData _rippleIcon = Icons.pause_rounded;
  int _rippleTrigger = 0;
  bool _showRipple = false;

  // ── 右侧轨道面板 ──
  String? _rightPanelType; // 'audio' / 'subtitle' / null

  // ── 下一集倒计时 ──
  bool _showNextEpisode = false;
  bool _nextEpisodeCancelled = false;
  int _nextEpisodeCountdown = 15;
  Timer? _nextEpisodeTimer;
  // 正在自动切换下一集（防止倒计时回调与位置检测双重触发）
  bool _nextEpisodePlaying = false;
  // 音量持久化（写 SharedPreferences 防抖；亮度变化由手势直接保存）
  Timer? _volBriSaveTimer;
  double _lastSavedVolume = 1.0;

  // ── 进度条 seek 中的临时位置 ──

  // ── 选集面板动画 ──
  late AnimationController _episodePanelController;
  late Animation<Offset> _episodeSlideAnim;
  late Animation<double> _episodeFadeAnim;

  // ── 控制栏显隐动画（顶栏上滑 / 底栏下滑 + 淡出）──
  late AnimationController _controlsController;
  late Animation<double> _controlsAnim;

  // ── 中心播放键扩散光晕（按下时从按钮向外扩散一圈柔和光圈）──
  late AnimationController _playPulseController;

  // ── Trickplay 缩略图 ──
  TrickplayInfo? _trickplayInfo;

  // ── 章节标记（Emby/Jellyfin Chapters API）──
  List<int> _chapterMarkers = [];
  bool _chaptersLoaded = false;

  @override
  void initState() {
    super.initState();
    _currentQuality = ref.read(playerSettingsProvider).defaultQuality;
    // ── 选集面板动画初始化 ──
    _episodePanelController = AnimationController(
      duration: AppAnimations.medium,
      vsync: this,
    );
    _episodeSlideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _episodePanelController,
      curve: AppAnimations.easeOut,
    ));
    _episodeFadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _episodePanelController, curve: AppAnimations.easeOut),
    );
    // ── 控制栏动画初始化（初始为可见）──
    _controlsController = AnimationController(
      duration: AppAnimations.medium,
      vsync: this,
      value: 1.0,
    );
    _controlsAnim = CurvedAnimation(
      parent: _controlsController,
      curve: AppAnimations.easeOut,
      reverseCurve: AppAnimations.easeIn,
    );
    // ── 播放键光晕动画控制器（按下时 forward(from:0) 重新扩散）──
    _playPulseController = AnimationController(
      duration: const Duration(milliseconds: 550),
      vsync: this,
    );
    final settings = ref.read(playerSettingsProvider);
    _cachedDisplay = ref.read(danmakuDisplayProvider);
    _danmakuEnabled = settings.enableDanmakuByDefault;
    // 创建弹幕控制器并初始化（屏幕尺寸在 build 中更新）
    _danmakuController = DanmakuController(this);
    _danmakuController.init(
      screenWidth: 0,
      screenHeight: 0,
      config: DanmakuRenderConfig.fromSettings(_cachedDisplay, playbackSpeed: _speed),
    );
    _danmakuController.setEnabled(_danmakuEnabled);
    // 监听弹幕显示设置变化，同步到控制器
    ref.listenManual(danmakuDisplayProvider, (prev, next) {
      _cachedDisplay = next;
      _danmakuController.updateConfig(
        DanmakuRenderConfig.fromSettings(next, playbackSpeed: _speed),
      );
    });
    // 初始化当前集数跟踪（切集后 widget.media 已过时）
    final eps = widget.episodes;
    _currentEpisodeIndex =
        (eps == null || eps.isEmpty) ? 0 : eps.indexWhere((e) => e.id == widget.media.id);
    if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    _currentMedia = widget.media;
    _initPlayer();
    _loadDanmaku();
    _loadIntroSkip();
    _loadTrickplayInfo();
    _loadChapters();
    // 控制栏初始可见，启动自动隐藏定时器
    _startHideTimer();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 提前获取屏幕尺寸，确保弹幕更新时 _screenWidth != 0
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _screenWidth = MediaQuery.of(context).size.width;
        _screenHeight = MediaQuery.of(context).size.height;
        _danmakuController.updateScreenSize(_screenWidth, _screenHeight);
      }
    });
  }

  @override
  void deactivate() {
    _cleanup();
    super.deactivate();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanup();
    super.dispose();
  }

  void _cleanup() {
    if (_cleanupDone) return;
    _cleanupDone = true;

    _progressTimer?.cancel();
    _uiUpdateTimer?.cancel();
    // 上报最终位置并关闭播放会话
    _reportProgress();
    final svc = ref.read(currentMediaServerServiceProvider);
    if (svc is EmbyService) {
      svc.reportPlaybackStopped(_activeMedia.id, positionMs: _position.inMilliseconds);
    }

    _danmakuController.dispose();

    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = null;

    _hideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _episodePanelController.dispose();
    _controlsController.dispose();
    _playPulseController.dispose();
    _stateSub?.cancel();
    _stateSub = null;
    
    // 移除画幅模式监听
    _engine?.fitModeNotifier.removeListener(_onFitModeChanged);

    try { ScreenBrightness().resetScreenBrightness(); } catch (_) {}

    _engine?.stop();
    final manager = ref.read(playerManagerProvider);
    manager.disposeEngine();
    _engine = null;

    _restoreOrientation();
  }

  Future<void> _initPlayer() async {
    final manager = ref.read(playerManagerProvider);

    try {
      _engine = await manager.createEngine(
        url: widget.streamUrl,
        httpHeaders: widget.httpHeaders,
        autoPlay: true,
      );
      _engineType = _engine!.engineType;
      _engineKey++;
      _currentStreamUrl = widget.streamUrl;

      // 恢复用户音量/亮度：持久化值优先，未设置过则读取系统当前值作为起点，
      // 保证 HUD 与系统实际状态对应（而不是从 100% 起跳）
      await _restoreVolumeBrightness();

      // 监听引擎状态
      _stateSub = _engine!.stateStream.listen((state) {
        if (mounted && !_isDisposed) {
          if (_streamTick++ % 20 == 0) AppLog.i("Player", "stateStream: playing=${state.isPlaying} pos=${state.position.inMilliseconds} dur=${state.duration.inMilliseconds}");
          // 先同步弹幕时钟与位置 —— 独立于 setState，任何后续异常都不影响弹幕时间轴
          try {
            _danmakuController.updateConfig(
              DanmakuRenderConfig.fromSettings(_cachedDisplay, playbackSpeed: _speed),
            );
            _danmakuController.updateActive(state.position.inMilliseconds);
          } catch (_) {}
          setState(() {
            _isPlaying = state.isPlaying;
            _isBuffering = state.isBuffering;
            if (_isPlaying) {
              _startProgressReporting();
              _danmakuController.start();
              if (!_playbackStartReported) {
                _playbackStartReported = true;
                try {
                  final svc = ref.read(currentMediaServerServiceProvider);
                  if (svc is EmbyService) {
                    svc.refreshPlaySession();
                    svc.reportPlaybackStart(_activeMedia.id);
                  }
                } catch (_) {}
              }
            } else {
              _progressTimer?.cancel();
              _uiUpdateTimer?.cancel();
              _danmakuController.pause();
            }
            _position = state.position;
            _lastStateTime = DateTime.now();
            // 对于 ISO/HDMV 等容器格式，MPV 可能报告错误的时长（0 或极大缩水）
            // 当服务器提供已知时长且引擎时长明显异常时，使用服务器时长
            final engineDur = state.duration;
            final serverDurSec = _activeMedia.duration; // 服务器提供的时长（秒）
            if (serverDurSec > 0 && engineDur > Duration.zero) {
              final serverDurMs = serverDurSec * 1000;
              // 如果引擎时长不到服务器时长的一半，可能是 ISO/HDMV 格式，使用服务器时长
              if (engineDur.inMilliseconds < serverDurMs * 0.6) {
                _duration = Duration(seconds: serverDurSec);
              } else {
                _duration = engineDur;
              }
            } else {
              _duration = engineDur;
            }
            // 续播：首次获取到正确时长后 seek 到上次位置
            if (!_resumeApplied && widget.resumePositionMs != null && _duration.inMilliseconds > widget.resumePositionMs!) {
              _resumeApplied = true;
              final resumePos = Duration(milliseconds: widget.resumePositionMs!);
              AppLog.i('Player', 'Resume → seek to ${resumePos.inMinutes}:${(resumePos.inSeconds % 60).toString().padLeft(2, '0')}');
              _engine?.seek(resumePos);
              // 弹幕游标同步到续播位置，避免续播后弹幕时间轴错位
              _danmakuController.seekTo(resumePos);
            }
            _buffer = state.buffer;
            _speed = state.speed;
            _volume = state.volume;
            // 硬件音量键/系统音量变化时同步持久化（防抖），下次切集/重开沿用
            if ((_volume - _lastSavedVolume).abs() > 0.02) _saveVolumeBrightness();
            _engineType = state.engineType;
          });
          // ── 跳过片头/片尾检测 ──
          _checkSkipState(state.position);

          // ── 下一集倒计时检测 ──
          _checkNextEpisode(state.position, state.duration);

          if (state.duration > Duration.zero && !_tracksLoaded) {
            _tracksLoaded = true;
            _loadTracks();
          }

          if (state.error?.isNotEmpty == true) {
            final err = state.error!.toLowerCase();
            if (err.contains('codec') || err.contains('audio') || err.contains('truehd') || err.contains('dts')) {
              if (!_showedAudioError) {
                _showedAudioError = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isDisposed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('音频解码失败，建议切换到其他音轨或ExoPlayer内核'),
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: '切换内核',
                          onPressed: () {
                            final manager = ref.read(playerManagerProvider);
                            manager.switchEngine(PlayerEngineType.exo);
                          },
                        ),
                      ),
                    );
                  }
                });
              }
            }
          }
        }
      });

      // 监听画幅模式变化
      _engine!.fitModeNotifier.addListener(_onFitModeChanged);

      // 应用用户配置的字幕样式（MPV 原生渲染 / ExoPlayer SubtitleView 渲染）
      _engine!.applySubtitleStyle(ref.read(playerSettingsProvider));

      // 监听引擎切换
      manager.engineChangeStream.listen((type) {
        if (mounted) {
          setState(() => _engineType = type);
        }
      });

      setState(() {});
    } catch (e) {
      AppLog.e('Player', '播放失败: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  Future<void> _loadTracks({int retry = 0}) async {
    if (_engine == null) return;
    try {
      final subtitles = await _engine!.getSubtitleTracks();
      final audios = await _engine!.getAudioTracks();
      if (mounted && !_isDisposed) {
        // 合并服务端字幕轨：转码流的字幕轨不进入 ExoPlayer currentTracks，
        // 导致面板只有"关闭"项、内嵌字幕永远选不到。
        // 服务端轨（MediaStreams）用 DeliveryUrl 下载后走 Flutter overlay 渲染。
        final serverSubs = (_activeMedia.subtitleTracks ?? const <Map<String, dynamic>>[])
            .where((t) {
              // 图片字幕（PGS/DVDsub 等）无法走文本渲染管线，不提供假选项
              final c = (t['Codec'] ?? '').toString().toLowerCase();
              return !['pgssub', 'dvdsub', 'hdmv_pgs_subtitle', 'dvb_subtitle', 's_avi'].contains(c);
            })
            .map((t) {
              final map = Map<String, dynamic>.from(t);
              map['server'] = true;
              // 标题沿用服务端 DisplayTitle/Title（规范命名），
              // 没有则用语言码，最后才是"字幕"占位
              map['title'] = trackDisplayTitle(map, prefix: '字幕');
              return map;
            })
            .toList();
        // ── 原生轨与服务端轨去重合并 ──
        // WEB-DL 的内嵌字幕轨同时出现在 ExoPlayer currentTracks（原生）和服务器
        // 字幕流（服务端）里。按标题去重不可靠（原生 label 与服务端 DisplayTitle
        // 不一致，标题有默认字样差异时全部重复），这里按 (语言,编码) 分组内顺序
        // 配对：同一流优先保留原生版本 —— Exo/mpv 直接从视频流读取内嵌字幕，
        // 不依赖服务器按需提取（FNNAS/Emby 对 mkv 内嵌字幕的提取端点实测挂起，
        // 服务端版会一直卡在"字幕加载中"）。标题沿用服务端 DisplayTitle 保持规范命名；
        // 原生独有/服务端独有（外挂 srt/ass 等）的轨各自保留。
        final serverGroups = <String, List<Map<String, dynamic>>>{};
        for (final s in serverSubs) {
          serverGroups.putIfAbsent(_subtitleMatchKey(s), () => []).add(s);
        }
        final consumed = <String, int>{};
        final pairedServer = <Map<String, dynamic>>{};
        final merged = <Map<String, dynamic>>[];
        for (var idx = 0; idx < subtitles.length; idx++) {
          final n = Map<String, dynamic>.from(subtitles[idx]);
          n['nativeIndex'] = idx; // 记录原生轨在引擎列表中的真实索引，排序后仍可正确切换
          final key = _subtitleMatchKey(n);
          final group = serverGroups[key];
          final used = consumed[key] ?? 0;
          if (group != null && used < group.length) {
            consumed[key] = used + 1;
            final server = group[used];
            pairedServer.add(server);
            // 沿用服务端 DisplayTitle（规范命名）避免面板出现 zh/en 短码；
            // 默认标记一并带到原生轨，自动启用逻辑照常工作
            n['title'] = server['title'] ?? n['title'];
            n['IsDefault'] =
                server['IsDefault'] ?? server['isDefault'] ?? n['isDefault'] ?? false;
            n['Language'] =
                server['Language'] ?? server['language'] ?? n['language'] ?? '';
          }
          merged.add(n);
        }
        // 服务端独有轨（外挂字幕等，无原生配对）追加
        for (final s in serverSubs) {
          if (!pairedServer.contains(s)) merged.add(s);
        }
        // 排序：默认轨最前 → 中文 → 英文 → 其他语言，避免 WEB-DL 多语言轨墙
        merged.sort((a, b) {
          int rank(Map<String, dynamic> t) {
            if (t['IsDefault'] == true || t['isDefault'] == true) return 0;
            final lang = (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
            if (const {'zho', 'chi', 'cmn', 'yue'}.contains(lang)) return 1;
            if (lang == 'eng') return 2;
            return 3;
          }

          return rank(a).compareTo(rank(b));
        });
        // 音轨合并服务端 MediaStreams：引擎轨按 (语言,编码) 配对服务端流，
        // 用服务端 DisplayTitle 规范命名（修复"音轨 1/2"）；保持引擎顺序，
        // 不追加服务端独有轨（引擎无对应原生轨时无法直接切换）。
        final serverAudios =
            _activeMedia.audioTracks ?? const <Map<String, dynamic>>[];
        final audiosMerged = _mergeServerAudioTracks(audios, serverAudios);
        setState(() {
          _fullSubtitleTracks = merged;
          // 面板默认只显示 中/英/默认轨，其余语言收进"显示全部"，
          // 避免 WEB-DL 多语言轨墙（用户已展开过则保持全量显示）
          _subtitleTracks = _filterSubtitleList(merged);
          _audioTracks = audiosMerged;
        });
        // 详情页预设的默认字幕语言（剧集"应用到全部"）：优先按语言匹配选中，
        // 找不到（该语言轨被过滤/不存在）时回落到下面的自动默认轨逻辑。
        final prefSubLang = ref.read(playerSettingsProvider).defaultSubtitleLang;
        if (_currentSubtitleIndex == -1 &&
            !_autoDefaultSubtitleApplied &&
            !_userDisabledSubtitles &&
            prefSubLang != null) {
          final prefIdx = _subtitleTracks.indexWhere((t) =>
              (t['Language'] ?? t['language'] ?? '')
                      .toString()
                      .toLowerCase() ==
                  prefSubLang.toLowerCase() &&
              t['isBitmap'] != true);
          if (prefIdx >= 0) {
            _autoDefaultSubtitleApplied = true;
            AppLog.i('Player', '按详情页偏好启用字幕轨: lang=$prefSubLang index=$prefIdx');
            _applySubtitleTrack(prefIdx);
          }
        }
        // 详情页预设的默认音轨语言：按语言匹配自动切换（未在播放器内手动选过时）
        final prefAudioLang = ref.read(playerSettingsProvider).defaultAudioLang;
        if (prefAudioLang != null &&
            _audioTracks.length > 1 &&
            _currentAudioIndex == 0) {
          String langOf(Map<String, dynamic> t) =>
              (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
          if (langOf(_audioTracks[0]) != prefAudioLang.toLowerCase()) {
            final prefAudioIdx = _audioTracks
                .indexWhere((t) => langOf(t) == prefAudioLang.toLowerCase());
            if (prefAudioIdx >= 0) {
              AppLog.i('Player', '按详情页偏好启用音轨: lang=$prefAudioLang index=$prefAudioIdx');
              _engine?.setAudioTrack(prefAudioIdx);
              setState(() => _currentAudioIndex = prefAudioIdx);
            }
          }
        }
        // 自动启用文件标记为默认的字幕轨（WEB-DL 通常默认简体中文）。
        // 原生轨（无需服务器提取、直接从视频流读取）就绪后优先选原生轨；
        // 原生轨始终未就绪（转码流/无内嵌轨）时等几轮后回退服务端轨。
        // 仅首次加载、用户未手动选择、且未显式关闭过字幕时生效
        // （视频带硬字幕的片源关闭一次后不再自动叠加）。
        final nativeReady = subtitles.isNotEmpty;
        final waitDone = retry >= 4; // 最多等 ~8s 让原生轨就绪
        if (_currentSubtitleIndex == -1 &&
            !_autoDefaultSubtitleApplied &&
            !_userDisabledSubtitles &&
            (nativeReady || waitDone)) {
          final defaultIdx = _subtitleTracks.indexWhere((t) =>
              (t['IsDefault'] == true || t['isDefault'] == true) &&
              t['isBitmap'] != true);
          if (defaultIdx >= 0) {
            _autoDefaultSubtitleApplied = true;
            final isNative = _subtitleTracks[defaultIdx]['server'] != true;
            AppLog.i('Player', '自动启用默认字幕轨: index=$defaultIdx (${isNative ? "原生" : "服务端"})');
            _applySubtitleTrack(defaultIdx);
          }
        } else if (nativeReady &&
            _autoDefaultSubtitleApplied &&
            !_userDisabledSubtitles &&
            !_externalSubtitleLoaded) {
          // 原生轨迟到：自动默认选中的服务端轨尚未加载成功（服务器提取可能挂起，
          // FNNAS/Emby 对 mkv 内嵌字幕实测 >90s 无响应），列表更新后改选原生默认轨。
          final defaultIdx = _subtitleTracks.indexWhere((t) =>
              t['server'] != true &&
              (t['IsDefault'] == true || t['isDefault'] == true) &&
              t['isBitmap'] != true);
          if (defaultIdx >= 0) {
            AppLog.i('Player', '原生轨就绪，改选原生默认轨: index=$defaultIdx');
            _applySubtitleTrack(defaultIdx);
          }
        }
        // 后台预取 默认/中文/英文 服务端字幕到本地缓存（不阻塞播放、不显示加载提示）。
        // 内嵌字幕已优先走原生渲染，这里只覆盖服务端独有轨（外挂 srt/ass 等）。
        if (!_subtitlePrefetched) {
          _prefetchServerSubtitles(merged);
        }
        // 检测位图字幕（PGS/DVDsub 等）并提示用户（只提示一次）
        final hasBitmap = subtitles.any((t) => t['isBitmap'] == true);
        if (hasBitmap && !_bitmapWarned) {
          _bitmapWarned = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('检测到图片字幕(PGS/SUP)，可能无法显示。建议使用外挂 SRT/ASS 字幕'),
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(label: '知道了', onPressed: () {}),
                ),
              );
            }
          });
        }
      }
      // ExoPlayer 文本轨可能远晚于时长才就绪（慢速 NAS/大文件索引解析），
      // 甚至首次拿到的列表为空后就不再刷新 → 内嵌字幕轨永远进不了面板。
      // 轮询直到出现文本轨（最多 ~30s）：一旦出现立即重建合并列表（上方 setState），
      // 原生轨优先的去重/自动启用逻辑随即生效。服务端字幕轨不受影响。
      if (subtitles.isEmpty && retry < 15 && mounted && !_isDisposed) {
        if (retry % 2 == 0) {
          AppLog.i('Player', '原生字幕轨未就绪，继续轮询 retry=$retry');
        }
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_isDisposed && _engine != null) {
            _loadTracks(retry: retry + 1);
          }
        });
      }
    } catch (_) {}
  }

  /// 字幕轨配对键：语言 + 编码（小写），用于原生轨与服务端轨去重配对
  String _subtitleMatchKey(Map<String, dynamic> t) {
    final lang = (t['language'] ?? t['Language'] ?? '').toString().toLowerCase();
    final codec = _normalizeSubtitleCodec((t['codec'] ?? t['Codec'] ?? '').toString());
    return '$lang|$codec';
  }

  /// 归一化字幕编码名：原生层返回 MIME（application/x-subrip），服务端返回短名
  /// （subrip），不归一化则同一条流配对不上、列表出现重复轨。
  String _normalizeSubtitleCodec(String codec) {
    final c = codec.toLowerCase().trim();
    if (c.isEmpty) return '';
    if (c.contains('subrip') || c == 'srt') return 'subrip';
    if (c.contains('ssa') || c == 'ass') return 'ass';
    if (c.contains('vtt') || c == 'webvtt') return 'vtt';
    if (c.contains('pgs') || c.contains('hdmv_pgs')) return 'pgs';
    if (c.contains('dvdsub') || c.contains('vobsub')) return 'dvdsub';
    if (c.contains('dvb')) return 'dvb';
    if (c.contains('cea') || c.contains('eia')) return 'cea';
    if (c == 'text' || c.contains('tx3g') || c.contains('mov_text')) return 'text';
    return c;
  }

  /// 音轨合并服务端 MediaStreams：按 (语言,编码) 配对，把服务端 DisplayTitle/
  /// Title 贴到原生轨上（面板与 toast 显示规范名称而非"音轨 1/2"）。
  /// 编码命名不一致（mpv 'dts-hdma' vs 服务端 'dts'）时按语言兑底配对。
  /// 保持引擎顺序且不追加服务端独有轨：列表索引 == 引擎索引，切换不受影响。
  List<Map<String, dynamic>> _mergeServerAudioTracks(
      List<Map<String, dynamic>> engineTracks,
      List<Map<String, dynamic>> serverTracks) {
    if (serverTracks.isEmpty) return engineTracks;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in serverTracks) {
      groups.putIfAbsent(_audioMatchKey(s), () => []).add(s);
    }
    final consumed = <String, int>{};
    Map<String, dynamic>? take(String key) {
      final g = groups[key];
      final used = consumed[key] ?? 0;
      if (g != null && used < g.length) {
        consumed[key] = used + 1;
        return g[used];
      }
      return null;
    }

    final result = <Map<String, dynamic>>[];
    for (final n in engineTracks) {
      final merged = Map<String, dynamic>.from(n);
      final lang = (merged['Language'] ?? merged['language'] ?? '')
          .toString()
          .toLowerCase();
      final codec =
          (merged['Codec'] ?? merged['codec'] ?? '').toString().toLowerCase();
      // 先按 (语言,编码) 精确配对；编码命名不一致（如 dts vs dts-hdma）时按语言兑底
      var server = take('$lang|$codec');
      if (server == null && codec.isNotEmpty) server = take('$lang|');
      if (server != null) {
        // 服务端有可读名（DisplayTitle/Title）就覆盖，否则用语言码；
        // 都没有则保留引擎原生名（如"音轨 1"）
        final serverName =
            (server['DisplayTitle'] ?? server['Title'] ?? '').toString().trim();
        if (serverName.isNotEmpty) {
          merged['title'] = serverName;
        } else {
          final serverLang =
              (server['Language'] ?? server['language'] ?? '').toString().trim();
          if (serverLang.isNotEmpty) merged['title'] = serverLang;
        }
        merged['Language'] =
            server['Language'] ?? server['language'] ?? merged['Language'] ?? '';
        merged['language'] =
            server['Language'] ?? server['language'] ?? merged['language'] ?? '';
        merged['codec'] =
            server['Codec']?.toString() ?? merged['codec'] ?? '';
        merged['Channels'] =
            server['Channels'] ?? merged['Channels'] ?? '';
        merged['channels'] =
            server['Channels'] ?? merged['channels'] ?? '';
      }
      result.add(merged);
    }
    return result;
  }

  /// 音轨配对键：语言 + 编码（小写），与字幕轨同套（服务端大写 key 兼容）
  String _audioMatchKey(Map<String, dynamic> t) {
    final lang = (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
    final codec = (t['Codec'] ?? t['codec'] ?? '').toString().toLowerCase();
    return '$lang|$codec';
  }

  /// 面板字幕列表：默认只保留 默认轨/中/英，其余语言收进"显示全部"占位轨。
  /// 占位轨索引在列表末尾，选择它时展开全量列表。
  List<Map<String, dynamic>> _filterSubtitleList(List<Map<String, dynamic>> full) {
    if (_showAllSubtitleTracks || full.length <= 3) return full;
    final preferred = full.where((t) {
      if (t['IsDefault'] == true || t['isDefault'] == true) return true;
      final lang = (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
      return const {'zho', 'chi', 'cmn', 'yue', 'eng'}.contains(lang);
    }).toList();
    if (preferred.length == full.length) return full;
    return [
      ...preferred,
      {
        'title': '显示全部 ${full.length} 条字幕',
        'showAll': true,
        'language': '',
      },
    ];
  }

  void _startProgressReporting() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _reportProgress();
    });
    // UI 更新 Timer：stateStream 频率可能太低，定期推算位置更新进度条
    if (_uiUpdateTimer == null || !_uiUpdateTimer!.isActive) {
      _lastStateTime = DateTime.now();
      _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!_isPlaying || _isDisposed || _isSeeking) return;
        final now = DateTime.now();
        final elapsed = now.difference(_lastStateTime).inMilliseconds;
        if (elapsed >= 500) {
          final oldPos = _position.inMilliseconds;
          setState(() {
            _position = Duration(milliseconds: oldPos + (elapsed * _speed).round());
          });
          // 500ms 定时器内检测跳过状态，确保片头按钮秒级响应
          _checkSkipState(_position);
          _lastStateTime = now;
          _uiTick++;
          if (_uiTick % 20 == 0) {
            AppLog.i('Player', '_uiUpdateTimer: pos=${_position.inMilliseconds}ms (was $oldPos, elapsed=${elapsed}ms, speed=$_speed)');
          }
        }
      });
    }
  }

  Future<void> _reportProgress() async {
    if (_engine == null || _isDisposed) return;
    final pos = _position.inMilliseconds;
    final dur = _duration.inMilliseconds;
    if (pos <= 0 || dur <= 0) return;
    if (pos - _lastReportedMs < 10000) return; // 10s 内去重
    _lastReportedMs = pos;
    AppLog.i('Player', '_reportProgress: pos=${pos}ms dur=${dur}ms');
    try {
      final svc = ref.read(currentMediaServerServiceProvider);
      if (svc is EmbyService) {
        await svc.reportPlaybackProgress(_activeMedia.id, pos, isPlaying: _isPlaying);
      } else if (svc != null) {
        await svc.markWatched(_activeMedia.id, positionMs: pos);
      }
    } catch (_) {}
  }

  void _onSeekEnd() {
    _lastReportedMs = 0;
    _reportProgress();
    // Seek 后清理弹幕状态，根据新位置重置扫描游标
    _danmakuController.seekTo(_position);
  }

  Future<void> _applyBrightness() async {
    try {
      await ScreenBrightness().setScreenBrightness(_brightness);
    } catch (_) {}
  }

  /// 恢复用户音量/亮度：优先取持久化值，未设置过则读取系统当前值作为起点，
  /// 保证应用内 HUD 与系统实际音量/亮度对应。
  Future<void> _restoreVolumeBrightness() async {
    await StorageService.ready;
    final savedBrightness = StorageService.getDouble('player_brightness');
    if (savedBrightness != null) {
      _brightness = savedBrightness.clamp(0.05, 1.0);
    } else {
      try {
        final sys = await ScreenBrightness().current;
        if (sys > 0) _brightness = sys.clamp(0.05, 1.0);
      } catch (_) {}
    }
    final savedVolume = StorageService.getDouble('player_volume');
    if (savedVolume != null) _volume = savedVolume.clamp(0.0, 1.0);
    _lastSavedVolume = _volume;
    await _applyBrightness();
    _engine?.setVolume(_volume);
  }

  /// 持久化音量/亮度（500ms 防抖，拖动/硬件音量键变化都会落到这里）
  void _saveVolumeBrightness() {
    _volBriSaveTimer?.cancel();
    _volBriSaveTimer = Timer(const Duration(milliseconds: 500), () async {
      _lastSavedVolume = _volume;
      await StorageService.setDouble('player_volume', _volume);
      await StorageService.setDouble('player_brightness', _brightness);
    });
  }

  /// 从 bangumi 详情响应中提取 bangumi 数据
  /// 兼容多种结构: { bangumi: {...} } / { data: { bangumi: {...} } } / { data: {...} }
  Map<String, dynamic>? _extractBangumiData(Map<String, dynamic> detail) {
    if (detail['bangumi'] is Map) {
      return detail['bangumi'] as Map<String, dynamic>;
    }
    if (detail['data'] is Map) {
      final data = detail['data'] as Map<String, dynamic>;
      if (data['bangumi'] is Map) {
        return data['bangumi'] as Map<String, dynamic>;
      }
      // data 本身就是 bangumi 数据（有 episodes 字段）
      if (data['episodes'] != null) {
        return data;
      }
    }
    // 响应本身就是 bangumi 数据
    if (detail['episodes'] != null) {
      return detail;
    }
    return null;
  }

  /// 匹配集号：兼容数字字符串 / int / 带前缀的格式
  bool _matchEpisodeNumber(dynamic ep, int target) {
    final num = ep['episodeNumber'] ?? ep['episode_number'] ?? ep['number'] ?? ep['ep'] ?? ep['index'];
    if (num == null) return false;
    final str = num.toString();
    return str == target.toString() || int.tryParse(str) == target;
  }

  /// 从标题中提取季号（中文/英文/数字格式）
  int? _extractSeasonFromTitle(String title) {
    final lower = title.toLowerCase();
    // 中文格式：第四季、第4季
    final cnMatch = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(lower);
    if (cnMatch != null) {
      return _parseChineseSeason(cnMatch.group(1)!);
    }
    // 英文格式：Season 4、S04
    final enMatch = RegExp(r'season\s*(\d+)|s(\d{1,2})(?!\d)').firstMatch(lower);
    if (enMatch != null) {
      return int.tryParse(enMatch.group(1) ?? enMatch.group(2) ?? '');
    }
    // 罗马数字：Ⅳ、Ⅳ
    return null;
  }

  int? _parseChineseSeason(String s) {
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10};
    if (map.containsKey(s)) return map[s];
    return int.tryParse(s);
  }

  /// 弹幕缓存目录
  Future<Directory> _danmakuCacheDir() async {
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory('${appCache.path}/danmaku');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<Danmaku>?> _getCachedDanmaku(String episodeId) async {
    try {
      final dir = await _danmakuCacheDir();
      final file = File('${dir.path}/${_safeFileName(episodeId)}.json');
      if (!await file.exists()) return null;
      // TTL: 24 小时
      final modified = await file.lastModified();
      if (DateTime.now().difference(modified) > const Duration(hours: 24)) {
        await file.delete();
        return null;
      }
      final json = await file.readAsString();
      final data = jsonDecode(json);
      final ver = data['v'] as int? ?? 1;
      if (ver < 4) {
        await file.delete();
        return null;
      }
      final list = (data['danmaku'] as List).map((j) => Danmaku.fromJson(j)).toList();
      AppLog.i('Danmaku', '文件缓存命中: ${list.length} 条弹幕');
      return list;
    } catch (e) {
      AppLog.d('Danmaku', '读取缓存失败: $e');
      return null;
    }
  }

  Future<void> _cacheDanmaku(String episodeId, List<Danmaku> danmaku) async {
    try {
      final dir = await _danmakuCacheDir();
      final file = File('${dir.path}/${_safeFileName(episodeId)}.json');
      await file.writeAsString(jsonEncode({
        'v': 4,
        'ts': DateTime.now().millisecondsSinceEpoch,
        'danmaku': danmaku.map((d) => d.toJson()).toList(),
      }));
      AppLog.i('Danmaku', '弹幕文件缓存写入: ${danmaku.length} 条');
      // 顺便清理过期缓存
      _cleanDanmakuCache();
    } catch (e) {
      AppLog.d('Danmaku', '写入缓存失败: $e');
    }
  }

  /// 清理超过 7 天的弹幕缓存文件
  Future<void> _cleanDanmakuCache() async {
    try {
      final dir = await _danmakuCacheDir();
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final entity in dir.list()) {
        if (entity is File) {
          final modified = await entity.lastModified();
          if (modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  /// 将 episodeId 转为安全的文件名
  String _safeFileName(String id) {
    return id.replaceAll(RegExp(r'[^\w\-]'), '_');
  }

  /// 等待引擎报告有效时长（用于弹幕匹配）
  ///
  /// 当 widget.media.duration 为 0 时，等待引擎 stateStream 返回有效的 duration。
  /// 最多等待 [timeoutMs] 毫秒，返回秒数；超时返回 0。
  Future<int> _waitForEngineDuration({int timeoutMs = 8000}) async {
    // 先检查引擎是否已有有效时长
    if (_engine != null && _engine!.currentState.duration > Duration.zero) {
      return _engine!.currentState.duration.inSeconds;
    }
    // 等待引擎 stateStream 报告有效时长
    final completer = Completer<int>();
    StreamSubscription? sub;
    Timer? timer;
    sub = _engine?.stateStream.listen((state) {
      if (state.duration > Duration.zero && !completer.isCompleted) {
        completer.complete(state.duration.inSeconds);
        timer?.cancel();
        sub?.cancel();
      }
    });
    timer = Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) {
        completer.complete(0);
        sub?.cancel();
      }
    });
    return completer.future;
  }

  /// 计算视频文件前 16KB 的 MD5 哈希（用于弹幕精准匹配）
  Future<String?> _computeVideoHash() async {
    try {
      final url = widget.streamUrl;
      if (url.isEmpty) return null;
      final headers = widget.httpHeaders ?? {};
      // 只请求前 16KB（rhttp 优先，Dio 回退）
      final bytes = await HttpClient.getBytes(
        url,
        headers: {...headers, 'Range': 'bytes=0-16383'},
        timeout: const Duration(seconds: 5),
      );
      if (bytes.isNotEmpty) {
        final digest = md5.convert(bytes);
        return digest.toString();
      }
    } catch (e) {
      AppLog.d('Danmaku', '视频哈希计算失败: $e');
    }
    return null;
  }

  /// 获取已记住的弹幕选择（mediaId → episodeId）
  Future<String?> _getRememberedDanmakuId() async {
    final mediaId = _activeMedia.id;
    try {
      final sel = await DbService.getDanmakuSelection(mediaId);
      if (sel != null) return sel;
    } catch (_) {}
    return StorageService.getString('danmaku_sel_$mediaId');
  }

  /// 记住弹幕选择
  Future<void> _rememberDanmakuId(String episodeId) async {
    final mediaId = _activeMedia.id;
    try { await DbService.setDanmakuSelection(mediaId, episodeId); } catch (_) {}
    await StorageService.setString('danmaku_sel_$mediaId', episodeId);
  }

  Future<void> _loadDanmaku() async {
    // 防止重复加载
    if (_danmakuLoading) {
      AppLog.d('Danmaku', '弹幕加载中，跳过重复请求');
      return;
    }
    _danmakuLoading = true;
    try {
      // 使用新的弹幕配置 Provider，不再读取旧的 StorageService key
      final configs = ref.read(danmakuConfigsProvider);
      final enabledConfigs = configs.where((c) => c.isEnabled && c.url.isNotEmpty).toList();

      if (enabledConfigs.isEmpty) {
        AppLog.i('Danmaku', '未配置弹幕服务或未启用，跳过加载');
        return;
      }

      for (int srcIdx = 0; srcIdx < enabledConfigs.length; srcIdx++) {
        final enabledConfig = enabledConfigs[srcIdx];
        final isLastSource = srcIdx == enabledConfigs.length - 1;
        try {

      String rawUrl = enabledConfig.url.trim();
      String? apiKey = enabledConfig.apiKey;
      
      // 智能识别：如果 URL 里包含路径段（用户可能把完整 API 地址填进去了）
      final extractedKey = DanmakuService.extractApiKeyFromUrl(rawUrl);
      if (extractedKey != null && (apiKey == null || apiKey.isEmpty)) {
        apiKey = extractedKey;
      }
      
      // 使用标题解析逻辑构建更好的文件名
      final isEpisode = _activeMedia.type == MediaType.episode;
      final rawTitle = isEpisode && _activeMedia.seriesTitle != null
        ? _activeMedia.seriesTitle!
        : _activeMedia.title;
      final season = _activeMedia.seasonNumber;
      final episode = _activeMedia.episodeNumber;

      AppLog.i('Danmaku', '开始加载弹幕: $rawTitle, baseUrl=${DanmakuService.normalizeBaseUrl(rawUrl)}, apiKey=${apiKey != null ? '***' : 'null'}');

      final danmakuService = DanmakuService(baseUrl: rawUrl, apiKey: apiKey);
      final connected = await danmakuService.testConnection();
      if (!connected) {
        AppLog.w('Danmaku', '弹幕服务[${enabledConfig.name}]连接失败，尝试下一个源');
        if (isLastSource) return;
        continue;
      }
      AppLog.i('Danmaku', '弹幕服务连接成功');

      String fileName = rawTitle;
      if (season != null && episode != null) {
        fileName = '$rawTitle S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
      } else if (episode != null) {
        fileName = '$rawTitle E${episode.toString().padLeft(2, '0')}';
      }
      AppLog.i('Danmaku', '匹配文件名: $fileName, 时长: ${_activeMedia.duration}s');

      // 0. 检查是否有已记住的弹幕选择（跳过匹配流程）
      String? episodeId = await _getRememberedDanmakuId();
      if (episodeId != null) {
        AppLog.i('Danmaku', '使用已记住的弹幕选择: episodeId=$episodeId');
      }

      // 计算视频文件哈希（用于精准匹配）
      String? fileHash;
      if (episodeId == null) {
        fileHash = await _computeVideoHash();
        if (fileHash != null) {
          AppLog.i('Danmaku', '视频哈希: $fileHash');
        }
      }

      // 1. 优先使用 v2 match API（精准匹配，含哈希）
      if (episodeId == null) {
        // 如果 media 没有时长信息，等待引擎报告真实时长（最多 8 秒）
        int durationSec = _activeMedia.duration > 0 ? _activeMedia.duration : 0;
        if (durationSec == 0) {
          durationSec = await _waitForEngineDuration(timeoutMs: 8000);
          if (durationSec > 0) {
            AppLog.i('Danmaku', '引擎报告时长: ${durationSec}s');
          }
        }
        final durationParam = durationSec > 0 ? durationSec : null;
        DanmakuMatch? match = await danmakuService.matchV2(
          fileName: fileName,
          fileHash: fileHash,
          duration: durationParam,
        );
        if (match != null) {
          episodeId = match.episodeId;
          AppLog.i('Danmaku', '精准匹配成功: episodeId=$episodeId');
        } else {
          AppLog.i('Danmaku', '精准匹配失败，尝试搜索...');
        }
      }

      // 2. 失败则用搜索 API（模糊匹配）
      if (episodeId == null) {
        // 先获取搜索结果
        final matches = await danmakuService.searchDanmaku(rawTitle);
        AppLog.i('Danmaku', '搜索结果: ${matches.length} 条');
        if (matches.isNotEmpty) {
          // 标题相似度校验：避免匹配到不相关的番剧
          // 例如搜索"肖申克的救赎"不应匹配到完全不相关的结果
          DanmakuMatch? bestMatch;

          // 先按标题相似度过滤：结果标题必须包含搜索关键词（或关键词包含结果标题的核心部分）
          final similarMatches = matches.where((m) {
            final mTitle = m.title.toLowerCase();
            final query = rawTitle.toLowerCase();
            // 结果标题包含搜索词，或搜索词包含结果标题
            if (mTitle.contains(query) || query.contains(mTitle)) return true;
            // 去除年份/括号等后缀后再比较核心标题
            final coreQuery = query.replaceAll(RegExp(r'[\s\(（\[\【].*'), '').trim();
            final coreMatch = mTitle.replaceAll(RegExp(r'[\s\(（\[\【第].*'), '').trim();
            if (coreQuery.isNotEmpty && coreMatch.isNotEmpty) {
              if (coreMatch.contains(coreQuery) || coreQuery.contains(coreMatch)) return true;
              // 至少前4个字符匹配
              final minLen = coreQuery.length < coreMatch.length ? coreQuery.length : coreMatch.length;
              if (minLen >= 2 && coreQuery.substring(0, minLen) == coreMatch.substring(0, minLen)) return true;
            }
            return false;
          }).toList();

          if (similarMatches.isEmpty) {
            AppLog.w('Danmaku', '搜索结果无标题匹配，跳过（rawTitle=$rawTitle, 首条=${matches.first.title}）');
          } else {
            bestMatch = similarMatches.first;
            if (season != null) {
              for (final m in similarMatches) {
                final s = _extractSeasonFromTitle(m.title);
                if (s == season) {
                  bestMatch = m;
                  AppLog.i('Danmaku', '季度匹配成功: title=${m.title}, season=$season');
                  break;
                }
              }
            }
          }

          if (bestMatch != null) {
            final seriesId = bestMatch.bangumiId;
            AppLog.i('Danmaku', '使用匹配: title=${bestMatch.title}, seriesId=$seriesId');

            // 无论是电影还是剧集，都优先尝试通过 bangumi 详情获取精确 episodeId
            // 因为搜索结果返回的 episodeId 实际是 bangumiId/animeId
            try {
              AppLog.i('Danmaku', 'Bangumi请求: seriesId=$seriesId');
              final detail = await danmakuService.getBangumiDetail(seriesId);
              if (detail != null) {
                // 兼容多种返回结构: bangumi / data.bangumi / data
                final bangumi = _extractBangumiData(detail);
                final episodes = (bangumi?['episodes'] as List?) ?? [];
                AppLog.i('Danmaku', 'Bangumi响应: episodes=${episodes.length}');

                if (episodes.isNotEmpty) {
                  final targetEpisode = episode ?? 1; // 默认第1集
                  final ep = episodes.firstWhere(
                    (e) => _matchEpisodeNumber(e, targetEpisode),
                    orElse: () => episodes.first,
                  ) as Map;
                  episodeId = (ep['episodeId'] ?? ep['episode_id'] ?? ep['id'])?.toString();
                  if (episodeId != null && episodeId.isNotEmpty) {
                    AppLog.i('Danmaku', 'Bangumi解析成功: episodeId=$episodeId (第$targetEpisode集)');
                  }
                }
              }
            } catch (e) {
              AppLog.w('Danmaku', 'Bangumi解析失败: $e');
            }

            // fallback: bangumi 返回空时直接使用 seriesId
            episodeId ??= seriesId;
          }
        }
      }

      // 3. 用 episodeId 获取弹幕
      if (episodeId != null) {
        // 记住弹幕选择，下次直接跳过匹配
        _rememberDanmakuId(episodeId);
        // 先查缓存
        final cached = await _getCachedDanmaku(episodeId);
        if (cached != null) {
          _preprocessDanmaku(cached);
          if (mounted) {
            _danmakuController.setData(cached);
            _danmakuController.updateActive(_position.inMilliseconds);
          }
          AppLog.i('Danmaku', '使用缓存弹幕: ${cached.length} 条');
          break; // 缓存命中，跳出源循环
        }
        final danmaku = await danmakuService.getDanmaku(
          episodeId: episodeId,
          episode: episode,
        );
        AppLog.i('Danmaku', '获取弹幕成功: ${danmaku.length} 条');
        if (danmaku.isNotEmpty) {
          _cacheDanmaku(episodeId, danmaku);
        }
        if (mounted) {
          _preprocessDanmaku(danmaku);
          _danmakuController.setData(danmaku);
          _danmakuController.updateActive(_position.inMilliseconds);
        }
        AppLog.i('Danmaku', '弹幕源[${enabledConfig.name}]加载成功: ${danmaku.length}条');
        break; // 成功加载，跳出源循环
      } else {
        AppLog.w('Danmaku', '弹幕源[${enabledConfig.name}]未找到匹配，${isLastSource ? "已无更多源" : "尝试下一个源"}');
      }
        } catch (e) {
          AppLog.e('Danmaku', '加载弹幕失败[${enabledConfig.name}]: $e');
          if (isLastSource) rethrow;
        }
      } // end of for loop
    } catch (e) {
      AppLog.e('Danmaku', '所有弹幕源均失败: $e');
    } finally {
      _danmakuLoading = false;
    }
  }

  /// 弹幕数据预处理（排序 → 过滤空文本 → 屏蔽词 → 去重合并）
  List<Danmaku> _preprocessDanmaku(List<Danmaku> danmaku) {
    // 1. 排序
    danmaku.sort((a, b) => a.time.compareTo(b.time));
    // 2. 过滤空文本
    danmaku.removeWhere((d) => d.text.isEmpty || d.text.trim().isEmpty);
    // 3. 屏蔽词过滤
    final blockKeywords = ref.read(danmakuDisplayProvider).blockKeywords;
    if (blockKeywords.isNotEmpty) {
      final lowerKeywords = blockKeywords.map((k) => k.toLowerCase()).toList();
      danmaku.removeWhere((d) {
        final lowerText = d.text.toLowerCase();
        return lowerKeywords.any((kw) => lowerText.contains(kw));
      });
    }
    // 4. 去重合并：500ms 内相同文本只保留第一条
    if (danmaku.length > 1) {
      final seen = <String>{};
      danmaku.removeWhere((d) {
        final timeGroup = d.time ~/ 500;
        final key = '${d.text}_$timeGroup';
        if (seen.contains(key)) return true;
        seen.add(key);
        return false;
      });
    }
    // 5. 简繁转换
    final charConversion = ref.read(danmakuDisplayProvider).charConversion;
    if (charConversion != 'none' && danmaku.isNotEmpty) {
      for (int i = 0; i < danmaku.length; i++) {
        final d = danmaku[i];
        final converted = charConversion == 's2t'
            ? ChineseConverter.toTraditional(d.text)
            : ChineseConverter.toSimplified(d.text);
        if (converted != d.text) {
          danmaku[i] = Danmaku(
            id: d.id,
            text: converted,
            time: d.time,
            color: d.color,
            type: d.type,
            author: d.author,
            fontSize: d.fontSize,
          );
        }
      }
    }
    return danmaku;
  }

  /// 锁定/解锁播放器：锁定时隐藏控制层并禁用全部手势
  void _toggleLock() {
    setState(() {
      _controlsLocked = !_controlsLocked;
      if (_controlsLocked) _controlsVisible = false;
    });
    if (_controlsLocked) {
      _closeAllPanels();
      _hideTimer?.cancel();
    } else {
      _startHideTimer();
    }
  }

  /// 锁定/解锁按钮（常驻右缘）：同一个按钮原地切换状态，不额外生成解锁按钮。
  /// 未锁定 = 半透明空心（锁开）；锁定 = 主题色填充描边（锁闭），点击即解锁。
  Widget _buildLockToggle() {
    final locked = _controlsLocked;
    return TapFeedback(
      onTap: _toggleLock,
      scaleOnPress: 0.9,
      springBack: true,
      highlightColor: Colors.transparent,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: locked
              ? AppTheme.primary.withValues(alpha: 0.30)
              : Colors.black.withValues(alpha: 0.28),
          shape: BoxShape.circle,
          border: locked ? Border.all(color: AppTheme.primary, width: 1.2) : null,
        ),
        child: Center(
          child: Icon(
            locked ? Icons.lock_rounded : Icons.lock_open_rounded,
            color: locked ? AppTheme.primary : Colors.white.withValues(alpha: 0.6),
            size: 18,
          ),
        ),
      ),
    );
  }

  void _toggleControls() {
    // 如果有面板打开，点击只关闭面板，不切换控制栏
    if (_hasAnyPanelOpen) {
      _closeAllPanels();
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    _syncControlsAnim();
    if (_controlsVisible) _startHideTimer();
  }

  /// 把 _controlsVisible 同步到滑动/淡出动画控制器
  void _syncControlsAnim() {
    if (_controlsVisible) {
      _controlsController.forward();
    } else {
      _controlsController.reverse();
    }
  }

  /// 是否有任意面板打开（剧集面板 / 任何右侧滑入面板）
  bool get _hasAnyPanelOpen => _showEpisodePanel || _rightPanelType != null;

  /// 关闭所有面板
  void _closeAllPanels() {
    if (_showEpisodePanel) {
      _animateCloseEpisodePanel();
    } else {
      setState(() => _rightPanelType = null);
    }
  }

  /// 选集面板关闭动画
  void _animateCloseEpisodePanel() {
    if (_episodePanelController.isAnimating || _showEpisodePanel) {
      _episodePanelController.reverse().then((_) {
        if (mounted) setState(() => _showEpisodePanel = false);
      });
    }
  }

  /// 切换面板（仅剧集面板使用）
  void _togglePanel(String panel) {
    if (panel == 'episode') {
      if (_showEpisodePanel) {
        _animateCloseEpisodePanel();
      } else {
        setState(() => _showEpisodePanel = true);
        _episodePanelController.forward();
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
        _syncControlsAnim();
      }
    });
  }

  void _togglePlay() {
    if (_isPlaying) {
      _engine?.pause();
    } else {
      _engine?.play();
    }
  }

  /// 通用底部抽屉（毛玻璃风格，与 TrackSelectorSheet 一致）
  void _showOptionSheet({
    required String title,
    required List<Map<String, dynamic>> options,
    required int currentIndex,
    required void Function(int index) onSelect,
  }) {
    _closeAllPanels();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      useSafeArea: true,
      builder: (_) => _OptionBottomSheet(
        title: title,
        options: options,
        currentIndex: currentIndex,
        onSelect: onSelect,
      ),
    );
  }

  /// 播放速度选择
  void _openSpeedSheet() {
    _showOptionSheet(
      title: '播放速度',
      options: _speeds.map((s) => {'label': '${s}x'}).toList(),
      currentIndex: _currentSpeedIndex,
      onSelect: (i) {
        _currentSpeedIndex = i;
        _speed = _speeds[i];
        _engine?.setSpeed(_speed);
        setState(() {});
      },
    );
  }

  String _qualityLabel(String q) => switch (q) {
        'auto' => '自动',
        '720p' => '720P',
        '1080p' => '1080P',
        '4k' => '4K',
        'original' => '原画',
        _ => q,
      };

  /// 切换画质：重新请求转码流（带码率上限）并保留播放进度
  Future<void> _setQuality(String q) async {
    if (q == _currentQuality) return;
    final svc = widget.service;
    if (svc == null) {
      setState(() => _currentQuality = q);
      return;
    }
    final oldQ = _currentQuality;
    setState(() => _currentQuality = q);
    try {
      final ps = ref.read(playerSettingsProvider);
      final url = await svc.getStreamUrl(_activeMedia.id, quality: q, burnInSubtitle: ps.burnInSubtitle);
      if (!mounted) return;
      _currentStreamUrl = url; // 记录新画质流地址（MediaSourceId 可能随转码源变化）
      final pos = _position;
      final wasPlaying = _isPlaying;
      await _engine?.stop();
      await _engine?.open(url: url, httpHeaders: svc.streamHeaders, autoPlay: false);
      if (pos > Duration.zero) await _engine?.seek(pos);
      if (wasPlaying) await _engine?.play();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已切换画质：${_qualityLabel(q)}'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      AppLog.w('Player', '切换画质失败: $e');
      if (mounted) {
        setState(() => _currentQuality = oldQ);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('画质切换失败：$e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  /// 画幅模式选择
  void _openFitSheet() {
    _showOptionSheet(
      title: '画幅模式',
      options: _fitModeOptions.map((e) => {'label': e.label}).toList(),
      currentIndex: _fitModeOptions.indexWhere((o) => o.mode == _currentFitMode),
      onSelect: (i) => _setFitMode(_fitModeOptions[i].mode),
    );
  }

  /// 加载外挂字幕文件（Phase 2）
  /// ExoPlayer 引擎使用 Flutter 层叠加渲染
  /// MPV 引擎通过 libmpv sub-files 加载到原生层
  Future<void> _loadExternalSubtitle() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['srt', 'vtt', 'ass', 'ssa'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null) return;

      await _applyExternalSubtitleFile(path);
    } catch (e) {
      AppLog.e('Player', '加载外挂字幕异常: $e');
      if (mounted) _showTopToast('加载字幕异常: $e');
    }
  }

  /// 在线搜索字幕（OpenSubtitles）
  Future<void> _openOnlineSubtitleSearch() async {
    if (!OpenSubtitlesService.isConfigured) {
      _showTopToast('请先在 设置 → 播放设置 → 在线字幕 中配置 OpenSubtitles 账号与 API Key');
      return;
    }
    _closeAllPanels();
    final isEpisode = _activeMedia.type == MediaType.episode;
    if (!mounted) return;
    await OnlineSubtitleSearchSheet.show(
      context,
      service: OpenSubtitlesService(),
      initialQuery: _activeMedia.seriesTitle ?? _activeMedia.title,
      season: isEpisode ? _activeMedia.seasonNumber : null,
      episode: isEpisode ? _activeMedia.episodeNumber : null,
      onDownloaded: _applyExternalSubtitleFile,
    );
  }

  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  /// 顶部浮动轻提示：不遮底部字幕/进度条，1.5s 自动淡出
  void _showTopToast(String msg) {
    _toastTimer?.cancel();
    _toastEntry?.remove();
    final overlay = Overlay.of(context);
    final topInset = MediaQuery.of(context).padding.top + 12;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => Positioned(
        top: topInset,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                msg,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
    _toastTimer = Timer(const Duration(milliseconds: 1500), () {
      entry.remove();
      if (_toastEntry == entry) _toastEntry = null;
    });
  }

  /// 把字幕文件交给引擎加载（本地挑选 / 在线下载共用）
  Future<void> _applyExternalSubtitleFile(String path) async {
    if (!mounted) return;
    final success = await _engine?.loadExternalSubtitle(path) ?? false;
    if (!mounted) return;

    if (success) {
      // 双保险：外挂渲染前再次关闭原生字幕轨，防止任何路径重新启用文本轨导致双层。
      // 仅 ExoPlayer 需要（外挂走 Flutter overlay，原生 SubtitleView 必须关闭）；
      // MPV 的外挂由 libmpv 原生渲染（sub-files），这里 sid=no 会把刚加载的外挂也隐藏掉。
      if (_engineType == PlayerEngineType.exo) {
        await _engine?.setSubtitleTrack(-1);
      }
      // ExoPlayer 引擎：更新外挂字幕状态，触发 UI 叠加层渲染
      final manager = _engine?.externalSubtitleManager;
      if (manager != null) {
        setState(() {
          _externalSubtitleCues = manager.cues;
          _externalSubtitleLoaded = true;
        });
      }
      // 轻提示：顶部浮动（去掉条数等调试信息，不遮底部字幕/进度条）
      _showTopToast('字幕已加载');
    } else {
      _showTopToast('字幕加载失败：${_engine?.externalSubtitleManager?.error ?? "未知错误"}');
    }
  }

  /// 字幕轨道选择统一处理（右侧面板 / 底部 sheet 共用）
  /// -1: 关闭；i >= 0: _subtitleTracks[i]（可能是原生轨或服务端轨）
  Future<void> _applySubtitleTrack(int i) async {
    if (i < 0) {
      // 关闭字幕：记住用户显式关闭的选择，本会话不再自动启用默认轨
      // （视频带硬字幕的片源，自动叠加软字幕会产生双层）
      _userDisabledSubtitles = true;
      _autoDefaultSubtitleApplied = true;
      if (_currentSubtitleIndex >= 0) {
        await _engine?.setSubtitleTrack(-1);
      }
      if (mounted) {
        setState(() {
          _currentSubtitleIndex = -1;
          _externalSubtitleLoaded = false;
          _externalSubtitleCues = [];
        });
      }
      return;
    }
    if (i >= _subtitleTracks.length) return;
    final track = _subtitleTracks[i];
    // "显示全部 N 条字幕"占位轨：展开全量列表
    if (track['showAll'] == true) {
      setState(() {
        _showAllSubtitleTracks = true;
        _subtitleTracks = _filterSubtitleList(_fullSubtitleTracks);
      });
      _showTopToast('已显示全部字幕轨');
      return;
    }
    // 用户主动选择了某条字幕轨 → 取消"已关闭"记忆
    _userDisabledSubtitles = false;
    final isServer = track['server'] == true;
    if (isServer) {
      // 服务端字幕轨：转码流的内嵌轨不进入引擎 currentTracks，
      // 下载字幕数据后走外挂字幕管线（Flutter overlay / mpv 原生）渲染。
      // 先关闭原生字幕轨，避免原生 SubtitleView 与外挂 overlay 双层渲染同一句对白
      await _engine?.setSubtitleTrack(-1);
      final prevIndex = _currentSubtitleIndex;
      setState(() {
        _currentSubtitleIndex = i;
        _serverSubtitleLoading = true;
      });
      final path = await _downloadServerSubtitle(track);
      if (!mounted) return;
      setState(() => _serverSubtitleLoading = false);
      if (path != null) {
        await _applyExternalSubtitleFile(path);
      } else if (mounted) {
        // 服务端字幕下载失败：若该服务端轨有同语言同编码的原生配对轨
        // （内嵌字幕，Exo 直接从视频流读取、不依赖服务器提取），回退原生轨。
        final nativeIdx = track['nativeIndex'];
        if (nativeIdx is int && nativeIdx >= 0 && _engineType == PlayerEngineType.exo) {
          await _engine?.setSubtitleTrack(nativeIdx);
          if (mounted) {
            setState(() {
              _currentSubtitleIndex = i;
              _externalSubtitleLoaded = false;
              _externalSubtitleCues = [];
            });
          }
          _showTopToast('服务端字幕不可用，已切换原生字幕轨');
          AppLog.w('Player', '服务端字幕下载失败，回退原生轨: nativeIndex=$nativeIdx');
          return;
        }
        // 失败：回退选中态，并给出具体原因便于排查
        setState(() => _currentSubtitleIndex = prevIndex);
        final reason = _subtitleDownloadError.isNotEmpty
            ? _subtitleDownloadError
            : '请检查服务器连接';
        _showTopToast('字幕下载失败：$reason');
      }
      return;
    }
    // 原生轨（排序/去重后 merged 索引 ≠ 引擎原生索引，用记录的真实索引切换）
    final nativeIdx = track['nativeIndex'];
    await _engine?.setSubtitleTrack(nativeIdx is int ? nativeIdx : i);
    if (mounted) {
      setState(() {
        _currentSubtitleIndex = i;
        // 切换原生轨时清除外挂字幕状态
        _externalSubtitleLoaded = false;
        _externalSubtitleCues = [];
      });
      // 操作反馈：原生轨切换没有下载流程，用户看不到任何提示会误以为没生效
      final title = track['title']?.toString() ?? '字幕 $i';
      _showTopToast('字幕：$title');
    }
  }

  /// 下载服务端字幕轨到本地缓存，返回文件路径；失败返回 null（原因写入 [_subtitleDownloadError]）
  /// 缓存键 = itemId|MediaSourceId|index|ext：同一字幕只下载一次，
  /// Emby 首次按需提取内嵌字幕可能要几十秒，缓存后重播/切回秒出。
  String _subtitleDownloadError = '';
  Future<String?> _downloadServerSubtitle(Map<String, dynamic> track) async {
    _subtitleDownloadError = '';
    try {
      final svc = widget.service;
      if (svc == null) return null;
      final codec = (track['Codec'] ?? track['codec'] ?? '').toString().toLowerCase();
      final ext = switch (codec) {
        'ass' || 'ssa' => 'ass',
        'vtt' || 'webvtt' => 'vtt',
        _ => 'srt',
      };
      final itemId = _activeMedia.id;
      final msId = Uri.tryParse(_currentStreamUrl)?.queryParameters['MediaSourceId'] ?? '';
      // 优先用服务端给的 DeliveryUrl；但 Emby/Jellyfin 的 Item 详情里 MediaStream
      // 常常不带 DeliveryUrl（只有 PlaybackInfo 才填充），此时按已知 id 自行构造，
      // 指向同一个官方字幕流端点：/Videos/{itemId}/{mediaSourceId}/Subtitles/{index}/Stream.{ext}
      var deliveryUrl = track['DeliveryUrl']?.toString() ?? '';
      if (deliveryUrl.isEmpty) {
        final index = (track['Index'] ?? track['index'])?.toString() ?? '0';
        deliveryUrl = '/Videos/$itemId/${msId.isEmpty ? itemId : msId}/Subtitles/$index/Stream.$ext';
        AppLog.d('Player', 'DeliveryUrl 为空，构造字幕 URL: $deliveryUrl (codec=$codec)');
      }
      final fullUrl = deliveryUrl.startsWith('http')
          ? deliveryUrl
          : '${svc.baseUrl}$deliveryUrl';
      // 认证：请求头 + api_key 查询参数双保险。部分服务器/代理会剥离自定义头，
      // 而图片一直靠 URL 里的 api_key 工作，字幕下载也应同样兼容。
      final apiKey = (svc is EmbyService) ? svc.apiKey : '';
      final headers = Map<String, String>.from(svc.streamHeaders);
      var url = fullUrl;
      if (apiKey.isNotEmpty && !Uri.parse(url).queryParameters.containsKey('api_key')) {
        url = '${url}${url.contains('?') ? '&' : '?'}api_key=$apiKey';
      }
      // 本地缓存命中直接返回，不再请求服务器
      final index = (track['Index'] ?? track['index'])?.toString() ?? '0';
      final cacheKey = md5.convert(utf8.encode('$itemId|$msId|$index|$ext')).toString();
      final cacheDir = Directory('${(await getApplicationSupportDirectory()).path}/subtitle_cache');
      if (!await cacheDir.exists()) await cacheDir.create(recursive: true);
      final cacheFile = File('${cacheDir.path}/$cacheKey.$ext');
      if (await cacheFile.exists() && await cacheFile.length() > 0) {
        AppLog.i('Player', '服务端字幕命中本地缓存: $cacheKey.$ext');
        return cacheFile.path;
      }
      // 下载（接收超时 60s：NAS/Emby 首次提取内嵌字幕可能极慢，默认 15s 会误判失败；
      // 超时后等 3s 重试一次——第一次请求往往已在服务器侧触发提取，重试即命中）
      var bytes = await _fetchSubtitleBytes(url, headers);
      // 兜底：若流 URL 缺 MediaSourceId 导致用了 itemId 当 mediaSourceId（部分
      // 服务器对错误路径返回空 200），换真实 MediaSourceId 形式重试一次。
      if (bytes.isEmpty && deliveryUrl.contains('/Videos/')) {
        if (msId.isNotEmpty && !deliveryUrl.contains('/$msId/')) {
          final altPath = '/Videos/$itemId/$msId/Subtitles/$index/Stream.$ext';
          final altUrl = '${svc.baseUrl}$altPath';
          AppLog.w('Player', '字幕空响应，回退重试: $altPath');
          bytes = await _fetchSubtitleBytes(altUrl, headers);
        }
      }
      if (bytes.isEmpty) {
        _subtitleDownloadError = '服务器返回空内容';
        AppLog.e('Player', '服务端字幕下载失败: 空内容 url=$url');
        return null;
      }
      await cacheFile.writeAsBytes(bytes);
      AppLog.i('Player', '服务端字幕已下载: ${bytes.length} bytes, codec=$codec (缓存 $cacheKey.$ext)');
      return cacheFile.path;
    } catch (e) {
      AppLog.e('Player', '服务端字幕下载失败: $e');
      if (e is DioException) {
        _subtitleDownloadError = 'HTTP ${e.response?.statusCode ?? '?'} ${e.type.name}';
      } else {
        _subtitleDownloadError = e.toString();
      }
      return null;
    }
  }  /// 字幕下载：单次 30s 接收超时（不重试）。内嵌字幕轨已优先走原生渲染，不经过这里；
  /// 服务端独有轨（外挂 srt/ass）正常应快速返回，30s 未响应说明服务器提取挂起
  /// （FNNAS/Emby 对 mkv 内嵌字幕实测 >90s 无响应），及时放弃避免"加载中"无限等待。
  Future<List<int>> _fetchSubtitleBytes(String url, Map<String, String> headers) async {
    return HttpClient.getBytes(url, headers: headers, timeout: const Duration(seconds: 30));
  }

  /// 后台预取常用服务端字幕（默认轨 + 中文 + 英文，最多 3 条）到本地缓存。
  /// 顺序下载避免同时打爆 NAS；不阻塞播放、不显示"字幕加载中"提示（那是用户主动
  /// 切换时才有的反馈）；已缓存/位图字幕自动跳过（[_downloadServerSubtitle] 内部处理）。
  /// 轨道尚未就绪时（首帧空列表）直接返回且不置位标志，留给 _loadTracks 重试。
  Future<void> _prefetchServerSubtitles(List<Map<String, dynamic>> tracks) async {
    if (_isDisposed || widget.service == null) return;
    final wanted = <Map<String, dynamic>>[];
    for (final t in tracks) {
      if (t['server'] != true) continue; // 只预取服务端轨（可下载走统一管线）
      if (t['isBitmap'] == true) continue; // 位图字幕（PGS/SUP）无法渲染，跳过
      final lang = (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
      final isDefault = t['IsDefault'] == true || t['isDefault'] == true;
      if (isDefault ||
          const {'zho', 'chi', 'cmn', 'yue'}.contains(lang) ||
          lang == 'eng') {
        wanted.add(t);
      }
      if (wanted.length >= 3) break; // 默认 + 中文 + 英文 三条即可
    }
    if (wanted.isEmpty) return;
    _subtitlePrefetched = true; // 真正开始预取才置位，空列表时不影响后续重试
    final langs = wanted.map((t) => (t['Language'] ?? t['language'] ?? '?')).join(',');
    AppLog.i('Player', '后台预取字幕($langs): ${wanted.length} 条');
    for (final t in wanted) {
      if (_isDisposed) return;
      try {
        await _downloadServerSubtitle(t);
      } catch (e) {
        AppLog.w('Player', '后台预取字幕失败: $e');
      }
    }
    if (!_isDisposed) AppLog.i('Player', '后台预取字幕完成');
  }

  /// 打开/切换右侧面板（弹幕/更多）：同面板再次点击 = 关闭；其他面板打开时直接切换；
  /// 选集面板打开时先收起。顶栏「弹」「⋯」共用。
  void _toggleRightPanel(String type) {
    if (_showEpisodePanel) _animateCloseEpisodePanel();
    setState(() {
      _rightPanelType = _rightPanelType == type ? null : type;
    });
  }

  /// 渲染"更多"面板及其二级选项（画质/切换内核/字幕样式），全部右侧滑入、
  /// 带 ‹ 返回宫格。外挂字幕/在线搜索为系统弹窗，直接关闭面板后调用。
  Widget _buildMoreRightPanel() {
    final type = _rightPanelType;
    if (type == 'quality') {
      const options = ['auto', '720p', '1080p', '4k', 'original'];
      return RightOptionListPanel(
        title: '画质',
        options: options.map((q) => {'label': _qualityLabel(q)}).toList(),
        currentIndex: options.indexOf(_currentQuality).clamp(0, options.length - 1),
        onBack: () => setState(() => _rightPanelType = 'more'),
        onClose: () => setState(() => _rightPanelType = null),
        onSelect: (i) {
          setState(() => _rightPanelType = null);
          _setQuality(options[i]);
        },
      );
    }
    if (type == 'engine') {
      final engines = PlayerEngineType.values;
      return RightOptionListPanel(
        title: '切换内核',
        options: engines.map((e) => {'label': e.label}).toList(),
        currentIndex: engines.indexOf(_engineType),
        onBack: () => setState(() => _rightPanelType = 'more'),
        onClose: () => setState(() => _rightPanelType = null),
        onSelect: (i) async {
          setState(() => _rightPanelType = null);
          if (engines[i] != _engineType) await _switchEngine(engines[i]);
        },
      );
    }
    if (type == 'style') {
      return RightPanelShell(
        title: '字幕样式',
        width: 320,
        onBack: () => setState(() => _rightPanelType = 'more'),
        onClose: () => setState(() => _rightPanelType = null),
        body: SubtitleStyleContent(
          engine: _engine,
          onDone: () => setState(() => _rightPanelType = null),
        ),
      );
    }
    // 'more' 宫格
    return MoreRightPanel(
      qualityLabel: _qualityLabel(_currentQuality),
      engineLabel: _engineType.shortLabel,
      externalSubtitleLoaded: _externalSubtitleLoaded,
      onQuality: () => setState(() => _rightPanelType = 'quality'),
      onEngine: () => setState(() => _rightPanelType = 'engine'),
      onStyle: () => setState(() => _rightPanelType = 'style'),
      onExternalSubtitle: () {
        setState(() => _rightPanelType = null);
        _loadExternalSubtitle();
      },
      onOnlineSearch: () {
        setState(() => _rightPanelType = null);
        _openOnlineSubtitleSearch();
      },
      onMore: () => _showTopToast('更多功能开发中'),
      onClose: () => setState(() => _rightPanelType = null),
    );
  }

  void _seekRelative(int seconds) {
    final newPos = _position + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    if (newPos < Duration.zero) {
      _engine?.seek(Duration.zero);
    } else if (newPos > _duration) {
      _engine?.seek(_duration);
    } else {
      _engine?.seek(newPos);
    }
    // 清理弹幕状态并重置扫描游标
    _danmakuController.seekTo(clamped);
  }

  void _toggleDanmaku() {
    setState(() {
      _danmakuEnabled = !_danmakuEnabled;
      _danmakuController.setEnabled(_danmakuEnabled);
    });
  }

  void _setFitMode(BoxFit mode) {
    setState(() {
      _currentFitMode = mode;
    });
    _engine?.setFitMode(mode);
  }

  void _onFitModeChanged() {
    if (mounted && _engine != null) {
      setState(() {
        _currentFitMode = _engine!.fitMode;
      });
    }
  }


  Future<void> _switchEngine(PlayerEngineType type) async {
    if (type == _engineType) return;
    if (_engine == null) return;
    final manager = ref.read(playerManagerProvider);
    try {
      _stateSub?.cancel();
      _stateSub = null;

      // 保存当前状态，引擎切换后恢复
      final oldEngine = _engine!;
      final restoredVolume = _volume;
      final restoredSpeed = _speed;
      final restoredFitMode = _currentFitMode;

      _tracksLoaded = false;
      _showedAudioError = false;
      // 切换内核时清空外挂字幕状态：旧引擎的 cue 列表/选中态对新引擎无意义，
      // 残留会导致原生轨与外挂 overlay 双层渲染或面板选中态错乱。
      _externalSubtitleLoaded = false;
      _externalSubtitleCues = [];
      _currentSubtitleIndex = -1;

      // 解绑旧引擎的 fitMode 监听
      oldEngine.fitModeNotifier.removeListener(_onFitModeChanged);

      _engine = await manager.switchEngine(type);
      _engineType = type;
      _engineKey++; // 强制视频 widget 重建，避免旧 engine 残留引发 disposed 错误

      // 恢复音量、速度和画幅模式
      _engine?.setVolume(restoredVolume);
      _engine?.setSpeed(restoredSpeed);
      _engine?.setFitMode(restoredFitMode);

      // 绑定新引擎的 fitMode 监听
      _engine?.fitModeNotifier.addListener(_onFitModeChanged);

      _stateSub = _engine!.stateStream.listen((state) {
        if (mounted && !_isDisposed) {
          // 先同步弹幕时钟与位置 —— 独立于 setState，任何后续异常都不影响弹幕时间轴
          try {
            _danmakuController.updateConfig(
              DanmakuRenderConfig.fromSettings(_cachedDisplay, playbackSpeed: _speed),
            );
            _danmakuController.updateActive(state.position.inMilliseconds);
          } catch (_) {}
          setState(() {
            _isPlaying = state.isPlaying;
            _isBuffering = state.isBuffering;
            if (_isPlaying) {
              _startProgressReporting();
              _danmakuController.start();
              if (!_playbackStartReported) {
                _playbackStartReported = true;
                try {
                  final svc = ref.read(currentMediaServerServiceProvider);
                  if (svc is EmbyService) {
                    svc.refreshPlaySession();
                    svc.reportPlaybackStart(_activeMedia.id);
                  }
                } catch (_) {}
              }
            } else {
              _progressTimer?.cancel();
              _uiUpdateTimer?.cancel();
              _danmakuController.pause();
            }
            _position = state.position;
            _lastStateTime = DateTime.now();
            // 对于 ISO/HDMV 等容器格式，MPV 可能报告错误的时长（0 或极大缩水）
            // 当服务器提供已知时长且引擎时长明显异常时，使用服务器时长
            final engineDur = state.duration;
            final serverDurSec = _activeMedia.duration; // 服务器提供的时长（秒）
            if (serverDurSec > 0 && engineDur > Duration.zero) {
              final serverDurMs = serverDurSec * 1000;
              // 如果引擎时长不到服务器时长的一半，可能是 ISO/HDMV 格式，使用服务器时长
              if (engineDur.inMilliseconds < serverDurMs * 0.6) {
                _duration = Duration(seconds: serverDurSec);
              } else {
                _duration = engineDur;
              }
            } else {
              _duration = engineDur;
            }
            // 续播：首次获取到正确时长后 seek 到上次位置
            if (!_resumeApplied && widget.resumePositionMs != null && _duration.inMilliseconds > widget.resumePositionMs!) {
              _resumeApplied = true;
              final resumePos = Duration(milliseconds: widget.resumePositionMs!);
              AppLog.i('Player', 'Resume → seek to ${resumePos.inMinutes}:${(resumePos.inSeconds % 60).toString().padLeft(2, '0')}');
              _engine?.seek(resumePos);
              // 弹幕游标同步到续播位置，避免续播后弹幕时间轴错位
              _danmakuController.seekTo(resumePos);
            }
            _buffer = state.buffer;
            _speed = state.speed;
            _volume = state.volume;
            // 硬件音量键/系统音量变化时同步持久化（防抖），下次切集/重开沿用
            if ((_volume - _lastSavedVolume).abs() > 0.02) _saveVolumeBrightness();
            _engineType = state.engineType;
          });
          // ── 跳过片头/片尾检测 ──
          _checkSkipState(state.position);

          // ── 下一集倒计时检测 ──
          _checkNextEpisode(state.position, state.duration);

          if (state.duration > Duration.zero && !_tracksLoaded) {
            _tracksLoaded = true;
            _loadTracks();
          }

          if (state.error?.isNotEmpty == true) {
            final err = state.error!.toLowerCase();
            if (err.contains('codec') || err.contains('audio') || err.contains('truehd') || err.contains('dts')) {
              if (!_showedAudioError) {
                _showedAudioError = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && !_isDisposed) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('音频解码失败，建议切换到其他音轨或ExoPlayer内核'),
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: '切换内核',
                          onPressed: () {
                            final mgr = ref.read(playerManagerProvider);
                            mgr.switchEngine(PlayerEngineType.exo);
                          },
                        ),
                      ),
                    );
                  }
                });
              }
            }
          }
        }
      });

      // 强制重建以清除旧 engine 的 widget
      if (mounted) setState(() {
        _subtitleTracks = [];
        _audioTracks = [];
      });

      // 旧 engine 已被 manager 接管，确保它不再被本 screen 引用
      oldEngine; // 标记引用防止 lint 警告

      if (mounted) setState(() {
        // 内核切换后重置控制栏
      });
    } catch (e) {
      AppLog.e('Player', '切换内核失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换内核失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 水平拖拽 seek 状态（累积亚像素，避免 round() 归零死区）
  double _accumulatedSeek = 0;
  bool _seekCapsuleVisible = false;
  String _seekCapsuleLabel = '';

  void _handleHorizontalDragStart(DragStartDetails d) {
    if (_duration.inMilliseconds <= 0) return;
    _accumulatedSeek = 0;
    setState(() {
      _seekCapsuleVisible = true;
      _seekCapsuleLabel = _formatTime(_position);
    });
  }

  void _handleHorizontalDrag(DragUpdateDetails d) {
    if (_duration.inMilliseconds <= 0) return;
    final delta = d.delta.dx;
    final sw = MediaQuery.of(context).size.width;
    _accumulatedSeek += (delta / sw) * 60;
    final whole = _accumulatedSeek.truncate();
    if (whole != 0) {
      _accumulatedSeek -= whole;
      _seekRelative(whole);
      // 本地预测位置，不依赖引擎流回传，避免拖拽滞后
      var predicted = _position + Duration(seconds: whole);
      if (predicted < Duration.zero) predicted = Duration.zero;
      if (predicted > _duration) predicted = _duration;
      setState(() {
        _position = predicted;
        _lastStateTime = DateTime.now();
        _seekCapsuleLabel = _formatTime(_position);
      });
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails d) {
    if (_seekCapsuleVisible) {
      setState(() => _seekCapsuleVisible = false);
    }
  }

  void _handleHorizontalDragCancel() {
    if (_seekCapsuleVisible) {
      setState(() => _seekCapsuleVisible = false);
    }
  }

  // 上下滑动手势状态
  bool _gestureVerticalActive = false;
  bool _gestureVerticalIsBrightness = false;
  double _gestureStartY = 0;
  double _gestureStartValue = 0;

  void _handleVerticalDrag(DragUpdateDetails details) {
    if (_hasAnyPanelOpen) return;

    final dx = details.localPosition.dx;
    final dy = details.localPosition.dy;

    // 控制栏可见时，避开顶栏和底部控制按钮区域，中间空白区仍可调节亮度/音量
    if (_controlsVisible) {
      final topBarHeight = MediaQuery.of(context).padding.top + 72;
      final bottomZone = _screenHeight - (MediaQuery.of(context).padding.bottom + 130);
      if (dy < topBarHeight || dy > bottomZone) return;
    }

    final isLeftSide = dx < _screenWidth * 0.5;

    if (!_gestureVerticalActive) {
      _gestureVerticalActive = true;
      _gestureStartY = dy;
      _gestureStartValue = isLeftSide ? _brightness : _volume;
      _gestureVerticalIsBrightness = isLeftSide;
      return;
    }

    final delta = _gestureStartY - dy;
    final sh = _screenHeight;
    if (sh <= 0) return;
    final ratio = delta / sh;
    final newValue = (_gestureStartValue + ratio).clamp(0.0, 1.0);

    if (_gestureVerticalIsBrightness) {
      final clamped = newValue.clamp(0.05, 1.0);
      if ((clamped - _brightness).abs() < 0.005) return;
      setState(() {
        _brightness = clamped;
        _showBrightnessIndicator = true;
        _showVolumeIndicator = false;
      });
      _applyBrightness();
    } else {
      if ((newValue - _volume).abs() < 0.005) return;
      setState(() {
        _volume = newValue;
        _showVolumeIndicator = true;
        _showBrightnessIndicator = false;
      });
      _engine?.setVolume(_volume);
    }
  }

  void _resetVerticalGesture() {
    if (_gestureVerticalActive) {
      _gestureVerticalActive = false;
      _saveVolumeBrightness(); // 手势结束：持久化音量/亮度
      if (_gestureVerticalIsBrightness) {
        _brightnessHideTimer?.cancel();
        _brightnessHideTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showBrightnessIndicator = false);
        });
      } else {
        _volumeHideTimer?.cancel();
        _volumeHideTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted) setState(() => _showVolumeIndicator = false);
        });
      }
    }
  }

  /// 双击三区（Streama DoubleTapLeft/Middle/Right）：
  /// 左 1/3 快退、中 1/3 播放/暂停、右 1/3 快进
  void _handleDoubleTap(TapDownDetails d) {
    final sw = MediaQuery.of(context).size.width;
    final x = d.localPosition.dx;
    if (x >= sw * 1 / 3 && x < sw * 2 / 3) {
      // 中间：播放/暂停（播放/暂停图标涟漪，不 seek、不显示快进快退圆弧）
      _togglePlay();
      if (mounted) {
        setState(() {
          _ripplePosition = d.localPosition;
          _rippleIsLeft = false;
          _ripplePlayPause = true;
          _rippleIcon = _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
          _rippleTrigger++;
          _showRipple = true;
        });
      }
      AppLog.i('Player', '双击中间：播放/暂停');
      return;
    }
    final isLeft = x < sw * 1 / 3;
    final seconds = isLeft ? -10 : 10;
    final newPos = _position + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero
        ? Duration.zero
        : (newPos > _duration ? _duration : newPos);
    AppLog.i('Player', '双击${isLeft ? "快退" : "快进"}: ${seconds > 0 ? "+" : ""}$seconds秒, pos=${_position.inMilliseconds}ms → ${clamped.inMilliseconds}ms');
    setState(() {
      _position = clamped;
      _lastStateTime = DateTime.now();
      // 触发涟漪动画
      _ripplePosition = d.localPosition;
      _rippleIsLeft = isLeft;
      _ripplePlayPause = false;
      _rippleTrigger++;
      _showRipple = true;
    });
    _engine?.seek(clamped);
    _danmakuController.seekTo(clamped);
  }

  String _formatTime(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> _playEpisode(MediaItem episode) async {
    final svc = widget.service;
    if (svc == null) {
      setState(() => _showEpisodePanel = false);
      return;
    }

    try {
      final ps = ref.read(playerSettingsProvider);
      final url = await svc.getStreamUrl(episode.id, quality: ps.defaultQuality, burnInSubtitle: ps.burnInSubtitle);
      if (!mounted) return;
      _currentStreamUrl = url; // 记录新一集的流地址（字幕下载据此取 MediaSourceId）

      final headers = svc.streamHeaders;

      // 停止当前播放
      await _engine?.stop();

      _tracksLoaded = false;
      _showedAudioError = false;
      _playbackStartReported = false;
      _lastReportedMs = 0;

      // 重新打开新集数
      await _engine?.open(url: url, httpHeaders: headers, autoPlay: true);

      // 新引擎音量默认重置为 1.0，重新应用用户音量（含持久化值）
      _engine?.setVolume(_volume);
      // 强制视频 widget 重建：旧 PlatformView 的 Surface 已被原生 release() 销毁，
      // 新播放器拿不到 Surface 会"有声音无画面"（画面停留在上一集）；
      // 重建后新 SurfaceView 的 surfaceCreated 会把新 Surface 绑定到新播放器。
      _engineKey++;

      // 更新当前集数跟踪（切集后 widget.media 已过时）
      _currentMedia = episode;
      final eps = widget.episodes;
      if (eps != null) {
        final idx = eps.indexWhere((e) => e.id == episode.id);
        if (idx >= 0) _currentEpisodeIndex = idx;
      }

      setState(() {
        _showEpisodePanel = false;
        _episodePanelController.reset();
        _danmakuController.setData([]);
        _subtitleTracks = [];
        _audioTracks = [];
        // 切集后上一集的外挂字幕/选中态全部失效，必须清空：
        // 否则旧 SRT cue 会残留叠加在新集画面上（双层/错位字幕），
        // 且 _currentSubtitleIndex 指向旧轨会让面板显示错误的选中态。
        _externalSubtitleLoaded = false;
        _externalSubtitleCues = [];
        _serverSubtitleLoading = false;
        _currentSubtitleIndex = -1;
        _autoDefaultSubtitleApplied = false; // 新一集重新自动启用其默认字幕轨
        _subtitlePrefetched = false; // 新一集重新后台预取其常用字幕轨
        _showAllSubtitleTracks = false; // 新一集恢复常用语言过滤
        _showNextEpisode = false;
        _nextEpisodeCancelled = false;
        _nextEpisodeTimer?.cancel();
        _nextEpisodePlaying = false;
        _skipButtonLabel = null;
        _skipIntroHandled = false;
        _introSkip = null;
        _trickplayInfo = null;
        _chapterMarkers = [];
        _rightPanelType = null;
      });

      // 重新加载弹幕、片头片尾、缩略图、章节标记
      _chaptersLoaded = false;
      _chapterMarkers = [];
      _loadDanmaku();
      _loadIntroSkip();
      _loadTrickplayInfo();
      _loadChapters();
    } catch (e) {
      _nextEpisodePlaying = false; // 失败后允许再次触发自动连播
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换集数失败: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _screenWidth = MediaQuery.of(context).size.width;
    _screenHeight = MediaQuery.of(context).size.height;
    _danmakuController.updateScreenSize(_screenWidth, _screenHeight);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _cleanup();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Listener(
        onPointerCancel: (_) => _resetVerticalGesture(),
        behavior: HitTestBehavior.translucent,
        child: GestureDetector(
        // 锁定：点击只显示解锁提示，全部手势（拖动/双击）禁用防误触
        onTap: _controlsLocked ? null : _toggleControls,
        onHorizontalDragStart: _controlsLocked ? null : _handleHorizontalDragStart,
        onHorizontalDragUpdate: _controlsLocked ? null : _handleHorizontalDrag,
        onHorizontalDragEnd: _controlsLocked ? null : _handleHorizontalDragEnd,
        onHorizontalDragCancel: _controlsLocked ? null : _handleHorizontalDragCancel,
        onVerticalDragUpdate: _controlsLocked ? null : _handleVerticalDrag,
        onVerticalDragEnd: _controlsLocked ? null : (_) => _resetVerticalGesture(),
        onDoubleTapDown: _controlsLocked ? null : (details) => _doubleTapDetails = details,
        onDoubleTap: _controlsLocked ? null : () => _handleDoubleTap(_doubleTapDetails!),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 视频渲染层 — 通过引擎抽象接口获取
            if (_engine != null)
              KeyedSubtree(
                key: ValueKey('video_$_engineKey'),
                child: _engine!.buildVideoWidget(),
              ),
            // 初始化错误显示
            if (_initError != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline_rounded, color: Colors.red, size: 64),
                      SizedBox(height: 16),
                      Text('播放失败', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                      SizedBox(height: 8),
                      Text(
                        _initError!,
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 24),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text('返回', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
              ),
            // 缓冲指示器
            if (_isBuffering)
              Center(
                child: CircularProgressIndicator(color: Colors.white70),
              ),
            // 服务端字幕下载中指示（Emby/NAS 首次按需提取内嵌字幕可能很慢，
            // 让用户知道字幕正在加载而非没反应）
            if (_serverSubtitleLoading)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                          ),
                          SizedBox(width: 8),
                          Text('字幕加载中…', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // 外挂字幕叠加层（仅 ExoPlayer 引擎使用 Flutter 层渲染）
            if (_externalSubtitleLoaded && _engineType == PlayerEngineType.exo)
              _buildExternalSubtitleLayer(),
            _buildDanmakuLayer(),
            _buildVolumeIndicator(),
            _buildBrightnessIndicator(),
            // 右缘控制：锁定按钮常驻（同一个按钮原地切换锁定/解锁，不额外生成
            // 解锁按钮）；倍速步进器仅在控制栏可见且未锁定时出现。
            // 面板打开时整组隐藏防误触（与之前一致）。
            if (_rightPanelType == null)
              Positioned(
                right: 8,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLockToggle(),
                      if (_controlsVisible && !_controlsLocked) ...[
                        const SizedBox(width: 8),
                        _buildSpeedStepper(),
                      ],
                    ],
                  ),
                ),
              ),
            // 控制栏：顶栏向上滑出、底栏向下滑出，同时淡出。
            // 用 AnimatedBuilder 驱动，动画结束后整棵子树从渲染树移除
            // —— opacity:0 的 widget 仍参与渲染，里面 4 处 BackdropFilter
            // 会持续做高斯模糊（看 2 小时电影期间控制栏 99% 时间隐藏）。
            AnimatedBuilder(
              animation: _controlsAnim,
              builder: (context, child) {
                if (_controlsAnim.value == 0 && !_controlsVisible) {
                  return const SizedBox.shrink();
                }
                return Opacity(
                  opacity: _controlsAnim.value,
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: child,
                  ),
                );
              },
              child: Stack(
                children: [
                  Column(
                    children: [
                      // 顶栏：向上滑出
                      SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(_controlsAnim),
                        child: _buildTopBar(),
                      ),
                      const Expanded(child: SizedBox()),
                      // 底栏：向下滑出
                      SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 1),
                          end: Offset.zero,
                        ).animate(_controlsAnim),
                        child: _buildBottomControls(),
                      ),
                    ],
                  ),
                  // 中心传输行：⟲10 ▶ ⟳10（Streama 中心控制样式）
                  Positioned.fill(
                    child: Center(child: _buildCenterTransport()),
                  ),

                ],
              ),
            ),
            // 面板遮罩：有面板打开时全屏透明遮罩，点击关闭弹窗
            if (_showEpisodePanel || _episodePanelController.isAnimating)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _closeAllPanels,
                ),
              ),
            // ── 选集面板（带底部滑入动画）──
            if (_showEpisodePanel || _episodePanelController.isAnimating)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedBuilder(
                  animation: _episodePanelController,
                  builder: (context, child) {
                    if (!_showEpisodePanel && _episodePanelController.value == 0) {
                      return const SizedBox.shrink();
                    }
                    return SlideTransition(
                      position: _episodeSlideAnim,
                      child: FadeTransition(
                        opacity: _episodeFadeAnim,
                        child: child,
                      ),
                    );
                  },
                  child: _buildEpisodeSheet(),
                ),
              ),
            // ── 双击涟漪动画 ──
            if (_showRipple)
              DoubleTapRipple(
                tapPosition: _ripplePosition,
                isLeftSide: _rippleIsLeft,
                seconds: 10,
                trigger: _rippleTrigger,
                playPause: _ripplePlayPause,
                playPauseIcon: _rippleIcon,
                onComplete: () {
                  if (mounted) setState(() => _showRipple = false);
                },
              ),
            // ── 拖拽时间胶囊（水平 seek 反馈） ──
            if (_seekCapsuleVisible)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _seekCapsuleLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // ── 跳过片头/片尾浮动按钮 ──
            if (_skipButtonLabel != null)
              Positioned(
                right: 32,
                bottom: MediaQuery.of(context).padding.bottom + 100,
                child: SkipButton(
                  key: ValueKey(_skipButtonLabel),
                  label: _skipButtonLabel!,
                  onTap: () => _skipToIntroEnd(),
                  onAutoExpire: () {
                    if (mounted) setState(() => _skipButtonLabel = null);
                  },
                ),
              ),
            // ── 下一集自动播放倒计时 ──
            if (_showNextEpisode && !_nextEpisodeCancelled)
              Positioned(
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom + 100,
                child: _buildNextEpisodeCard(),
              ),
            // ── 右侧轨道面板 ──
            // 遮罩不覆盖顶栏区域：面板打开时顶栏「弹」「⋯」仍可点，
            // 可直接切换弹幕/更多面板（全屏遮罩会吞掉顶栏点击）。
            if (_rightPanelType != null)
              Positioned(
                top: MediaQuery.of(context).padding.top + 6 + 44 + 24,
                left: 0,
                right: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => setState(() => _rightPanelType = null),
                  child: const SizedBox.expand(),
                ),
              ),
            // 音频/字幕轨道面板：仅这两种类型渲染（之前条件用 != 'danmaku' 排除，
            // 把 more/quality/engine/style 也放行了 → 点「⋯」时字幕面板和更多面板
            // 同时打开。必须显式限定类型。）
            if (_rightPanelType == 'audio' || _rightPanelType == 'subtitle')
              TrackRightPanel(
                title: _rightPanelType == 'audio' ? '音频' : '字幕',
                tracks: _rightPanelType == 'audio' ? _audioTracks : _subtitleTracks,
                currentIndex: _rightPanelType == 'audio' ? _currentAudioIndex : _currentSubtitleIndex,
                onSelect: (i) {
                  if (_rightPanelType == 'audio') {
                    if (i >= 0) {
                      _engine?.setAudioTrack(i);
                      setState(() => _currentAudioIndex = i);
                    }
                  } else {
                    _applySubtitleTrack(i);
                  }
                },
                onClose: () => setState(() => _rightPanelType = null),
              ),
            if (_rightPanelType == 'danmaku')
              _buildDanmakuPanel(),
            // ── 更多面板及二级选项（画质/切换内核/字幕样式，全部右侧滑入）──
            if (_rightPanelType == 'more' ||
                _rightPanelType == 'quality' ||
                _rightPanelType == 'engine' ||
                _rightPanelType == 'style')
              _buildMoreRightPanel(),
          ],
        ),
        ),
      ),
      ),
    );
  }

  void _restoreOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  Widget _buildTopBar() {
    // 全宽渐变 scrim：与底栏呼应的 Netflix/Streama 式顶部渐变压暗。
    // 贴顶不悬浮：按钮为纯白图标（仅阴影），去掉玻璃浮层感；
    // 信息层级对齐 Streama：返回 | 标题 + 剧集徽章 | 操作按钮。
    final showBadge = (_activeMedia.type == MediaType.series ||
            _activeMedia.type == MediaType.episode) &&
        _activeMedia.seasonNumber != null &&
        _activeMedia.episodeNumber != null;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.black.withValues(alpha: 0.42),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 6,
          left: 6,
          right: 6,
          bottom: 24, // 渐变在按钮下方继续淡出，形成信息区“贴顶”的视觉带
        ),
        child: Row(
          children: [
            _buildTopBarIcon(Icons.arrow_back_rounded, () => Navigator.pop(context), size: 24),
            const SizedBox(width: 4),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _activeMedia.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                      ),
                    ),
                  ),
                  if (showBadge) ...[
                    const SizedBox(width: 8),
                    // 徽章改纯文字（无容器，嵌入标题行）
                    Text(
                      'S${_activeMedia.seasonNumber}\u00B7E${_activeMedia.episodeNumber}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 弹幕按钮 — 徽章样式：开启=主题色圆徽章，关闭=空心（点开面板 · 长按开关）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _toggleRightPanel('danmaku'),
              onLongPress: _toggleDanmaku,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _danmakuEnabled
                      ? AppTheme.primary.withValues(alpha: 0.22)
                      : Colors.transparent,
                  border: Border.all(
                    color: _danmakuEnabled
                        ? AppTheme.primary
                        : Colors.white.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '弹',
                    style: TextStyle(
                      color: _danmakuEnabled
                          ? AppTheme.primary
                          : Colors.white.withValues(alpha: 0.75),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                  ),
                ),
              ),
            ),
            // 与「弹」按钮拉开 8dp 间距、缩小命中域，避免相邻误触
            const SizedBox(width: 8),
            // 锁定按钮已移到右缘控制簇（倍速步进器左侧），顶栏只留 ⋯
            _buildTopBarIcon(
              Icons.more_vert_rounded,
              () => _toggleRightPanel('more'),
              size: 26,
              tapSize: 40,
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏扁平图标按钮（仅阴影、无玻璃底 —— 贴顶不悬浮）
  Widget _buildTopBarIcon(IconData icon, VoidCallback? onTap,
      {double size = 22, double tapSize = 44, Color? color}) {
    // 按压缩放 0.9 + 弹性回弹（无框扁平图标的手感）
    return TapFeedback(
      onTap: onTap,
      scaleOnPress: 0.9,
      springBack: true,
      highlightColor: Colors.transparent,
      child: SizedBox(
        width: tapSize,
        height: tapSize,
        child: Center(
          child: Icon(
            icon,
            color: color ?? Colors.white,
            size: size,
            shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
          ),
        ),
      ),
    );
  }

  /// 弹幕设置面板（右侧滑入）
  Widget _buildDanmakuPanel() {
    return _DanmakuRightPanel(
      danmakuEnabled: _danmakuEnabled,
      onToggleDanmaku: (v) {
        setState(() {
          _danmakuEnabled = v;
          _danmakuController.setEnabled(v);
        });
      },
      onClose: () => setState(() => _rightPanelType = null),
    );
  }

  /// 播放器底部控制面板：悬浮玻璃面板（Netflix/Streama 风格）
  /// 两层结构：进度条 + 主控制行（左播放簇 / 右辅助簇）
  Widget _buildBottomControls() {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    // 底部布局（Netflix / Streama 式）：进度条独立在上、控制区直接嵌在底部渐变
    // scrim 上 —— 无玻璃面板、无按钮框，图标扁平融入画面。
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.78),
            Colors.black.withValues(alpha: 0.42),
            Colors.transparent,
          ],
          stops: const [0.0, 0.42, 0.72],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 进度区（无裁剪，拖拽缩略图可浮出到画面）──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左下元数据行：分辨率 · 编码 · 码率 · 帧率（参考 CapyPlayer / Hills）
                if (_videoMetadata != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5, left: 2),
                    child: Text(
                      _videoMetadata!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                _buildProgressBar(),
              ],
            ),
          ),
          // ── 底部单行：左=上/下集，右=音轨/字幕/画幅/选集（Hills / Capy 布局）──
          Padding(
            padding: EdgeInsets.fromLTRB(8, 2, 8, 6 + safeBottom),
            child: Row(
              children: [
                // 上一集 / 下一集（仅剧集有选集列表时显示）
                if (_hasEpisodeList) ...[    
                  _buildFlatIconButton(
                    Icons.skip_previous_rounded,
                    _currentEpisodeIndex > 0
                        ? () => _playEpisode(widget.episodes![_currentEpisodeIndex - 1])
                        : null,
                    size: 26,
                  ),
                  _buildFlatIconButton(
                    Icons.skip_next_rounded,
                    _currentEpisodeIndex < widget.episodes!.length - 1
                        ? () => _playEpisode(widget.episodes![_currentEpisodeIndex + 1])
                        : null,
                    size: 26,
                  ),
                ],
                const Spacer(),
                _buildControlIcon(
                  Icons.audiotrack_rounded,
                  () => _showRightPanel('audio'),
                  label: '音轨',
                ),
                const SizedBox(width: 12),
                _buildControlIcon(
                  Icons.subtitles_outlined,
                  () => _showRightPanel('subtitle'),
                  label: '字幕',
                ),
                const SizedBox(width: 12),
                _buildControlIcon(
                  Icons.aspect_ratio_rounded,
                  _openFitSheet,
                  label: '画幅',
                ),
                // 选集按钮（仅剧集时显示）
                if (_activeMedia.type == MediaType.series || _activeMedia.type == MediaType.episode) ...[  
                  const SizedBox(width: 12),
                  _buildControlIcon(
                    Icons.list_rounded,
                    () => _togglePanel('episode'),
                    label: '选集',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 中心传输行：⟲10 ▶ ⟳10（Streama 中心控制样式，画面垂直中心悬浮）
  Widget _buildCenterTransport() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildFlatIconButton(Icons.replay_10_rounded, () => _seekRelative(-10), size: 32),
        const SizedBox(width: 22),
        // 播放/暂停 — 最大的主控制图标（带扩散光晕）
        _buildPlayPauseButton(),
        const SizedBox(width: 22),
        _buildFlatIconButton(Icons.forward_10_rounded, () => _seekRelative(10), size: 32),
      ],
    );
  }

  /// 中心播放/暂停键：按下时从按钮扩散出一圈柔和光晕 + 波纹环，
  /// 播放/暂停反馈更明确（参考 Netflix 中心按键的按压涟漪）
  Widget _buildPlayPauseButton() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 扩散光晕层：柔和径向渐变圆盘，随动画外扩并淡出
        AnimatedBuilder(
          animation: _playPulseController,
          builder: (_, __) {
            final t = Curves.easeOutCubic.transform(_playPulseController.value);
            final radius = 26 + 62 * t;
            final opacity = (1 - t) * 0.6;
            return IgnorePointer(
              child: Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withValues(alpha: opacity * 0.85),
                      Colors.white.withValues(alpha: opacity * 0.22),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.4, 1.0],
                  ),
                ),
              ),
            );
          },
        ),
        // 波纹环：与光晕同步外扩的细白环，形成"水波"层次
        AnimatedBuilder(
          animation: _playPulseController,
          builder: (_, __) {
            final t = Curves.easeOut.transform(_playPulseController.value);
            final radius = 30 + 56 * t;
            final opacity = (1 - t) * 0.5;
            return IgnorePointer(
              child: Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: opacity),
                    width: 1.6,
                  ),
                ),
              ),
            );
          },
        ),
        // 图标本体（保留 0.9 按压缩放 + 弹性回弹）
        TapFeedback(
          onTap: () {
            _togglePlay();
            _playPulseController.forward(from: 0);
          },
          scaleOnPress: 0.9,
          springBack: true,
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 54,
            height: 54,
            child: Center(
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 46,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 10)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 扁平图标按钮（无框、无底，直接嵌入播放画面 —— 参考 Yamby / Hills / CapyPlayer）
  Widget _buildFlatIconButton(IconData icon, VoidCallback? onTap,
      {double size = 28, double tapSize = 54}) {
    final enabled = onTap != null;
    // 按压缩放 0.9 + 弹性回弹；禁用（首/末集等）时无按压视觉
    return TapFeedback(
      onTap: onTap,
      scaleOnPress: 0.9,
      springBack: true,
      highlightColor: Colors.transparent,
      child: SizedBox(
        width: tapSize,
        height: tapSize,
        child: Center(
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white24,
            size: size,
            shadows: enabled ? const [Shadow(color: Colors.black87, blurRadius: 10)] : null,
          ),
        ),
      ),
    );
  }

  /// 右侧垂直倍速步进器：+ / 当前速率 / −（参考 AfuseKt / Hills 竖排面板，无描边嵌入画面）
  Widget _buildSpeedStepper() {
    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _stepperButton(Icons.add_rounded, () => _stepSpeed(0.25)),
          const SizedBox(height: 6),
          TapFeedback(
            onTap: _openSpeedSheet,
            scaleOnPress: 0.9,
            springBack: true,
            highlightColor: Colors.transparent,
            child: SizedBox(
              width: 46,
              height: 24,
              child: Center(
                child: Text(
                  '${_speed}x',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          _stepperButton(Icons.remove_rounded, () => _stepSpeed(-0.25)),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    // 步进器 +/− 也带按压缩放反馈
    return TapFeedback(
      onTap: onTap,
      scaleOnPress: 0.9,
      springBack: true,
      highlightColor: Colors.transparent,
      child: SizedBox(
        width: 46,
        height: 34,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  /// 步进倍速（0.5 ~ 4.0，步长 0.25），同步引擎与弹幕位移
  void _stepSpeed(double delta) {
    final next = (_speed + delta).clamp(0.5, 4.0);
    if ((next - _speed).abs() < 0.001) return;
    setState(() => _speed = next);
    _engine?.setSpeed(next);
    _danmakuController.updateConfig(
      DanmakuRenderConfig.fromSettings(_cachedDisplay, playbackSpeed: next),
    );
  }

  /// 扁平控制图标（无框，图标+标签直接嵌在玻璃面板上）
  Widget _buildControlIcon(IconData icon, VoidCallback? onTap,
      {String? label, bool enabled = true, double size = 22}) {
    // 按压缩放 0.9 + 弹性回弹
    return TapFeedback(
      onTap: enabled ? onTap : null,
      scaleOnPress: 0.9,
      springBack: true,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 46,
            height: 38,
            child: Center(
              child: Icon(
                icon,
                color: enabled ? Colors.white : Colors.white30,
                size: size,
                shadows: enabled ? const [Shadow(color: Colors.black87, blurRadius: 8)] : null,
              ),
            ),
          ),
          if (label != null) ...[    
            Text(
              label,
              style: TextStyle(
                color: enabled ? Colors.white.withValues(alpha: 0.75) : Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return CustomProgressBar(
      position: _position,
      duration: _duration,
      buffer: _buffer,
      canSeek: _duration.inMilliseconds > 0,
      formatTime: _formatTime,
      chapterMarkers: _chapterMarkers,
      // 弹幕热力图：开关开启且加载到弹幕数据时显示（密度分桶缓存，O(1) 查表）
      heatmap: ref.watch(danmakuDisplayProvider).heatmap
          ? _danmakuController.heatmapDensity
          : null,
      heatmapBucketMs: _danmakuController.heatmapBucketWidthMs,
      thumbnailProvider: (positionMs) {
        final trickplay = _trickplayInfo;
        final svc = widget.service;
        if (trickplay == null || svc is! JellyfinService) return null;
        if (trickplay.intervalMs <= 0 || trickplay.thumbnailCount <= 0) return null;
        // 帧索引（positionMs 对应第几张缩略图）
        final frameIndex = positionMs ~/ trickplay.intervalMs;
        // 精灵图索引（每张精灵图含 thumbnailCount 张缩略图）
        final sheetIndex = frameIndex ~/ trickplay.thumbnailCount;
        // 精灵图内的局部索引 → 行列位置
        final tileInSheet = frameIndex % trickplay.thumbnailCount;
        final col = tileInSheet % trickplay.tileWidth;
        final row = tileInSheet ~/ trickplay.tileWidth;
        return TrickplayTile(
          spriteSheetUrl: svc.getTrickplayTileUrl(_activeMedia.id, sheetIndex),
          col: col,
          row: row,
          gridWidth: trickplay.tileWidth,
          gridHeight: trickplay.tileHeight,
        );
      },
      onSeekStart: (v) {
        if (!_isSeeking) {
          _isSeeking = true;
          _danmakuController.setSeeking(true);
        }
        final newPos = Duration(
          milliseconds: (v * _duration.inMilliseconds).toInt(),
        );
        setState(() {
          _position = newPos;
        });
      },
      onSeekUpdate: (v) {
        final newPos = Duration(
          milliseconds: (v * _duration.inMilliseconds).toInt(),
        );
        setState(() {
          _position = newPos;
        });
      },
      onSeekEnd: (v) {
        _isSeeking = false;
        _danmakuController.setSeeking(false);
        final newPos = Duration(
          milliseconds: (v * _duration.inMilliseconds).toInt(),
        );
        _engine?.seek(newPos);
        _onSeekEnd();
        // Seek 结束后重启自动隐藏定时器
        if (_controlsVisible) _startHideTimer();
      },
    );
  }

  Widget _buildExternalSubtitleLayer() {
    if (!_externalSubtitleLoaded) return const SizedBox.shrink();
    final manager = _engine?.externalSubtitleManager;
    if (manager == null || !manager.isLoaded) return const SizedBox.shrink();
    // watch 而非 read：字幕样式面板调节字号/颜色时实时生效，无需重建页面
    final settings = ref.watch(playerSettingsProvider);
    return Positioned.fill(
      child: IgnorePointer(
        child: SubtitleOverlay(
          cues: manager.cues,
          // 字幕延迟：播放位置加上偏移（正=延后，负=提前），与 MPV 的 sub-delay 语义一致
          currentPosition: () => _position + Duration(milliseconds: (settings.subtitleDelaySeconds * 1000).round()),
          settings: settings,
          screenWidth: _screenWidth,
          screenHeight: _screenHeight,
        ),
      ),
    );
  }

  Widget _buildDanmakuLayer() {
    if (!_danmakuEnabled) {
      return const SizedBox.shrink();
    }
    final tapToSearch = ref.watch(danmakuDisplayProvider).tapToSearch;
    return Positioned.fill(
      // 点弹幕搜索：开启后点击弹幕命中检测，弹出复制/搜索操作（不拦截其他手势）
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapUp: tapToSearch ? _onDanmakuTap : null,
        child: IgnorePointer(
          child: DanmakuRenderer(
            tickNotifier: _danmakuController.tickNotifier,
            getActiveDanmaku: () => _danmakuController.activeDanmaku,
            screenWidth: _screenWidth,
            screenHeight: _screenHeight,
            displayArea: ref.watch(danmakuDisplayProvider).displayArea,
          ),
        ),
      ),
    );
  }

  /// 点弹幕命中检测：显示该弹幕内容 + 复制/搜索操作
  void _onDanmakuTap(TapUpDetails details) {
    final hit = _danmakuController.hitTest(details.localPosition.dx, details.localPosition.dy);
    if (hit == null) return;
    final text = hit.danmaku.text;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (_) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 120),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('弹幕内容已复制'), duration: Duration(seconds: 2)));
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                    label: const Text('复制', style: TextStyle(color: Colors.white70)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      _searchDanmaku(text);
                    },
                    icon: const Icon(Icons.search_rounded, size: 18, color: AppTheme.primary),
                    label: const Text('搜索', style: TextStyle(color: AppTheme.primary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 用弹幕内容打开浏览器搜索
  void _searchDanmaku(String text) {
    final uri = Uri.parse('https://www.baidu.com/s?wd=${Uri.encodeComponent(text)}');
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildVolumeIndicator() {
    // 用 AnimatedSwitcher 做淡入 + 轻微缩放，而非 SizedBox.shrink 硬出硬消。
    // 每次调音量都会遇到，属于高频接触点。
    return Positioned(
      right: 40,
      top: _screenHeight * 0.25,
      child: _HudTransition(
        visible: _showVolumeIndicator,
        child: _showVolumeIndicator
            ? _VerticalBarIndicator(
                value: _volume,
                icon: _volume == 0
                    ? Icons.volume_off_rounded
                    : _volume < 0.4
                        ? Icons.volume_down_rounded
                        : Icons.volume_up_rounded,
              )
            : null,
      ),
    );
  }

  Widget _buildBrightnessIndicator() {
    return Positioned(
      left: 40,
      top: _screenHeight * 0.25,
      child: _HudTransition(
        visible: _showBrightnessIndicator,
        child: _showBrightnessIndicator
            ? _VerticalBarIndicator(
                value: _brightness,
                icon: _brightness < 0.4
                    ? Icons.brightness_low_rounded
                    : _brightness < 0.7
                        ? Icons.brightness_5_rounded
                        : Icons.brightness_high_rounded,
              )
            : null,
      ),
    );
  }

  Widget _buildEpisodeSheet() {
    if (!_showEpisodePanel) return const SizedBox.shrink();

    final episodes = widget.episodes ?? [];
    if (episodes.isEmpty) {
      // 没有剧集列表数据时，回退到数字选集
      return _buildSimpleEpisodeSheet();
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('选集', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('  ·  共${episodes.length}集', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => _animateCloseEpisodePanel(),
                child: Icon(Icons.close_rounded, color: Colors.white54, size: 22),
              ),
            ],
          ),
            SizedBox(height: 16),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final ep = episodes[index];
                  final epNum = ep.episodeNumber ?? (index + 1);
                  final isCurrent = ep.id == _activeMedia.id;
                  return GestureDetector(
                    onTap: () => _playEpisode(ep),
                    child: Container(
                      width: 110,
                      margin: const EdgeInsets.only(right: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 封面图（固定 16:9 比例，避免拉伸留白）
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(10),
                                      border: isCurrent ? Border.all(color: AppTheme.primary, width: 2) : null,
                                    ),
                                    child: ep.posterUrl.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: ep.posterUrl,
                                          fit: BoxFit.cover,
                                          memCacheWidth: 200,
                                          errorWidget: (_, __, ___) => Center(
                                            child: Text('$epNum', style: TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.bold)),
                                          ),
                                        )
                                      : Center(
                                          child: Text('$epNum', style: TextStyle(color: Colors.white70, fontSize: 28, fontWeight: FontWeight.bold)),
                                        ),
                                  ),
                                ),
                                // 底部渐变遮罩
                                Positioned(
                                  left: 0, right: 0, bottom: 0,
                                  child: Container(
                                    height: 20,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [Colors.transparent, Colors.black54],
                                      ),
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                                    ),
                                  ),
                                ),
                                // 播放指示
                                if (isCurrent)
                                  Positioned(
                                    top: 6, right: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 6),
                          // 集数标签
                          Text(
                            '第${epNum}集',
                            style: TextStyle(
                              color: isCurrent ? AppTheme.primary : Colors.white,
                              fontSize: 12,
                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                              shadows: [Shadow(color: Colors.black54, blurRadius: 2)],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }

  // 简单数字选集（无剧集列表时的回退方案）
  Widget _buildSimpleEpisodeSheet() {
    final totalEpisodes = widget.media.totalEpisodes ?? 12;
    final currentEpisode = _activeMedia.episodeNumber ?? 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('选集', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('  ·  共$totalEpisodes集', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const Spacer(),
              GestureDetector(
                onTap: () => _animateCloseEpisodePanel(),
                child: Icon(Icons.close_rounded, color: Colors.white54, size: 22),
              ),
            ],
          ),
            SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: totalEpisodes,
                itemBuilder: (context, index) {
                  final ep = index + 1;
                  final isSelected = ep == currentEpisode;
                  return GestureDetector(
                    onTap: () => setState(() => _showEpisodePanel = false),
                    child: Container(
                      width: 52,
                      height: 52,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primary : Colors.white10,
                        borderRadius: BorderRadius.circular(14),
                        border: isSelected ? Border.all(color: AppTheme.primary, width: 1.5) : null,
                      ),
                      child: Center(
                        child: Text('$ep', style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 16,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        )),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
    );
  }

  // ════════════════════════════════════════════════
  // 右侧轨道面板
  // ════════════════════════════════════════════════

  void _showRightPanel(String type) {
    if (type == 'audio' && _audioTracks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可选音轨')),
      );
      return;
    }
    _closeAllPanels();
    setState(() => _rightPanelType = type);
  }

  // ════════════════════════════════════════════════
  // 跳过片头/片尾
  // ════════════════════════════════════════════════

  Future<void> _loadIntroSkip() async {
    final svc = widget.service;
    if (svc == null) {
      AppLog.i('Player', 'IntroSkip: service 为空，跳过加载');
      return;
    }
    try {
      AppLog.i('Player', 'IntroSkip: 开始加载 (itemId=${_activeMedia.id}, svc=${svc.runtimeType})');
      final introSkip = await svc.getIntroSkipInfo(_activeMedia.id);
      if (mounted) {
        setState(() => _introSkip = introSkip);
        AppLog.i('Player', 'IntroSkip loaded: hasIntro=${introSkip?.hasIntro}, hasCredits=${introSkip?.hasCredits}');
      }
    } catch (e) {
      AppLog.i('Player', '加载片头片尾信息失败: $e');
    }
  }

  /// 加载 Trickplay 缩略图元数据（仅 Jellyfin 10.9+ 支持）
  Future<void> _loadTrickplayInfo() async {
    final svc = widget.service;
    if (svc is! JellyfinService) return;
    try {
      final info = await svc.getTrickplayInfo(_activeMedia.id);
      if (mounted && info != null) {
        setState(() => _trickplayInfo = info);
        AppLog.i('Player', 'Trickplay loaded: intervalMs=${info.intervalMs}, grid=${info.tileWidth}x${info.tileHeight}, thumbnails=${info.thumbnailCount}');
      }
    } catch (e) {
      AppLog.w('Player', '加载 Trickplay 信息失败: $e');
    }
  }

  /// 加载章节标记（Emby/Jellyfin Chapters API），在进度条上绘制 tick
  Future<void> _loadChapters() async {
    final svc = widget.service;
    if (svc == null || _chaptersLoaded) return;
    try {
      final chapters = await svc.getChapters(_activeMedia.id);
      if (!mounted || chapters.isEmpty) return;
      _chaptersLoaded = true;
      final markers = chapters
          .map((c) => c.startDuration.inMilliseconds)
          .where((ms) => ms > 1000)
          .toList();
      if (markers.isNotEmpty) {
        setState(() => _chapterMarkers = markers);
        AppLog.i('Player', '章节标记: ${markers.length} 个 (${chapters.map((c) => c.name).join(' / ')})');
      }
    } catch (e) {
      AppLog.d('Player', '加载章节标记失败: $e');
    }
  }

  /// 数据防御：introEnd 异常（≥ 总时长，部分服务器/插件返回错误区间）时
  /// 回退到总时长前 30s，避免"跳过片头"直接跳到片尾/结束（误跳整集）。
  Duration _clampIntroEnd(Duration target) {
    if (_duration > Duration.zero && target >= _duration) {
      final fallback = _duration - const Duration(seconds: 30);
      return fallback > Duration.zero ? fallback : Duration.zero;
    }
    return target;
  }

  void _checkSkipState(Duration position) {
    final introSkip = _introSkip;
    if (introSkip == null) return;
    final settings = ref.read(playerSettingsProvider);
    final posMs = position.inMilliseconds;

    // 片头检测
    if (introSkip.hasIntro) {
      final introStart = introSkip.introStartDuration.inMilliseconds;
      final introEnd = introSkip.introEndDuration.inMilliseconds;
      if (posMs >= introStart && posMs < introEnd) {
        if (settings.autoSkipIntro && !_skipIntroHandled) {
          _skipIntroHandled = true;
          final target = _clampIntroEnd(introSkip.introEndDuration);
          _engine?.seek(target);
          _danmakuController.seekTo(target);
          AppLog.i('Player', '自动跳过片头 → ${target.inMilliseconds}ms');
          return;
        }
        if (settings.showSkipButton && _skipButtonLabel != '跳过片头') {
          setState(() => _skipButtonLabel = '跳过片头');
        }
        return;
      } else if (posMs >= introEnd) {
        _skipIntroHandled = false;
      }
    }

    // 片尾检测
    if (introSkip.hasCredits) {
      final creditsStart = introSkip.creditsStartDuration?.inMilliseconds ?? 0;
      final introEnd = introSkip.hasIntro ? introSkip.introEndDuration.inMilliseconds : 0;
      // 数据防御：部分服务器/插件的 credits 起点早于/等于片头结束（区间重叠、
      // 字段错位），会导致刚跳过片头就立刻弹"跳过片尾"、误跳整集。
      // 有效起点取 max(creditsStart, introEnd + 1s)。
      final effectiveCreditsStart = (creditsStart > introEnd) ? creditsStart : (introEnd + 1000);
      if (effectiveCreditsStart > 0 &&
          posMs >= effectiveCreditsStart &&
          posMs < _duration.inMilliseconds) {
        if (settings.autoSkipOutro && _duration.inMilliseconds - posMs > 5000) {
          _engine?.seek(_duration);
          AppLog.i('Player', '自动跳过片尾');
          return;
        }
        if (settings.showSkipButton && _skipButtonLabel != '跳过片尾') {
          setState(() => _skipButtonLabel = '跳过片尾');
        }
        return;
      }
    }

    if (_skipButtonLabel != null) {
      setState(() => _skipButtonLabel = null);
    }
  }

  void _skipToIntroEnd() {
    final introSkip = _introSkip;
    if (introSkip == null) return;
    if (_skipButtonLabel == '跳过片头' && introSkip.hasIntro) {
      final target = _clampIntroEnd(introSkip.introEndDuration);
      _engine?.seek(target);
      _danmakuController.seekTo(target);
    } else if (_skipButtonLabel == '跳过片尾' && introSkip.hasCredits) {
      _engine?.seek(_duration);
    }
    setState(() => _skipButtonLabel = null);
  }

  // ════════════════════════════════════════════════
  // 下一集自动播放倒计时
  // ════════════════════════════════════════════════

  void _checkNextEpisode(Duration position, Duration duration) {
    if (_activeMedia.type != MediaType.series && _activeMedia.type != MediaType.episode) return;
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return;
    if (duration.inMilliseconds <= 0) return;
    if (_nextEpisodeCancelled || _nextEpisodePlaying) return;
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= episodes.length - 1) return;

    final remaining = duration - position;
    final remainingMs = remaining.inMilliseconds;

    // 已到达/越过结尾（自然播完、自动跳过片尾 seek 到结尾、手动拖到底）：
    // 倒计时流程未启动时直接切下一集。覆盖"自动跳过片尾"把位置直接跳到
    // duration 导致 remaining 瞬间归零、倒计时卡片永不出现、连播卡死的路径。
    if (remainingMs <= 0) {
      _playNextEpisode();
      return;
    }

    if (remainingMs <= 30000 && !_showNextEpisode) {
      setState(() {
        _showNextEpisode = true;
        _nextEpisodeCountdown = remaining.inSeconds.clamp(1, 30);
      });
      _startNextEpisodeTimer(duration);
    }

    if (_showNextEpisode && remaining.inSeconds != _nextEpisodeCountdown) {
      setState(() => _nextEpisodeCountdown = remaining.inSeconds);
    }
  }

  void _startNextEpisodeTimer(Duration duration) {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _nextEpisodeCancelled) {
        timer.cancel();
        return;
      }
      final remaining = duration - _position;
      if (remaining.inSeconds <= 0) {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  void _playNextEpisode() {
    if (_nextEpisodePlaying) return; // 防重复触发（倒计时回调 + 位置检测可能同时命中）
    _nextEpisodePlaying = true;
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return;
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= episodes.length - 1) return;
    final nextEp = episodes[_currentEpisodeIndex + 1];
    setState(() => _showNextEpisode = false);
    _playEpisode(nextEp);
  }

  Widget _buildNextEpisodeCard() {
    final episodes = widget.episodes;
    if (episodes == null || episodes.isEmpty) return const SizedBox.shrink();
    if (_currentEpisodeIndex < 0 || _currentEpisodeIndex >= episodes.length - 1) {
      return const SizedBox.shrink();
    }
    final nextEp = episodes[_currentEpisodeIndex + 1];

    return NextEpisodeCard(
      title: nextEp.title.isNotEmpty ? nextEp.title : '第${nextEp.episodeNumber ?? _currentEpisodeIndex + 2}集',
      subtitle: nextEp.title.isNotEmpty ? '第${nextEp.episodeNumber ?? _currentEpisodeIndex + 2}集' : null,
      thumbnailUrl: nextEp.posterUrl.isNotEmpty ? nextEp.posterUrl : null,
      totalSeconds: 30,
      remainingSeconds: _nextEpisodeCountdown.clamp(0, 30),
      onPlay: () {
        _nextEpisodeTimer?.cancel();
        _playNextEpisode();
      },
      onCancel: () {
        _nextEpisodeTimer?.cancel();
        setState(() {
          _nextEpisodeCancelled = true;
          _showNextEpisode = false;
        });
      },
    );
  }
}

/// 通用底部抽屉（毛玻璃风格，用于速度/内核/画幅等选项选择）
class _OptionBottomSheet extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> options;
  final int currentIndex;
  final void Function(int index) onSelect;

  const _OptionBottomSheet({
    required this.title,
    required this.options,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * 0.5;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24).withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.12), width: 1),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 拖拽手柄
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: Row(children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ]),
              ),
              // 选项列表
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, i) {
                    final opt = options[i];
                    final label = opt['label']?.toString() ?? '';
                    final isSelected = i == currentIndex;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          onSelect(i);
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          child: Row(children: [
                            if (isSelected)
                              Container(
                                width: 4, height: 20, margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(2)),
                              )
                            else
                              const SizedBox(width: 16),
                            Expanded(
                              child: Text(label, style: TextStyle(
                                color: isSelected ? Colors.white : Colors.white70,
                                fontSize: 15,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              )),
                            ),
                            Icon(
                              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                              color: isSelected ? AppTheme.primary : Colors.white24,
                              size: 22,
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FitModeOption {
  final BoxFit mode;
  final String label;
  final IconData icon;

  const _FitModeOption(this.mode, this.label, this.icon);
}

/// 播放器 HUD（音量/亮度指示器）出现消失过渡。
///
/// 出现：150ms 淡入 + 0.9→1.0 缩放（接近 iOS 音量 HUD 质感）
/// 消失：淡出 + 轻微缩小
/// 不可见时返回零尺寸占位，不参与渲染。
class _HudTransition extends StatelessWidget {
  final bool visible;
  final Widget? child;

  const _HudTransition({required this.visible, this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppAnimations.fast,
      switchInCurve: AppAnimations.easeOut,
      switchOutCurve: AppAnimations.easeIn,
      transitionBuilder: (c, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
          child: c,
        ),
      ),
      child: visible && child != null
          ? child!
          : const SizedBox.shrink(key: ValueKey('hud_hidden')),
    );
  }
}

/// 竖向进度条指示器（音量/亮度通用）
/// 单一 CustomPaint 绘制，从源头避免"两条进度条"问题
class _VerticalBarIndicator extends StatelessWidget {
  final double value; // 0.0 - 1.0
  final IconData icon;

  const _VerticalBarIndicator({
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: AppAnimations.normal,
      curve: AppAnimations.easeOut,
      builder: (context, animatedValue, _) => _buildIndicator(animatedValue),
    );
  }

  Widget _buildIndicator(double animatedValue) {
    return Container(
      width: 56,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 10),
          SizedBox(
            width: 24,
            height: 120,
            child: CustomPaint(
              painter: _VerticalBarPainter(value: animatedValue),
              size: const Size(24, 120),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${(animatedValue * 100).round()}%',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// 竖向进度条绘制器
/// 一次性绘制：背景轨道 + 前景填充
class _VerticalBarPainter extends CustomPainter {
  final double value;

  _VerticalBarPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final trackColor = Colors.white.withValues(alpha: 0.25);
    final fillColor = AppTheme.primary;
    final width = 4.0;
    final cx = size.width / 2;
    final top = 0.0;
    final bottom = size.height;

    // 背景轨道（从顶到底）
    final trackPaint = Paint()
      ..color = trackColor
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width;
    canvas.drawLine(Offset(cx, top), Offset(cx, bottom), trackPaint);

    // 前景填充（从 (1-value) 到底）
    final fillTop = bottom * (1 - value);
    if (fillTop < bottom) {
      final fillPaint = Paint()
        ..color = fillColor
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width;
      canvas.drawLine(Offset(cx, fillTop), Offset(cx, bottom), fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _VerticalBarPainter old) => old.value != value;
}

/// 弹幕设置右侧滑入面板（带动画 + 分组布局）
class _DanmakuRightPanel extends ConsumerStatefulWidget {
  final bool danmakuEnabled;
  final ValueChanged<bool> onToggleDanmaku;
  final VoidCallback onClose;

  const _DanmakuRightPanel({
    required this.danmakuEnabled,
    required this.onToggleDanmaku,
    required this.onClose,
  });

  @override
  ConsumerState<_DanmakuRightPanel> createState() => _DanmakuRightPanelState();
}

class _DanmakuRightPanelState extends ConsumerState<_DanmakuRightPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<Offset> _slideAnim;
  late Animation<double> _opacityAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 280),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.0, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _animateClose() async {
    await _animController.reverse();
    if (mounted) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final display = ref.watch(danmakuDisplayProvider);
    final dn = ref.read(danmakuDisplayProvider.notifier);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _opacityAnim,
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            width: 280,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            margin: const EdgeInsets.symmetric(vertical: 76, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0F1A).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 12, 10),
                      child: Row(
                        children: [
                          const Icon(Icons.comment_rounded, color: AppTheme.primary, size: 18),
                          const SizedBox(width: 8),
                          const Text('弹幕设置', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          GestureDetector(
                            onTap: _animateClose,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 弹幕总开关
                    SwitchListTile(
                      title: const Text('启用弹幕', style: TextStyle(color: Colors.white, fontSize: 14)),
                      value: widget.danmakuEnabled,
                      activeTrackColor: AppTheme.primary,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                      onChanged: (v) => widget.onToggleDanmaku(v),
                    ),
                    const Divider(color: Colors.white12, height: 1),
                    // 设置列表
                    Flexible(
                      child: widget.danmakuEnabled
                          ? ListView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              children: [
                                // ── 显示分组 ──
                                _groupLabel('显示'),
                                _dmToggle('顶部弹幕', display.showTop, (v) => dn.update(display.copyWith(showTop: v))),
                                _dmToggle('底部弹幕', display.showBottom, (v) => dn.update(display.copyWith(showBottom: v))),
                                _dmToggle('滚动弹幕', display.showScroll, (v) => dn.update(display.copyWith(showScroll: v))),
                                _dmToggle('合并重复', display.mergeDuplicates, (v) => dn.update(display.copyWith(mergeDuplicates: v))),
                                _dmToggle('进度条热力图', display.heatmap, (v) => dn.update(display.copyWith(heatmap: v))),
                                _dmToggle('点击弹幕搜索', display.tapToSearch, (v) => dn.update(display.copyWith(tapToSearch: v))),
                                _dmSlider('显示区域', display.displayArea, 0.5, 1.0, (v) => dn.update(display.copyWith(displayArea: double.parse(v.toStringAsFixed(2))))),
                                const SizedBox(height: 8),
                                // ── 布局分组 ──
                                _groupLabel('布局'),
                                _dmSlider('滚动行数', display.maxScrollLines.toDouble(), 1, 12, (v) {
                                  dn.update(display.copyWith(maxScrollLines: v.round()));
                                }, isInt: true),
                                _dmSlider('顶部行数', display.maxTopLines.toDouble(), 1, 8, (v) {
                                  dn.update(display.copyWith(maxTopLines: v.round()));
                                }, isInt: true),
                                _dmSlider('底部行数', display.maxBottomLines.toDouble(), 1, 8, (v) {
                                  dn.update(display.copyWith(maxBottomLines: v.round()));
                                }, isInt: true),
                                _dmToggle('防止重叠', display.preventOverlap, (v) => dn.update(display.copyWith(preventOverlap: v))),
                                const SizedBox(height: 8),
                                // ── 样式分组 ──
                                _groupLabel('样式'),
                                _dmSlider('字体大小', display.fontSize, 14, 40, (v) {
                                  dn.update(display.copyWith(fontSize: double.parse(v.toStringAsFixed(0))));
                                }, suffix: 'px'),
                                _dmSlider('透明度', display.opacity, 0.2, 1.0, (v) {
                                  dn.update(display.copyWith(opacity: double.parse(v.toStringAsFixed(2))));
                                }),
                                _dmSlider('弹幕速度', display.speed, 6, 24, (v) {
                                  dn.update(display.copyWith(speed: double.parse(v.toStringAsFixed(0))));
                                }),
                                _dmSlider('同步偏移', display.syncDelay, -5.0, 5.0, (v) {
                                  dn.update(display.copyWith(syncDelay: double.parse(v.toStringAsFixed(1))));
                                }, suffix: 's'),
                                _dmToggle('粗体', display.bold, (v) => dn.update(display.copyWith(bold: v))),
                                const SizedBox(height: 12),
                                // 恢复默认
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () => dn.update(const DanmakuDisplaySettings()),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white54,
                                      side: const BorderSide(color: Colors.white24),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                    child: const Text('恢复默认', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text('弹幕已关闭', style: TextStyle(color: Colors.white38, fontSize: 14)),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.primary.withValues(alpha: 0.8),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _dmSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {String suffix = '', bool isInt = false}) {
    final displayValue = isInt ? value.round().toString() : value.toStringAsFixed(suffix == 's' ? 1 : (suffix == 'px' ? 0 : 2));
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Text('$displayValue$suffix', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppTheme.primary,
              inactiveTrackColor: Colors.white12,
              thumbColor: AppTheme.primary,
              overlayColor: AppTheme.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dmToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          SizedBox(
            height: 26,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: AppTheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
