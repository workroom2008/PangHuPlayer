import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../models/media_models.dart';
import '../../utils/animation_config.dart';
import 'media_hero.dart';

class TvHero extends StatefulWidget {
  final List<MediaItem> items;
  final void Function(MediaItem) onPlay;
  final void Function(MediaItem) onDetail;
  final void Function(MediaItem)? onTogglePlaylist;
  final bool Function(MediaItem)? isInPlaylist;
  final Duration autoPlayDuration;
  final bool autoPlay;
  final Map<String, String> imageHeaders;
  /// Hero 按钮获得焦点时回调（用于让父级滚回顶部显示完整大图背景）
  final VoidCallback? onButtonFocused;

  const TvHero({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onDetail,
    this.onTogglePlaylist,
    this.isInPlaylist,
    this.autoPlayDuration = const Duration(seconds: 6),
    this.autoPlay = true,
    this.imageHeaders = const {},
    this.onButtonFocused,
  });

  @override
  State<TvHero> createState() => _TvHeroState();
}

class _TvHeroState extends State<TvHero> {
  int _currentIndex = 0;
  int _slideDirection = 1; // 1 = 从右滑入(next), -1 = 从左滑入(prev)
  final Set<String> _playlistToggled = {}; // 本地乐观状态：记录已切换的 item ID
  Timer? _autoPlayTimer;
  late FocusNode _playFocusNode;
  late FocusNode _detailFocusNode;
  late FocusNode _addFocusNode;

  @override
  void initState() {
    super.initState();
    _playFocusNode = FocusNode();
    _detailFocusNode = FocusNode();
    _addFocusNode = FocusNode();
    // 任一 Hero 按钮获焦 → 通知父级滚回顶部，确保完整大图背景可见
    _playFocusNode.addListener(_onHeroButtonFocus);
    _detailFocusNode.addListener(_onHeroButtonFocus);
    _addFocusNode.addListener(_onHeroButtonFocus);
    if (widget.autoPlay && widget.items.length > 1) {
      _startAutoPlay();
    }
  }

