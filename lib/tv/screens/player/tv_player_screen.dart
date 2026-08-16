import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:path_provider/path_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../models/media_models.dart';
import '../../../services/media_server_service.dart';
import '../../../services/danmaku_service.dart';
import '../../../services/storage_service.dart';
import '../../../database/database_service.dart';
import '../../../utils/app_log.dart';
import '../../../widgets/skip_button.dart';
import '../../../providers/app_providers.dart';
import '../../../player/core/player_engine.dart';
import '../../../player/core/player_manager.dart';
import '../../../player/danmaku/danmaku_controller.dart';
import '../../../player/danmaku/danmaku_renderer.dart';
import '../../../player/danmaku/danmaku_models.dart';
import '../../../player/subtitle/libass_bridge.dart';
import '../../../utils/animation_config.dart';
import '../../../utils/track_titles.dart';
import '../../utils/tv_focus.dart';
import '../../widgets/focusable_widgets.dart';

/// TV端 Netflix 风格播放器
/// 特性：
/// - 引擎管理（MPV/ExoPlayer 自动选择 + 回退 + 切换）
/// - 剧集选集面板
/// - 进度条预览缩略图（Jellyfin Trickplay）
/// - 跳过片头/片尾按钮
/// - 下一集自动播放倒计时
/// - 弹幕系统（匹配 + 渲染 + 设置）
/// - 字幕系统（轨道选择 + 外挂字幕 + 样式）
class TvPlayerScreen extends ConsumerStatefulWidget {
  final MediaItem media;
  final String streamUrl;
  final Map<String, String>? httpHeaders;
  final List<MediaItem>? episodes;
  final MediaServerService? service;
  final int? resumePositionMs;

  const TvPlayerScreen({
    super.key,
    required this.media,
    required this.streamUrl,
    this.httpHeaders,
    this.episodes,
    this.service,
    this.resumePositionMs,
  });

  @override
  ConsumerState<TvPlayerScreen> createState() => _TvPlayerScreenState();
}

