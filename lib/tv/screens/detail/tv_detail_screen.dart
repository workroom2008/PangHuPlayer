import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/media_library_provider.dart';
import '../../../theme/app_theme.dart';
import '../../../models/media_models.dart';
import '../../../services/media_server_service.dart';
import '../../../utils/app_log.dart';
import '../../../database/media_library_repository.dart';
import '../../../utils/animation_config.dart';
import '../../widgets/focusable_widgets.dart';
import '../../widgets/media_hero.dart';

class TvDetailScreen extends ConsumerStatefulWidget {
  final MediaItem item;
  final MediaServerService? service;

  /// 共享元素飞行 tag（由来源卡片传入；null 表示无 Hero，背景走入场动画）
  final String? heroTag;

  const TvDetailScreen({super.key, required this.item, this.service, this.heroTag});

  @override
  ConsumerState<TvDetailScreen> createState() => _TvDetailScreenState();
}

class _TvDetailScreenState extends ConsumerState<TvDetailScreen>
    with TickerProviderStateMixin {
  MediaItem? _full;
  bool _fav = false;
  bool _inPlaylist = false;
  List<MediaItem> _seasons = [], _episodes = [];
  String? _seasonId;
  bool _inLibrary = false;
  String? _libraryItemId;
  bool _checkingLibrary = true;
  MediaItem? _selectedEpisode;

  // 剧集加载状态：区分 加载中 / 失败 / 无数据 / 有数据（替代空列表永久转圈）
  // 初始为 true：剧集类型详情页必然会发起加载，避免先闪"暂无剧集数据"再转圈
  bool _episodesLoading = true;
  String? _episodesError;

  // 集数范围选择器：每段30集，当前段索引
  int _episodePageIndex = 0;

  // 取流中（播放键 loading morph + 防重复点击）
  bool _preparingPlay = false;

  // 续播记录
  Map<String, dynamic>? _resumeRecord;

  // 滚动控制
  final ScrollController _scrollCtrl = ScrollController();

  // ── 详情页入场动画：信息区自下而上分级浮现（Netflix 式 cascade）──
  late AnimationController _entranceCtrl;

  MediaItem get _item => _full ?? widget.item;
  MediaServerService? get _svc =>
      widget.service ?? ref.read(currentMediaServerServiceProvider);

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();

    final cachedItem = _loadFromCache();
    if (cachedItem != null) {
      _full = cachedItem;
      _inLibrary = true;
      _libraryItemId = cachedItem.id;
      _checkingLibrary = false;
    }
    _loadResumeInfo();
    _load();
    _checkFavorites();
    _checkPlaylist();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// 入场分级浮现：第 [order] 个区块依次延迟，24px 上移 + 淡入（easeOutCubic）。
  /// 用 Transform.translate 固定像素位移（SlideTransition 的 Offset 是相对自身高度）。
  Widget _entrance(int order, Widget child) {
    final start = (0.12 + order * 0.13).clamp(0.0, 1.0);
    final end = (start + 0.5).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        return Transform.translate(
          offset: Offset(0, 24 * (1 - anim.value)),
          child: Opacity(opacity: anim.value, child: child),
        );
      },
    );
  }

  MediaItem? _loadFromCache() {
    try {
      final mediaLib = ref.read(mediaLibraryProvider.notifier);
      return mediaLib.getItemById(widget.item.id) ??
          mediaLib.getItemByTitle(widget.item.title);
    } catch (_) {
      return null;
    }
  }

  /// 从观看历史中加载续播记录
  void _loadResumeInfo() {
    Future.microtask(() {
      final history = ref.read(watchHistoryProvider);
      final itemId = widget.item.id;
      final title = widget.item.title.trim();

      Map<String, dynamic>? match;

      if (widget.item.type == MediaType.series) {
        // series：按 seriesTitle 匹配，取最近一条且未看完的
        for (final h in history) {
          final seriesTitle = (h['seriesTitle'] as String?)?.trim();
          final hId = h['id'] as String?;
          if (seriesTitle == title || hId == itemId) {
            final pos = (h['positionMs'] as num?)?.toInt() ?? 0;
            final dur = (h['durationMs'] as num?)?.toInt() ?? 0;
            final progress = dur > 0 ? pos / dur : 0.0;
            // 跳过已看完（>95%）
            if (progress > 0.95) continue;
            if (match == null ||
                (h['updatedAt'] as int? ?? 0) >
                    (match['updatedAt'] as int? ?? 0)) {
              match = h;
            }
          }
        }
      } else {
        // 电影/单集：按 itemId 匹配
        for (final h in history) {
          if (h['id'] == itemId) {
            final pos = (h['positionMs'] as num?)?.toInt() ?? 0;
            final dur = (h['durationMs'] as num?)?.toInt() ?? 0;
            final progress = dur > 0 ? pos / dur : 0.0;
            if (progress > 0.95) continue;
            match = h;
            break;
          }
        }
      }

      if (match != null && mounted) {
        setState(() => _resumeRecord = match);
        // 续播到特定季集 → 自动切换季并选中集
        _applyResumeToSelection(match);
      }
    });
  }

  /// 根据续播记录自动切换季和选中集
  void _applyResumeToSelection(Map<String, dynamic> r) {
    final s = r['seasonNumber'] as int?;
    final e = r['episodeNumber'] as int?;
    if (s == null || e == null) return;
    // 季列表加载后会在 _loadSeasons 回调里匹配
    _pendingResumeSeason = s;
    _pendingResumeEpisode = e;
  }

  int? _pendingResumeSeason;
  int? _pendingResumeEpisode;

  Future<void> _checkFavorites() async {
    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId != null) {
      final service = await ref.read(favoriteServiceProvider.future);
      setState(() => _fav = service.isFavorite(tmdbId));
    }
  }

  Future<void> _checkPlaylist() async {
    final playlist = ref.read(playlistProvider);
    setState(() => _inPlaylist = playlist.any((p) => p.itemId == widget.item.id));
  }

  Future<void> _togglePlaylist() async {
    await ref.read(playlistProvider.notifier).togglePlaylist(_item);
    setState(() => _inPlaylist = !_inPlaylist);
  }

  Future<void> _load() async {
    final svc = _svc;
    if (svc == null) {
      if (mounted) setState(() => _checkingLibrary = false);
      return;
    }

    final serverId = _currentServerId();

    final cache = ref.read(mediaCacheProvider.notifier);
    final cachedId = cache.itemId(widget.item.title);

    // 优先从数据库缓存读取详情（本地SQLite，24小时TTL）
    final targetId = cachedId ?? widget.item.id;
    final dbCache = await _loadFromDbCache(serverId, targetId);
    if (dbCache != null && mounted) {
      setState(() {
        _full = dbCache;
        _inLibrary = true;
        _libraryItemId = dbCache.id;
        _checkingLibrary = false;
      });
      if (dbCache.type == MediaType.series) _loadSeasons(svc, dbCache.id);
    }

    if (cachedId != null) {
      if (mounted && _libraryItemId == null) {
        setState(() {
          _inLibrary = true;
          _libraryItemId = cachedId;
        });
      }
      _fetchFullDetails(svc, id: cachedId, serverId: serverId);
      return;
    }

    // 发起网络请求前先确保已认证：首页缓存新鲜时会跳过登录，
    // service 单例可能一直未认证，直接请求会 401
    await svc.ensureAuthenticated();

    await Future.any([
      svc.getItemDetails(widget.item.id).then((d) {
        if (!mounted) return;
        setState(() {
          _full = d;
          _inLibrary = true;
          _libraryItemId = d.id;
          _checkingLibrary = false;
        });
        _saveToDbCache(serverId, d);
        if (d.type == MediaType.series) _loadSeasons(svc, d.id);
      }).catchError((e) {
        AppLog.w('TvDetail', 'getItemDetails failed: $e');
      }),
      svc.search(widget.item.title).then((results) {
        if (!mounted || results.isEmpty) return;
        final match = results.firstWhere(
          (r) =>
              r.title.trim().toLowerCase() ==
              widget.item.title.trim().toLowerCase(),
          orElse: () => results.first,
        );
        if (mounted && _libraryItemId == null) {
          setState(() {
            _inLibrary = true;
            _libraryItemId = match.id;
          });
        }
      }).catchError((e) {
        AppLog.w('TvDetail', 'search failed: $e');
      }),
    ]);

    if (mounted) setState(() => _checkingLibrary = false);
  }

  String? _currentServerId() {
    final servers = ref.read(mediaServersProvider);
    return servers.where((s) => s.isDefault).firstOrNull?.id ?? servers.firstOrNull?.id;
  }

  Future<MediaItem?> _loadFromDbCache(String? serverId, String itemId) async {
    if (serverId == null) return null;
    try {
      return await MediaLibraryRepository.getDetailCache(serverId, itemId);
    } catch (e) {
      AppLog.w('TvDetail', 'DB cache read failed: $e');
      return null;
    }
  }

  Future<void> _saveToDbCache(String? serverId, MediaItem item) async {
    if (serverId == null) return;
    try {
      // libraryId 未知时使用空字符串（详情缓存不依赖 libraryId）
      await MediaLibraryRepository.saveDetailCache(serverId, '', item);
    } catch (e) {
      AppLog.w('TvDetail', 'DB cache save failed: $e');
    }
  }

  Future<void> _fetchFullDetails(MediaServerService svc, {String? id, String? serverId}) async {
    final targetId = id ?? _libraryItemId ?? widget.item.id;
    try {
      final d = await svc.getItemDetails(targetId);
      if (!mounted) return;
      setState(() {
        _full = d;
        _libraryItemId = d.id;
      });
      _saveToDbCache(serverId ?? _currentServerId(), d);
      if (d.type == MediaType.series) _loadSeasons(svc, d.id);
    } catch (e) {
      AppLog.w('TvDetail', 'fetchFullDetails failed for $targetId: $e');
    }
  }

  Future<void> _loadSeasons(MediaServerService svc, String id) async {
    setState(() {
      _episodesLoading = true;
      _episodesError = null;
    });
    try {
      final seasons = await svc.getSeasons(id);
      if (!mounted) return;
      setState(() {
        _seasons = seasons;
      });
      if (seasons.isNotEmpty) {
        // 优先切到续播记录的季
        String? targetSeasonId;
        if (_pendingResumeSeason != null) {
          final idx = _pendingResumeSeason! - 1;
          if (idx >= 0 && idx < seasons.length) {
            targetSeasonId = seasons[idx].id;
          }
        }
        _loadEpisodes(targetSeasonId ?? seasons.first.id);
      } else {
        // 季为空（无季数据）：结束加载，不视为错误
        setState(() => _episodesLoading = false);
      }
    } catch (e) {
      AppLog.w('TvDetail', 'loadSeasons failed: $e');
      if (!mounted) return;
      setState(() {
        _episodesLoading = false;
        _episodesError = '剧集信息加载失败';
      });
    }
  }

  Future<void> _loadEpisodes(String sid) async {
    final svc = _svc;
    if (svc == null) return;
    setState(() {
      _seasonId = sid;
      _selectedEpisode = null;
      _episodesLoading = true;
      _episodesError = null;
      _episodePageIndex = 0;
    });
    try {
      final eps = await svc.getEpisodes(_item.id, seasonId: sid);
      if (!mounted) return;
      // 如果有 pending 的续播集，选中它
      MediaItem? selected;
      if (_pendingResumeEpisode != null) {
        try {
          selected = eps.firstWhere(
            (e) => e.episodeNumber == _pendingResumeEpisode,
          );
        } catch (_) {}
        _pendingResumeEpisode = null;
        _pendingResumeSeason = null;
      }
      setState(() {
        _episodes = eps;
        _selectedEpisode = selected;
        _episodesLoading = false;
      });
    } catch (e) {
      AppLog.w('TvDetail', 'loadEpisodes failed: $e');
      if (!mounted) return;
      setState(() {
        _episodesLoading = false;
        _episodesError = '剧集信息加载失败';
      });
    }
  }

  /// 剧集加载失败后的重试：重新加载季（内部会联动加载剧集）
  void _retryLoadEpisodes() {
    final svc = _svc;
    if (svc == null) return;
    _loadSeasons(svc, _libraryItemId ?? _item.id);
  }

  Future<void> _play({MediaItem? episode}) async {
    final svc = _svc;
    if (svc == null) return;
    if (_preparingPlay) return; // 取流中，防止重复触发
    if (_libraryItemId == null || _libraryItemId!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('该媒体尚未在媒体库中')));
      return;
    }
    setState(() => _preparingPlay = true);

    // 决定播放哪一集
    MediaItem? playEpisode = episode ?? _selectedEpisode;
    int? resumePosMs;

    // 没有手动选集时，使用续播记录
    if (playEpisode == null && _resumeRecord != null) {
      final r = _resumeRecord!;
      final s = r['seasonNumber'] as int?;
      final e = r['episodeNumber'] as int?;
      if (s != null && e != null && _item.type == MediaType.series) {
        // 从已加载的剧集中查找匹配的季集
        playEpisode = _findEpisodeBySeasonEpisode(s, e);
      }
      resumePosMs = (r['positionMs'] as num?)?.toInt();
      // 小于 5 秒视为未观看
      if (resumePosMs != null && resumePosMs < 5000) {
        resumePosMs = null;
      }
    }

    // 兜底：剧集类型未选集且无续播记录时，默认播放第一集，
    // 并把真实的集对象传给播放器（否则传 series 对象，顶栏 S·E 行/弹幕匹配会失效）
    playEpisode ??= (_item.type == MediaType.series && _episodes.isNotEmpty)
        ? _episodes.first
        : null;

    final playId = playEpisode?.id ??
        (_item.type == MediaType.series && _episodes.isNotEmpty
            ? _episodes.first.id
            : _libraryItemId!);

    // 取流前确保已认证，避免拼出的流地址带空 api_key 导致播放 401 黑屏
    await svc.ensureAuthenticated();

    svc.getStreamUrl(playId).then((url) {
      if (!mounted) return;
      setState(() => _preparingPlay = false);
      context.push('/player/$playId', extra: {
        'media': playEpisode ?? _item,
        'url': url,
        'headers': svc.streamHeaders,
        if (_item.type == MediaType.series && _episodes.isNotEmpty)
          'episodes': _episodes,
        'service': svc,
        if (resumePosMs != null) 'resumePositionMs': resumePosMs,
      });
    }).catchError((e) {
      AppLog.e('TvDetail', 'getStreamUrl failed', e);
      if (mounted) {
        setState(() => _preparingPlay = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('获取播放链接失败: ${e.toString()}')));
      }
    });
  }

  /// 在已加载的剧集中按季号和集号查找
  MediaItem? _findEpisodeBySeasonEpisode(int season, int episode) {
    if (_episodes.isEmpty) return null;
    try {
      return _episodes.firstWhere(
        (e) => (e.seasonNumber == season || season == 1) && e.episodeNumber == episode,
      );
    } catch (_) {
      return null;
    }
  }

  void _toggleFav() async {
    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId == null) return;
    final service = await ref.read(favoriteServiceProvider.future);
    if (_fav) {
      await service.removeFavorite(tmdbId);
    } else {
      await service.addFavorite(TMDBMovie(
        id: tmdbId,
        title: widget.item.title,
        posterPath: widget.item.posterUrl.isNotEmpty
            ? widget.item.posterUrl
                .replaceAll('https://image.tmdb.org/t/p/w500', '')
            : null,
        backdropPath: widget.item.backdropUrl?.isNotEmpty == true
            ? widget.item.backdropUrl!
                .replaceAll('https://image.tmdb.org/t/p/w1280', '')
            : null,
        overview: widget.item.overview,
        voteAverage: widget.item.rating,
        releaseDate: widget.item.releaseDate,
      ));
    }
    setState(() => _fav = !_fav);
    ref.invalidate(favoriteMoviesProvider);
  }

  String _formatGenres() {
    if (_item.genres.isEmpty) return '';
    return _item.genres.take(4).join('  ·  ');
  }

  /// 播放按钮文字：优先显示续播信息
  String _playButtonLabel(int seasonNum, int selectedEpIndex) {
    // 手动选了集 → 显示集号
    if (_selectedEpisode != null) {
      return 'S$seasonNum·E$selectedEpIndex';
    }
    // 有续播记录 → 显示"继续 S1·E1 · 剩余 18分钟"
    final r = _resumeRecord;
    if (r != null) {
      final s = r['seasonNumber'] as int?;
      final e = r['episodeNumber'] as int?;
      final posMs = (r['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (r['durationMs'] as num?)?.toInt() ?? 0;
      final remainingMin = durMs > posMs ? (durMs - posMs) ~/ 60000 : 0;

      if (s != null && e != null) {
        return remainingMin > 0
            ? '继续 S$s·E$e · 剩余${remainingMin}分钟'
            : '继续 S$s·E$e';
      }
      return remainingMin > 0 ? '继续 · 剩余${remainingMin}分钟' : '继续观看';
    }
    return '播放';
  }

  // ==================== Build ====================

  @override
  Widget build(BuildContext context) {
    final backdropUrl = _item.backdropUrl?.isNotEmpty == true
        ? _item.backdropUrl!
        : (_item.posterUrl.isNotEmpty ? _item.posterUrl : '');

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.black),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ============ 固定全页背景图 ============
            Positioned.fill(child: _buildBackdrop(backdropUrl)),

            // ============ 滚动内容层 ============
            SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  // Hero 信息区（透明，背景图已固定在底层）
                  SizedBox(
                    height: 560,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned(
                          left: 64, right: 64, bottom: 80,
                          child: _buildHeroInfo(),
                        ),
                      ],
                    ),
                  ),
                  // Content below
                  if (_item.type == MediaType.series) ...[
                    _buildEpisodeSection(),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
            // Fixed top nav
            _buildTopBar(),
          ],
        ),
      ),
    );
  }

  // ==================== Backdrop (可选 Hero 共享元素飞行) ====================

  Widget _buildBackdrop(String backdropUrl) {
    final image = backdropUrl.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: backdropUrl,
            httpHeaders: _svc?.imageHeaders,
            memCacheWidth: 960,
            memCacheHeight: 540,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget: (_, __, ___) =>
                Container(color: const Color(0xFF0A0A0A)),
          )
        : Container(color: const Color(0xFF0A0A0A));

    final tag = widget.heroTag;
    if (tag == null) return image;

    // 轮播来源：飞行起点就是背景图本身；卡片来源：起点是海报（2:3 → 16:9 交叉淡化）
    final fromUrl = isCarouselHeroTag(tag) ? backdropUrl : _item.posterUrl;
    return Hero(
      tag: tag,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      flightShuttleBuilder: mediaFlightShuttle(
        fromUrl: fromUrl,
        toUrl: backdropUrl,
        headers: _svc?.imageHeaders,
        sourceRadius: isCarouselHeroTag(tag) ? 0 : 8,
      ),
      child: image,
    );
  }

  // ==================== Top Bar (TV端移除，遥控器通过Back键返回) ====================

  Widget _buildTopBar() {
    return const SizedBox.shrink();
  }

  // ==================== Hero Info (复刻 TvHero) ====================

  Widget _buildHeroInfo() {
    final isLoading = _checkingLibrary;
    final seasonNum = _seasons.indexWhere((s) => s.id == _seasonId) + 1;
    final selectedEpIndex = _selectedEpisode != null
        ? _episodes.indexWhere((e) => e.id == _selectedEpisode!.id) + 1
        : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Rating + Meta row ──
        _entrance(0, Row(
          children: [
            if (_item.rating != null && _item.rating! > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE50914),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _item.rating!.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            Text(
              _buildMetaText(),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                shadows: [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1))],
              ),
            ),
          ],
        )),
        // ── Genre line ──
        if (_item.genres.isNotEmpty) ...[
          const SizedBox(height: 6),
          _entrance(1, Text(
            _formatGenres(),
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(0, 1))],
            ),
          )),
        ],
        const SizedBox(height: 12),

        // ── Title (52sp/w900 — 复刻首页) ──
        _entrance(2, Text(
          _item.title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 52,
            fontWeight: FontWeight.w900,
            height: 1.1,
            letterSpacing: -0.5,
            shadows: [
              Shadow(color: Colors.black54, blurRadius: 12, offset: Offset(0, 2)),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        )),
        const SizedBox(height: 16),

        // ── Overview (3 lines) ──
        if (_item.overview != null && _item.overview!.isNotEmpty)
          _entrance(3, SizedBox(
            width: 560,
            child: Text(
              _item.overview!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.4,
                shadows: [Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 1))],
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          )),

        const SizedBox(height: 24),

        // ── Play button ──
        _entrance(4, Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 48),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white38),
                  ),
                ),
              )
            else if (!_inLibrary)
              _FocusableButton(
                focusId: 'detail_subscribe',
                onTap: () {},
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_download_rounded,
                          color: AppTheme.primary, size: 22),
                      SizedBox(width: 8),
                      Text('订阅',
                          style: TextStyle(
                              color: AppTheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              )
            else
              _FocusableButton(
                focusId: 'detail_play',
                onTap: () => _play(episode: _selectedEpisode),
                onFocusGained: _scrollToTop,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 取流期间播放图标 morph 为转圈（固定槽位保持按钮宽度稳定）
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: AnimatedSwitcher(
                          duration: AppAnimations.fast,
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          child: _preparingPlay
                              ? const SizedBox(
                                  key: ValueKey('loading'),
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5, color: Colors.black),
                                )
                              : const Icon(
                                  key: ValueKey('play'),
                                  Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 28,
                                ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _playButtonLabel(seasonNum, selectedEpIndex),
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_inLibrary) ...[
              const SizedBox(width: 12),
              _FocusableButton(
                focusId: 'detail_playlist',
                onTap: _togglePlaylist,
                onFocusGained: _scrollToTop,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _inPlaylist ? Icons.check : Icons.add_rounded,
                        color: Colors.white, size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _inPlaylist ? '已添加' : '加入片单',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_inLibrary &&
                _item.type == MediaType.series &&
                _seasons.isNotEmpty) ...[
              const SizedBox(width: 12),
              _FocusableButton(
                focusId: 'detail_season_tag',
                onTap: () => _showSeasonDialog(),
                onFocusGained: _scrollToTop,
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.list_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text('S$seasonNum',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        )),
      ],
    );
  }

  String _buildMetaText() {
    final parts = <String>[];
    if (_item.year != null) parts.add('${_item.year}');
    parts.add(_item.type == MediaType.series ? '剧集' : '电影');
    if (_item.duration > 0) parts.add('${_item.duration ~/ 60} 分钟');
    return parts.join(' · ');
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: AppAnimations.slow,
          curve: Curves.easeOutCubic);
    }
  }

  // ==================== Content Sections ====================

  void _showSeasonDialog() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '选择季',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.6, end: 1.0).animate(curved),
          alignment: Alignment.centerLeft,
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondaryAnim) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 360,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.6,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E3A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 12),
                    child: Text(
                      '选择季',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: _seasons.length,
                      itemBuilder: (_, i) {
                        final s = _seasons[i];
                        final sel = s.id == _seasonId;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _FocusableSeasonItem(
                            title: s.title,
                            isSelected: sel,
                            onTap: () {
                              Navigator.pop(ctx);
                              _loadEpisodes(s.id);
                            },
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
      },
    );
  }

  Widget _buildEpisodeSection() {
    // 加载失败：错误提示 + 可聚焦的重试按钮（替代原来的永久转圈）
    if (_episodesError != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
        child: SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    color: Colors.white.withValues(alpha: 0.4), size: 28),
                const SizedBox(height: 10),
                Text(
                  _episodesError!,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6), fontSize: 15),
                ),
                const SizedBox(height: 16),
                _FocusableButton(
                  focusId: 'retry_episodes',
                  onTap: _retryLoadEpisodes,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh,
                            size: 18,
                            color: Colors.white.withValues(alpha: 0.9)),
                        const SizedBox(width: 8),
                        Text(
                          '重试',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 15,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 加载中
    if (_episodesLoading) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
        child: SizedBox(
          height: 180,
          child: Center(
            child: SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    // 加载完成但无剧集数据
    if (_episodes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
          ),
        ),
        child: SizedBox(
          height: 100,
          child: Center(
            child: Text(
              '暂无剧集数据',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 15),
            ),
          ),
        ),
      );
    }

    // 计算分页
    const pageSize = 30;
    final totalPages = (_episodes.length / pageSize).ceil();
    final pageStart = _episodePageIndex * pageSize;
    final pageEnd = (pageStart + pageSize).clamp(0, _episodes.length);
    final pageEpisodes = _episodes.sublist(pageStart, pageEnd);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 28, 40, 14),
            child: Row(
              children: [
                _sectionHeader('剧集'),
                const Spacer(),
                // 集数范围选择器（>30集才显示）
                if (totalPages > 1) ..._buildRangeSelector(totalPages),
              ],
            ),
          ),
          SizedBox(
            height: 175,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) {
                final isIncoming =
                    child.key == ValueKey('eps_p$_episodePageIndex');
                final dx = isIncoming ? 0.04 : -0.04;
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(dx, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: FadeTransition(opacity: anim, child: child),
                );
              },
              child: ListView.builder(
                key: ValueKey('eps_p$_episodePageIndex'),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 8),
                itemCount: pageEpisodes.length,
                itemBuilder: (_, i) {
                  final ep = pageEpisodes[i];
                  final globalIndex = pageStart + i;
                  final isSelected = _selectedEpisode?.id == ep.id;
                  return _EpisodeCard(
                    episode: ep,
                    index: globalIndex,
                    isSelected: isSelected,
                    focusId: 'episode_$globalIndex',
                    onSelect: () =>
                        setState(() => _selectedEpisode = isSelected ? null : ep),
                    onPlay: () => _play(episode: ep),
                    imageHeaders: _svc?.imageHeaders,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 集数范围选择器胶囊按钮（1-30, 31-60, ...）
  List<Widget> _buildRangeSelector(int totalPages) {
    final widgets = <Widget>[];
    for (int p = 0; p < totalPages; p++) {
      final start = p * 30 + 1;
      final end = ((p + 1) * 30).clamp(0, _episodes.length);
      final isActive = p == _episodePageIndex;
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 8),
        child: _FocusableButton(
          focusId: 'range_$p',
          onTap: () => setState(() => _episodePageIndex = p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primary : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '$start-$end',
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ));
    }
    return widgets;
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }
}
// ==================== Focusable Button ====================

