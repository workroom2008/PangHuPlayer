import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/media_models.dart';
import '../../../providers/media_library_provider.dart';
import '../../../providers/app_providers.dart';
import '../../../utils/app_log.dart';
import '../../widgets/media_hero.dart';

class TvLibraryScreen extends ConsumerStatefulWidget {
  final MediaItem library;

  const TvLibraryScreen({super.key, required this.library});

  @override
  ConsumerState<TvLibraryScreen> createState() => _TvLibraryScreenState();
}

class _TvLibraryScreenState extends ConsumerState<TvLibraryScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<MediaItem> _getItems() {
    final state = ref.watch(mediaLibraryProvider);
    return state.libraryItems[widget.library.id] ?? [];
  }

  /// 图片请求头（飞牛原生 API 的图片端点需要 Authorization 头）
  Map<String, String> get _imageHeaders =>
      ref.read(currentMediaServerServiceProvider)?.imageHeaders ?? const {};

  Widget _buildTopBar() {
    final items = _getItems();
    return Container(
      padding: EdgeInsets.fromLTRB(48, MediaQuery.of(context).padding.top + 12, 48, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.8),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 16),
          Text(
            widget.library.title,
            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${items.length} 部',
              style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail(MediaItem item, {String? heroTag}) {
    context.push('/detail/${item.id}', extra: {
      'item': item,
      if (heroTag != null) 'heroTag': heroTag,
    });
  }

  Future<void> _playItem(MediaItem item) async {
    final svc = ref.read(currentMediaServerServiceProvider);
    if (svc == null) return;
    String url = '';
    try {
      url = await svc.getStreamUrl(item.id);
    } catch (e) {
      AppLog.e('TvLibrary', '获取流URL失败: $e');
    }
    if (!mounted) return;
    context.push('/player/${item.id}', extra: {
      'media': item,
      'url': url,
      'headers': svc.streamHeaders,
      'service': svc,
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _getItems();

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0A0A)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.movie_outlined, size: 64, color: Colors.white24),
                          SizedBox(height: 16),
                          Text('暂无内容', style: TextStyle(color: Colors.white54, fontSize: 18)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      controller: _scrollController,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.fromLTRB(56, 24, 56, 48),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 140,
                        mainAxisSpacing: 32,
                        crossAxisSpacing: 16,
                        childAspectRatio: 120 / 200,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final fid = 'lib_${widget.library.id}_$index';
                        return _MediaCard(
                          item: item,
                          focusId: fid,
                          imageHeaders: _imageHeaders,
                          onTap: () =>
                              _openDetail(item, heroTag: mediaHeroTag(fid)),
                          onPlay: () => _playItem(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatefulWidget {
  final MediaItem item;
  final String focusId;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final Map<String, String> imageHeaders;

  const _MediaCard({
    required this.item,
    required this.focusId,
    required this.onTap,
    this.onPlay,
    this.imageHeaders = const {},
  });

  @override
  State<_MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<_MediaCard> {
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

  static const double _cardWidth = 100;
  static const double _cardHeight = 150;
  static const double _focusScale = 1.12;

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
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.mediaPlay ||
                event.logicalKey == LogicalKeyboardKey.mediaPlayPause)) {
          widget.onPlay?.call();
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
            // 弹簧缩放：与首页卡片/统一焦点语言一致（聚焦 easeOutBack 微弹，离开 easeOut）
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
          child: AnimatedContainer(
            duration: Duration(milliseconds: _isFocused ? 280 : 200),
            curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: _isFocused
                  ? Border.all(color: Colors.white, width: 2.5)
                  : Border.all(color: Colors.transparent, width: 2.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  widget.item.posterUrl.isNotEmpty
                      ? Hero(
                          tag: mediaHeroTag(widget.focusId),
                          child: CachedNetworkImage(
                            imageUrl: widget.item.posterUrl,
                            httpHeaders: widget.imageHeaders,
                            memCacheWidth: 240,
                            memCacheHeight: 360,
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
                      // 常驻：底部轻渐变 + 标题（聚焦时淡出，让位给焦点面板）
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isFocused ? 0.0 : 1.0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.75),
                                ],
                              ),
                            ),
                            child: Text(
                              widget.item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 常驻：左上角评分角标
                      if (widget.item.rating != null && widget.item.rating! > 0)
                        Positioned(
                          top: 6,
                          left: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 11),
                                const SizedBox(width: 2),
                                Text(
                                  widget.item.rating!.toStringAsFixed(1),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_isFocused) _buildFocusedInfo(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFocusedInfo() {
    return Positioned(
      left: 6,
      right: 6,
      bottom: 6,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: widget.item.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            if (widget.item.year != null)
              TextSpan(
                text: ' · ${widget.item.year}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
