import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../widgets/track_selector_sheet.dart';
import '../../widgets/server_subtitle_search_sheet.dart';
import '../../widgets/credit_list.dart';

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

  const DetailScreen(
      {super.key,
      required this.item,
      this.service,
      this.server,
      this.resumeEpisodeId,
      this.heroTag});

  factory DetailScreen.fromTMDB(TMDBMovie movie) => DetailScreen(
      heroTag: 'movie_${movie.id}_poster',
      item: MediaItem(
        id: movie.id.toString(),
        title: movie.title,
        tmdbId: movie.id,
        posterUrl: movie.posterPath != null
            ? 'https://image.tmdb.org/t/p/w500${movie.posterPath}'
            : '',
        backdropUrl: movie.backdropPath != null
            ? 'https://image.tmdb.org/t/p/w1280${movie.backdropPath}'
            : null,
        overview: movie.overview,
        rating: movie.voteAverage,
        year: movie.releaseDate != null
            ? int.tryParse(movie.releaseDate!.substring(0, 4))
            : null,
        releaseDate: movie.releaseDate,
        type: MediaType.movie,
      ));

  factory DetailScreen.fromTMDBTV(dynamic tv) => DetailScreen(
      heroTag: 'tv_${tv['id']}_poster',
      item: MediaItem(
        id: tv['id'].toString(),
        tmdbId: tv['id'],
        title: tv['name'] ?? tv['title'] ?? '',
        posterUrl: tv['poster_path'] != null
            ? 'https://image.tmdb.org/t/p/w500${tv['poster_path']}'
            : '',
        backdropUrl: tv['backdrop_path'] != null
            ? 'https://image.tmdb.org/t/p/w1280${tv['backdrop_path']}'
            : null,
        overview: tv['overview'],
        rating: tv['vote_average']?.toDouble(),
        year: tv['first_air_date'] != null
            ? int.tryParse(tv['first_air_date'].toString().substring(0, 4))
            : null,
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
  bool _watched = false;
  String? _selectedSubtitleLang; // 详情页预设的默认字幕语言（剧集全部集生效）
  String? _selectedAudioLang; // 详情页预设的默认音频语言
  List<MediaItem> _seasons = [], _episodes = [];
  String? _seasonId;
  bool _inLibrary = false;
  String? _libraryItemId;
  bool _checkingLibrary = true;
  String? _playError; // 播放按钮内联错误态（获取播放链接失败时显示）
  List<MediaItem> _similarItems = []; // 相似推荐（服务端不支持时为空，不显示分区）
  List<Map<String, dynamic>> _credits = [];
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
  MediaServerService? get _svc =>
      widget.service ?? ref.read(currentMediaServerServiceProvider);

  /// 详情页 Hero tag：外部传入优先（TMDB 入口），媒体库回退 media_xxx_poster
  String get _heroTag => widget.heroTag ?? 'media_${_item.id}_poster';

  /// 音/字幕轨道的有效来源媒体：
  /// - 电影：媒体本身（getItemDetails 已带 MediaStreams）
  /// - 剧集：当前选中集（Series 级对象没有 MediaSources/MediaStreams，
  ///   轨道属于具体剧集；未选中时回退第一集）
  MediaItem get _trackItem =>
      _item.type == MediaType.series && _episodes.isNotEmpty
          ? (_selectedEpisode ?? _episodes.first)
          : _item;

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

    _load();
    _checkFavorites();

    // 读取详情页预设的默认字幕/音频偏好（跨剧集全局生效）
    final ps = ref.read(playerSettingsProvider);
    _selectedSubtitleLang = ps.defaultSubtitleLang;
    _selectedAudioLang = ps.defaultAudioLang;
    _watched = widget.item.isWatched == true;

    // 异步提取封面颜色（后台执行，不阻塞）
    // Hero 飞行（300ms）落地后短暂停留，再触发 backdrop 交叉淡入（450ms ≈
    // route 350ms + Hero 100ms，poster 与 backdrop 交叉更紧凑，不悬空）
    Future.delayed(const Duration(milliseconds: 450), () {
      if (mounted) setState(() => _heroLanded = true);
    });
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

  Future<void> _checkFavorites() async {
    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId != null) {
      final service = await ref.read(favoriteServiceProvider.future);
      setState(() => _fav = service.isFavorite(tmdbId));
    } else if (_inLibrary) {
      // 服务器媒体 id 是 GUID，非 TMDB id：收藏状态来自服务端返回的 isFavorite
      setState(() => _fav = _item.isFavorite == true);
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
      if (mounted)
        setState(() {
          _inLibrary = true;
          _libraryItemId = cachedId;
        });
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
          if (int.tryParse(widget.item.id) == null) _fav = d.isFavorite == true;
          _watched = _watched || d.isWatched == true;
        });
        if (d.type == MediaType.series) {
          _loadSeasonsAndEpisodes(svc, d.id);
        }
        // 搜索可能先于详情返回，详情到达后必须再次加载演员数据。
        _loadTMDBCredits();
      }).catchError((_) {}),
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
      }).catchError((_) {}),
    ]);

    if (mounted) setState(() => _checkingLibrary = false);
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
        // 服务器媒体：同步服务端返回的收藏/已观看状态
        if (int.tryParse(widget.item.id) == null) _fav = d.isFavorite == true;
        _watched = _watched || d.isWatched == true;
      });
      if (d.type == MediaType.series) {
        _loadSeasonsAndEpisodes(svc, d.id);
      }
      _loadTMDBCredits();
    } catch (_) {}
  }

  Future<void> _loadSeasonsAndEpisodes(
      MediaServerService svc, String id) async {
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
          final targetIndex =
              episodes.indexWhere((e) => e.id == _resumeEpisodeId);
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

    // 尝试用 TMDB 补全头像（剧集用 getTVCredits，电影用 getMovieCredits）
    final tmdbId = _item.tmdbId ?? int.tryParse(widget.item.id);
    if (tmdbId == null) return;

    try {
      final tmdbService = ref.read(tmdbServiceProvider);
      // 根据媒体类型选择正确的 credits 接口
      final tmdbCredits = _item.type == MediaType.series
          ? await tmdbService.getTVCredits(tmdbId)
          : await tmdbService.getMovieCredits(tmdbId);
      if (!mounted || tmdbCredits.isEmpty) return;

      // 构建 TMDB 头像映射：名字 -> profile_path（大小写不敏感）
      final tmdbAvatarMap = <String, String>{};
      // 构建 TMDB 角色映射：名字 -> character（补全服务器缺失的角色信息）
      final tmdbRoleMap = <String, String>{};
      for (final c in tmdbCredits) {
        final name = (c['name'] as String?)?.trim() ?? '';
        final profilePath = c['profile_path'] as String?;
        final character = (c['character'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) {
          if (profilePath != null && profilePath.isNotEmpty) {
            tmdbAvatarMap[name.toLowerCase()] =
                'https://image.tmdb.org/t/p/w185$profilePath';
          }
          if (character.isNotEmpty) {
            tmdbRoleMap[name.toLowerCase()] = character;
          }
        }
      }

      // 合并：为缺头像/缺角色的演员补全
      final mergedCredits = _credits.map((p) {
        final name =
            (p['name'] as String? ?? p['Name'] as String? ?? '').trim();
        final imgUrl = p['ImageUrl'] as String?;
        final hasImage = imgUrl != null && imgUrl.isNotEmpty;
        final role =
            (p['character'] as String? ?? p['Role'] as String? ?? '').trim();
        final hasRole = role.isNotEmpty;

        final merged = Map<String, dynamic>.from(p);
        // 补全头像
        if (!hasImage) {
          final tmdbUrl = tmdbAvatarMap[name.toLowerCase()];
          if (tmdbUrl != null) {
            merged['ImageUrl'] = tmdbUrl;
          }
        }
        // 补全角色名（服务器只有 Type/Director 时 Role 为空）
        if (!hasRole && name.isNotEmpty) {
          final tmdbChar = tmdbRoleMap[name.toLowerCase()];
          if (tmdbChar != null) {
            merged['character'] = tmdbChar;
            merged['Role'] = tmdbChar;
          }
        }
        return merged;
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
      if (!mounted || generation != _episodeLoadGeneration || sid != _seasonId)
        return;

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
    final svc = _svc;
    if (svc == null) {
      AppLog.w('Detail', '_play: no service');
      return;
    }
    // 无选中剧集时取第一集，传系列本身会导致播放器用系列ID查片头片尾数据（无数据）
    final target = episode ??
        (_item.type == MediaType.series && _episodes.isNotEmpty
            ? _episodes.first
            : _item);

    if (_libraryItemId == null || _libraryItemId!.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('该媒体尚未在媒体库中，请先订阅')));
      return;
    }

    final playId = episode?.id ??
        (_item.type == MediaType.series && _episodes.isNotEmpty
            ? _episodes.first.id
            : _libraryItemId!);
    AppLog.i('Detail',
        'play: id=$playId title=${target.title} type=${target.type.name}');

    final ps = ref.read(playerSettingsProvider);
    final burnIn = ps.burnInSubtitle;
    // 高端音频编码（TrueHD/DTS/Atmos/EAC3 等）Exo 无法硬解，且当前服务器的
    // FFmpeg 转码不可用（返回 500）→ 直接走 MPV（内置 FFmpeg 软解，原始流）。
    // 若服务器转码可用，可改回请求 Emby 音频转码。
    final needMpv = _needsAudioTranscode(target);
    (() async {
      try {
        final url = await svc.getStreamUrl(playId,
            quality: ps.defaultQuality, burnInSubtitle: burnIn);
        if (!mounted) return;
        if (_playError != null) setState(() => _playError = null);
        AppLog.i('Detail',
            'streamUrl=$url${needMpv ? ' [高端音频→MPV 软解]' : ''}');

        // 统一使用 svc.streamHeaders，覆盖 Emby/Jellyfin/FnOS 各自的认证方式
        final headers = svc.streamHeaders;

        context.push('/player/$playId', extra: {
          'media': target, 'url': url, 'headers': headers,
          if (needMpv) 'forceMpv': true,
          // 续播位置
          if (target.watchProgress != null && target.duration > 0)
            'resumePositionMs':
                (target.watchProgress! * target.duration * 1000).round(),
          // 新增：传入剧集列表和服务
          if (_item.type == MediaType.series && _episodes.isNotEmpty)
            'episodes': _episodes,
          'service': svc,
          'server': widget.server ??
              ref
                  .read(mediaServersProvider)
                  .where((s) => s.isDefault)
                  .firstOrNull,
        });
      } catch (e) {
        AppLog.e('Detail', 'getStreamUrl failed', e);
        // 错误态内联到播放按钮（点击重试），不再只弹一次性 SnackBar
        if (mounted) setState(() => _playError = '获取播放链接失败');
      }
    })();
  }

  /// 音频编码是否为 Exo 无法硬解的高端格式（TrueHD/DTS/Atmos 等）。
  /// 命中时让 Emby 服务器硬解转码音频（服务器转成 AAC，Exo 可硬解）。
  bool _needsAudioTranscode(MediaItem m) {
    final tracks = m.audioTracks ?? const <Map<String, dynamic>>[];
    for (final t in tracks) {
      final codec = (t['Codec'] ?? t['codec'] ?? '').toString().toLowerCase();
      if (codec.isEmpty) continue;
      if (codec.contains('dts') ||
          codec.contains('truehd') ||
          codec.contains('mlp') ||
          codec.contains('eac3') ||
          codec.contains('ec-3') ||
          codec.contains('ac4') ||
          codec.contains('atmos')) {
        AppLog.i('Detail', '音频编码 $codec 需 Emby 转码');
        return true;
      }
    }
    return false;
  }

  /// 已观看按钮当前语义：选中剧集时显示该集状态，未选中时显示整体状态
  bool get _currentWatched =>
      _selectedEpisode?.isWatched == true ||
      (_selectedEpisode == null && _watched);

  /// 切换已观看（真实调用服务端；按钮变色，并联动列表卡片绿勾）
  /// 剧集：精确到当前选中的集（按钮状态与集卡片右上角绿勾同步）；
  /// 未选中集/电影时作用于整体并联动首页/查看全部卡片。
  Future<void> _markWatched() async {
    final svc = _svc;
    if (svc == null) return;
    final target = _selectedEpisode;
    final id = target?.id ?? _libraryItemId ?? _item.id;
    final currentlyWatched = _currentWatched;
    try {
      if (currentlyWatched) {
        await svc.markUnwatched(id);
      } else {
        await svc.markWatched(id);
      }
      if (mounted) {
        setState(() {
          if (target != null) {
            // 精确到集：更新当前集与集卡片列表（右上角绿勾实时联动）
            _selectedEpisode = target.copyWith(isWatched: !currentlyWatched);
            _episodes = _episodes
                .map((e) => e.id == target.id
                    ? e.copyWith(isWatched: !currentlyWatched)
                    : e)
                .toList();
          } else {
            _watched = !currentlyWatched;
            // 联动：更新媒体库状态，返回首页/查看全部后卡片右上角显示/隐藏绿勾
            ref
                .read(mediaLibraryProvider.notifier)
                .markWatchedLocal(id, watched: !currentlyWatched);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(currentlyWatched ? '已取消已观看' : '已标记为已观看'),
          duration: const Duration(seconds: 1),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失败: $e')));
      }
    }
  }

  /// 次级操作图标行：收藏 / 标记已看 / 删除。
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
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        roundIcon(
          icon: _fav ? Icons.favorite : Icons.favorite_border,
          color: _fav ? Colors.redAccent : Colors.white70,
          onTap: _toggleFav,
          tooltip: _fav ? '取消收藏' : '收藏',
        ),
        if (_inLibrary) ...[
          const SizedBox(width: 3),
          roundIcon(
            icon: Icons.download_outlined,
            color: Colors.white70,
            onTap: _downloadItem,
            tooltip: '下载',
          ),
          const SizedBox(width: 3),
          roundIcon(
            icon: _currentWatched
                ? Icons.check_circle_rounded
                : Icons.check_circle_outline_rounded,
            color: _currentWatched ? AppTheme.primary : Colors.white70,
            onTap: _markWatched,
            tooltip: _currentWatched ? '取消已观看' : '标记已观看',
          ),
        ],
      ],
    );
  }

  /// 下载（飞牛详情页操作之一）；Emby 下载接口待接入，先提示
  void _downloadItem() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('下载功能开发中'),
      duration: Duration(seconds: 1),
    ));
  }

  Widget _detailTrackControls() {
    Widget control({
      required String label,
      required String value,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return Tooltip(
        message: label == '音频' ? '选择音频' : '选择字幕',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white70, size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 9)),
                      const SizedBox(height: 1),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white54, size: 14),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 与下方「播放按钮 + 三个小按钮」组等宽对齐（对称），窄屏自动收缩
        final itemWidth =
            ((constraints.maxWidth - 10) / 2).clamp(96.0, 148.0);
        return Row(
          key: const ValueKey('detail-track-controls'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: itemWidth,
              child: control(
                label: '音频',
                value: _selectedAudioLang ?? '默认音轨',
                icon: Icons.audiotrack_rounded,
                onTap: _selectAudio,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: itemWidth,
              child: control(
                label: '字幕',
                value: _selectedSubtitleLang ?? '关闭',
                icon: Icons.subtitles_rounded,
                onTap: _selectSubtitle,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 轨道语言字段（MediaStreams 的 Language/language）
  String? _trackLang(Map<String, dynamic> t) {
    final lang = (t['Language'] ?? t['language'] ?? '').toString();
    return lang.isEmpty ? null : lang;
  }

  /// 获取某类轨道列表（'subtitle' / 'audio'）。
  /// 剧集取选中集的轨道；若剧集列表接口未返回 MediaStreams（部分服务器
  /// 列表不带流信息），延迟拉取剧集详情补齐。
  Future<List<Map<String, dynamic>>> _resolveTracks(String kind) async {
    final item = _trackItem;
    final cached = kind == 'subtitle' ? item.subtitleTracks : item.audioTracks;
    final tracks = cached ?? const <Map<String, dynamic>>[];
    if (tracks.isNotEmpty || _item.type != MediaType.series) return tracks;

    final svc = _svc;
    if (svc == null) return const [];
    try {
      final full = await svc.getItemDetails(item.id);
      final fullTracks =
          kind == 'subtitle' ? full.subtitleTracks : full.audioTracks;
      return fullTracks ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const [];
    }
  }

  /// 选择默认字幕轨（存语言偏好，剧集的所有集都套用，即"应用到全部"）
  Future<void> _selectSubtitle() async {
    final tracks = await _resolveTracks('subtitle');
    if (tracks.isEmpty) {
      await _searchServerSubtitles();
      return;
    }
    final current = _selectedSubtitleLang != null
        ? tracks.indexWhere((t) => _trackLang(t) == _selectedSubtitleLang)
        : -1;
    await TrackSelectorSheet.show(
      context: context,
      title: '字幕',
      tracks: tracks,
      currentIndex: current,
      onSearch: _searchServerSubtitles,
      onSelect: (i) {
        final lang = i >= 0 && i < tracks.length ? _trackLang(tracks[i]) : null;
        ref
            .read(playerSettingsProvider.notifier)
            .update((s) => s.copyWith(defaultSubtitleLang: lang));
        if (mounted) setState(() => _selectedSubtitleLang = lang);
      },
    );
  }

  /// 调用 Emby/Jellyfin 原生远程字幕搜索并展示可用结果。
  Future<void> _searchServerSubtitles() async {
    final svc = _svc;
    final itemId = _trackItem.id;
    if (svc == null || itemId.isEmpty) return;
    await ServerSubtitleSearchSheet.show(
      context: context,
      service: svc,
      itemId: itemId,
      initialQuery: _trackItem.title,
    );
  }

  /// 选择默认音轨（存语言偏好，播放器按语言自动应用）
  Future<void> _selectAudio() async {
    final tracks = await _resolveTracks('audio');
    if (tracks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('该媒体无可用音轨'), duration: Duration(seconds: 1)));
      }
      return;
    }
    final current = _selectedAudioLang != null
        ? tracks.indexWhere((t) => _trackLang(t) == _selectedAudioLang)
        : -1;
    await TrackSelectorSheet.show(
      context: context,
      title: '音频',
      tracks: tracks,
      currentIndex: current,
      onSelect: (i) {
        final lang = i >= 0 && i < tracks.length ? _trackLang(tracks[i]) : null;
        ref
            .read(playerSettingsProvider.notifier)
            .update((s) => s.copyWith(defaultAudioLang: lang));
        if (mounted) setState(() => _selectedAudioLang = lang);
      },
    );
  }

  void _toggleFav() async {
    final svc = _svc;
    // 服务器媒体（GUID id）：调用服务端收藏接口，状态立即反映到按钮
    if (_inLibrary &&
        svc != null &&
        _libraryItemId != null &&
        _libraryItemId!.isNotEmpty) {
      final id = _libraryItemId!;
      try {
        if (_fav) {
          await svc.unmarkFavorite(id);
        } else {
          await svc.markFavorite(id);
        }
        if (mounted) setState(() => _fav = !_fav);
      } catch (e) {
        AppLog.w('Detail', 'toggleFav server failed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('收藏失败: $e')));
        }
      }
      return;
    }

    final tmdbId = int.tryParse(widget.item.id);
    if (tmdbId == null) return;

    final service = await ref.read(favoriteServiceProvider.future);
    if (_fav) {
      await service.removeFavorite(tmdbId);
    } else {
      final movie = TMDBMovie(
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
      );
      await service.addFavorite(movie);
    }
    setState(() => _fav = !_fav);
    ref.invalidate(favoriteMoviesProvider);
  }

  @override
  Widget build(BuildContext c) {
    // 详情页背景始终是深色（封面或主色调），所以文字应该用浅色
    // 详情页背景固定黑灰（不跟随海报主色），保证白字阅读性
    return Scaffold(
      backgroundColor: Colors.black,
      body: SingleChildScrollView(
        controller: _scrollController,
        child: _buildContent(c),
      ),
    );
  }

  Widget _buildContent(BuildContext c) {
    final hasBackdrop = _item.backdropUrl?.isNotEmpty == true;
    final hasPoster = _item.posterUrl.isNotEmpty;
    final backdropUrl =
        hasBackdrop ? _item.backdropUrl! : (hasPoster ? _item.posterUrl : '');
    final posterUrl = hasPoster ? _item.posterUrl : backdropUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // 仅在电视/桌面宽屏隐藏海报；中等平板宽度仍保留海报列。
            final wide = constraints.maxWidth >= 1000;
            final screenH = MediaQuery.of(context).size.height;
            // 海报占屏幕 3/4 高（飞牛布局），竖版 2:3，宽度按比例并 clamp
            final posterH = (screenH * 0.75).clamp(440.0, 920.0);
            final posterW = (posterH * 0.66).clamp(180.0, 360.0);

            // 宽屏（桌面/TV）：保留原信息列 + 底部左侧布局
            if (wide) {
              return Stack(
                children: [
                  if (backdropUrl.isNotEmpty)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: _heroLanded ? 0.62 : 0.0,
                          duration: AppAnimations.medium,
                          curve: AppAnimations.easeOut,
                          child: ServerImage(
                            imageUrl: backdropUrl,
                            headers: _svc?.imageHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 560),
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.18),
                          Colors.black.withValues(alpha: 0.78),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailTopBar(c),
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(20, 210, 20, 22),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 680),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _detailInfoColumn(),
                                  const SizedBox(height: 16),
                                  _actionGroup(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // 移动/平板：飞牛详情页布局 —— 海报占 3/4 屏高，信息/按钮叠在左下
            return SizedBox(
              height: posterH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景大图（无模糊，直铺）
                  if (backdropUrl.isNotEmpty)
                    ServerImage(
                      imageUrl: backdropUrl,
                      headers: _svc?.imageHeaders,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  // 渐变压暗，保证左下文字可读
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.0),
                          Colors.black.withValues(alpha: 0.30),
                          Colors.black.withValues(alpha: 0.88),
                        ],
                        stops: const [0.0, 0.55, 1.0],
                      ),
                    ),
                  ),
                  // 顶部栏（只返回）
                  Align(
                    alignment: Alignment.topCenter,
                    child: _detailTopBar(c),
                  ),
                  // 海报居中（占 3/4 屏高）
                  Center(
                    child: SizedBox(
                      width: posterW,
                      child: _posterCard(posterUrl),
                    ),
                  ),
                  // 信息组（左下 3/4 位置，操作区上方）：标题特效 + 评分 + 年份/地区/类型
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 128,
                    child: _detailInfoColumn(),
                  ),
                  // 操作组（4/4 底部）：字幕/音源 + 播放 + 收藏/下载/已观看
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: _actionGroup(),
                  ),
                ],
              ),
            );
          },
        ),
        if (_item.overview != null && _item.overview!.isNotEmpty) ...[
          const SizedBox(height: 20),
          _reveal('overview', _overview(),
              delay: const Duration(milliseconds: 0)),
        ],
        if (_item.type == MediaType.series) ...[
          _reveal(
              'episodes',
              Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [_seasonPicker(), _episodeList()]),
              delay: const Duration(milliseconds: 60)),
        ],
        _reveal('cast', _castSection(),
            delay: const Duration(milliseconds: 120)),
        _reveal('similar', _similarSection(),
            delay: const Duration(milliseconds: 180)),
        _reveal('info', _mediaInfoSection(),
            delay: const Duration(milliseconds: 240)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _detailTopBar(BuildContext c) {
    // 飞牛风格：顶部栏只保留返回按钮，标题/信息都叠在海报上，不额外占位
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Tooltip(
              message: '返回',
              child: TapFeedback(
                onTap: () => Navigator.pop(c),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterCard(String posterUrl) {
    final image = posterUrl.isEmpty
        ? Container(
            color: Colors.white.withValues(alpha: 0.08),
            child: const Center(
              child:
                  Icon(Icons.movie_outlined, color: Colors.white38, size: 42),
            ),
          )
        : ServerImage(
            imageUrl: posterUrl,
            headers: _svc?.imageHeaders,
            fit: BoxFit.cover,
            // 使用较高缓存分辨率并取消淡入，保证海报清晰显示。
            memCacheWidth: 1080,
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => Container(
              color: Colors.white.withValues(alpha: 0.08),
              child: const Center(
                child:
                    Icon(Icons.movie_outlined, color: Colors.white38, size: 42),
              ),
            ),
          );

    return Container(
      key: const ValueKey('detail-poster'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.38),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: posterUrl.isEmpty
            ? image
            : Hero(
                tag: _heroTag,
                flightShuttleBuilder: heroFlightShuttle,
                child: image,
              ),
      ),
    );
  }

  Widget _detailInfoColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题：大字号 + 深投影 + 蓝色光晕（飞牛标题特效）
        AnimatedOpacity(
          opacity: _heroLanded ? 1.0 : 0.0,
          duration: AppAnimations.medium,
          curve: AppAnimations.easeOut,
          child: Text(
            _item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.bold,
              height: 1.15,
              shadows: [
                // 深色投影（保证在大图上可读）
                Shadow(
                  color: Colors.black87,
                  blurRadius: 14,
                  offset: Offset(0, 3),
                ),
                // 主光晕
                Shadow(color: Color(0x9958A6FF), blurRadius: 32),
                // 外圈柔光
                Shadow(color: Color(0x3358A6FF), blurRadius: 56),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        _ratingBadge(),
        const SizedBox(height: 4),
        _meta(),
        if (_item.genres.isNotEmpty) ...[
          const SizedBox(height: 10),
          _genreTags(),
        ],
      ],
    );
  }

  /// 底部操作组（飞牛布局）：字幕/音源 在播放按钮上方，播放 + 收藏/下载/已观看 一行
  Widget _actionGroup() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailTrackControls(),
        const SizedBox(height: 12),
        // 播放按钮固定宽度，三个小按钮紧跟其右侧（不再用 Expanded 把按钮推走）
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _actionButtons(),
            const SizedBox(width: 12),
            _actionIconRow(),
          ],
        ),
      ],
    );
  }

  /// 参考图中的小字号评分徽标，独立放在年份信息上方。
  Widget _ratingBadge() {
    final rating = _item.rating;
    if (rating == null || rating <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '评分 ${rating.toStringAsFixed(1)}',
        style: const TextStyle(
          color: Color(0xFFFFD54F),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _actionButtons() {
    final isLoading = _checkingLibrary;
    final seasonNum = _seasons.indexWhere((s) => s.id == _seasonId) + 1;
    final selectedEpIndex = _selectedEpisode != null
        ? _episodes.indexWhere((e) => e.id == _selectedEpisode!.id) + 1
        : 0;
    final hasResume = _selectedEpisode?.watchProgress != null &&
        _selectedEpisode!.watchProgress! > 0;

    // 四种状态各自带唯一 key，AnimatedSwitcher 才能识别状态切换并做过渡。
    // 这里用 AnimatedSwitcher 是正确的（内容真的换了），
    // 与底部导航栏那处误用（内容不变只变样式）不同。
    final Widget current;
    if (isLoading) {
      current = Container(
          key: const ValueKey('detail-loading'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white38)),
            SizedBox(width: 8),
            const Text('查询中...',
                style: TextStyle(color: Colors.white38, fontSize: 16))
          ]));
    } else if (_playError != null) {
      // 错误态内联：获取播放链接失败时按钮切换为「点击重试」
      current = GestureDetector(
        key: const ValueKey('play_error'),
        onTap: () => _play(episode: _selectedEpisode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(31),
            border: Border.all(color: AppTheme.error.withValues(alpha: 0.5)),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded,
                color: AppTheme.error, size: 20),
            const SizedBox(width: 8),
            Text(_playError!,
                style: const TextStyle(
                    color: AppTheme.error,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Text('点击重试',
                style: TextStyle(
                    color: AppTheme.error.withValues(alpha: 0.8),
                    fontSize: 13)),
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
        key: const ValueKey('detail-play-button'),
        onTap: () => _play(episode: _selectedEpisode),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            // 飞牛风格：蓝色毛玻璃播放按钮，白字
            filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2E93FF), Color(0xFF1B6FE0)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                      color: const Color(0xFF2E93FF).withValues(alpha: 0.35),
                      blurRadius: 14,
                      offset: const Offset(0, 4)),
                ],
              ),
              child: Stack(
                children: [
                  // 续播进度覆盖：从左到右填充（已观看部分用半透明白色）
                  if (resume)
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (progress ?? 0).clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(22),
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
                            const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 22),
                            const SizedBox(width: 6),
                            Text(
                              resume ? '继续观看' : '播放',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        if (subLabel.isNotEmpty)
                          Text(
                            subLabel,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      current = Container(
        key: const ValueKey('not-in-library'),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14)),
        child: const Center(
          child: Text('媒体未入库',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
        ),
      );
    }

    return Tooltip(
      message: _inLibrary ? '播放' : '媒体未入库',
      child: LayoutBuilder(
        builder: (context, constraints) => Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            // 只缩小宽度，高度和内部文字保持不变。
            width: constraints.maxWidth > 180 ? 180 : constraints.maxWidth,
            // 状态切换时内容淡入淡出 + 高度平滑变化，不再是「换了个按钮」的硬跳
            child: AnimatedSwitcher(
              duration: AppAnimations.medium,
              switchInCurve: AppAnimations.easeOut,
              switchOutCurve: AppAnimations.easeIn,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild
                ],
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
          ),
        ),
      ),
    );
  }

  Widget _meta() {
    final p = <Widget>[];
    if (_item.year != null)
      p.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10)),
        child: Text('${_item.year}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
      ));
    if (_item.type == MediaType.series)
      p.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10)),
        child: Text('剧集',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
      ));
    else
      p.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10)),
        child: Text('电影',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
      ));
    if (_item.duration > 0)
      p.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10)),
        child: Text('${_item.duration ~/ 60}分钟',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
      ));
    // 地区（Emby ProductionLocations / FnOS area），与年份/类型并列
    for (final loc in _item.productionLocations) {
      if (loc.trim().isEmpty) continue;
      p.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(10)),
        child: Text(loc,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9), fontSize: 14)),
      ));
    }
    return Wrap(spacing: 8, runSpacing: 4, children: p);
  }

  Widget _genreTags() {
    if (_item.genres.isEmpty) return const SizedBox.shrink();
    return Wrap(
        spacing: 8,
        children: _item.genres
            .map((g) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(g,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 12)),
                ))
            .toList());
  }

  Widget _overview() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_item.overview!,
              style: const TextStyle(
                  color: Colors.white, fontSize: 14, height: 1.7),
              maxLines: 4,
              overflow: TextOverflow.fade),
          // 飞牛风格：点「更多」弹出小窗显示全文
          if (_item.overview!.length > 200)
            GestureDetector(
              onTap: _showFullOverview,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('更多',
                      style: const TextStyle(
                          color: AppTheme.primary, fontSize: 12)),
                  const SizedBox(width: 2),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primary, size: 16),
                ]),
              ),
            ),
        ]),
      ));

  /// 简介全文弹窗（飞牛「更多」交互）
  void _showFullOverview() {
    showDialog<void>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.92),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(_item.overview!,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.7)),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('关闭',
                      style: TextStyle(color: AppTheme.primary)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seasonPicker() {
    if (_seasons.isEmpty) return const SizedBox.shrink();
    // 飞牛风格：季用海报图 + 第几季网格排列（无「季」标题，内容上移）
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: _seasons.length,
        itemBuilder: (_, i) {
          final s = _seasons[i];
          final sel = s.id == _seasonId;
          return GestureDetector(
            onTap: () => _loadEpisodes(s.id),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 季海报缩略图
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (s.posterUrl.isNotEmpty)
                          ServerImage(
                            imageUrl: s.posterUrl,
                            headers: _svc?.imageHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: Colors.white.withValues(alpha: 0.08),
                              child: const Center(
                                  child: Icon(Icons.ondemand_video,
                                      color: Colors.white24, size: 24)),
                            ),
                          )
                        else
                          Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: const Center(
                                child: Icon(Icons.ondemand_video,
                                    color: Colors.white24, size: 24)),
                          ),
                        // 选中框
                        if (sel)
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppTheme.primary, width: 2.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '第${i + 1}季',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: sel ? AppTheme.primary : Colors.white70,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _episodeList() {
    if (_episodes.isEmpty)
      return SizedBox(
          height: 120,
          child: Center(
              child: CircularProgressIndicator(
                  color: AppTheme.primary, strokeWidth: 2)));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text('剧集',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold))),
      SizedBox(
          height: 132,
          child: ListView.builder(
            controller: _episodeScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _episodes.length,
            itemBuilder: (_, i) {
              final ep = _episodes[i];
              final isSelected = _selectedEpisode?.id == ep.id;
              return GestureDetector(
                onTap: () =>
                    setState(() => _selectedEpisode = isSelected ? null : ep),
                child: Transform.scale(
                  scale: isSelected ? 1.02 : 1.0,
                  child: Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: Colors.white.withValues(alpha: 0.6),
                              width: 2)
                          : null,
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 横图缩略图占满剩余高度，选框整体呈横长方形（适配 16:9 图）
                          Expanded(
                            child: Stack(fit: StackFit.expand, children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                decoration: BoxDecoration(
                                    color:
                                        Colors.white.withValues(alpha: 0.08)),
                                child: ep.posterUrl.isNotEmpty
                                    ? ServerImage(
                                        imageUrl: ep.posterUrl,
                                        headers: _svc?.imageHeaders,
                                        fit: BoxFit.cover,
                                        errorWidget: (_, __, ___) => Center(
                                            child: Icon(Icons.movie,
                                                color: Colors.white24,
                                                size: 32)))
                                    : Center(
                                        child: Icon(Icons.play_circle_outline,
                                            color: Colors.white24, size: 32)),
                              ),
                            ),
                            Positioned.fill(
                                child: Center(
                                    child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle),
                              child: Icon(Icons.play_arrow_rounded,
                                  color: Colors.white70, size: 24),
                            ))),
                            Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                      color: AppTheme.primary
                                          .withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(6)),
                                  child: Text('E${ep.episodeNumber ?? i + 1}',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                )),
                            if (ep.isWatched == true)
                              Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                        color: AppTheme.success,
                                        borderRadius: BorderRadius.circular(4)),
                                    child: Icon(Icons.check,
                                        color: Colors.white, size: 12),
                                  )),
                            // 续播进度条：未看完的剧集底部显示进度（Streama 卡片风格）
                            if (ep.watchProgress != null &&
                                ep.watchProgress! > 0 &&
                                ep.watchProgress! < 0.98)
                              Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(12)),
                                    child: SizedBox(
                                      height: 4,
                                      child: LinearProgressIndicator(
                                        value:
                                            ep.watchProgress!.clamp(0.0, 1.0),
                                        backgroundColor: Colors.black
                                            .withValues(alpha: 0.55),
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  )),
                          ]),
                          ),
                          SizedBox(height: 6),
                          Text(ep.title,
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          SizedBox(height: 2),
                          Text(
                            ep.duration > 0
                                ? '${ep.duration ~/ 60}分钟'
                                : 'E${ep.episodeNumber ?? i + 1}',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 10),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                  ),
                ),
              );
            },
          )),
    ]);
  }

  Widget _castSection() {
    return CreditList(
      credits: _credits,
      imageHeaders: _svc?.imageHeaders,
      imageBaseUrl: _svc?.baseUrl,
      imageApiKey: _svc?.getAuthInfo()['apiKey'],
    );
  }

  /// 相似推荐横向海报卡（点击进入对应详情页）
  Widget _similarSection() {
    if (_similarItems.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Text('相关推荐',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold))),
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
                  context.push('/detail/tmdb_${item.tmdbId}',
                      extra: {'item': item});
                } else {
                  context.push('/detail/${item.id}',
                      extra: {'item': item, 'server': widget.server});
                }
              },
              child: Container(
                width: 110,
                margin: const EdgeInsets.only(right: 12),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: ServerImage(
                            imageUrl: item.posterUrl,
                            headers: _svc?.imageHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                                color: Colors.white.withValues(alpha: 0.08),
                                child: const Icon(Icons.movie,
                                    color: Colors.white24, size: 28)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                      if (item.year != null)
                        Text('${item.year}',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 10)),
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

    // 剧集：媒体信息展示选中集的轨道（Series 级对象无 MediaStreams）
    final ti = _trackItem;
    final hasVideo = ti.videoTracks?.isNotEmpty == true;
    final hasAudio = ti.audioTracks?.isNotEmpty == true;
    final hasSubtitle = ti.subtitleTracks?.isNotEmpty == true;

    if (!hasVideo && !hasAudio && !hasSubtitle) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      // key 随媒体变化：切换剧集后重建 Tab（轨道列表可能不同）
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文件信息：添加日期 + 文件路径（飞牛：媒体/文件信息可看添加日期）
          _fileInfoRow(ti),
          const SizedBox(height: 12),
          _MediaInfoTabs(key: ValueKey(ti.id), item: ti),
        ],
      ),
    );
  }

  /// 文件信息行：添加日期 / 文件路径（飞牛详情页信息区）
  Widget _fileInfoRow(MediaItem ti) {
    final date = ti.dateCreated;
    final dateStr =
        (date != null && date.length >= 10) ? date.substring(0, 10) : '';
    if (dateStr.isEmpty) return const SizedBox.shrink();

    Widget chip(IconData icon, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white38, size: 13),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ),
          ],
        );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Wrap(
        spacing: 18,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (dateStr.isNotEmpty) chip(Icons.calendar_today_rounded, '添加日期 $dateStr'),
        ],
      ),
    );
  }
}