  void _onHeroButtonFocus() {
    if (_playFocusNode.hasFocus || _detailFocusNode.hasFocus || _addFocusNode.hasFocus) {
      widget.onButtonFocused?.call();
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _playFocusNode.removeListener(_onHeroButtonFocus);
    _detailFocusNode.removeListener(_onHeroButtonFocus);
    _addFocusNode.removeListener(_onHeroButtonFocus);
    _playFocusNode.dispose();
    _detailFocusNode.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = Timer.periodic(widget.autoPlayDuration, (_) {
      if (widget.items.isEmpty) return;
      final next = (_currentIndex + 1) % widget.items.length;
      // 预缓存下一张背景图，避免切换时因网络加载产生闪白/闪黑
      _precacheNextBackdrop(next);
      // 切换索引 + 方向，背景由 AnimatedSwitcher 方向感滑入
      setState(() { _slideDirection = 1; _currentIndex = next; });
    });
  }

  void _precacheNextBackdrop(int index) {
    if (index < 0 || index >= widget.items.length) return;
    final url = widget.items[index].backdropUrl ?? widget.items[index].posterUrl;
    if (url.isEmpty) return;
    // CachedNetworkImage 内部使用 ImageCache，提前触发加载
    precacheImage(
      CachedNetworkImageProvider(url, headers: widget.imageHeaders),
      context,
    ).catchError((_) {});
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
  }

  /// 有效片单状态 = provider 状态 XOR 本地乐观翻转
  bool _isItemInPlaylist(MediaItem item) {
    final providerState = widget.isInPlaylist?.call(item) ?? false;
    final localToggled = _playlistToggled.contains(item.id);
    return providerState ^ localToggled;
  }

  void _nextPage() {
    if (widget.items.isEmpty) return;
    _stopAutoPlay();
    final next = (_currentIndex + 1) % widget.items.length;
    setState(() { _slideDirection = 1; _currentIndex = next; });
    if (widget.autoPlay) _startAutoPlay();
  }

  void _prevPage() {
    if (widget.items.isEmpty) return;
    _stopAutoPlay();
    final prev = (_currentIndex - 1 + widget.items.length) % widget.items.length;
    setState(() { _slideDirection = -1; _currentIndex = prev; });
    if (widget.autoPlay) _startAutoPlay();
  }

  String _formatGenres(List<String> genres) {
    if (genres.isEmpty) return '';
    return genres.take(3).join(' · ');
  }

  String _formatDuration(int minutes) {
    if (minutes <= 0) return '';
    if (minutes < 60) return '${minutes}分钟';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m > 0 ? '${h}小时${m}分钟' : '${h}小时';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return _buildEmptyHero();
    }

    final currentItem = widget.items[_currentIndex];

    return SizedBox(
      height: 520,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景图方向感水平滑动 + 淡入淡出，替代纯交叉淡化，消除”闪”感。
          // Hero 仍包裹当前背景 → 详情页背景同比例矩形变形无缝飞行。
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOutQuint,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              final isIncoming = child.key == ValueKey('hero_bg_$_currentIndex');
              final beginX = isIncoming ? _slideDirection * 0.06 : -_slideDirection * 0.06;
              return SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(beginX, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: Hero(
              key: ValueKey('hero_bg_$_currentIndex'),
              tag: carouselHeroTag(currentItem.id),
              child: _buildBackground(currentItem),
            ),
          ),
          _buildTopGradient(),
          _buildBottomGradient(),
          _buildContent(currentItem),
          _buildIndicator(),
          _buildSideIndicators(),
        ],
      ),
    );
  }

  Widget _buildBackground(MediaItem item) {
    final url = item.backdropUrl ?? item.posterUrl;
    if (url.isEmpty) {
      return Container(color: const Color(0xFF1A1A2E));
    }
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: widget.imageHeaders,
      memCacheWidth: 1920,
      memCacheHeight: 1080,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      // AnimatedSwitcher 已负责交叉淡入淡出，CachedNetworkImage 自身不再做二次 fade，
      // 避免两层动画叠加导致切换"不顺畅"
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => Container(color: const Color(0xFF1A1A2E)),
      errorWidget: (_, __, ___) => Container(color: const Color(0xFF1A1A2E)),
    );
  }

  Widget _buildTopGradient() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 200,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.6),
              Colors.black.withValues(alpha: 0.2),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGradient() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 280,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.3),
              Colors.black.withValues(alpha: 0.75),
              const Color(0xFF0A0A0A),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(MediaItem item) {
    return Positioned(
      left: 64,
      right: 64,
      bottom: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 文字信息区：交叉淡入淡出（标题/评分/简介随轮播切换）
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: KeyedSubtree(
              key: ValueKey('hero_info_$_currentIndex'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.rating != null && item.rating! > 0) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE50914),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                item.rating!.toStringAsFixed(1),
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
                        Text(
                          _formatMeta(item),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 12,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 560,
                    child: Text(
                      item.overview ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 操作按钮区：放在 AnimatedSwitcher 外部，Focus 节点不随轮播重建，
          // 确保 D-pad 焦点遍历始终能找到这些按钮（修复分类区 UP 无法到达 Hero 的问题）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HeroActionButton(
                focusNode: _playFocusNode,
                label: '播放',
                icon: Icons.play_arrow_rounded,
                primary: true,
                onTap: () => widget.onPlay(item),
              ),
              const SizedBox(width: 12),
              _HeroActionButton(
                focusNode: _detailFocusNode,
                label: '详情',
                icon: Icons.info_outline_rounded,
                onTap: () => widget.onDetail(item),
              ),
              const SizedBox(width: 12),
              _HeroActionButton(
                focusNode: _addFocusNode,
                label: _isItemInPlaylist(item) ? '已添加' : '加入片单',
                icon: _isItemInPlaylist(item) ? Icons.check_rounded : Icons.add_rounded,
                onTap: () {
                  // 乐观更新：立即翻转本地状态
                  if (_playlistToggled.contains(item.id)) {
                    _playlistToggled.remove(item.id);
                  } else {
                    _playlistToggled.add(item.id);
                  }
                  setState(() {});
                  widget.onTogglePlaylist?.call(item);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMeta(MediaItem item) {
    final parts = <String>[];
    if (item.year != null) parts.add('${item.year}');
    if (item.quality != null && item.quality!.isNotEmpty) parts.add(item.quality!);
    final duration = _formatDuration(item.duration);
    if (duration.isNotEmpty) parts.add(duration);
    final genres = _formatGenres(item.genres);
    if (genres.isNotEmpty) parts.add(genres);
    return parts.join(' · ');
  }

  Widget _buildIndicator() {
    if (widget.items.length <= 1) return const SizedBox.shrink();
    return Positioned(
      bottom: 32,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.items.length, (index) {
          final isActive = index == _currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isActive ? 24 : 8,
            height: 4,
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.white38,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSideIndicators() {
    if (widget.items.length <= 1) return const SizedBox.shrink();
    return Positioned.fill(
      child: Row(
        children: [
          const SizedBox(width: 16),
          _SideIndicator(
            direction: AxisDirection.left,
            onTap: _prevPage,
          ),
          const Spacer(),
          _SideIndicator(
            direction: AxisDirection.right,
            onTap: _nextPage,
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _buildEmptyHero() {
    return Container(
      height: 520,
      margin: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: const Color(0xFF1A1A2E),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_rounded, size: 64, color: Colors.white38),
            const SizedBox(height: 16),
            const Text(
              '暂无内容',
              style: TextStyle(color: Colors.white54, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  final FocusNode focusNode;

  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.focusNode,
    this.primary = false,
  });

  @override
  State<_HeroActionButton> createState() => _HeroActionButtonState();
}

class _HeroActionButtonState extends State<_HeroActionButton> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final bgColor = widget.primary ? Colors.white : Colors.white24;
    final textColor = widget.primary ? Colors.black : Colors.white;

    return Focus(
      focusNode: widget.focusNode,
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
        // 焦点缩放用 AnimatedScale（仅 paint 层），不再用 AnimatedContainer.transform
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: focused ? 1.06 : 1.0,
            duration: AppAnimations.normal,
            curve: AppAnimations.easeOut,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              curve: AppAnimations.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ]
                    : [],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: textColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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

class _SideIndicator extends StatefulWidget {
  final AxisDirection direction;
  final VoidCallback onTap;

  const _SideIndicator({
    required this.direction,
    required this.onTap,
  });

  @override
  State<_SideIndicator> createState() => _SideIndicatorState();
}

class _SideIndicatorState extends State<_SideIndicator> {
  bool _hover = false;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() => _hover = _focusNode.hasFocus);
  }

  IconData get _icon {
    switch (widget.direction) {
      case AxisDirection.left:
        return Icons.chevron_left_rounded;
      case AxisDirection.right:
        return Icons.chevron_right_rounded;
      default:
        return Icons.chevron_right_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      // TV 遥控器：左右切换箭头不参与 D-pad 焦点遍历，避免按↑从分类区返回时
      // 焦点落到左侧箭头上（该箭头形似“返回键”且会抢占焦点，导致无法回到播放/详情按钮）。
      // 触摸/鼠标仍可通过 GestureDetector 点击切换。
      skipTraversal: true,
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
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _hover ? Colors.white30 : Colors.black38,
              shape: BoxShape.circle,
              border: Border.all(
                color: _hover ? Colors.white54 : Colors.white24,
                width: 1,
              ),
            ),
            child: Icon(
              _icon,
              color: _hover ? Colors.white : Colors.white70,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}