class _FocusableButton extends StatefulWidget {
  final String focusId;
  final VoidCallback onTap;
  final Widget child;
  final VoidCallback? onFocusGained;

  const _FocusableButton({
    super.key,
    required this.focusId,
    required this.onTap,
    required this.child,
    this.onFocusGained,
  });

  @override
  State<_FocusableButton> createState() => _FocusableButtonState();
}

class _FocusableButtonState extends State<_FocusableButton> {
  late FocusNode _focusNode;
  bool _isPressed = false;
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
    if (_focusNode.hasFocus) widget.onFocusGained?.call();
  }

  void _onPress() {
    setState(() => _isPressed = true);
    widget.onTap();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (mounted) setState(() => _isPressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _onPress();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _onPress,
        // 统一弹簧缩放：聚焦 1.08 微弹、按压 0.94，替代原先仅有按压、
        // 聚焦零反馈的实现（遥控器选中时看不出当前焦点在哪）
        child: SpringScale(
          focused: _isFocused,
          pressed: _isPressed,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: _isFocused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ==================== Episode Card (横屏景观卡片) ====================

class _EpisodeCard extends StatefulWidget {
  final MediaItem episode;
  final int index;
  final bool isSelected;
  final String focusId;
  final VoidCallback onSelect;
  final VoidCallback onPlay;
  final Map<String, String>? imageHeaders;

  const _EpisodeCard({
    required this.episode,
    required this.index,
    required this.isSelected,
    required this.focusId,
    required this.onSelect,
    required this.onPlay,
    this.imageHeaders,
  });

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
    final active = _isFocused || widget.isSelected;
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onSelect();
          return KeyEventResult.handled;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.mediaPlay ||
                event.logicalKey == LogicalKeyboardKey.mediaPlayPause)) {
          widget.onPlay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onSelect,
        child: AnimatedScale(
          scale: active ? 1.06 : 1.0,
          duration: Duration(milliseconds: active ? 280 : 200),
          curve: active ? Curves.easeOutBack : Curves.easeOut,
          child: Container(
            width: 240,
            height: 135,
            margin: const EdgeInsets.only(right: 16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 缩略图背景
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.episode.posterUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.episode.posterUrl,
                          httpHeaders: widget.imageHeaders,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              Container(color: const Color(0xFF1A1A2E)),
                        )
                      : Container(
                          color: const Color(0xFF1A1A2E),
                          child: const Center(
                            child: Icon(Icons.movie_outlined,
                                color: Colors.white24, size: 36),
                          ),
                        ),
                ),
                // 底部渐变 + 标题/时长
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 32, 14, 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.85),
                            ],
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.episode.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.episode.duration > 0) ...[
                              const SizedBox(height: 3),
                              Text(
                                '${widget.episode.duration ~/ 60} 分钟',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // 左上角集号角标：常驻淡数字，聚焦时 accent 胶囊激活
                Positioned(
                  top: 10,
                  left: 12,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: active ? 280 : 200),
                    curve: active ? Curves.easeOutBack : Curves.easeOut,
                    padding: active
                        ? const EdgeInsets.symmetric(horizontal: 8, vertical: 3)
                        : EdgeInsets.zero,
                    decoration: BoxDecoration(
                      color: active
                          ? const Color(0xFF6C63FF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${widget.index + 1}',
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        fontSize: active ? 12 : 11,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                // 右上角已观看对号（灰色圆形）
                if (widget.episode.isWatched == true)
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                // 选中/正在看 徽章
                if (widget.isSelected)
                  Positioned(
                    top: 10,
                    right: widget.episode.isWatched == true ? 42 : 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '正在看',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                // 聚焦边框（干净描边）
                Positioned.fill(
                  child: AnimatedOpacity(
                    duration: Duration(milliseconds: active ? 280 : 200),
                    curve: active ? Curves.easeOutBack : Curves.easeOut,
                    opacity: active ? 1.0 : 0.0,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选季弹窗中的可聚焦条目（D-pad 导航高亮）
class _FocusableSeasonItem extends StatefulWidget {
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  const _FocusableSeasonItem({
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_FocusableSeasonItem> createState() => _FocusableSeasonItemState();
}

class _FocusableSeasonItemState extends State<_FocusableSeasonItem> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: _isFocused
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: _isFocused
                ? Border.all(color: Colors.white, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: TextStyle(
                    color: widget.isSelected ? AppTheme.primary : Colors.white,
                    fontSize: 16,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
              if (widget.isSelected)
                const Icon(Icons.check, color: AppTheme.primary, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}