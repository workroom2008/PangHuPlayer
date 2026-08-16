import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../providers/app_providers.dart';
import '../../../theme/app_theme.dart';
import '../../../models/media_models.dart';
import '../../widgets/focusable_widgets.dart';
import '../../widgets/media_hero.dart';

class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key});

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _navFocusNode = FocusNode(debugLabel: 'search_nav');
  final FocusNode _editFocusNode = FocusNode(debugLabel: 'search_edit');
  bool _searching = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _navFocusNode.addListener(_onNavFocusChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _navFocusNode.removeListener(_onNavFocusChange);
    _controller.dispose();
    _navFocusNode.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onNavFocusChange() {
    if (mounted) setState(() {});
  }

  /// 进入编辑模式：聚焦可编辑节点 + 强制唤起输入法
  void _enterEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  /// 退出编辑模式，回到导航聚焦
  void _exitEditMode() {
    _editFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => _isEditing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _navFocusNode.requestFocus();
    });
  }

  /// 图片请求头（飞牛原生 API 的图片端点需要 Authorization 头）
  Map<String, String> get _imageHeaders =>
      ref.read(currentMediaServerServiceProvider)?.imageHeaders ?? const {};

  void _onQueryChanged(String q) {
    final query = q.trim();
    if (query.isEmpty) {
      ref.read(searchQueryProvider.notifier).state = '';
      return;
    }
    setState(() => _searching = true);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted && _controller.text.trim() == query) {
        ref.read(searchQueryProvider.notifier).state = query;
        setState(() => _searching = false);
      }
    });
  }

  void _openDetail(MediaItem item, {String? heroTag}) {
    final svc = ref.read(currentMediaServerServiceProvider);
    context.push('/detail/${item.id}', extra: {
      'item': item,
      'service': svc,
      if (heroTag != null) 'heroTag': heroTag,
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = ref.watch(searchQueryProvider);
    final aggResult = ref.watch(aggregatedSearchProvider);

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0A0A)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: searchQuery.isEmpty
                  ? _buildEmptyState()
                  : aggResult.when(
                      loading: () => _buildLoading(),
                      error: (err, _) => _buildError(err.toString()),
                      data: (sections) => sections.isEmpty
                          ? _buildNoResults()
                          : _buildResults(sections),
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
          FocusableCard(
            focusId: 'search_back',
            onTap: () => Navigator.pop(context),
            borderRadius: 14,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Focus(
              focusNode: _navFocusNode,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.select ||
                        event.logicalKey == LogicalKeyboardKey.enter ||
                        event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
                  _enterEditMode();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                onTap: _enterEditMode,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: _isEditing ? 0.12 : (_navFocusNode.hasFocus ? 0.10 : 0.08)),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: _isEditing
                          ? Colors.white.withValues(alpha: 0.8)
                          : _navFocusNode.hasFocus
                              ? AppTheme.primary.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.1),
                      width: (_isEditing || _navFocusNode.hasFocus) ? 2 : 1,
                    ),
                    boxShadow: _navFocusNode.hasFocus && !_isEditing
                        ? [
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.2),
                              blurRadius: 14,
                              spreadRadius: 1,
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Icon(
                        _isEditing ? Icons.keyboard_rounded : Icons.search_rounded,
                        color: _isEditing ? Colors.white70 : Colors.white54,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _isEditing
                            ? KeyboardListener(
                                focusNode: _editFocusNode,
                                onKeyEvent: (event) {
                                  if (event is KeyDownEvent &&
                                      (event.logicalKey == LogicalKeyboardKey.escape ||
                                       event.logicalKey == LogicalKeyboardKey.goBack)) {
                                    _exitEditMode();
                                  }
                                },
                                child: TextField(
                                  key: const Key('search_editor'),
                                  controller: _controller,
                                  autofocus: true,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  onChanged: _onQueryChanged,
                                  onSubmitted: (_) => _exitEditMode(),
                                  decoration: const InputDecoration(
                                    hintText: '输入关键词...',
                                    hintStyle: TextStyle(color: Colors.white38, fontSize: 16),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              )
                            : Text(
                                _controller.text.isEmpty
                                    ? '搜索电影、电视剧...'
                                    : _controller.text,
                                style: TextStyle(
                                  color: _controller.text.isEmpty ? Colors.white38 : Colors.white,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                      ),
                      if (_controller.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                          onPressed: () {
                            _controller.clear();
                            ref.read(searchQueryProvider.notifier).state = '';
                            if (_isEditing) _exitEditMode();
                          },
                        ),
                      if (!_isEditing && _navFocusNode.hasFocus)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(Icons.edit_rounded, color: Colors.white54, size: 18),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_rounded, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('输入关键词搜索', style: TextStyle(color: Colors.white54, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: SizedBox(
        width: 32, height: 32,
        child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 3),
      ),
    );
  }

  Widget _buildError(String err) {
    return Center(
      child: Text('搜索出错: $err', style: const TextStyle(color: Colors.white54, fontSize: 16)),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.movie_outlined, size: 64, color: Colors.white24),
          const SizedBox(height: 16),
          const Text('没有找到相关内容', style: TextStyle(color: Colors.white54, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildResults(Map<String, List> sections) {
    final allItems = <MediaItem>[];
    for (final entry in sections.entries) {
      for (final item in entry.value) {
        if (item is MediaItem) allItems.add(item);
      }
    }
    if (allItems.isEmpty) return _buildNoResults();

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(56, 16, 56, 48),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 140,
        mainAxisSpacing: 24,
        crossAxisSpacing: 12,
        childAspectRatio: 120 / 200,
      ),
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        final fid = 'search_$index';
        return _SearchCard(
          item: item,
          focusId: fid,
          imageHeaders: _imageHeaders,
          onTap: () => _openDetail(item, heroTag: mediaHeroTag(fid)),
        );
      },
    );
  }
}

class _SearchCard extends StatefulWidget {
  final MediaItem item;
  final String focusId;
  final VoidCallback onTap;
  final Map<String, String> imageHeaders;

  const _SearchCard({
    required this.item,
    required this.focusId,
    required this.onTap,
    this.imageHeaders = const {},
  });

  @override
  State<_SearchCard> createState() => _SearchCardState();
}

class _SearchCardState extends State<_SearchCard> {
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
  static const double _focusScale = 1.2;

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
              Positioned(
                top: -2,
                left: -2,
                right: -2,
                bottom: -2,
                child: AnimatedOpacity(
                  duration: Duration(milliseconds: _isFocused ? 280 : 200),
                  curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
                  opacity: _isFocused ? 1.0 : 0.0,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 3.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.55),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
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
      left: 6,
      right: 6,
      bottom: 6,
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
              fontSize: 11,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if (widget.item.year != null) ...[
            const SizedBox(height: 2),
            Text(
              '${widget.item.year}',
              style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w500),
            ),
          ],
        ],
      ),
    );
  }
}