/// 媒体信息 Tab 组件：视频/音频/字幕 三个可左右滑动的 Tab
class _MediaInfoTabs extends StatefulWidget {
  final MediaItem item;
  const _MediaInfoTabs({super.key, required this.item});

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
                Icon(Icons.info_outline_rounded,
                    color: AppTheme.primary, size: 18),
                const SizedBox(width: 8),
                Text('媒体信息',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (item.duration > 0) _infoTag(_formatDuration(item.duration)),
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
                for (final tab in _tabs) _infoTag('${tab.label} ×${tab.count}'),
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
            labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            dividerColor: Colors.white12,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            tabs: _tabs
                .map((t) => Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(t.icon, color: t.iconColor, size: 15),
                          const SizedBox(width: 5),
                          Text('${t.label} (${t.count})'),
                        ],
                      ),
                    ))
                .toList(),
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
          children:
              item.subtitleTracks!.map((t) => _subtitleTrackDetail(t)).toList(),
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
    final fps =
        _s(t, ['FrameRate', 'frame_rate', 'r_frame_rate', 'avg_frame_rate']);
    final bitrateVal = (t['Bitrate'] ?? t['bitrate']) as num?;
    final bitrate = bitrateVal != null
        ? '${(bitrateVal / 1000).toStringAsFixed(0)} kbps'
        : '';
    final profile = _s(t, ['Profile', 'profile']);
    final bitDepth = _s(t, ['BitDepth', 'bit_depth', 'bits_per_raw_sample']);
    final colorSpace = _s(t, ['ColorSpace', 'color_space']);
    final colorTransfer = _s(t, ['ColorTransfer', 'color_transfer']);
    final pixFmt = _s(t, ['PixelFormat', 'pix_fmt']);
    final resolution =
        (width.isNotEmpty && height.isNotEmpty) ? '${width}×$height' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (codec.isNotEmpty)
                Text(codec.toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              if (resolution.isNotEmpty) ...[
                const SizedBox(width: 8),
                _infoTag(resolution)
              ],
              if (bitrate.isNotEmpty) ...[
                const SizedBox(width: 6),
                _infoTag(bitrate)
              ],
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
    final bitrate = bitrateVal != null
        ? '${(bitrateVal / 1000).toStringAsFixed(0)} kbps'
        : '';
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
              if (lang.isNotEmpty)
                Text(lang,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              if (codec.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(codec.toUpperCase(),
                    style: const TextStyle(color: Colors.white60, fontSize: 12))
              ],
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
          if (lang.isNotEmpty)
            Text(lang,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          if (codec.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(codec,
                style: const TextStyle(color: Colors.white54, fontSize: 11))
          ],
          if (isDefault) ...[
            const SizedBox(width: 6),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('默认',
                    style: TextStyle(color: AppTheme.primary, fontSize: 10)))
          ],
          if (isForced) ...[
            const SizedBox(width: 4),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4)),
                child: const Text('强制',
                    style: TextStyle(color: Colors.amber, fontSize: 10)))
          ],
          if (title.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(title,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                overflow: TextOverflow.ellipsis)
          ],
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
  _TabInfo(
      {required this.label,
      required this.icon,
      required this.iconColor,
      required this.count});
}