class _TvPlayerScreenState extends ConsumerState<TvPlayerScreen>
    with TickerProviderStateMixin {
  // ===== 引擎 =====
  PlayerEngine? _engine;
  PlayerEngineType _engineType = PlayerEngineType.mpv;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlayerEngineType>? _engineChangeSub;
  int _engineKey = 0;
  String? _initError;

  // "有声无画"自动回退守卫：轮询会持续上报 error，确保 Exo→MPV 回退只触发一次
  bool _engineFallbackTriggered = false;

  // ===== Stall 恢复状态机 =====
  DateTime? _stallStartTime;       // 卡顿开始时间
  int _stallRecoveryCount = 0;     // 当前播放会话的恢复次数
  Duration _lastStallPosition = Duration.zero; // 卡顿时记录的播放位置
  static const int _maxStallRecovery = 3;      // 最大自动恢复次数
  static const Duration _stallThreshold = Duration(seconds: 5); // 卡顿判定阈值

  // ===== 播放状态 =====
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isBuffering = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;
  Timer? _positionRefreshTimer;
  double _speed = 1.0;
  Timer? _hideControlsTimer;
  Timer? _seekDebounceTimer;
  Duration? _seekTarget;
  bool _isSeeking = false;

  // ===== 三期动画 =====
  /// 播放/暂停图标 morph（0=播放图标，1=暂停图标）
  late AnimationController _playPauseMorphCtrl;
  /// 缓冲圈可见性（延迟 300ms 显示避免闪烁，淡入淡出）
  bool _showBuffering = false;
  Timer? _bufferDelayTimer;

  // ===== 剧集 =====
  late List<MediaItem> _episodes;
  int _currentEpisodeIndex = 0;
  bool _showEpisodePanel = false;
  MediaItem? _currentMedia;

  // ===== 跳过片头片尾 =====
  IntroSkip? _introSkip;
  String? _skipButtonLabel;
  bool _skipIntroHandled = false;

  // ===== Trickplay =====
  TrickplayInfo? _trickplayInfo;
  TrickplayTile? _previewTile;
  Duration _previewPosition = Duration.zero;

  // ===== 下一集 =====
  bool _showNextEpisode = false;
  int _nextEpisodeCountdown = 10;
  Timer? _nextEpisodeTimer;

  // ===== 弹幕 =====
  late DanmakuController _danmakuController;
  bool _danmakuEnabled = true;
  bool _danmakuLoading = false;
  double _screenWidth = 0;
  double _screenHeight = 0;
  bool _tracksLoaded = false;

  // ===== 轨道 =====
  List<Map<String, dynamic>> _subtitleTracks = [];
  int _currentSubtitleIndex = -1;
  // ===== libass 原生字幕覆盖层 =====
  bool _libassActive = false;
  ui.Image? _libassImage;
  Timer? _libassRenderTimer;
  int _libassWidth = 1920;
  int _libassHeight = 1080;
  List<Map<String, dynamic>> _audioTracks = [];
  int _currentAudioIndex = 0;

  // ===== 速度选项 =====
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  int _currentSpeedIndex = 2;

  // ===== 续播与进度保存 =====
  int? _resumePositionMs;
  bool _resumeApplied = false;
  Timer? _progressSaveTimer;
  DateTime? _lastSaveTime;

  // ===== 焦点节点 =====
  late FocusNode _playPauseFocus;
  late FocusNode _seekLeftFocus;
  late FocusNode _seekRightFocus;
  late FocusNode _speedFocus;
  late FocusNode _episodesFocus;
  late FocusNode _danmakuFocus;
  late FocusNode _subtitleFocus;
  late FocusNode _audioFocus;
  late FocusNode _progressBarFocus;

  // ===== Seek 时间指示器 =====
  bool _showSeekIndicator = false;
  Timer? _seekIndicatorTimer;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _episodes = widget.episodes ?? [];
    _currentEpisodeIndex = _episodes.indexWhere((e) => e.id == widget.media.id);
    if (_currentEpisodeIndex < 0) _currentEpisodeIndex = 0;
    _currentMedia = widget.media;

    _playPauseFocus = FocusNode(debugLabel: 'play_pause');
    _seekLeftFocus = FocusNode(debugLabel: 'seek_left');
    _seekRightFocus = FocusNode(debugLabel: 'seek_right');
    _speedFocus = FocusNode(debugLabel: 'speed');
    _episodesFocus = FocusNode(debugLabel: 'episodes');
    _danmakuFocus = FocusNode(debugLabel: 'danmaku');
    _subtitleFocus = FocusNode(debugLabel: 'subtitle');
    _audioFocus = FocusNode(debugLabel: 'audio');
    _progressBarFocus = FocusNode(debugLabel: 'progress_bar');

    // 播放/暂停图标 morph：初始 0（播放图标），播放中 forward 到暂停图标
    _playPauseMorphCtrl = AnimationController(
      vsync: this,
      duration: AppAnimations.medium,
      value: 0.0,
    );

    // 读取详情页传入的续播位置
    final r = widget.resumePositionMs;
    _resumePositionMs = (r != null && r > 5000) ? r : null;

    // 初始化弹幕控制器
    final settings = ref.read(playerSettingsProvider);
    final danmakuDisplay = ref.read(danmakuDisplayProvider);
    _danmakuEnabled = settings.enableDanmakuByDefault;
    _danmakuController = DanmakuController(this);
    _danmakuController.init(
      screenWidth: 0,
      screenHeight: 0,
      config: DanmakuRenderConfig.fromSettings(danmakuDisplay, playbackSpeed: _speed),
    );
    _danmakuController.setEnabled(_danmakuEnabled);

    // 监听弹幕显示设置变化
    ref.listenManual(danmakuDisplayProvider, (prev, next) {
      _danmakuController.updateConfig(
        DanmakuRenderConfig.fromSettings(next, playbackSpeed: _speed),
      );
    });

    _initPlayer();
    _loadDanmaku();
    _loadIntroSkip();
    _loadTrickplayInfo();
    _startHideControlsTimer();

    // 获取屏幕尺寸
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _screenWidth = MediaQuery.of(context).size.width;
        _screenHeight = MediaQuery.of(context).size.height;
        _libassWidth = _screenWidth.toInt();
        _libassHeight = _screenHeight.toInt();
        _danmakuController.updateScreenSize(_screenWidth, _screenHeight);
      }
    });
  }

  /// 初始化播放器引擎
  Future<void> _initPlayer() async {
    final manager = ref.read(playerManagerProvider);
    // 每次初始化播放时同步用户设置的内核偏好，修复设置变更后不生效的问题
    final settings = ref.read(playerSettingsProvider);
    switch (settings.playerKernel) {
      case 'exo':
        manager.setStrategy(EngineSelectStrategy.exoOnly);
        break;
      case 'mpv':
        manager.setStrategy(EngineSelectStrategy.mpvOnly);
        break;
      default:
        manager.setStrategy(EngineSelectStrategy.auto);
    }
    try {
      // 如果 URL 为空，从 service 获取流地址
      var url = widget.streamUrl;
      if (url.isEmpty && widget.service != null) {
        try { url = await widget.service!.getStreamUrl(widget.media.id); } catch (_) {}
      }
      // 如果 headers 为空，从 service 获取
      final headers = widget.httpHeaders ?? widget.service?.streamHeaders;
      _engine = await manager.createEngine(
        url: url,
        httpHeaders: headers,
        autoPlay: true,
      );
      _engineType = _engine!.engineType;
      _engineKey++;

      // 监听引擎状态
      _stateSub = _engine!.stateStream.listen(_handleEngineState);

      // 应用字幕样式
      _engine!.applySubtitleStyle(ref.read(playerSettingsProvider));

      // 监听引擎切换
      _engineChangeSub = manager.engineChangeStream.listen((type) {
        if (mounted) setState(() => _engineType = type);
      });

      setState(() {});
    } catch (e) {
      AppLog.e('TVPlayer', '播放失败: $e');
      if (mounted) setState(() => _initError = e.toString());
    }
  }

  /// 引擎状态处理（提取为命名方法，引擎回退后可重新订阅复用）
  void _handleEngineState(PlayerState state) {
    if (!(mounted && !_isDisposed)) return;

    // "有声无画"检测：设备缺少解码器（如 HEVC Main10）时 ExoPlayer 只播音频，
    // 原生层识别后上报 error → 自动切换到 MPV 软解内核
    if (state.error != null &&
        !_engineFallbackTriggered &&
        _engine?.engineType == PlayerEngineType.exo) {
      _engineFallbackTriggered = true;
      _fallbackEngineOnError(state.error!);
      return;
    }

    final wasPlaying = _isPlaying;
    setState(() {
      _isPlaying = state.isPlaying;
      _isBuffering = state.isBuffering;
      _position = state.position;
      _duration = state.duration;
      _buffer = state.buffer;
      _speed = state.speed;
      _engineType = state.engineType;
    });
    _syncPlayPauseMorph();
    _syncBufferingIndicator();

    // ===== Stall 恢复状态机 =====
    if (_isBuffering && _isPlaying) {
      // 正在缓冲：记录卡顿起始
      _stallStartTime ??= DateTime.now();
      _lastStallPosition = state.position;
      // 超过阈值且位置未前进 → 触发恢复
      final elapsed = DateTime.now().difference(_stallStartTime!);
      if (elapsed >= _stallThreshold && _stallRecoveryCount < _maxStallRecovery) {
        _stallRecoveryCount++;
        _stallStartTime = null;
        AppLog.w('TVPlayer', 'Stall 检测: 缓冲 ${elapsed.inSeconds}s 无进展，自动恢复 ($_stallRecoveryCount/$_maxStallRecovery)');
        // seek 到当前位置触发重新解码
        _engine?.seek(state.position > Duration.zero ? state.position - const Duration(seconds: 1) : Duration.zero);
      }
    } else if (!_isBuffering) {
      // 缓冲结束：重置卡顿计时
      _stallStartTime = null;
    }
    // 只在播放状态变化时启停弹幕和定时器，避免高频反复重置定时器
    if (_isPlaying && !wasPlaying) {
      _danmakuController.start();
      _startPositionRefreshTimer();
      _startProgressSaveTimer();
      _applyResumeIfNeeded();
    } else if (!_isPlaying && wasPlaying) {
      _danmakuController.pause();
      _stopPositionRefreshTimer();
    }

    // 同步倍速到弹幕
    _danmakuController.updateConfig(
      DanmakuRenderConfig.fromSettings(
        ref.read(danmakuDisplayProvider),
        playbackSpeed: _speed,
      ),
    );
    _danmakuController.updateActive(state.position.inMilliseconds);

    // 跳过片头片尾检测
    _checkSkipState(state.position);

    // 下一集检测
    _checkNextEpisode(state.position);

    // 加载轨道
    if (state.duration > Duration.zero && !_tracksLoaded) {
      _tracksLoaded = true;
      _loadTracks();
    }
  }

  /// Exo 视频解码失败（有声无画）时自动切换到 MPV 软解内核。
  /// switchEngine 会保持当前播放进度并续播；切换后重新订阅新引擎的状态流。
  Future<void> _fallbackEngineOnError(String error) async {
    final manager = ref.read(playerManagerProvider);
    AppLog.w('TVPlayer', 'Exo 视频解码失败（$error），自动切换 MPV 软解');
    try {
      _engine = await manager.switchEngine(PlayerEngineType.mpv);
      _engineType = _engine!.engineType;
      _engineKey++;
      _stateSub?.cancel();
      _stateSub = _engine!.stateStream.listen(_handleEngineState);
      _engine!.applySubtitleStyle(ref.read(playerSettingsProvider));
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('当前设备不支持该视频硬解，已自动切换软解内核'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppLog.e('TVPlayer', '切换 MPV 内核失败: $e');
      if (mounted) setState(() => _initError = '播放失败: $e');
    }
  }

  /// 加载字幕和音轨列表
  Future<void> _loadTracks({int retry = 0}) async {
    if (_engine == null) return;
    try {
      final subtitles = await _engine!.getSubtitleTracks();
      final audios = await _engine!.getAudioTracks();
      // ExoPlayer 轨道信息可能延迟可用，空结果时重试
      if (subtitles.isEmpty && audios.isEmpty && retry < 2) {
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && _engine != null) _loadTracks(retry: retry + 1);
        });
        return;
      }
      if (mounted) {
        setState(() {
          _subtitleTracks = _mergeTrackInfo(subtitles, widget.media.subtitleTracks);
          _audioTracks = _mergeTrackInfo(audios, widget.media.audioTracks);
        });
      }
    } catch (e) {
      AppLog.w('TVPlayer', '加载轨道失败: $e');
    }
  }

  /// 将引擎返回的简单轨道信息与服务端详情中的完整元数据合并
  /// 按 (语言,编码) 配对（引擎轨顺序与服务端 MediaStreams 顺序可能不一致，
  /// 按索引硬配会贴错名字）；保持引擎顺序 → 列表索引 == 引擎索引，切换不受影响。
  List<Map<String, dynamic>> _mergeTrackInfo(
      List<Map<String, dynamic>> engineTracks,
      List<Map<String, dynamic>>? serverTracks) {
    if (serverTracks == null || serverTracks.isEmpty) return engineTracks;
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final s in serverTracks) {
      groups.putIfAbsent(_trackMatchKey(s), () => []).add(s);
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
    for (final engineTrack in engineTracks) {
      final merged = Map<String, dynamic>.from(engineTrack);
      final lang = (merged['Language'] ?? merged['language'] ?? '')
          .toString()
          .toLowerCase();
      final codec =
          (merged['Codec'] ?? merged['codec'] ?? '').toString().toLowerCase();
      // 先按 (语言,编码) 精确配对；编码命名不一致（dts vs dts-hdma）时按语言兑底
      var server = take('$lang|$codec');
      if (server == null && codec.isNotEmpty) server = take('$lang|');
      if (server != null) {
        // 服务端有可读名（DisplayTitle/Title）就覆盖，否则用语言码；
        // 都没有则保留引擎原生名（如"音轨 1"）
        final serverName =
            (server['DisplayTitle'] ?? server['Title'] ?? '').toString().trim();
        final serverLang =
            (server['Language'] ?? server['language'] ?? '').toString().trim();
        if (serverName.isNotEmpty) {
          merged['title'] = serverName;
        } else if (serverLang.isNotEmpty) {
          merged['title'] = serverLang;
        }
        if (serverLang.isNotEmpty) {
          merged['language'] = serverLang;
          merged['Language'] = serverLang;
        }
        merged['codec'] = server['Codec']?.toString() ?? merged['codec'] ?? '';
        merged['displayTitle'] = serverName;
      }
      result.add(merged);
    }
    return result;
  }

  /// 轨道配对键：语言 + 编码（小写，兼容服务端大写 key）
  String _trackMatchKey(Map<String, dynamic> t) {
    final lang = (t['Language'] ?? t['language'] ?? '').toString().toLowerCase();
    final codec = (t['Codec'] ?? t['codec'] ?? '').toString().toLowerCase();
    return '$lang|$codec';
  }

  /// 加载跳过片头片尾信息
  Future<void> _loadIntroSkip() async {
    final svc = widget.service;
    if (svc == null) {
      AppLog.w('TVPlayer', '_loadIntroSkip: service 为 null，跳过');
      return;
    }
    try {
      AppLog.i('TVPlayer', '_loadIntroSkip: 开始加载 itemId=${widget.media.id}');
      final introSkip = await svc.getIntroSkipInfo(widget.media.id);
      AppLog.i('TVPlayer', '_loadIntroSkip: 结果=${introSkip == null ? "null" : "hasIntro=${introSkip.hasIntro}, hasCredits=${introSkip.hasCredits}"}');
      if (mounted) setState(() => _introSkip = introSkip);
    } catch (e) {
      AppLog.w('TVPlayer', '加载跳过片头信息失败: $e');
    }
  }

  /// 加载Trickplay缩略图信息
  Future<void> _loadTrickplayInfo() async {
    final svc = widget.service;
    if (svc == null) return;
    if (svc is! JellyfinService) return; // TODO: Emby trickplay 待确认服务器支持
    try {
      final info = await svc.getTrickplayInfo(widget.media.id);
      if (mounted) setState(() => _trickplayInfo = info);
      if (info != null) {
        AppLog.i('TVPlayer', 'Trickplay 已加载: interval=${info.intervalMs}ms, tiles=${info.tileWidth}x${info.tileHeight}, count=${info.thumbnailCount}');
      } else {
        AppLog.w('TVPlayer', 'Trickplay: 服务器无数据（需在后台开启提取）');
      }
    } catch (e) {
      AppLog.w('TVPlayer', '加载Trickplay信息失败: $e');
    }
  }

  // ==================== 弹幕系统 ====================

  Future<void> _loadDanmaku() async {
    if (_danmakuLoading) return;
    _danmakuLoading = true;
    try {
      final configs = ref.read(danmakuConfigsProvider);
      final enabledConfigs = configs.where((c) => c.isEnabled && c.url.isNotEmpty).toList();
      if (enabledConfigs.isEmpty) {
        AppLog.i('TVDanmaku', '未配置弹幕服务，跳过加载');
        return;
      }

      for (int srcIdx = 0; srcIdx < enabledConfigs.length; srcIdx++) {
        final enabledConfig = enabledConfigs[srcIdx];
        final isLastSource = srcIdx == enabledConfigs.length - 1;
        try {
          final rawUrl = enabledConfig.url.trim();
          String? apiKey = enabledConfig.apiKey;
          final extractedKey = DanmakuService.extractApiKeyFromUrl(rawUrl);
          if (extractedKey != null && (apiKey == null || apiKey.isEmpty)) {
            apiKey = extractedKey;
          }

          final isEpisode = (_currentMedia ?? widget.media).type == MediaType.episode;
          final rawTitle = isEpisode && (_currentMedia ?? widget.media).seriesTitle != null
              ? (_currentMedia ?? widget.media).seriesTitle!
              : (_currentMedia ?? widget.media).title;
          final season = (_currentMedia ?? widget.media).seasonNumber;
          final episode = (_currentMedia ?? widget.media).episodeNumber;

          final danmakuService = DanmakuService(baseUrl: rawUrl, apiKey: apiKey);
          final connected = await danmakuService.testConnection();
          if (!connected) {
            if (isLastSource) return;
            continue;
          }

          String fileName = rawTitle;
          if (season != null && episode != null) {
            fileName = '$rawTitle S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
          } else if (episode != null) {
            fileName = '$rawTitle E${episode.toString().padLeft(2, '0')}';
          }

          // 检查已记住的选择
          String? episodeId = await _getRememberedDanmakuId();

          // v2 精准匹配
          if (episodeId == null) {
            int durationSec = (_currentMedia ?? widget.media).duration > 0 ? (_currentMedia ?? widget.media).duration : 0;
            if (durationSec == 0) {
              durationSec = await _waitForEngineDuration(timeoutMs: 8000);
            }
            final match = await danmakuService.matchV2(
              fileName: fileName,
              fileHash: null,
              duration: durationSec > 0 ? durationSec : null,
            );
            if (match != null) {
              episodeId = match.episodeId;
            }
          }

          // 搜索匹配
          if (episodeId == null) {
            final matches = await danmakuService.searchDanmaku(rawTitle);
            if (matches.isNotEmpty) {
              DanmakuMatch? bestMatch;
              final similarMatches = matches.where((m) {
                final mTitle = m.title.toLowerCase();
                final query = rawTitle.toLowerCase();
                if (mTitle.contains(query) || query.contains(mTitle)) return true;
                final coreQuery = query.replaceAll(RegExp(r'[\s\(（\[\【].*'), '').trim();
                final coreMatch = mTitle.replaceAll(RegExp(r'[\s\(（\[\【第].*'), '').trim();
                if (coreQuery.isNotEmpty && coreMatch.isNotEmpty) {
                  if (coreMatch.contains(coreQuery) || coreQuery.contains(coreMatch)) return true;
                  final minLen = coreQuery.length < coreMatch.length ? coreQuery.length : coreMatch.length;
                  if (minLen >= 2 && coreQuery.substring(0, minLen) == coreMatch.substring(0, minLen)) return true;
                }
                return false;
              }).toList();

              if (similarMatches.isNotEmpty) {
                bestMatch = similarMatches.first;
                if (season != null) {
                  for (final m in similarMatches) {
                    final s = _extractSeasonFromTitle(m.title);
                    if (s == season) { bestMatch = m; break; }
                  }
                }
              }

              if (bestMatch != null) {
                final seriesId = bestMatch.bangumiId;
                try {
                  final detail = await danmakuService.getBangumiDetail(seriesId);
                  if (detail != null) {
                    final bangumi = _extractBangumiData(detail);
                    final episodes = (bangumi?['episodes'] as List?) ?? [];
                    if (episodes.isNotEmpty) {
                      final targetEpisode = episode ?? 1;
                      final ep = episodes.firstWhere(
                        (e) => _matchEpisodeNumber(e, targetEpisode),
                        orElse: () => episodes.first,
                      ) as Map;
                      episodeId = (ep['episodeId'] ?? ep['episode_id'] ?? ep['id'])?.toString();
                    }
                  }
                } catch (e) {
                  AppLog.w('TVDanmaku', 'Bangumi解析失败: $e');
                }
                episodeId ??= seriesId;
              }
            }
          }

          // 获取弹幕
          if (episodeId != null) {
            _rememberDanmakuId(episodeId);
            final cached = await _getCachedDanmaku(episodeId);
            if (cached != null) {
              _preprocessDanmaku(cached);
              if (mounted) {
                _danmakuController.setData(cached);
                _danmakuController.updateActive(_position.inMilliseconds);
              }
              break;
            }
            final danmaku = await danmakuService.getDanmaku(
              episodeId: episodeId,
              episode: episode,
            );
            if (danmaku.isNotEmpty) {
              _cacheDanmaku(episodeId, danmaku);
            }
            if (mounted) {
              _preprocessDanmaku(danmaku);
              _danmakuController.setData(danmaku);
              _danmakuController.updateActive(_position.inMilliseconds);
            }
            break;
          }
        } catch (e) {
          AppLog.e('TVDanmaku', '加载弹幕失败: $e');
          if (isLastSource) rethrow;
        }
      }
    } catch (e) {
      AppLog.e('TVDanmaku', '所有弹幕源均失败: $e');
    } finally {
      _danmakuLoading = false;
    }
  }

  List<Danmaku> _preprocessDanmaku(List<Danmaku> danmaku) {
    danmaku.sort((a, b) => a.time.compareTo(b.time));
    danmaku.removeWhere((d) => d.text.isEmpty || d.text.trim().isEmpty);
    final blockKeywords = ref.read(danmakuDisplayProvider).blockKeywords;
    if (blockKeywords.isNotEmpty) {
      final lowerKeywords = blockKeywords.map((k) => k.toLowerCase()).toList();
      danmaku.removeWhere((d) {
        final lowerText = d.text.toLowerCase();
        return lowerKeywords.any((kw) => lowerText.contains(kw));
      });
    }
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
    return danmaku;
  }

  Map<String, dynamic>? _extractBangumiData(Map<String, dynamic> detail) {
    if (detail['bangumi'] is Map) return detail['bangumi'] as Map<String, dynamic>;
    if (detail['data'] is Map) {
      final data = detail['data'] as Map<String, dynamic>;
      if (data['bangumi'] is Map) return data['bangumi'] as Map<String, dynamic>;
      if (data['episodes'] != null) return data;
    }
    if (detail['episodes'] != null) return detail;
    return null;
  }

  bool _matchEpisodeNumber(dynamic ep, int target) {
    final num = ep['episodeNumber'] ?? ep['episode_number'] ?? ep['number'] ?? ep['ep'] ?? ep['index'];
    if (num == null) return false;
    final str = num.toString();
    return str == target.toString() || int.tryParse(str) == target;
  }

  int? _extractSeasonFromTitle(String title) {
    final lower = title.toLowerCase();
    final cnMatch = RegExp(r'第([一二三四五六七八九十\d]+)季').firstMatch(lower);
    if (cnMatch != null) return _parseChineseSeason(cnMatch.group(1)!);
    final enMatch = RegExp(r'season\s*(\d+)|s(\d{1,2})(?!\d)').firstMatch(lower);
    if (enMatch != null) return int.tryParse(enMatch.group(1) ?? enMatch.group(2) ?? '');
    return null;
  }

  int? _parseChineseSeason(String s) {
    const map = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5, '六': 6, '七': 7, '八': 8, '九': 9, '十': 10};
    if (map.containsKey(s)) return map[s];
    return int.tryParse(s);
  }

  Future<int> _waitForEngineDuration({int timeoutMs = 8000}) async {
    if (_engine == null) return 0;
    if (_duration.inSeconds > 0) return _duration.inSeconds;
    final completer = Completer<int>();
    StreamSubscription? sub;
    sub = _engine!.stateStream.listen((state) {
      if (state.duration.inSeconds > 0 && !completer.isCompleted) {
        completer.complete(state.duration.inSeconds);
        sub?.cancel();
      }
    });
    Timer(Duration(milliseconds: timeoutMs), () {
      if (!completer.isCompleted) { completer.complete(0); sub?.cancel(); }
    });
    return completer.future;
  }

  Future<String?> _getRememberedDanmakuId() async {
    final mediaId = widget.media.id;
    try {
      final sel = await DbService.getDanmakuSelection(mediaId);
      if (sel != null) return sel;
    } catch (_) {}
    return StorageService.getString('danmaku_sel_$mediaId');
  }

  Future<void> _rememberDanmakuId(String episodeId) async {
    final mediaId = widget.media.id;
    try { await DbService.setDanmakuSelection(mediaId, episodeId); } catch (_) {}
    await StorageService.setString('danmaku_sel_$mediaId', episodeId);
  }

  Future<List<Danmaku>?> _getCachedDanmaku(String episodeId) async {
    try {
      final dir = await _danmakuCacheDir();
      final file = File('${dir.path}/${_safeFileName(episodeId)}.json');
      if (!await file.exists()) return null;
      final modified = await file.lastModified();
      if (DateTime.now().difference(modified) > const Duration(hours: 24)) {
        await file.delete();
        return null;
      }
      final json = await file.readAsString();
      final data = jsonDecode(json);
      final ver = data['v'] as int? ?? 1;
      if (ver < 4) { await file.delete(); return null; }
      return (data['danmaku'] as List).map((j) => Danmaku.fromJson(j)).toList();
    } catch (_) { return null; }
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
    } catch (_) {}
  }

  Future<Directory> _danmakuCacheDir() async {
    final appCache = await getApplicationCacheDirectory();
    final dir = Directory('${appCache.path}/danmaku');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _safeFileName(String id) => id.replaceAll(RegExp(r'[^\w\-]'), '_');

  // ==================== 播放控制 ====================

  void _checkSkipState(Duration position) {
    final introSkip = _introSkip;
    if (introSkip == null) return;
    final settings = ref.read(playerSettingsProvider);
    final posMs = position.inMilliseconds;
    final introStart = introSkip.introStartDuration.inMilliseconds;
    final introEnd = introSkip.introEndDuration.inMilliseconds;

    // ── 片头检测 ──
    if (introSkip.hasIntro && posMs >= introStart && posMs < introEnd) {
      // 自动跳过片头
      if (settings.autoSkipIntro && !_skipIntroHandled) {
        _skipIntroHandled = true;
        // 数据防御：introEnd 异常（≥总时长）时回退到总时长前 30s，避免误跳整集
        var target = introSkip.introEndDuration;
        if (_duration > Duration.zero && target >= _duration) {
          final fallback = _duration - const Duration(seconds: 30);
          target = fallback > Duration.zero ? fallback : Duration.zero;
        }
        AppLog.i('TVPlayer', '自动跳过片头 → ${target.inMilliseconds}ms');
        _engine?.seek(target);
        _danmakuController.seekTo(target);
        return;
      }
      // 手动按钮
      if (settings.showSkipButton && _skipButtonLabel != '跳过片头') {
        setState(() => _skipButtonLabel = '跳过片头');
      }
      return;
    } else if (posMs >= introEnd) {
      _skipIntroHandled = false;
    }

    // ── 片尾检测 ──
    if (introSkip.hasCredits) {
      final creditsStart = introSkip.creditsStartDuration?.inMilliseconds ?? 0;
      // 数据防御：credits 起点早于/等于片头结束（区间重叠/字段错位）时，
      // 有效起点取 introEnd+1s，避免刚跳过片头立刻弹"跳过片尾"误跳整集
      final effectiveCreditsStart = (creditsStart > introEnd) ? creditsStart : (introEnd + 1000);
      if (effectiveCreditsStart > 0 && posMs >= effectiveCreditsStart && posMs < _duration.inMilliseconds) {
        // 自动跳过片尾（距末尾>5s 时才跳）
        if (settings.autoSkipOutro && _duration.inMilliseconds - posMs > 5000) {
          AppLog.i('TVPlayer', '自动跳过片尾');
          final creditsEnd = introSkip.creditsEndDuration ?? _duration;
          _engine?.seek(creditsEnd);
          _danmakuController.seekTo(creditsEnd);
          return;
        }
        // 手动按钮
        if (settings.showSkipButton && _skipButtonLabel != '跳过片尾') {
          setState(() => _skipButtonLabel = '跳过片尾');
        }
        return;
      }
    }

    // 离开区间 → 清理按钮
    if (_skipButtonLabel == '跳过片头' && posMs >= introEnd) {
      setState(() => _skipButtonLabel = null);
    } else if (_skipButtonLabel == '跳过片尾') {
      final creditsStart = introSkip.creditsStartDuration?.inMilliseconds ?? 0;
      if (posMs < creditsStart || posMs >= _duration.inMilliseconds) {
        setState(() => _skipButtonLabel = null);
      }
    }
  }

  void _checkNextEpisode(Duration position) {
    if (_episodes.isEmpty || _currentEpisodeIndex >= _episodes.length - 1) return;
    final remaining = _duration - position;
    if (remaining.inSeconds <= 10 && remaining.inSeconds > 0 && !_showNextEpisode) {
      setState(() => _showNextEpisode = true);
      _startNextEpisodeCountdown();
    } else if (remaining.inSeconds > 10 && _showNextEpisode) {
      _cancelNextEpisode();
    }
  }

  void _startNextEpisodeCountdown() {
    _nextEpisodeCountdown = 10;
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _nextEpisodeCountdown--);
      if (_nextEpisodeCountdown <= 0) { timer.cancel(); _playNextEpisode(); }
    });
  }

  void _cancelNextEpisode() {
    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = null;
    if (mounted) setState(() => _showNextEpisode = false);
  }

  Future<void> _playNextEpisode() async {
    _cancelNextEpisode();
    if (_currentEpisodeIndex >= _episodes.length - 1) return;
    final nextEp = _episodes[_currentEpisodeIndex + 1];
    await _switchToEpisode(_currentEpisodeIndex + 1, nextEp);
  }

  Future<void> _playEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    await _switchToEpisode(index, _episodes[index]);
  }

  Future<void> _switchToEpisode(int index, MediaItem ep) async {
    final svc = widget.service;
    String url = '';
    if (svc != null) {
      try { url = await svc.getStreamUrl(ep.id); } catch (e) { AppLog.e('TVPlayer', '获取流URL失败: $e'); }
    }

    setState(() {
      _currentEpisodeIndex = index;
      _currentMedia = ep;
      _showEpisodePanel = false;
      _skipIntroHandled = false;
      _skipButtonLabel = null;
      _introSkip = null;
      _trickplayInfo = null;
      _tracksLoaded = false;
      _subtitleTracks = [];
      _danmakuController.setData([]);
      // 切集后从头播放，不续播
      _resumeApplied = false;
      _resumePositionMs = null;
    });
    _startHideControlsTimer();

    try {
      final manager = ref.read(playerManagerProvider);
      _engine = await manager.createEngine(url: url, httpHeaders: widget.httpHeaders ?? widget.service?.streamHeaders, autoPlay: true);
      _engineType = _engine!.engineType;
      _engineKey++;
      // 新剧集新建引擎，允许再次触发"有声无画" MPV 回退
      _engineFallbackTriggered = false;
      _stallRecoveryCount = 0;
      _stallStartTime = null;
      _stateSub?.cancel();
      _stateSub = _engine!.stateStream.listen(_handleEngineState);
      _engine!.applySubtitleStyle(ref.read(playerSettingsProvider));
      _loadIntroSkip();
      _loadTrickplayInfo();
      _loadDanmaku();
    } catch (e) {
      AppLog.e('TVPlayer', '切换剧集失败: $e');
    }
  }

  void _skipToIntroEnd() {
    final introSkip = _introSkip;
    if (introSkip == null) return;
    if (_skipButtonLabel == '跳过片头') {
      _engine?.seek(introSkip.introEndDuration);
      _danmakuController.seekTo(introSkip.introEndDuration);
    } else if (_skipButtonLabel == '跳过片尾') {
      // 优先用片尾结束时间，没有就用视频总时长
      final creditsEnd = introSkip.creditsEndDuration ?? _duration;
      _engine?.seek(creditsEnd);
      _danmakuController.seekTo(creditsEnd);
    }
    setState(() => _skipButtonLabel = null);
  }

  void _togglePlay() {
    // 图标 morph 即时响应按键（不等引擎状态回执），stateStream 到达后幂等同步
    if (_isPlaying) {
      _playPauseMorphCtrl.reverse();
      _engine?.pause();
    } else {
      _playPauseMorphCtrl.forward();
      _engine?.play();
    }
    _resetHideControlsTimer();
  }

  /// 播放/暂停图标 morph：播放中 → 暂停图标（forward），暂停 → 播放图标（reverse）。
  /// 幂等，可由 stateStream 高频调用。
  void _syncPlayPauseMorph() {
    if (_isPlaying) {
      _playPauseMorphCtrl.forward();
    } else {
      _playPauseMorphCtrl.reverse();
    }
  }

  /// 缓冲指示器：持续缓冲 300ms 后才淡入（避免短暂缓冲闪烁），
  /// 缓冲结束立即淡出。
  void _syncBufferingIndicator() {
    if (_isBuffering) {
      if (!_showBuffering && !(_bufferDelayTimer?.isActive ?? false)) {
        _bufferDelayTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted && _isBuffering && !_showBuffering) {
            setState(() => _showBuffering = true);
          }
        });
      }
    } else {
      _bufferDelayTimer?.cancel();
      _bufferDelayTimer = null;
      if (_showBuffering) setState(() => _showBuffering = false);
    }
  }

  void _seekRelative(int seconds) {
    final current = _seekTarget ?? _position;
    final newPos = current + Duration(seconds: seconds);
    final clamped = newPos < Duration.zero ? Duration.zero : (newPos > _duration ? _duration : newPos);
    // UI 即时更新（进度条 + 时间胶囊 + 预览图）
    setState(() { _seekTarget = clamped; _isSeeking = true; _showSeekIndicator = true; });
    _updatePreview(clamped);
    _resetHideControlsTimer();
    // seek 指示器 800ms 后淡出
    _seekIndicatorTimer?.cancel();
    _seekIndicatorTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) setState(() => _showSeekIndicator = false);
    });
    // 防抖：300ms 内无新 seek 才真正执行 engine.seek，快速连按只跳最终位置
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && _seekTarget != null) {
        _engine?.seek(_seekTarget!);
        _danmakuController.seekTo(_seekTarget!);
        setState(() { _seekTarget = null; _isSeeking = false; });
      }
    });
  }

  void _updatePreview(Duration position) {
    final trickplay = _trickplayInfo;
    final svc = widget.service;
    if (trickplay == null || svc is! JellyfinService) return;
    final positionMs = position.inMilliseconds;
    final frameIndex = positionMs ~/ trickplay.intervalMs;
    final sheetIndex = frameIndex ~/ trickplay.thumbnailCount;
    final tileInSheet = frameIndex % trickplay.thumbnailCount;
    final col = tileInSheet % trickplay.tileWidth;
    final row = tileInSheet ~/ trickplay.tileWidth;
    setState(() {
      _previewPosition = position;
      _previewTile = TrickplayTile(
        spriteSheetUrl: svc.getTrickplayTileUrl(widget.media.id, sheetIndex),
        col: col, row: row,
        gridWidth: trickplay.tileWidth, gridHeight: trickplay.tileHeight,
      );
    });
  }

  void _changeSpeed() {
    _currentSpeedIndex = (_currentSpeedIndex + 1) % _speeds.length;
    _speed = _speeds[_currentSpeedIndex];
    _engine?.setSpeed(_speed);
    _danmakuController.updateConfig(
      DanmakuRenderConfig.fromSettings(ref.read(danmakuDisplayProvider), playbackSpeed: _speed),
    );
    setState(() {});
    _resetHideControlsTimer();
  }

  void _toggleDanmaku() {
    _danmakuEnabled = !_danmakuEnabled;
    _danmakuController.setEnabled(_danmakuEnabled);
    setState(() {});
    _resetHideControlsTimer();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideControlsTimer();
      _requestButtonFocus();
    }
  }

  /// 遥控器按键唤出控制条（控制条隐藏时，任意键先显示控制条而不执行对应动作）
  void _showControlsFromKey() {
    if (_showControls) return;
    setState(() => _showControls = true);
    _startHideControlsTimer();
    _requestButtonFocus();
  }

  /// 控制栏显示后主动聚焦播放/暂停按钮（Netflix/Leanback 式：默认在按钮行）
  void _requestButtonFocus() {
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _showControls && !_showEpisodePanel) {
        _playPauseFocus.requestFocus();
      }
    });
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isPlaying) setState(() => _showControls = false);
    });
  }

  void _startPositionRefreshTimer() {
    _stopPositionRefreshTimer();
    _positionRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (_engine != null && mounted) {
        final pos = _engine!.currentState.position;
        setState(() {
          _position = pos;
        });
        // 同步检测片头片尾（引擎 stateStream 触发不频繁时的兜底）
        _checkSkipState(pos);
      }
    });
  }

  void _stopPositionRefreshTimer() {
    _positionRefreshTimer?.cancel();
    _positionRefreshTimer = null;
  }

  /// 续播：首次播放时 seek 到上次位置
  void _applyResumeIfNeeded() {
    if (_resumeApplied || _resumePositionMs == null || _engine == null) return;
    if (_duration.inMilliseconds < _resumePositionMs!) return;
    _resumeApplied = true;
    final target = Duration(milliseconds: _resumePositionMs!);
    AppLog.i('TVPlayer', 'Resume → seek to ${target.inMinutes}:${(target.inSeconds % 60).toString().padLeft(2, '0')}');
    _engine!.seek(target);
  }

  /// 启动进度保存定时器（每 10 秒）
  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _savePlaybackProgress();
    });
  }

  void _stopProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
  }

  /// 保存当前播放进度到本地观看历史
  void _savePlaybackProgress() {
    if (_engine == null || _isDisposed) return;
    if (_duration.inSeconds == 0) return;

    final positionMs = _position.inMilliseconds;
    final durationMs = _duration.inMilliseconds;
    final progress = durationMs > 0 ? positionMs / durationMs : 0.0;

    // 节流：距离上次保存不足 3 秒就跳过
    final now = DateTime.now();
    if (_lastSaveTime != null && now.difference(_lastSaveTime!).inSeconds < 3) return;
    _lastSaveTime = now;

    final media = _currentMedia ?? widget.media;
    final isCompleted = progress > 0.95;

    // 剧集信息
    int? seasonNumber;
    int? episodeNumber;
    String? seriesTitle;
    if (_episodes.isNotEmpty && _currentEpisodeIndex >= 0 && _currentEpisodeIndex < _episodes.length) {
      final ep = _episodes[_currentEpisodeIndex];
      seasonNumber = ep.seasonNumber;
      episodeNumber = ep.episodeNumber;
      seriesTitle = ep.seriesTitle ?? media.title;
    }

    final serverId = widget.service?.baseUrl;

    ref.read(watchHistoryProvider.notifier).addToHistory({
      'id': media.id,
      'title': media.title,
      'posterUrl': media.posterUrl,
      'backdropUrl': media.backdropUrl,
      'serverId': serverId,
      'progress': isCompleted ? 1.0 : progress,
      'positionMs': isCompleted ? 0 : positionMs,
      'durationMs': durationMs,
      'seasonNumber': seasonNumber,
      'episodeNumber': episodeNumber,
      'seriesTitle': seriesTitle,
      'updatedAt': now.millisecondsSinceEpoch,
    });
  }

  void _resetHideControlsTimer() {
    if (_showControls) _startHideControlsTimer();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    _isDisposed = true;
    _savePlaybackProgress();
    _nextEpisodeTimer?.cancel();
    _hideControlsTimer?.cancel();
    _bufferDelayTimer?.cancel();
    _playPauseMorphCtrl.dispose();
    _stopPositionRefreshTimer();
    _stopProgressSaveTimer();
    _stateSub?.cancel();
    _engineChangeSub?.cancel();
    _danmakuController.dispose();
    _engine?.stop();
    final manager = ref.read(playerManagerProvider);
    manager.disposeEngine();
    _playPauseFocus.dispose();
    _seekLeftFocus.dispose();
    _seekRightFocus.dispose();
    _speedFocus.dispose();
    _episodesFocus.dispose();
    _danmakuFocus.dispose();
    _subtitleFocus.dispose();
    _audioFocus.dispose();
    _progressBarFocus.dispose();
    _seekIndicatorTimer?.cancel();
    _seekDebounceTimer?.cancel();
    _stopLibass();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Android 系统返回键走 Navigator popRoute，不经过 Focus 按键事件，
    // 因此 TvShortcuts 的 onAnyKey/onBack 收不到它。用 PopScope 拦截：
    // 先关选集面板 → 控制条隐藏时先唤出控制条 → 最后才退出播放页。
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showEpisodePanel) {
          setState(() => _showEpisodePanel = false);
          _startHideControlsTimer();
        } else if (!_showControls) {
          // 控制栏隐藏时，按返回先显示控制栏
          _showControlsFromKey();
        } else {
          // 控制栏可见时，按返回退出播放器
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: TvShortcuts(
        // 控制条隐藏时，任意遥控器按键先唤出控制条（消费该键，不执行原动作/不退出）
        onAnyKey: (key) {
          if (!_showControls) {
            // 控制栏隐藏时：LEFT/RIGHT 直接 seek（不唤控制栏），其他键唤醒控制栏
            if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind) {
              _seekRelative(-10);
              return true;
            }
            if (key == LogicalKeyboardKey.arrowRight || key == LogicalKeyboardKey.mediaFastForward) {
              _seekRelative(10);
              return true;
            }
            _showControlsFromKey();
            return true;
          }
          return false;
        },
        onSelect: _togglePlay,
        onPlayPause: _togglePlay,
        onRewind: () => _seekRelative(-10),
        onFastForward: () => _seekRelative(10),
        onBack: () {
          // 遥控器返回键由 PopScope 统一拦截处理，此处不做任何操作
          // （Android 系统 BACK 走 Navigator popRoute → PopScope，不经过 Focus 按键）
        },
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 视频画面
              if (_engine != null)
                KeyedSubtree(
                  key: ValueKey('video_$_engineKey'),
                  child: _engine!.buildVideoWidget(),
                ),

              // 初始化错误
              if (_initError != null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white54, size: 64),
                      const SizedBox(height: 16),
                      Text(_initError!, style: const TextStyle(color: Colors.white54, fontSize: 16)),
                    ],
                  ),
                ),

              // 加载指示器（持续缓冲 300ms 才淡入，缓冲结束淡出，避免闪烁）
              if (_initError == null)
                Center(
                  child: AnimatedOpacity(
                    duration: AppAnimations.medium,
                    opacity: _showBuffering ? 1.0 : 0.0,
                    child: const CircularProgressIndicator(color: Colors.white),
                  ),
                ),

              // Seek 时间指示器：屏幕中央胶囊显示目标时间
              Center(
                child: AnimatedOpacity(
                  duration: AppAnimations.normal,
                  opacity: _showSeekIndicator ? 1.0 : 0.0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Text(
                      _formatDuration(_seekTarget ?? _position),
                      style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),

              // 弹幕渲染层（开关时 300ms 淡入淡出，而非瞬间消失）
              if (_screenWidth > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: AppAnimations.medium,
                      opacity: _danmakuEnabled ? 1.0 : 0.0,
                      child: DanmakuRenderer(
                        tickNotifier: _danmakuController.tickNotifier,
                        getActiveDanmaku: () => _danmakuController.activeDanmaku,
                        screenWidth: _screenWidth,
                        screenHeight: _screenHeight,
                      ),
                    ),
                  ),
                ),

              // libass 原生 ASS 字幕覆盖层
              if (_libassActive && _libassImage != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: RawImage(image: _libassImage, fit: BoxFit.fill),
                  ),
                ),

              // 跳过片头/片尾按钮
              if (_skipButtonLabel != null)
                Positioned(
                  right: 48, bottom: 140,
                  child: SkipButton(
                    label: _skipButtonLabel!,
                    onTap: _skipToIntroEnd,
                    onAutoExpire: () { if (mounted) setState(() => _skipButtonLabel = null); },
                  ),
                ),

              // 下一集倒计时
              if (_showNextEpisode && _episodes.isNotEmpty && _currentEpisodeIndex < _episodes.length - 1)
                Positioned(right: 48, bottom: 140, child: _buildNextEpisodeCard()),

              // 控制栏：顶栏从上方滑入/滑出，底栏从下方滑入/滑出 + 淡入淡出
              Column(
                children: [
                  IgnorePointer(
                    ignoring: !_showControls,
                    child: AnimatedSlide(
                      offset: _showControls ? Offset.zero : const Offset(0, -1),
                      duration: AppAnimations.medium,
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        duration: AppAnimations.medium,
                        opacity: _showControls ? 1.0 : 0.0,
                        child: _buildTopBar(),
                      ),
                    ),
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: AppAnimations.medium,
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: _showEpisodePanel
                          ? KeyedSubtree(
                              key: const ValueKey('episode_panel'),
                              child: _buildEpisodePanel(),
                            )
                          : KeyedSubtree(
                              key: const ValueKey('bottom_controls'),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: IgnorePointer(
                                  ignoring: !_showControls,
                                  child: AnimatedSlide(
                                    offset: _showControls ? Offset.zero : const Offset(0, 1),
                                    duration: AppAnimations.medium,
                                    curve: Curves.easeOutCubic,
                                    child: AnimatedOpacity(
                                      duration: AppAnimations.medium,
                                      opacity: _showControls ? 1.0 : 0.0,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [_buildPreviewBar(), _buildBottomControls()],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildTopBar() {
    final media = _currentMedia ?? widget.media;
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 32, 48, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  media.seriesTitle ?? media.title,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                if (media.seasonNumber != null || media.episodeNumber != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'S${media.seasonNumber ?? 1} · E${media.episodeNumber ?? _currentEpisodeIndex + 1} · ${_engineType.shortLabel}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBar() {
    final displayPosition = _seekTarget ?? _position;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          if (_previewTile != null && _isSeeking)
            _EntranceFade(
              begin: const Offset(0, 0.18),
              duration: AppAnimations.normal,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 240, height: 135,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white30, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _buildTrickplayTile(_previewTile!),
                            Positioned(
                              left: 8, bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _formatDuration(_previewPosition),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              SizedBox(width: 80, child: Text(_formatDuration(displayPosition), style: const TextStyle(color: Colors.white70, fontSize: 14))),
              Expanded(
                child: Focus(
                  focusNode: _progressBarFocus,
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft || event.logicalKey == LogicalKeyboardKey.mediaRewind) {
                      _seekRelative(-10);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight || event.logicalKey == LogicalKeyboardKey.mediaFastForward) {
                      _seekRelative(10);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                      _playPauseFocus.requestFocus();
                      _startHideControlsTimer();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _buildProgressBar(),
                ),
              ),
              SizedBox(width: 80, child: Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 14), textAlign: TextAlign.right)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final progress = _duration.inMilliseconds > 0
        ? ((_seekTarget ?? _position).inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    final bufferedProgress = _duration.inMilliseconds > 0
        ? (_buffer.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        // seek 时轨道加粗、thumb 放大，给出"正在操控"的反馈
        final double trackH = _isSeeking ? 8 : 4;
        final double thumbSize = _isSeeking ? 22 : 16;
        const sizeAnim = Duration(milliseconds: 200);
        return GestureDetector(
          onTap: _resetHideControlsTimer,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: progress),
            // 正常播放：300ms 线性补齐 250ms 采样间隔，进度条连续流动；
            // seek 期间：Duration.zero 瞬时跟随（直接操控，1:1 响应按键）
            duration: _isSeeking ? Duration.zero : const Duration(milliseconds: 300),
            curve: Curves.linear,
            builder: (context, value, _) {
              return Container(
                height: 24, alignment: Alignment.centerLeft,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    AnimatedContainer(
                      duration: sizeAnim, curve: Curves.easeOut,
                      height: trackH, width: totalWidth,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(trackH / 2)),
                    ),
                    AnimatedContainer(
                      duration: sizeAnim, curve: Curves.easeOut,
                      height: trackH, width: totalWidth * bufferedProgress,
                      decoration: BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.circular(trackH / 2)),
                    ),
                    Container(
                      height: trackH, width: totalWidth * value,
                      decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(trackH / 2)),
                    ),
                    Positioned(
                      left: (totalWidth * value - thumbSize / 2).clamp(0.0, totalWidth - thumbSize),
                      child: AnimatedContainer(
                        duration: sizeAnim, curve: Curves.easeOut,
                        width: thumbSize, height: thumbSize,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4)]),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTrickplayTile(TrickplayTile tile) {
    final tileWidth = 320 ~/ tile.gridWidth;
    final tileHeight = 180 ~/ tile.gridHeight;
    return OverflowBox(
      maxWidth: tile.gridWidth * tileWidth.toDouble(),
      maxHeight: tile.gridHeight * tileHeight.toDouble(),
      child: CachedNetworkImage(
        imageUrl: tile.spriteSheetUrl,
        httpHeaders: widget.service?.imageHeaders ?? const {},
        fit: BoxFit.none,
        alignment: Alignment(
          tile.gridWidth > 1 ? (tile.col * 2.0 / (tile.gridWidth - 1) - 1) : 0,
          tile.gridHeight > 1 ? (tile.row * 2.0 / (tile.gridHeight - 1) - 1) : 0,
        ),
        memCacheWidth: 320 * tile.gridWidth,
        errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(48, 24, 48, 48),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
        ),
      ),
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildIconButton(focusNode: _seekLeftFocus, icon: Icons.replay_10, onTap: () => _seekRelative(-10), onUp: () => _progressBarFocus.requestFocus(), onRight: () => _playPauseFocus.requestFocus()),
          const SizedBox(width: 32),
          _buildIconButton(
            focusNode: _playPauseFocus,
            onTap: _togglePlay,
            isPrimary: true,
            onUp: () => _progressBarFocus.requestFocus(),
            onLeft: () => _seekLeftFocus.requestFocus(),
            onRight: () => _seekRightFocus.requestFocus(),
            // 播放/暂停图标形变（morph），而非瞬间切换
            child: AnimatedIcon(
              icon: AnimatedIcons.play_pause,
              progress: _playPauseMorphCtrl,
              color: Colors.black,
              size: 36,
            ),
          ),
          const SizedBox(width: 32),
          _buildIconButton(focusNode: _seekRightFocus, icon: Icons.forward_10, onTap: () => _seekRelative(10), onUp: () => _progressBarFocus.requestFocus(), onLeft: () => _playPauseFocus.requestFocus(), onRight: () => _speedFocus.requestFocus()),
          const SizedBox(width: 48),
          _buildIconButtonWithLabel(focusNode: _speedFocus, icon: Icons.speed, label: '${_speed}x', onTap: _changeSpeed, onUp: () => _progressBarFocus.requestFocus(), onLeft: () => _seekRightFocus.requestFocus(), onRight: () => _focusNextAfter(_speedFocus)),
          _buildIconButtonWithLabel(
            focusNode: _danmakuFocus,
            label: _danmakuEnabled ? '弹幕' : '关',
            onTap: _toggleDanmaku,
            onUp: () => _progressBarFocus.requestFocus(),
            onLeft: () => _speedFocus.requestFocus(),
            onRight: () => _focusNextAfter(_danmakuFocus),
            // 弹幕开关图标交叉淡化切换
            child: AnimatedSwitcher(
              duration: AppAnimations.fast,
              child: Icon(
                _danmakuEnabled ? Icons.comment_bank_rounded : Icons.comments_disabled_outlined,
                key: ValueKey<bool>(_danmakuEnabled),
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          if (_subtitleTracks.isNotEmpty) ...[
            const SizedBox(width: 16),
            _buildIconButtonWithLabel(
              focusNode: _subtitleFocus,
              icon: Icons.subtitles_rounded,
              label: _currentSubtitleIndex >= 0 ? '字幕' : '无',
              onTap: () => _showSubtitleSelector(),
              onUp: () => _progressBarFocus.requestFocus(),
              onLeft: () => _danmakuFocus.requestFocus(),
              onRight: () => _focusNextAfter(_subtitleFocus),
            ),
          ],
          if (_audioTracks.isNotEmpty) ...[
            const SizedBox(width: 16),
            _buildIconButtonWithLabel(
              focusNode: _audioFocus,
              icon: Icons.audiotrack_rounded,
              label: '音轨',
              onTap: () => _showAudioSelector(),
              onUp: () => _progressBarFocus.requestFocus(),
              onLeft: () => _focusPrevBefore(_audioFocus),
              onRight: () => _focusNextAfter(_audioFocus),
            ),
          ],
          if (_episodes.isNotEmpty) ...[
            const SizedBox(width: 16),
            _buildIconButtonWithLabel(
              focusNode: _episodesFocus,
              icon: Icons.video_library_rounded,
              label: '选集',
              onUp: () => _progressBarFocus.requestFocus(),
              onLeft: () => _focusPrevBefore(_episodesFocus),
              onTap: () {
                setState(() {
                  _showEpisodePanel = true;
                  _showControls = true;
                });
                // 面板打开期间不自动隐藏控制栏
                _hideControlsTimer?.cancel();
              },
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// 按钮焦点导航：按顺序找到 current 之后第一个已挂载的 FocusNode 并聚焦
  void _focusNextAfter(FocusNode current) {
    final nodes = [_seekLeftFocus, _playPauseFocus, _seekRightFocus, _speedFocus, _danmakuFocus, _subtitleFocus, _audioFocus, _episodesFocus];
    final idx = nodes.indexOf(current);
    for (int i = idx + 1; i < nodes.length; i++) {
      if (nodes[i].context != null) { nodes[i].requestFocus(); return; }
    }
  }

  /// 按钮焦点导航：按顺序找到 current 之前第一个已挂载的 FocusNode 并聚焦
  void _focusPrevBefore(FocusNode current) {
    final nodes = [_seekLeftFocus, _playPauseFocus, _seekRightFocus, _speedFocus, _danmakuFocus, _subtitleFocus, _audioFocus, _episodesFocus];
    final idx = nodes.indexOf(current);
    for (int i = idx - 1; i >= 0; i--) {
      if (nodes[i].context != null) { nodes[i].requestFocus(); return; }
    }
  }

  void _showSubtitleSelector() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('选择字幕', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _subtitleTracks.length + 1,
            itemBuilder: (ctx, idx) {
              if (idx == 0) {
                return ListTile(
                  title: const Text('关闭字幕', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    _engine?.setSubtitleTrack(-1);
                    _stopLibass();
                    setState(() => _currentSubtitleIndex = -1);
                    Navigator.pop(ctx);
                  },
                );
              }
              final track = _subtitleTracks[idx - 1];
              final name = trackDisplayTitle(track, index: idx - 1);
              return ListTile(
                title: Text(
                  name,
                  style: TextStyle(color: _currentSubtitleIndex == idx - 1 ? AppTheme.primary : Colors.white),
                ),
                subtitle: track['language'] != null
                    ? Text(track['language']!, style: const TextStyle(color: Colors.white54, fontSize: 12))
                    : null,
                onTap: () async {
                  _stopLibass(); // 先停止旧的 libass 渲染
                  _engine?.setSubtitleTrack(-1); // 先清除引擎字幕
                  setState(() => _currentSubtitleIndex = idx - 1);
                  Navigator.pop(ctx);
                  // 尝试 libass 原生渲染（ASS/SSA），失败则回退引擎内置
                  final loaded = await _tryLoadLibassSubtitle(track);
                  if (!loaded) {
                    _engine?.setSubtitleTrack(idx - 1);
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // ===== libass 原生 ASS 字幕渲染 =====

  /// 尝试用 libass 加载 ASS/SSA 字幕。返回 true 表示成功激活，false 表示需要回退引擎内置。
  Future<bool> _tryLoadLibassSubtitle(Map<String, dynamic> track) async {
    final codec = (track['Codec'] ?? track['codec'] ?? '').toString().toLowerCase();
    if (codec != 'ass' && codec != 'ssa') return false; // 非 ASS 格式，走引擎内置

    // 获取字幕数据 URL
    final deliveryUrl = track['DeliveryUrl']?.toString() ?? '';
    if (deliveryUrl.isEmpty) return false;

    final svc = widget.service;
    final fullUrl = deliveryUrl.startsWith('http') ? deliveryUrl : '${svc?.baseUrl ?? ''}$deliveryUrl';

    try {
      // 下载 ASS 数据
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(fullUrl));
      svc?.streamHeaders.forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final bytes = await response.fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      client.close();

      if (bytes.isEmpty) return false;

      // 初始化 libass（使用视频分辨率或默认 1080p）
      final w = _libassWidth;
      final h = _libassHeight;
      final inited = await LibassBridge.init(width: w, height: h);
      if (!inited) {
        AppLog.w('TVPlayer', 'libass 不可用，回退引擎字幕');
        return false;
      }

      // 加载字幕数据
      final loaded = await LibassBridge.loadData(Uint8List.fromList(bytes));
      if (!loaded) {
        AppLog.w('TVPlayer', 'libass 加载字幕失败');
        await LibassBridge.release();
        return false;
      }

      // 成功：启动 libass 渲染循环（引擎字幕已由调用方清除）
      setState(() => _libassActive = true);
      _startLibassRender();
      AppLog.i('TVPlayer', 'libass 字幕已激活: ${bytes.length} bytes');
      return true;
    } catch (e) {
      AppLog.w('TVPlayer', 'libass 字幕加载异常: $e');
      return false;
    }
  }

  /// 启动 libass 渲染定时器（200ms 间隔，仅在字幕内容变化时更新 Image）
  void _startLibassRender() {
    _libassRenderTimer?.cancel();
    _libassRenderTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!_libassActive || _engine == null || !mounted) return;
      final posMs = _engine!.currentState.position.inMilliseconds;
      final pixels = await LibassBridge.render(posMs, _libassWidth, _libassHeight);
      if (pixels == null || pixels.isEmpty || !mounted) return;

      // ARGB bytes → ui.Image
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        _libassWidth,
        _libassHeight,
        ui.PixelFormat.rgba8888,
        (img) => completer.complete(img),
      );
      final newImage = await completer.future;
      if (!mounted) { newImage.dispose(); return; }
      setState(() {
        _libassImage?.dispose();
        _libassImage = newImage;
      });
    });
  }

  /// 停止 libass 渲染并释放资源
  void _stopLibass() {
    _libassRenderTimer?.cancel();
    _libassRenderTimer = null;
    _libassImage?.dispose();
    _libassImage = null;
    _libassActive = false;
    LibassBridge.release();
  }

  void _showAudioSelector() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('选择音轨', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _audioTracks.length,
            itemBuilder: (ctx, idx) {
              final track = _audioTracks[idx];
              final name = trackDisplayTitle(track, index: idx, prefix: '音轨');
              return ListTile(
                title: Text(
                  name,
                  style: TextStyle(color: _currentAudioIndex == idx ? AppTheme.primary : Colors.white),
                ),
                subtitle: track['language'] != null || track['codec'] != null
                    ? Text(
                        [track['language'], track['codec']]
                            .where((e) => e != null && e.toString().isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      )
                    : null,
                onTap: () {
                  _engine?.setAudioTrack(idx);
                  setState(() => _currentAudioIndex = idx);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({required FocusNode focusNode, IconData? icon, Widget? child, required VoidCallback onTap, bool isPrimary = false, VoidCallback? onUp, VoidCallback? onLeft, VoidCallback? onRight}) {
    return _FocusTap(
      focusNode: focusNode,
      onTap: onTap,
      onUp: onUp,
      onLeft: onLeft,
      onRight: onRight,
      builder: (context, isFocused, isPressed) {
        return SpringScale(
          focused: isFocused,
          pressed: isPressed,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            width: isPrimary ? 72 : 56,
            height: isPrimary ? 72 : 56,
            decoration: BoxDecoration(
              color: isPrimary ? Colors.white : (isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1)),
              shape: BoxShape.circle,
              border: isFocused && !isPrimary ? Border.all(color: Colors.white, width: 2) : null,
            ),
            // AnimatedIcon 不自居中（painter 仅 scale 从原点绘制），必须包 Center；普通 Icon 自带居中，Center 为无害空操作
            child: Center(
              child: child ?? Icon(icon!, color: isPrimary ? Colors.black : Colors.white, size: isPrimary ? 36 : 28),
            ),
          ),
        );
      },
    );
  }

  Widget _buildIconButtonWithLabel({required FocusNode focusNode, IconData? icon, Widget? child, required String label, required VoidCallback onTap, VoidCallback? onUp, VoidCallback? onLeft, VoidCallback? onRight}) {
    return _FocusTap(
      focusNode: focusNode,
      onTap: onTap,
      onUp: onUp,
      onLeft: onLeft,
      onRight: onRight,
      builder: (context, isFocused, isPressed) {
        return SpringScale(
          focused: isFocused,
          pressed: isPressed,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(24),
              border: isFocused ? Border.all(color: Colors.white, width: 2) : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                child ?? Icon(icon!, color: Colors.white, size: 20),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNextEpisodeCard() {
    if (_currentEpisodeIndex >= _episodes.length - 1) return const SizedBox.shrink();
    final nextEp = _episodes[_currentEpisodeIndex + 1];
    return NextEpisodeCard(
      title: nextEp.title,
      subtitle: nextEp.episodeNumber != null ? '第${nextEp.episodeNumber}集' : null,
      thumbnailUrl: nextEp.posterUrl.isNotEmpty ? nextEp.posterUrl : null,
      totalSeconds: 10,
      remainingSeconds: _nextEpisodeCountdown,
      onPlay: _playNextEpisode,
      onCancel: _cancelNextEpisode,
    );
  }

  Widget _buildEpisodePanel() {
    return _EntranceFade(
      begin: const Offset(0, 0.35),
      duration: AppAnimations.medium,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.95), Colors.black.withValues(alpha: 0.7)],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 48, 8),
              child: Row(
                children: [
                  const Text('剧集列表', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            SizedBox(
              height: 130,
              child: _episodes.isEmpty
                  ? const Center(child: Text('暂无剧集', style: TextStyle(color: Colors.white54, fontSize: 16)))
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        final ep = _episodes[index];
                        final isCurrent = index == _currentEpisodeIndex;
                        final epNum = ep.episodeNumber ?? (index + 1);
                        return Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: _EpisodeCard(episode: ep, episodeNumber: epNum, isCurrent: isCurrent, focusId: 'episode_$index', imageHeaders: widget.service?.imageHeaders ?? const {}, onTap: () => _playEpisode(index)),
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

class _EpisodeCard extends StatefulWidget {
  final MediaItem episode;
  final int episodeNumber;
  final bool isCurrent;
  final String focusId;
  final VoidCallback onTap;
  final Map<String, String> imageHeaders;

  const _EpisodeCard({required this.episode, required this.episodeNumber, required this.isCurrent, required this.focusId, required this.onTap, this.imageHeaders = const {}});

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.focusId);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final active = _isFocused || widget.isCurrent;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.select || event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.06 : 1.0,
          duration: Duration(milliseconds: active ? 280 : 200),
          curve: active ? Curves.easeOutBack : Curves.easeOut,
          child: AnimatedContainer(
            duration: Duration(milliseconds: active ? 280 : 200),
            width: 160,
            height: 90,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: active
                  ? Border.all(color: Colors.white, width: 2)
                  : Border.all(color: Colors.transparent, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 缩略图背景
                  widget.episode.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.episode.posterUrl,
                          httpHeaders: widget.imageHeaders,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Center(child: Icon(Icons.movie_outlined, color: Colors.white24, size: 20)),
                        ),
                  // 底部渐变 + 标题
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(6, 12, 6, 4),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                        ),
                      ),
                      child: Text(
                        widget.episode.title,
                        style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // 左上角集数（详情页同款：静止淡数字，聚焦 accent 胶囊）
                  Positioned(
                    top: 4, left: 5,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: active ? 280 : 200),
                      curve: active ? Curves.easeOutBack : Curves.easeOut,
                      padding: active
                          ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
                          : EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF6C63FF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${widget.episodeNumber}',
                        style: TextStyle(
                          color: active ? Colors.white : Colors.white.withValues(alpha: 0.4),
                          fontSize: active ? 9 : 8,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // 正在看 徽章
                  if (widget.isCurrent)
                    Positioned(
                      top: 4, right: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                        child: const Text('正在看', style: TextStyle(color: Colors.white, fontSize: 7, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放器按钮的焦点/按压状态壳：复用外部传入的 FocusNode，
/// 按键按下即刻触发回调并给出 150ms 按压反馈（统一弹簧焦点语言）。
class _FocusTap extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onTap;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final Widget Function(BuildContext context, bool focused, bool pressed) builder;

  const _FocusTap({required this.focusNode, required this.onTap, this.onUp, this.onLeft, this.onRight, required this.builder});

  @override
  State<_FocusTap> createState() => _FocusTapState();
}

class _FocusTapState extends State<_FocusTap> {
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(covariant _FocusTap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocus);
      widget.focusNode.addListener(_onFocus);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _focused = widget.focusNode.hasFocus);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final isSelect = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;
    if (isSelect && event is KeyDownEvent) {
      setState(() => _pressed = true);
      widget.onTap();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _pressed = false);
      });
      return KeyEventResult.handled;
    }
    if (isSelect) return KeyEventResult.handled;
    // UP 键：从按钮行回到进度条（两层焦点系统）
    if (event.logicalKey == LogicalKeyboardKey.arrowUp && event is KeyDownEvent) {
      if (widget.onUp != null) {
        widget.onUp!();
        return KeyEventResult.handled;
      }
    }
    // LEFT/RIGHT 键：显式导航到相邻按钮（绕过 Flutter 焦点遍历在 TV 上的不可靠行为）
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft && event is KeyDownEvent) {
      if (widget.onLeft != null) {
        widget.onLeft!();
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight && event is KeyDownEvent) {
      if (widget.onRight != null) {
        widget.onRight!();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(context, _focused, _pressed),
      ),
    );
  }
}

/// 挂载时执行一次的入场动画：位移 + 淡入。
/// 用于 Trickplay 预览、选集面板等"出现即入场"的浮层。
class _EntranceFade extends StatefulWidget {
  final Widget child;
  final Offset begin;
  final Duration duration;

  const _EntranceFade({
    required this.child,
    this.begin = const Offset(0, 0.2),
    this.duration = const Duration(milliseconds: 300),
  });

  @override
  State<_EntranceFade> createState() => _EntranceFadeState();
}

class _EntranceFadeState extends State<_EntranceFade>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween<Offset>(begin: widget.begin, end: Offset.zero).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(opacity: _ctrl, child: widget.child),
    );
  }
}