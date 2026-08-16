import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/http_client.dart';
import '../../providers/app_providers.dart';
import '../../providers/media_library_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../utils/app_log.dart';
import '../../utils/animation_config.dart';
import '../../widgets/server_image.dart';
import '../../widgets/tap_feedback.dart';
import '../../widgets/hero_flight.dart';
import '../danmaku/danmaku_screen.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final MediaItem item;
  final MediaServerService? service;
  final MediaServer? server;
  final String? resumeEpisodeId;

  /// 卡片侧 Hero tag（图一致性铁律：两侧必须同一 URL 的同一张图）。
  /// 媒体库入口用默认 `media_xxx_poster`；TMDB 入口由 fromTMDB/fromTMDBTV
  /// 传入 `movie_xxx_poster` / `tv_xxx_poster`（与卡片侧一致）。
  /// 为 null 时回退 `media_${item.id}_poster`。
  final String? heroTag;

  const DetailScreen({super.key, required this.item, this.service, this.server, this.resumeEpisodeId, this.heroTag});

  factory DetailScreen.fromTMDB(TMDBMovie movie) => DetailScreen(
    heroTag: 'movie_${movie.id}_poster',
    item: MediaItem(
    id: movie.id.toString(), title: movie.title,
    tmdbId: movie.id,
    posterUrl: movie.posterPath != null ? 'https://image.tmdb.org/t/p/w500${movie.posterPath}' : '',
    backdropUrl: movie.backdropPath != null ? 'https://image.tmdb.org/t/p/w1280${movie.backdropPath}' : null,
    overview: movie.overview, rating: movie.voteAverage,
    year: movie.releaseDate != null ? int.tryParse(movie.releaseDate!.substring(0, 4)) : null,
    releaseDate: movie.releaseDate, type: MediaType.movie,
  ));

  factory DetailScreen.fromTMDBTV(dynamic tv) => DetailScreen(
    heroTag: 'tv_${tv['id']}_poster',
    item: MediaItem(
    id: tv['id'].toString(),
    tmdbId: tv['id'],
    title: tv['name'] ?? tv['title'] ?? '',
    posterUrl: tv['poster_path'] != null ? 'https://image.tmdb.org/t/p/w500${tv['poster_path']}' : '',
    backdropUrl: tv['backdrop_path'] != null ? 'https://image.tmdb.org/t/p/w1280${tv['backdrop_path']}' : null,
    overview: tv['overview'],
    rating: tv['vote_average']?.toDouble(),
    year: tv['first_air_date'] != null ? int.tryParse(tv['first_air_date'].toString().substring(0, 4)) : null,
    releaseDate: tv['first_air_date']?.toString(),
    type: MediaType.series,
    totalSeasons: tv['number_of_seasons'],
    totalEpisodes: tv['number_of_episodes'],
  ));

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  MediaItem? _full;
  bool _fav = false;
  bool _expanded = false;
  List<MediaItem> _seasons = [], _episodes = [];
  String? _seasonId;
  bool _inLibrary = false;
  String? _libraryItemId;
  bool _checkingLibrary = true;
  bool _isSubscribed = false;
  String? _mpSubscribeId;
  bool _checkingSubscription = true;
  bool _subscribing = false;
  String? _playError; // 播放按钮内联错误态（获取播放链接失败时显示）
  List<MediaItem> _similarItems = []; // 相似推荐（服务端不支持时为空，不显示分区）
  List<Map<String, dynamic>> _credits = [];
  Color? _dominantColor;
  String _serverName = '';
  MediaItem? _selectedEpisode;
  bool _heroLanded = false;
  String? _resumeEpisodeId; // 从继续观看卡片传入的剧集ID
  final ScrollController _episodeScrollController = ScrollController();
  final ScrollController _scrollController = ScrollController(); // 主滚动：内容渐入触发
  final Set<String> _revealed = {}; // 已进入视口的区块（触发渐入）
  final Map<String, GlobalKey> _sectionKeys = {
    'overview': GlobalKey(),
    'episodes': GlobalKey(),
    'cast': GlobalKey(),
    'similar': GlobalKey(),
    'info': GlobalKey(),
  };
  int _episodeLoadGeneration = 0;

    MediaItem get _item => _full ?? widget.item;
    MediaServerService? get _svc => widget.service ?? ref.read(currentMediaServerServiceProvider);

    /// 详情页 Hero tag：外部传入优先（TMDB 入口），媒体库回退 media_xxx_poster
    String get _heroTag => widget.heroTag ?? 'media_${_item.id}_poster';

  /// 季选择药丸的统一宽度（滑动指示器需要固定宽度才能算偏移）
  static const double _seasonPillWidth = 92;

  /// 当前选中季在列表中的下标（未选中时回退到 0，避免指示器跑到 -1）
  int get _selectedSeasonIndex {
    final i = _seasons.indexWhere((s) => s.id == _seasonId);
    return i < 0 ? 0 : i;
  }

  @override
      void initState() {
        super.initState();
        _initReveal();
    
      // 从 widget 参数读取继续观看剧集 ID
            _resumeEpisodeId = widget.resumeEpisodeId;
    
      final cachedItem = _loadFromCache();
      if (cachedItem != null) {
        _full = cachedItem;
        _inLibrary = true;
        _libraryItemId = cachedItem.id;
        _checkingLibrary = false;
      }
    
      _loadServerName();
      _load();
      _checkFavorites();
    
      // 异步提取封面颜色（后台执行，不阻塞）
      _extractCoverColor();

      // Hero 飞行（300ms）落地后短暂停留，再触发 backdrop 交叉淡入（450ms ≈
      // route 350ms + Hero 100ms，poster 与 backdrop 交叉更紧凑，不悬空）
            Future.delayed(const Duration(milliseconds: 450), () {
              if (mounted) setState(() => _heroLanded = true);
            });
    }
  
  /// 后台提取封面颜色
  Future<void> _extractCoverColor() async {
    final imageUrl = _item.backdropUrl?.isNotEmpty == true
        ? _item.backdropUrl!
        : _item.posterUrl;
    if (imageUrl.isEmpty) return;

    try {
      final palette = await _extractPaletteFromUrl(imageUrl, 100, _svc?.imageHeaders);
      if (palette == null) return;
      // 优先选择更鲜艳的色彩作为背景，避免 dominant 颜色过暗导致背景呈黑色
      final color = palette.darkVibrantColor?.color
          ?? palette.vibrantColor?.color
          ?? palette.lightVibrantColor?.color
          ?? palette.dominantColor?.color;
      if (color != null && mounted) {
        setState(() => _dominantColor = color);
      }
    } catch (_) {}
  }

  /// 主 isolate 内执行：下载 → 缩放到 size x size → PaletteGenerator
  /// 缩放后只解码小图，避免下载/解码原始大图超时
  static Future<PaletteGenerator?> _extractPaletteFromUrl(
    String url,
    int size,
    Map<String, String>? headers,
  ) async {
    try {
      // 1. HttpClient 下载图片字节（rhttp 优先，Dio 回退）
      final bytes = await HttpClient.getBytes(
        url,
        headers: headers,
        timeout: const Duration(seconds: 10),
      );
      if (bytes.isEmpty) return null;

      // 2. 缩放到 size x size 并重新编码为 PNG
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: size,
        targetHeight: size,
      );
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final pngBytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (pngBytes == null) return null;

      // 3. 用 MemoryImage 喂给 PaletteGenerator
      return await PaletteGenerator.fromImageProvider(
        MemoryImage(pngBytes.buffer.asUint8List()),
        size: const Size(128, 128),
      );
    } on Exception catch (e) {
      AppLog.w('Detail', 'download failed: $e');
      return null;
    } catch (e) {
      AppLog.w('Detail', 'palette failed: $e');
      return null;
    }
  }

  void _loadServerName() {
    final servers = ref.read(mediaServersProvider);
    _serverName = widget.server?.name ?? servers.where((s) => s.isDefault).firstOrNull?.name ?? '';
  }

  MediaItem? _loadFromCache() {
    try {
      final mediaLib = ref.read(mediaLibraryProvider.notifier);
      final byId = mediaLib.getItemById(widget.item.id);
      if (byId != null) return byId;
      final byTitle = mediaLib.getItemByTitle(widget.item.title);
      return byTitle;
    } catch (_) {
      return null;
    }
  }

  Future<void> _checkSubscription() async {
    final mp = ref.read(moviePilotServiceProvider);
    final tmdbId = _item.tmdbId ?? int.tryParse(widget.item.id);
    if (mp == null || tmdbId == null) {
      if (mounted) setState(() => _checkingSubscription = false);
      return;
    }

    // 如果在本地媒体库中，不需要订阅
    if (_inLibrary) {
      if (mounted) setState(() {
        _isSubscribed = false;
        _mpSubscribeId = null;
        _checkingSubscription = false;
      });
      return;
    }

    try {
      AppLog.d('Detail', '_checkSubscription: tmdbId=$tmdbId');
      final sub = await mp.getSubscriptionByMediaId(tmdbId);
      // 关键修复：检查返回数据是否包含有效的订阅记录
      final hasValidSubscription = sub != null && sub['id'] != null;
      if (hasValidSubscription && mounted) {
        setState(() {
          _isSubscribed = true;
          _mpSubscribeId = sub['id']?.toString();
          _checkingSubscription = false;
        });
      } else if (mounted) {
        setState(() {
          _isSubscribed = false;
          _mpSubscribeId = null;
          _checkingSubscription = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingSubscription = false);
    }
  }

  Future<void> _checkFavorites() async {
    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId != null) {
      final service = await ref.read(favoriteServiceProvider.future);
      setState(() => _fav = service.isFavorite(tmdbId));
    }
  }

  Future<void> _load() async {
    final svc = _svc;
    if (svc == null) {
      if (mounted) setState(() => _checkingLibrary = false);
      _loadTMDBCredits();
      return;
    }

    // 先尝试从缓存获取（快速）
    final cache = ref.read(mediaCacheProvider.notifier);
    final cachedId = cache.itemId(widget.item.title);
    if (cachedId != null) {
      if (mounted) setState(() { _inLibrary = true; _libraryItemId = cachedId; });
      // 缓存命中时仍需获取详情，但放在后台
      _fetchFullDetails(svc);
      return;
    }

    // 缓存未命中，并行执行：获取详情 + 搜索匹配
    await Future.any([
      svc.getItemDetails(widget.item.id).then((d) {
        if (!mounted) return;
        setState(() { 
          _full = d; 
          _inLibrary = true; 
          _libraryItemId = d.id; 
          _checkingLibrary = false; 
        });
        if (d.type == MediaType.series) {
          _loadSeasonsAndEpisodes(svc, d.id);
        }
      }).catchError((_) {}),
      svc.search(widget.item.title).then((results) {
        if (!mounted || results.isEmpty) return;
        final match = results.firstWhere(
          (r) => r.title.trim().toLowerCase() == widget.item.title.trim().toLowerCase(),
          orElse: () => results.first,
        );
        if (mounted && _libraryItemId == null) {
          setState(() { _inLibrary = true; _libraryItemId = match.id; });
        }
      }).catchError((_) {}),
    ]);

    if (mounted) setState(() => _checkingLibrary = false);
    if (_inLibrary && _isSubscribed && mounted) {
      setState(() { _isSubscribed = false; _mpSubscribeId = null; });
    }
    _checkSubscription();
    _loadTMDBCredits();
    if (_libraryItemId != null) _loadSimilar(svc);
  }

  /// 加载相似推荐（服务端不支持时静默返回空，UI 不显示该分区）
  Future<void> _loadSimilar(MediaServerService svc) async {
    final id = _libraryItemId;
    if (id == null) return;
    try {
      final items = await svc.getSimilarItems(id);
      if (mounted && _similarItems.isEmpty) {
        setState(() => _similarItems = items);
      }
    } catch (e) {
      AppLog.w('Detail', '加载相似推荐失败: $e');
    }
  }

  Future<void> _fetchFullDetails(MediaServerService svc) async {
    try {
      final d = await svc.getItemDetails(widget.item.id);
      if (!mounted) return;
      setState(() { 
        _full = d; 
        _libraryItemId = d.id; 
      });
      if (d.type == MediaType.series) {
        _loadSeasonsAndEpisodes(svc, d.id);
      }
      _loadTMDBCredits();
    } catch (_) {}
  }

  Future<void> _loadSeasonsAndEpisodes(MediaServerService svc, String id) async {
    try {
      final seasons = await svc.getSeasons(id);
      if (!mounted) return;
      setState(() => _seasons = seasons);
      if (seasons.isEmpty) return;

      // 继续观看可能位于第二季以后。依次查找目标剧集所属季，
      // 找到后直接落到对应季；普通入口仍默认加载第一季。
      if (_resumeEpisodeId != null) {
        for (final season in seasons) {
          final episodes = await svc.getEpisodes(id, seasonId: season.id);
          if (!mounted) return;
          final targetIndex = episodes.indexWhere((e) => e.id == _resumeEpisodeId);
          if (targetIndex >= 0) {
            _episodeLoadGeneration++;
            setState(() {
              _seasonId = season.id;
              _episodes = episodes;
              _selectedEpisode = episodes[targetIndex];
            });
            _scrollToEpisode(targetIndex);
            return;
          }
        }
      }

      await _loadEpisodes(seasons.first.id);
    } catch (_) {}
  }

  Future<void> _loadTMDBCredits() async {
    // 先用媒体服务器数据
    if (_full != null && _full!.people != null && _full!.people!.isNotEmpty) {
      setState(() => _credits = _full!.people!.cast<Map<String, dynamic>>());
    }
    
    // 尝试用 TMDB 补全头像
    final tmdbId = _item.tmdbId ?? int.tryParse(widget.item.id);
    if (tmdbId == null) return;
    
    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      final tmdbCredits = await tmdbService.getMovieCredits(tmdbId);
      if (!mounted || tmdbCredits.isEmpty) return;
      
      // 构建 TMDB 头像映射：名字 -> profile_path
      final tmdbAvatarMap = <String, String>{};
      for (final c in tmdbCredits) {
        final name = (c['name'] as String?)?.trim() ?? '';
        final profilePath = c['profile_path'] as String?;
        if (name.isNotEmpty && profilePath != null && profilePath.isNotEmpty) {
          tmdbAvatarMap[name.toLowerCase()] = 'https://image.tmdb.org/t/p/w185$profilePath';
        }
      }
      
      // 合并：为缺头像的演员补全
      final mergedCredits = _credits.map((p) {
        final name = (p['name'] as String? ?? p['Name'] as String? ?? '').trim();
        final imgUrl = p['ImageUrl'] as String?;
        final hasImage = imgUrl != null && imgUrl.isNotEmpty;
        
        if (!hasImage) {
          final tmdbUrl = tmdbAvatarMap[name.toLowerCase()];
          if (tmdbUrl != null) {
            return Map<String, dynamic>.from(p)..['ImageUrl'] = tmdbUrl;
          }
        }
        return p;
      }).toList();
      
      // 如果 _credits 为空（非本地库内容），直接用 TMDB 数据
      if (_credits.isEmpty && mounted) {
        setState(() => _credits = tmdbCredits.cast<Map<String, dynamic>>());
      } else if (mounted) {
        setState(() => _credits = mergedCredits);
      }
    } catch (_) {}
  }

  Future<void> _loadEpisodes(String sid) async {
    final svc = _svc;
    if (svc == null) return;
    final generation = ++_episodeLoadGeneration;
    setState(() {
      _seasonId = sid;
      _selectedEpisode = null;
      _episodes = [];
    });
    try {
      final eps = await svc.getEpisodes(_item.id, seasonId: sid);
      if (!mounted || generation != _episodeLoadGeneration || sid != _seasonId) return;

      final selected = eps.isEmpty
          ? null
          : eps.firstWhere(
              (e) => e.isWatched != true,
              orElse: () => eps.first,
            );
      setState(() {
        _episodes = eps;
        _selectedEpisode = selected;
      });
      if (selected != null) {
        _scrollToEpisode(eps.indexOf(selected));
      }
    } catch (_) {}
  }

  void _scrollToEpisode(int index) {
    if (index < 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_episodeScrollController.hasClients) return;
      const itemExtent = 152.0; // 140px 卡片 + 12px 间距
      final viewport = _episodeScrollController.position.viewportDimension;
      final target = (index * itemExtent - (viewport - itemExtent) / 2).clamp(
        0.0,
        _episodeScrollController.position.maxScrollExtent,
      );
      _episodeScrollController.animateTo(
        target,
        duration: AppAnimations.medium,
        curve: AppAnimations.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _episodeScrollController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _initReveal() {
    _scrollController.addListener(_onScrollReveal);
    // 首帧先检查一次：首屏区块立即渐入，避免整页空白
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScrollReveal());
  }

  /// 滚动触发内容渐入：区块进入视口 90% 高度时开始淡入+上移
  void _onScrollReveal() {
    final screenH = MediaQuery.of(context).size.height;
    var changed = false;
    for (final entry in _sectionKeys.entries) {
      if (_revealed.contains(entry.key)) continue;
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top < screenH * 0.92) {
        _revealed.add(entry.key);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  /// 内容渐入包装：进入视口前透明+下移，进入后 450ms 淡入上移（占位不跳位）。
  /// [delay] 用于转场时的「内容分层进场」——首屏区块按顺序错峰（60ms 间隔），
  /// 形成 hero 先行、内容跟进的层级；滚动进入的区块 delay 为 0 立即渐入。
  Widget _reveal(String key, Widget child, {Duration delay = Duration.zero}) {
    final visible = _revealed.contains(key);
    final delayFraction = (delay.inMilliseconds / 450.0).clamp(0.0, 0.8);
    return KeyedSubtree(
      key: _sectionKeys[key],
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: visible ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 450),
        curve: Interval(delayFraction, 1.0, curve: Curves.easeOut),
        child: child,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 26 * (1 - t)),
            child: child,
          ),
        ),
      ),
    );
  }

  void _play({MediaItem? episode}) {
      final svc = _svc; if (svc == null) { AppLog.w('Detail', '_play: no service'); return; }
      // 无选中剧集时取第一集，传系列本身会导致播放器用系列ID查片头片尾数据（无数据）
      final target = episode ?? (_item.type == MediaType.series && _episodes.isNotEmpty ? _episodes.first : _item);
    
    if (_libraryItemId == null || _libraryItemId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('该媒体尚未在媒体库中，请先订阅')));
      return;
    }
    
    final playId = episode?.id ?? (_item.type == MediaType.series && _episodes.isNotEmpty ? _episodes.first.id : _libraryItemId!);
    AppLog.i('Detail', 'play: id=$playId title=${target.title} type=${target.type.name}');
    
    final ps = ref.read(playerSettingsProvider);
    final burnIn = ps.burnInSubtitle;
    svc.getStreamUrl(playId, quality: ps.defaultQuality, burnInSubtitle: burnIn).then((url) {
      AppLog.i('Detail', 'streamUrl=$url');
      if (!mounted) return;
      if (_playError != null) setState(() => _playError = null);

      // 统一使用 svc.streamHeaders，覆盖 Emby/Jellyfin/FnOS 各自的认证方式
      final headers = svc.streamHeaders;

      context.push('/player/$playId', extra: {
              'media': target, 'url': url, 'headers': headers,
              // 续播位置
              if (target.watchProgress != null && target.duration > 0)
                'resumePositionMs': (target.watchProgress! * target.duration * 1000).round(),
              // 新增：传入剧集列表和服务
              if (_item.type == MediaType.series && _episodes.isNotEmpty)
                'episodes': _episodes,
        'service': svc,
        'server': widget.server ?? ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull,
      });
    }).catchError((e) { 
      AppLog.e('Detail', 'getStreamUrl failed', e);
      // 错误态内联到播放按钮（点击重试），不再只弹一次性 SnackBar
      if (mounted) setState(() => _playError = '获取播放链接失败');
    });
  }

  Future<void> _subscribe() async {
    final mp = ref.read(moviePilotServiceProvider);
    if (mp == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先配置 MoviePilot'))); return; }
    AppLog.i('Detail', '_subscribe: START, item.id=${widget.item.id}, item.tmdbId=${_item.tmdbId}, item.title=${widget.item.title}');
    
    final tmdbId = _item.tmdbId ?? int.tryParse(widget.item.id);
    if (tmdbId == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无效的媒体ID'))); return; }
    
    if (mounted) setState(() => _subscribing = true);
    
    if (mp.username != null && mp.password != null && mp.apiKey == null) {
      final loginOk = await mp.login();
      AppLog.i('Detail', '_subscribe: loginOk=$loginOk');
      if (!loginOk) {
        if (mounted) {
          setState(() => _subscribing = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('MoviePilot 登录失败，请检查用户名密码')));
        }
        return;
      }
    }
    
    final tmdb = _item;
    AppLog.i('Detail', '_subscribe: calling createSubscribe - title=${tmdb.title}, tmdbId=$tmdbId, type=${tmdb.type == MediaType.series ? '电视剧' : '电影'}');
    final result = await mp.createSubscribe(
      title: tmdb.title, 
      tmdbId: tmdbId,
      type: tmdb.type == MediaType.series ? '电视剧' : '电影',
      year: tmdb.year?.toString(),
    );
    if (mounted) {
      setState(() => _subscribing = false);
      if (result != null) {
        AppLog.i('Detail', '_subscribe: SUCCESS - result=$result');
        setState(() {
          _isSubscribed = true;
          _mpSubscribeId = result['id']?.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('订阅成功，MoviePilot 将自动下载')));
      } else {
        AppLog.w('Detail', '_subscribe: FAILED - ${mp.lastError}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mp.lastError ?? '订阅失败，请检查服务器配置')),
        );
      }
    }
  }

  Future<void> _unsubscribe() async {
    final mp = ref.read(moviePilotServiceProvider);
    if (mp == null || _mpSubscribeId == null) return;
    
    final success = await mp.deleteSubscribe(_mpSubscribeId!);
    if (mounted) {
      if (success) {
        setState(() {
          _isSubscribed = false;
          _mpSubscribeId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已取消订阅')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('取消订阅失败')));
      }
    }
  }

  /// 标记为已观看（真实调用服务端 markWatched）
  Future<void> _markWatched() async {
    final svc = _svc;
    if (svc == null) return;
    final id = _libraryItemId ?? _item.id;
    try {
      await svc.markWatched(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已标记为已观看'), duration: Duration(seconds: 1)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('标记失败: $e')));
      }
    }
  }

  /// 分享：用默认浏览器打开服务器 Web 详情页（真实功能）
  Future<void> _shareItem() async {
    final server = widget.server ?? ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull;
    if (server == null) return;
    final url = '${server.url}/#!/details?id=${_item.id}';
    try {
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开浏览器')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('分享失败: $e')));
    }
  }

  /// 次级操作图标行：收藏 / 标记已看 / 分享（全部为真实功能）
  Widget _actionIconRow() {
    Widget roundIcon({
      required IconData icon,
      required Color color,
      required VoidCallback onTap,
      required String tooltip,
    }) {
      return Tooltip(
        message: tooltip,
        child: TapFeedback(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        roundIcon(
          icon: _fav ? Icons.favorite : Icons.favorite_border,
          color: _fav ? Colors.redAccent : Colors.white70,
          onTap: _toggleFav,
          tooltip: _fav ? '取消收藏' : '收藏',
        ),
        const SizedBox(width: 14),
        roundIcon(
          icon: Icons.comment_rounded,
          color: Colors.white70,
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DanmakuScreen())),
          tooltip: '弹幕源设置',
        ),
        if (_inLibrary) ...[
          const SizedBox(width: 14),
          roundIcon(
            icon: Icons.done_all_rounded,
            color: Colors.white70,
            onTap: _markWatched,
            tooltip: '标记已观看',
          ),
          const SizedBox(width: 14),
          roundIcon(
            icon: Icons.share_rounded,
            color: Colors.white70,
            onTap: _shareItem,
            tooltip: '分享',
          ),
        ],
      ],
    );
  }

  void _toggleFav() async {
    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId == null) return;
    
    final service = await ref.read(favoriteServiceProvider.future);
    if (_fav) {
      await service.removeFavorite(tmdbId);
    } else {
      final movie = TMDBMovie(
        id: tmdbId,
        title: widget.item.title,
        posterPath: widget.item.posterUrl.isNotEmpty ? widget.item.posterUrl.replaceAll('https://image.tmdb.org/t/p/w500', '') : null,
        backdropPath: widget.item.backdropUrl?.isNotEmpty == true ? widget.item.backdropUrl!.replaceAll('https://image.tmdb.org/t/p/w1280', '') : null,
        overview: widget.item.overview,
        voteAverage: widget.item.rating,
        releaseDate: widget.item.releaseDate,
      );
      await service.addFavorite(movie);
    }
    setState(() => _fav = !_fav);
    ref.invalidate(favoriteMoviesProvider);
  }

  @override
  Widget build(BuildContext c) {
    // 详情页背景始终是深色（封面或主色调），所以文字应该用浅色
    return Scaffold(
      backgroundColor: _dominantColor ?? Colors.black,
      body: SingleChildScrollView(
        controller: _scrollController,
        child: _buildContent(c),
      ),
    );
  }

  Widget _buildContent(BuildContext c) {
      final hasBackdrop = _item.backdropUrl?.isNotEmpty == true;
      final hasPoster = _item.posterUrl.isNotEmpty;
      final backdropUrl = hasBackdrop ? _item.backdropUrl! : (hasPoster ? _item.posterUrl : '');
      final posterUrl = hasPoster ? _item.posterUrl : backdropUrl;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          // 480px 背景区域：两层叠加
          // 1. 底层：backdrop 背景图（落地后淡入）
          // 2. Hero 层：poster 海报（飞行中保持与卡片一致，落地后淡出让给 backdrop）
          SizedBox(height: 480, width: double.infinity, child: Stack(
            fit: StackFit.expand,
            children: [
              // 底层：backdrop 背景（若无 backdrop 则用 poster 兜底）
              if (backdropUrl.isNotEmpty)
                AnimatedOpacity(
                  opacity: _heroLanded ? 1.0 : 0.0,
                  duration: AppAnimations.medium,
                  curve: AppAnimations.easeOut,
                  child: ServerImage(
                    imageUrl: backdropUrl,
                    headers: _svc?.imageHeaders,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(color: Colors.black),
                  ),
                ),
              // Hero 层：poster 海报（飞行途中的视觉锚点，落地后淡出）
              if (posterUrl.isNotEmpty && backdropUrl.isNotEmpty)
                Positioned.fill(
                  child: _heroLanded
                      ? const SizedBox.shrink()
                      : Hero(
                                                tag: _heroTag,
                                                flightShuttleBuilder: heroFlightShuttle,
                                                child: ServerImage(
                            imageUrl: posterUrl,
                            headers: _svc?.imageHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(color: Colors.black),
                          ),
                        ),
                )
              else if (posterUrl.isNotEmpty)
                Hero(
                  tag: _heroTag,
                  flightShuttleBuilder: heroFlightShuttle,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(0),
                    child: ServerImage(
                      imageUrl: posterUrl,
                      headers: _svc?.imageHeaders,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: Colors.black),
                    ),
                  ),
                )
              else
                Container(color: Colors.black),
            ],
          )),
        Positioned.fill(child: Container(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.black.withValues(alpha: 0.3), Colors.black.withValues(alpha: 0), Colors.black.withValues(alpha: 0.1), Colors.black.withValues(alpha: 0.4), _dominantColor ?? Colors.black],
          stops: const [0.0, 0.2, 0.5, 0.8, 1.0])))),
        Positioned(top: MediaQuery.of(c).padding.top + 8, left: 8, right: 8, child: Row(children: [
                  TapFeedback(
                    onTap: () => Navigator.pop(c),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)), child: Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22)),
                  ),
                  const Spacer(),
                  if (_serverName.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(20)), child: Text(_serverName, style: const TextStyle(color: Colors.white, fontSize: 12))),
                  SizedBox(width: 8),
                  TapFeedback(
                    onTap: _toggleFav,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)), child: Icon(_fav ? Icons.favorite : Icons.favorite_border, color: _fav ? Colors.red : Colors.white, size: 22)),
                  ),
                ])),
        Positioned(bottom: 0, left: 0, right: 0, child: Padding(padding: const EdgeInsets.fromLTRB(20, 60, 20, 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_item.title, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold, height: 1.2, shadows: [Shadow(color: Colors.black54, blurRadius: 8)])),
          SizedBox(height: 8), _meta(),
          if (_item.genres.isNotEmpty) ...[SizedBox(height: 12), _genreTags()],
          SizedBox(height: 20), _actionButtons(),
          SizedBox(height: 14), _actionIconRow(),
        ]))),
      ]),
      // 转场内容分层进场：首屏区块按 60ms 错峰（hero 先行、内容跟进）
      if (_item.overview != null && _item.overview!.isNotEmpty) ...[SizedBox(height: 20), _reveal('overview', _overview(), delay: const Duration(milliseconds: 0))],
      if (_item.type == MediaType.series) ...[
        _reveal('episodes', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_seasonPicker(), _episodeList()]), delay: const Duration(milliseconds: 60)),
      ],
      _reveal('cast', _castSection(), delay: const Duration(milliseconds: 120)),
      _reveal('similar', _similarSection(), delay: const Duration(milliseconds: 180)),
      _reveal('info', _mediaInfoSection(), delay: const Duration(milliseconds: 240)),
      SizedBox(height: 80),
    ]);
  }

  Widget _actionButtons() {
    final isChecking = _checkingLibrary || _checkingSubscription;
    final isLoading = isChecking || _subscribing;
    final seasonNum = _seasons.indexWhere((s) => s.id == _seasonId) + 1;
        final selectedEpIndex = _selectedEpisode != null ? _episodes.indexWhere((e) => e.id == _selectedEpisode!.id) + 1 : 0;
        final hasResume = _selectedEpisode?.watchProgress != null && _selectedEpisode!.watchProgress! > 0;

    // 四种状态各自带唯一 key，AnimatedSwitcher 才能识别状态切换并做过渡。
    // 这里用 AnimatedSwitcher 是正确的（内容真的换了），
    // 与底部导航栏那处误用（内容不变只变样式）不同。
    final Widget current;
    if (isLoading) {
      current = Container(
        key: ValueKey('loading_$_subscribing'),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38)),
          SizedBox(width: 8),
          Text(_subscribing ? '订阅中...' : '查询中...', style: TextStyle(color: Colors.white38, fontSize: 16))
        ]));
    } else if (_playError != null) {
      // 错误态内联：获取播放链接失败时按钮切换为「点击重试」
      current = GestureDetector(
        key: const ValueKey('play_error'),
        onTap: () => _play(episode: _selectedEpisode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded, color: AppTheme.error, size: 20),
            const SizedBox(width: 8),
            Text(_playError!, style: const TextStyle(color: AppTheme.error, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('点击重试', style: TextStyle(color: AppTheme.error.withValues(alpha: 0.8), fontSize: 13)),
          ]),
        ),
      );
    } else if (_inLibrary) {
      final progress = _selectedEpisode?.watchProgress ?? _item.watchProgress;
      final resume = hasResume || (progress != null && progress > 0);
      final subLabel = _selectedEpisode != null
          ? '第$seasonNum季 第$selectedEpIndex集'
          : (_item.type == MediaType.series && _seasons.isNotEmpty
              ? '第$seasonNum季 · 共${_episodes.length}集'
              : (_item.duration > 0 ? '${_item.duration ~/ 60}分钟' : ''));
      current = GestureDetector(
        key: const ValueKey('play'),
        onTap: () => _play(episode: _selectedEpisode),
        child: Container(
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6)),
            ],
          ),
          child: Stack(
            children: [
              // 续播进度覆盖（Streama 风格）：从左到右填充，
              // 进度语义=已观看部分，与进度条方向一致
              if (resume)
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (progress ?? 0).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(26),
                    ),
                  ),
                ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow_rounded, color: Colors.black, size: 26),
                        SizedBox(width: 8),
                        Text(
                          resume ? '继续观看' : '播放',
                          style: const TextStyle(color: Colors.black, fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    if (subLabel.isNotEmpty)
                      Text(
                        subLabel,
                        style: TextStyle(color: Colors.black.withValues(alpha: 0.55), fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_isSubscribed) {
      current = GestureDetector(
        key: const ValueKey('subscribed'),
        onTap: _unsubscribe,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_outline_rounded, color: AppTheme.primary, size: 28),
            SizedBox(width: 8),
            Text('已订阅·等待下载', style: TextStyle(color: AppTheme.primary, fontSize: 17, fontWeight: FontWeight.w600))
          ]),
        ),
      );
    } else {
      current = GestureDetector(
        key: const ValueKey('subscribe'),
        onTap: _subscribe,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppTheme.primary.withValues(alpha: 0.5))),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.cloud_download_rounded, color: AppTheme.primary, size: 28),
            SizedBox(width: 8),
            Text('订阅', style: TextStyle(color: AppTheme.primary, fontSize: 17, fontWeight: FontWeight.w600))
          ]),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      // 状态切换时内容淡入淡出 + 高度平滑变化，不再是「换了个按钮」的硬跳
      child: AnimatedSwitcher(
        duration: AppAnimations.medium,
        switchInCurve: AppAnimations.easeOut,
        switchOutCurve: AppAnimations.easeIn,
        layoutBuilder: (currentChild, previousChildren) => Stack(
          alignment: Alignment.center,
          children: [...previousChildren, if (currentChild != null) currentChild],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.center,
            child: child,
          ),
        ),
        child: current,
      ),
    );
  }

  Widget _meta() {
    final p = <Widget>[];
    if (_item.year != null) p.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Text('${_item.year}', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
    ));
    if (_item.type == MediaType.series) p.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Text('剧集', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
    ));
    else p.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Text('电影', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
    ));
    if (_item.duration > 0) p.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Text('${_item.duration ~/ 60}分钟', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
    ));
    if (_item.rating != null && _item.rating! > 0) p.add(Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [Icon(Icons.star_rounded, color: AppTheme.primary, size: 16), SizedBox(width: 2), Text(_item.rating!.toStringAsFixed(1), style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14, fontWeight: FontWeight.w500))]),
    ));
    return Wrap(spacing: 8, runSpacing: 4, children: p);
  }

  Widget _genreTags() {
    if (_item.genres.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, children: _item.genres.map((g) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(20)),
      child: Text(g, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12)),
    )).toList());
  }

  Widget _overview() => Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(16)),
    // AnimatedSize 让文字区域平滑长高/缩短，下方内容跟着平移而非突然跳位
    child: AnimatedSize(
      duration: AppAnimations.medium,
      curve: AppAnimations.easeInOut,
      alignment: Alignment.topCenter,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_item.overview!, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.7),
          maxLines: _expanded ? null : 4, overflow: TextOverflow.fade),
        if (_item.overview!.length > 200)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // 按钮文字随状态切换（原实现恒为「收起」，收起状态下也显示「收起」）
                Text(_expanded ? '收起' : '展开', style: const TextStyle(color: AppTheme.primary, fontSize: 12)),
                const SizedBox(width: 2),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0.0,
                  duration: AppAnimations.medium,
                  curve: AppAnimations.easeInOut,
                  child: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.primary, size: 16),
                ),
              ]),
            ),
          ),
      ]),
    ),
  ));

  Widget _seasonPicker() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Text('季', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      // 选中态用滑动药丸而非直接换色：一个紫色药丸从旧位置滑到新位置，
      // 选中感连续，不是「熄灭一个再点亮另一个」两次独立突变。
      // 药丸宽度需固定才能算出偏移，因此每项统一 _seasonPillWidth。
      SizedBox(
        height: 50,
        child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            SizedBox(
              width: _seasons.length * (_seasonPillWidth + 12),
              child: Stack(children: [
                // 底层：未选中背景
                Row(children: List.generate(_seasons.length, (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(
                    width: _seasonPillWidth,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ))),
                // 滑动指示器
                AnimatedPositioned(
                  duration: AppAnimations.navPill,
                  curve: AppAnimations.easeOut,
                  left: _selectedSeasonIndex * (_seasonPillWidth + 12) + 6,
                  top: 0,
                  child: Container(
                    width: _seasonPillWidth,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // 顶层：文字 + 点击区
                Row(children: List.generate(_seasons.length, (i) {
                  final s = _seasons[i];
                  final sel = s.id == _seasonId;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => _loadEpisodes(s.id),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: _seasonPillWidth,
                        height: 44,
                        child: Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: sel ? 1.0 : 0.0),
                            duration: AppAnimations.navPill,
                            curve: AppAnimations.easeOut,
                            builder: (_, t, __) => Text(
                              s.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Color.lerp(Colors.white70, Colors.white, t),
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                })),
              ]),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _episodeList() {
    if (_episodes.isEmpty) return SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Text('剧集', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(height: 160, child: ListView.builder(
        controller: _episodeScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _episodes.length,
        itemBuilder: (_, i) {
          final ep = _episodes[i];
          final isSelected = _selectedEpisode?.id == ep.id;
          return GestureDetector(
            onTap: () => setState(() => _selectedEpisode = isSelected ? null : ep),
            child: Transform.scale(
              scale: isSelected ? 1.02 : 1.0,
              child: Container(
                width: 140, margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected ? Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2) : null,
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 140, height: 82,
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
                        child: ep.posterUrl.isNotEmpty
                            ? ServerImage(imageUrl: ep.posterUrl, headers: _svc?.imageHeaders, fit: BoxFit.cover, errorWidget: (_, __, ___) => Center(child: Icon(Icons.movie, color: Colors.white24, size: 32)))
                            : Center(child: Icon(Icons.play_circle_outline, color: Colors.white24, size: 32)),
                      ),
                    ),
                    Positioned.fill(child: Center(child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), shape: BoxShape.circle),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 24),
                    ))),
                    Positioned(top: 4, left: 4, child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(6)),
                      child: Text('E${ep.episodeNumber ?? i + 1}', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    )),
                    if (ep.isWatched == true) Positioned(top: 4, right: 4, child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: AppTheme.success, borderRadius: BorderRadius.circular(4)),
                      child: Icon(Icons.check, color: Colors.white, size: 12),
                    )),
                    // 续播进度条：未看完的剧集底部显示进度（Streama 卡片风格）
                    if (ep.watchProgress != null && ep.watchProgress! > 0 && ep.watchProgress! < 0.98)
                      Positioned(left: 0, right: 0, bottom: 0, child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: SizedBox(
                          height: 4,
                          child: LinearProgressIndicator(
                            value: ep.watchProgress!.clamp(0.0, 1.0),
                            backgroundColor: Colors.black.withValues(alpha: 0.55),
                            color: AppTheme.primary,
                          ),
                        ),
                      )),
                  ]),
                  SizedBox(height: 8),
                  Text(ep.title, style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (ep.duration > 0) Text('${ep.duration ~/ 60}分钟', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ]),
              ),
            ),
          );
        },
      )),
    ]);
  }

  Widget _castSection() {
    if (_credits.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Text('演员', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(height: 130, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _credits.length, itemBuilder: (_, i) {
        final p = _credits[i];
        final name = (p['name'] as String? ?? p['Name'] as String? ?? '').trim();
        final role = (p['character'] as String? ?? p['Role'] as String? ?? '').trim();
        final imgPath = p['profile_path'] as String?;
        final imgUrl = p['ImageUrl'] as String?;
        String? img;
        if (imgUrl != null && imgUrl.isNotEmpty) {
          img = imgUrl;
        } else if (imgPath != null && imgPath.isNotEmpty) {
          img = 'https://image.tmdb.org/t/p/w185$imgPath';
        }
        return Container(width: 90, margin: const EdgeInsets.only(right: 12), child: Column(children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: Container(width: 70, height: 90, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
            child: img != null && img.isNotEmpty ? CachedNetworkImage(imageUrl: img, fit: BoxFit.cover, errorWidget: (_, __, ___) => Icon(Icons.person, color: Colors.white38, size: 32))
              : Icon(Icons.person, color: Colors.white38, size: 32))),
          SizedBox(height: 6),
          Flexible(child: Text(name.isNotEmpty ? name : '未知', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (role.isNotEmpty) Flexible(child: Text(role, style: TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]));
      })),
    ]);
  }

  /// 相似推荐横向海报卡（点击进入对应详情页）
  Widget _similarSection() {
    if (_similarItems.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10), child: Text('相关推荐', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
      SizedBox(
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: _similarItems.length,
          itemBuilder: (_, i) {
            final item = _similarItems[i];
            return GestureDetector(
              onTap: () {
                if (item.tmdbId != null) {
                  context.push('/detail/tmdb_${item.tmdbId}', extra: {'item': item});
                } else {
                  context.push('/detail/${item.id}', extra: {'item': item, 'server': widget.server});
                }
              },
              child: Container(
                width: 110,
                margin: const EdgeInsets.only(right: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: ServerImage(
                        imageUrl: item.posterUrl,
                        headers: _svc?.imageHeaders,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(color: Colors.white.withValues(alpha: 0.08), child: const Icon(Icons.movie, color: Colors.white24, size: 28)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
                  if (item.year != null) Text('${item.year}', style: TextStyle(color: Colors.white38, fontSize: 10)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _mediaInfoSection() {
    if (!_inLibrary) return const SizedBox.shrink();

    final hasVideo = _item.videoTracks?.isNotEmpty == true;
    final hasAudio = _item.audioTracks?.isNotEmpty == true;
    final hasSubtitle = _item.subtitleTracks?.isNotEmpty == true;

    if (!hasVideo && !hasAudio && !hasSubtitle) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: _MediaInfoTabs(item: _item),
    );
  }
}

/// 媒体信息 Tab 组件：视频/音频/字幕 三个可左右滑动的 Tab
class _MediaInfoTabs extends StatefulWidget {
  final MediaItem item;
  const _MediaInfoTabs({required this.item});

  @override
  State<_MediaInfoTabs> createState() => _MediaInfoTabsState();
}

class _MediaInfoTabsState extends State<_MediaInfoTabs>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_TabInfo> _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<_TabInfo> _buildTabs() {
    final item = widget.item;
    final tabs = <_TabInfo>[];
    if (item.videoTracks?.isNotEmpty == true) {
      tabs.add(_TabInfo(
        label: '视频',
        icon: Icons.video_library_rounded,
        iconColor: AppTheme.primary,
        count: item.videoTracks!.length,
      ));
    }
    if (item.audioTracks?.isNotEmpty == true) {
      tabs.add(_TabInfo(
        label: '音频',
        icon: Icons.audiotrack_rounded,
        iconColor: Colors.blue,
        count: item.audioTracks!.length,
      ));
    }
    if (item.subtitleTracks?.isNotEmpty == true) {
      tabs.add(_TabInfo(
        label: '字幕',
        icon: Icons.subtitles_rounded,
        iconColor: Colors.green,
        count: item.subtitleTracks!.length,
      ));
    }
    return tabs;
  }

  /// Key 归一化
  String _s(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return '';
  }

  Widget _infoTag(String text, {double? maxW}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      constraints: maxW != null ? BoxConstraints(maxWidth: maxW) : null,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white60, fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text('媒体信息', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (item.duration > 0)
                  _infoTag(_formatDuration(item.duration)),
              ],
            ),
          ),
          // 文件概要
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (item.title.isNotEmpty) _infoTag(item.title, maxW: 200),
                for (final tab in _tabs)
                  _infoTag('${tab.label} ×${tab.count}'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Tab 栏
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AppTheme.primary,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            dividerColor: Colors.white12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: _tabs.map((t) => Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(t.icon, color: t.iconColor, size: 15),
                  const SizedBox(width: 5),
                  Text('${t.label} (${t.count})'),
                ],
              ),
            )).toList(),
          ),
          // Tab 内容区（可左右滑动）
          SizedBox(
            height: _calcTabContentHeight(),
            child: TabBarView(
              controller: _tabController,
              children: _tabs.map((t) => _buildTabContent(t)).toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 根据轨道数量动态计算 Tab 内容区高度
  double _calcTabContentHeight() {
    // 取当前 Tab 中轨道数量最多的来估算高度
    // 视频每条约 60px, 音频每条约 55px, 字幕每条约 30px
    double maxH = 60;
    final item = widget.item;
    if (_tabController.index < _tabs.length) {
      final tab = _tabs[_tabController.index];
      if (tab.label == '视频') {
        maxH = item.videoTracks!.length * 68.0;
      } else if (tab.label == '音频') {
        maxH = item.audioTracks!.length * 62.0;
      } else {
        maxH = item.subtitleTracks!.length * 36.0;
      }
    }
    return maxH.clamp(60.0, 280.0);
  }

  Widget _buildTabContent(_TabInfo tab) {
    final item = widget.item;
    if (tab.label == '视频' && item.videoTracks != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: item.videoTracks!.map((t) => _videoTrackDetail(t)).toList(),
        ),
      );
    } else if (tab.label == '音频' && item.audioTracks != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: item.audioTracks!.map((t) => _audioTrackDetail(t)).toList(),
        ),
      );
    } else if (tab.label == '字幕' && item.subtitleTracks != null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: item.subtitleTracks!.map((t) => _subtitleTrackDetail(t)).toList(),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h > 0) return '${h}h${m}m';
    return '${m}min';
  }

  Widget _videoTrackDetail(Map<String, dynamic> t) {
    final codec = _s(t, ['Codec', 'codec', 'codec_name']);
    final width = _s(t, ['Width', 'width']);
    final height = _s(t, ['Height', 'height']);
    final fps = _s(t, ['FrameRate', 'frame_rate', 'r_frame_rate', 'avg_frame_rate']);
    final bitrateVal = (t['Bitrate'] ?? t['bitrate']) as num?;
    final bitrate = bitrateVal != null ? '${(bitrateVal / 1000).toStringAsFixed(0)} kbps' : '';
    final profile = _s(t, ['Profile', 'profile']);
    final bitDepth = _s(t, ['BitDepth', 'bit_depth', 'bits_per_raw_sample']);
    final colorSpace = _s(t, ['ColorSpace', 'color_space']);
    final colorTransfer = _s(t, ['ColorTransfer', 'color_transfer']);
    final pixFmt = _s(t, ['PixelFormat', 'pix_fmt']);
    final resolution = (width.isNotEmpty && height.isNotEmpty) ? '${width}×$height' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (codec.isNotEmpty) Text(codec.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              if (resolution.isNotEmpty) ...[const SizedBox(width: 8), _infoTag(resolution)],
              if (bitrate.isNotEmpty) ...[const SizedBox(width: 6), _infoTag(bitrate)],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (fps.isNotEmpty) _infoTag('${fps}fps'),
            if (profile.isNotEmpty) _infoTag(profile),
            if (bitDepth.isNotEmpty) _infoTag('${bitDepth}bit'),
            if (colorSpace.isNotEmpty) _infoTag(colorSpace),
            if (colorTransfer.isNotEmpty) _infoTag(colorTransfer),
            if (pixFmt.isNotEmpty) _infoTag(pixFmt),
          ]),
        ],
      ),
    );
  }

  Widget _audioTrackDetail(Map<String, dynamic> t) {
    final lang = _s(t, ['Language', 'language', 'lang']);
    final codec = _s(t, ['Codec', 'codec', 'codec_name']);
    final channelsVal = (t['Channels'] ?? t['channels']) as num?;
    final channels = channelsVal != null ? '${channelsVal.toInt()}ch' : '';
    final bitrateVal = (t['Bitrate'] ?? t['bitrate']) as num?;
    final bitrate = bitrateVal != null ? '${(bitrateVal / 1000).toStringAsFixed(0)} kbps' : '';
    final profile = _s(t, ['Profile', 'profile']);
    final sampleRate = _s(t, ['SampleRate', 'sample_rate']);
    final isDefault = t['IsDefault'] == true || t['is_default'] == true;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (lang.isNotEmpty) Text(lang, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              if (codec.isNotEmpty) ...[const SizedBox(width: 6), Text(codec.toUpperCase(), style: const TextStyle(color: Colors.white60, fontSize: 12))],
              if (isDefault) ...[const SizedBox(width: 6), _infoTag('默认')],
            ],
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 4, children: [
            if (channels.isNotEmpty) _infoTag(channels),
            if (bitrate.isNotEmpty) _infoTag(bitrate),
            if (profile.isNotEmpty) _infoTag(profile),
            if (sampleRate.isNotEmpty) _infoTag('${sampleRate}Hz'),
          ]),
        ],
      ),
    );
  }

  Widget _subtitleTrackDetail(Map<String, dynamic> t) {
    final lang = _s(t, ['Language', 'language', 'lang']);
    final codec = _s(t, ['Codec', 'codec', 'codec_name']);
    final isForced = t['IsForced'] == true || t['is_forced'] == true;
    final isDefault = t['IsDefault'] == true || t['is_default'] == true;
    final title = _s(t, ['Title', 'title', 'display_title']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          if (lang.isNotEmpty) Text(lang, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
          if (codec.isNotEmpty) ...[const SizedBox(width: 6), Text(codec, style: const TextStyle(color: Colors.white54, fontSize: 11))],
          if (isDefault) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: const Text('默认', style: TextStyle(color: AppTheme.primary, fontSize: 10)))],
          if (isForced) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)), child: const Text('强制', style: TextStyle(color: Colors.amber, fontSize: 10)))],
          if (title.isNotEmpty) ...[const SizedBox(width: 6), Text(title, style: const TextStyle(color: Colors.white38, fontSize: 11), overflow: TextOverflow.ellipsis)],
        ],
      ),
    );
  }
}

class _TabInfo {
  final String label;
  final IconData icon;
  final Color iconColor;
  final int count;
  _TabInfo({required this.label, required this.icon, required this.iconColor, required this.count});
}


