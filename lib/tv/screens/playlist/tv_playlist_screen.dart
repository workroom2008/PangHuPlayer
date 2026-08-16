import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/app_providers.dart';
import '../../../services/favorite_service.dart';
import '../../../models/media_models.dart';
import '../../widgets/media_hero.dart';

class TvPlaylistScreen extends ConsumerStatefulWidget {
  const TvPlaylistScreen({super.key});

  @override
  ConsumerState<TvPlaylistScreen> createState() => _TvPlaylistScreenState();
}

class _TvPlaylistScreenState extends ConsumerState<TvPlaylistScreen> {
  /// 图片请求头（飞牛原生 API 的图片端点需要 Authorization 头）
  Map<String, String> get _imageHeaders =>
      ref.read(currentMediaServerServiceProvider)?.imageHeaders ?? const {};

  void _openDetail(PlaylistItem item, {String? heroTag}) {
    final svc = ref.read(currentMediaServerServiceProvider);
    final mediaItem = MediaItem(
      id: item.itemId,
      title: item.title,
      posterUrl: item.posterUrl,
      backdropUrl: item.backdropUrl,
      overview: item.overview,
      rating: item.rating,
      year: item.year,
      type: item.type,
      seriesTitle: item.seriesTitle,
      seasonNumber: item.seasonNumber,
      episodeNumber: item.episodeNumber,
    );
    context.push('/detail/${item.itemId}', extra: {
      'item': mediaItem,
      'service': svc,
      if (heroTag != null) 'heroTag': heroTag,
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlist = ref.watch(playlistProvider);

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0A0A)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: playlist.isEmpty
                  ? _buildEmptyState()
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(56, 16, 56, 48),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 140,
                        mainAxisSpacing: 24,
                        crossAxisSpacing: 12,
                        childAspectRatio: 120 / 200,
                      ),
                      itemCount: playlist.length,
                      itemBuilder: (context, index) {
                        final item = playlist[index];
                        final fid = 'playlist_$index';
                        return _PlaylistCard(
                          item: item,
                          focusId: fid,
                          imageHeaders: _imageHeaders,
                          onTap: () =>
                              _openDetail(item, heroTag: mediaHeroTag(fid)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(56, MediaQuery.of(context).padding.top + 20, 56, 20),
      child: Row(
        children: [
          const Text(
            '我的片单',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${playlist.length} 部',
              style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  List<PlaylistItem> get playlist => ref.watch(playlistProvider);

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bookmark_border_rounded, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('片单还是空的', style: TextStyle(color: Colors.white54, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('在详情页点击"加入片单"来收藏喜欢的内容', style: TextStyle(color: Colors.white38, fontSize: 14)),
        ],
      ),
    );
  }
}

class _PlaylistCard extends StatefulWidget {
  final PlaylistItem item;
  final String focusId;
  final VoidCallback onTap;
  final Map<String, String> imageHeaders;

  const _PlaylistCard({
    required this.item,
    required this.focusId,
    required this.onTap,
    this.imageHeaders = const {},
  });

  @override
  State<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<_PlaylistCard> {
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

  static const double _cardWidth = 120;
  static const double _cardHeight = 180;
  static const double _focusScale = 1.1;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _focusNode,
          builder: (context, child) {
            final isFocused = _focusNode.hasFocus;
            // 弹簧缩放：与统一焦点语言一致（聚焦 easeOutBack 微弹，离开 easeOut）
            return AnimatedScale(
              scale: isFocused ? _focusScale : 1.0,
              duration: Duration(milliseconds: isFocused ? 280 : 200),
              curve: isFocused ? Curves.easeOutBack : Curves.easeOut,
              alignment: Alignment.center,
              child: SizedBox(
                width: _cardWidth,
                height: _cardHeight,
                child: child,
              ),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: _isFocused
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : [],
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.item.posterUrl.isNotEmpty
                          ? Hero(
                              tag: mediaHeroTag(widget.focusId),
                              child: CachedNetworkImage(
                                imageUrl: widget.item.posterUrl,
                                httpHeaders: widget.imageHeaders,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    Container(color: const Color(0xFF1E1E3A)),
                              ),
                            )
                          : Container(color: const Color(0xFF1E1E3A)),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _isFocused ? 1.0 : 0.0,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.8),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_isFocused) _buildFocusedInfo(),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: -2,
                left: -2,
                right: -2,
                bottom: -2,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _isFocused ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFocusedInfo() {
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (widget.item.rating != null && widget.item.rating! > 0) ...[
                const Icon(Icons.star_rounded, color: Color(0xFFE50914), size: 12),
                const SizedBox(width: 3),
                Text(
                  widget.item.rating!.toStringAsFixed(1),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
              ],
              if (widget.item.year != null)
                Text(
                  '${widget.item.year}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
