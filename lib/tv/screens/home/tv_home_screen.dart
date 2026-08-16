import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../utils/app_log.dart';
import '../../../models/media_models.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/media_library_provider.dart';
import '../../../utils/animation_config.dart';
import '../../widgets/tv_top_bar.dart';
import '../../widgets/tv_hero.dart';
import '../../widgets/focusable_widgets.dart';
import '../../widgets/media_hero.dart';

class TvHomeScreen extends ConsumerStatefulWidget {
  const TvHomeScreen({super.key});

  @override
  ConsumerState<TvHomeScreen> createState() => _TvHomeScreenState();
}

class _TvHomeScreenState extends ConsumerState<TvHomeScreen> {
  int _selectedNavIndex = 0;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0;
  final Map<String, FocusNode> _seeAllFocusNodes = {};
  final FocusNode _navTabFocus = FocusNode(debugLabel: 'nav_current_tab');

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // mediaLibraryProvider 构造时已经自动 loadAll()，这里不再重复触发
    // 只有首次启动且 provider 未加载时才手动触发
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(mediaLibraryProvider);
      if (!state.hasLoaded && !state.isLoading) {
        ref.read(mediaLibraryProvider.notifier).loadAll();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.hasClients) {
      final offset = _scrollController.offset;
      if ((offset - _scrollOffset).abs() > 2) {
        setState(() => _scrollOffset = offset);
      }
    }
  }

  /// 图片请求头（飞牛原生 API 的图片端点需要 Authorization 头）
  Map<String, String> get _imageHeaders =>
      ref.read(currentMediaServerServiceProvider)?.imageHeaders ?? const {};

  @override
  Widget build(BuildContext context) {
    final mediaCache = ref.watch(mediaLibraryProvider);
    final servers = ref.watch(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;

    if (defaultServer == null) {
      return Theme(
        data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0A0A)),
        child: Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.dns_rounded, size: 80, color: Colors.white38),
                const SizedBox(height: 24),
                const Text('暂无媒体服务器', style: TextStyle(color: Colors.white, fontSize: 22)),
                const SizedBox(height: 8),
                const Text('请在设置中添加媒体服务器', style: TextStyle(color: Colors.white54, fontSize: 15)),
                const SizedBox(height: 32),
                TvFocusable(
                  focusId: 'go_settings_empty',
                  onTap: () => context.push('/settings'),
                  borderRadius: 8,
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedDecoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.settings_rounded, color: Colors.black, size: 22),
                      SizedBox(width: 10),
                      Text('去设置', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: const Color(0xFF0A0A0A)),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          children: [
            _buildContent(mediaCache),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: TvTopBar(
                selectedIndex: _selectedNavIndex,
                scrollOffset: _scrollOffset,
                selectedTabFocusNode: _navTabFocus,
                onSelect: (index) {
                  if (index == 3) {
                    context.push('/playlist');
                  } else {
                    setState(() => _selectedNavIndex = index);
                  }
                },
                onSearch: () => _navigateTo('/search'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(MediaLibraryState cache) {
    final showHero = _selectedNavIndex == 0;

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Hero 折叠动画（Apple §4 弹簧行为：height + opacity 联动）──
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutQuint,
            height: showHero ? 520 : 0,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: AnimatedOpacity(
              duration: AppAnimations.medium,
              opacity: showHero ? 1.0 : 0.0,
              child: _buildHeroSection(cache),
            ),
          ),
          // ── 顶部间距：Hero 折叠时增加留白避免导航栏遮挡 ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutQuint,
            height: showHero ? 24 : 88,
          ),
          // ── 内容区过渡：Apple §4 弹簧行为 — 去掉廉价缩放，改用
          //   方向感滑入 + 分层曲线（opacity easeOutCubic / position easeOutQuint）──
          AnimatedSwitcher(
            duration: AppAnimations.medium,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeIn,
                ),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.018),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutQuint,
                  )),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey('content_$_selectedNavIndex'),
              child: _selectedNavIndex == 0
                  ? _buildHomeContent(cache)
                  : _buildCategoryRows(cache),
            ),
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildHeroSection(MediaLibraryState cache) {
    final items = cache.carouselItems;

    // 加载中：显示优雅的转圈加载动画
    if (items.isEmpty && cache.isLoading) {
      return SizedBox(
        height: 520,
        child: Stack(
          children: [
            // 背景渐变占位
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E1E3A), Color(0xFF0A0A0A)],
                ),
              ),
            ),
            // 居中转圈
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      color: Color(0xFF6366F1),
                      strokeWidth: 3,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '正在加载媒体库',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '正在从服务器获取资源，请稍候...',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 加载完成但无内容
    if (items.isEmpty) {
      return SizedBox(
        height: 520,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.movie_rounded, size: 64, color: Colors.white24),
              const SizedBox(height: 16),
              const Text('暂无内容', style: TextStyle(color: Colors.white38, fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return TvHero(
      items: items,
      imageHeaders: _imageHeaders,
      onPlay: (item) => _playItem(item),
      onDetail: (item) =>
          _openDetail(item, heroTag: carouselHeroTag(item.id)),
      onTogglePlaylist: (item) {
        ref.read(playlistProvider.notifier).togglePlaylist(item);
      },
      isInPlaylist: (item) {
        final playlist = ref.read(playlistProvider);
        return playlist.any((p) => p.itemId == item.id);
      },
      // Hero 按钮获焦时滚回顶部，让用户看到完整大图背景（而非只看到按钮）
      onButtonFocused: () {
        if (_scrollController.hasClients && _scrollController.offset > 0) {
          _scrollController.animateTo(
            0,
            duration: AppAnimations.slow,
            curve: Curves.easeOutCubic,
          );
        }
      },
    );
  }

  // ── 首页内容：我的媒体 + 继续观看（替代原分类行）──
  Widget _buildHomeContent(MediaLibraryState cache) {
    if (!cache.hasLoaded && cache.isLoading) {
      return _buildLoadingState();
    }
    if (cache.errorMessage != null && cache.libraries.isEmpty) {
      return _buildErrorState();
    }
    if (cache.libraries.isEmpty) {
      return _buildEmptyState();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMyMediaSection(cache),
        const SizedBox(height: 44),
        _buildContinueWatchingSection(),
      ],
    );
  }

  Widget _buildMyMediaSection(MediaLibraryState cache) {
    final libraries = cache.libraries;
    if (libraries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(64, 0, 64, 0),
          child: Text(
            '我的媒体',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(horizontal: 56),
            itemCount: libraries.length,
            itemBuilder: (context, index) {
              final library = libraries[index];
              final items = cache.libraryItems[library.id] ?? [];
              // 取库内第一个有 backdrop 的条目做卡片宽幅背景
              String backdrop = '';
              for (final it in items) {
                if (it.backdropUrl != null && it.backdropUrl!.isNotEmpty) {
                  backdrop = it.backdropUrl!;
                  break;
                }
              }
              if (backdrop.isEmpty && library.posterUrl.isNotEmpty) {
                backdrop = library.posterUrl;
              }
              return Padding(
                padding: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
                child: _LibraryCard(
                  title: library.title,
                  backdropUrl: backdrop,
                  itemCount: items.length,
                  imageHeaders: _imageHeaders,
                  focusId: 'lib_${library.id}',
                  onTap: () => _openLibrary(library),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildContinueWatchingSection() {
    final svc = ref.read(currentMediaServerServiceProvider);
    if (svc == null) return const SizedBox.shrink();

    return FutureBuilder<List<MediaItem>>(
      future: svc.getResumeItems(limit: 20),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        final items = snapshot.data!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(64, 0, 64, 0),
              child: Text(
                '继续观看',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 210,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 56),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(right: 20, top: 10, bottom: 10),
                    child: _ResumeCard(
                      item: item,
                      imageHeaders: _imageHeaders,
                      focusId: 'resume_$index',
                      onTap: () => _playItem(item),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCategoryRows(MediaLibraryState cache) {
    if (!cache.hasLoaded && cache.isLoading) {
      return _buildLoadingState();
    }

    if (cache.errorMessage != null && cache.libraries.isEmpty) {
      return _buildErrorState();
    }

    if (cache.libraries.isEmpty) {
      return _buildEmptyState();
    }

    List<MediaItem> filteredLibraries = cache.libraries;

    if (_selectedNavIndex == 1) {
      filteredLibraries = cache.libraries.where((lib) =>
        lib.type == MediaType.movie ||
        lib.title.toLowerCase().contains('电影')
      ).toList();
    } else if (_selectedNavIndex == 2) {
      filteredLibraries = cache.libraries.where((lib) =>
        lib.type == MediaType.series ||
        lib.title.toLowerCase().contains('剧')
      ).toList();
    }

    if (filteredLibraries.isEmpty) {
      return _buildEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: filteredLibraries.asMap().entries.map((entry) {
        final index = entry.key;
        final library = entry.value;
        final items = cache.libraryItems[library.id] ?? [];
        return FocusTraversalGroup(
          child: Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(64, 0, 64, 0),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: library.posterUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: library.posterUrl,
                                httpHeaders: _imageHeaders,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    const Icon(Icons.video_library, color: Colors.white70, size: 24),
                              )
                            : const Icon(Icons.video_library, color: Colors.white70, size: 24),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            library.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '查看全部',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    _buildSeeAllButton(
                      library,
                      _seeAllFocusNodes.putIfAbsent(library.id, () => FocusNode()),
                      onUp: index == 0 ? () => _navTabFocus.requestFocus() : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (items.isNotEmpty)
                SizedBox(
                  height: 185,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    itemCount: items.length > 20 ? 20 : items.length,
                    itemBuilder: (context, itemIndex) {
                      final item = items[itemIndex];
                      final fid = 'cat_${library.id}_$itemIndex';
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: _MediaCard(
                          item: item,
                          focusId: fid,
                          imageHeaders: _imageHeaders,
                          onTap: () =>
                              _openDetail(item, heroTag: mediaHeroTag(fid)),
                          onPlay: () => _playItem(item),
                          onUp: () => _seeAllFocusNodes[library.id]?.requestFocus(),
                        ),
                      );
                    },
                  ),
                )
              else if (cache.isLoading)
                _buildCategoryLoading()
              else
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('暂无内容', style: TextStyle(color: Colors.white54, fontSize: 15)),
                  ),
                ),
            ],
          ),
        ),
        );
      }).toList(),
    );
  }

  Widget _buildSeeAllButton(MediaItem library, FocusNode focusNode, {VoidCallback? onUp}) {
    return _SeeAllButton(
      onTap: () => _openLibrary(library),
      focusNode: focusNode,
      onUp: onUp,
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 0, 64, 0),
      child: Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        width: 120,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildCategoryLoading(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCategoryLoading() {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 56),
        itemCount: 6,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            width: 100,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          const Text('加载媒体库失败', style: TextStyle(color: Colors.white, fontSize: 18)),
          const SizedBox(height: 8),
          const Text('请检查服务器连接', style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 24),
          TvFocusable(
            focusId: 'retry_load',
            onTap: () => ref.read(mediaLibraryProvider.notifier).refresh(),
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('重试', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library_rounded, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          const Text('暂无内容', style: TextStyle(color: Colors.white, fontSize: 18)),
        ],
      ),
    );
  }

  void _playItem(MediaItem item) async {
    final svc = ref.read(currentMediaServerServiceProvider);
    if (svc == null) return;

    try {
      await svc.ensureAuthenticated();

      // 确定播放目标：剧集类型需要先获取集，不能直接用 series ID 取流
      MediaItem playTarget = item;
      List<MediaItem>? episodes;
      final seriesId = item.type == MediaType.series ? item.id : item.seriesId;

      if (seriesId != null && seriesId.isNotEmpty) {
        try {
          episodes = await svc.getEpisodes(seriesId);
        } catch (_) {}
        // 剧集类型：播放第一集（而非 series 本身）
        if (item.type == MediaType.series && episodes != null && episodes.isNotEmpty) {
          playTarget = episodes.first;
        }
      }

      if (!mounted) return;
      final url = await svc.getStreamUrl(playTarget.id);
      if (!mounted) return;

      context.push('/player/${playTarget.id}', extra: {
        'media': playTarget,
        'url': url,
        'headers': svc.streamHeaders,
        'service': svc,
        if (episodes != null && episodes.isNotEmpty) 'episodes': episodes,
      });
    } catch (e) {
      AppLog.e('TvHome', 'playItem failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('播放失败: $e')),
        );
      }
    }
  }

  void _openDetail(MediaItem item, {String? heroTag}) {
    context.push('/detail/${item.id}', extra: {
      'item': item,
      if (heroTag != null) 'heroTag': heroTag,
    });
  }

  void _openLibrary(MediaItem library) {
    context.push('/library/${library.id}', extra: {'library': library});
  }

  void _navigateTo(String path) {
    context.push(path);
  }
}

/// "查看全部"按钮：强聚焦效果 + RIGHT 键拦截防止逃逸到设置
class _SeeAllButton extends StatefulWidget {
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final VoidCallback? onUp;
  const _SeeAllButton({required this.onTap, this.focusNode, this.onUp});

  @override
  State<_SeeAllButton> createState() => _SeeAllButtonState();
}

class _SeeAllButtonState extends State<_SeeAllButton> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          // 拦截 RIGHT 键，防止焦点逃逸到导航栏设置按钮
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            return KeyEventResult.handled;
          }
          // UP 键：优先用显式回调（第一个分区→导航栏），否则方向遍历
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            if (widget.onUp != null) {
              widget.onUp!();
            } else {
              node.focusInDirection(TraversalDirection.up);
            }
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isFocused ? 1.08 : 1.0,
          duration: Duration(milliseconds: _isFocused ? 280 : 200),
          curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: _isFocused ? Colors.white.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isFocused ? Colors.white : Colors.white30,
                width: _isFocused ? 2.5 : 1,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '查看全部',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white54),
              ],
            ),
          ),
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
  final VoidCallback? onUp;

  const _MediaCard({
    required this.item,
    required this.focusId,
    required this.onTap,
    this.onPlay,
    this.onUp,
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
    // 聚焦时自动把卡片滚动到横向分类行中央，避免聚焦卡被视口边缘裁剪、
    // 用户丢失焦点位置；居中后聚焦卡两侧留白，缩放重叠也更自然
    if (_focusNode.hasFocus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: AppAnimations.medium,
          curve: Curves.easeOutCubic,
          alignment: 0.5,
        );
      });
    }
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
        // UP 键：显式聚焦到本分区的"查看全部"按钮
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (widget.onUp != null) {
            widget.onUp!();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _focusNode,
          builder: (context, child) {
            final isFocused = _focusNode.hasFocus;
            // 弹簧缩放：聚焦进入 easeOutBack 微弹（280ms），离开 easeOut（200ms），
            // 与统一焦点语言（SpringScale）参数一致，替代原先的瞬间跳变
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
                    duration: AppAnimations.normal,
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

/// 我的媒体 — 分类库横幅卡片
class _LibraryCard extends StatefulWidget {
  final String title;
  final String backdropUrl;
  final int itemCount;
  final Map<String, String> imageHeaders;
  final String focusId;
  final VoidCallback onTap;

  const _LibraryCard({
    required this.title,
    required this.backdropUrl,
    required this.itemCount,
    required this.imageHeaders,
    required this.focusId,
    required this.onTap,
  });

  @override
  State<_LibraryCard> createState() => _LibraryCardState();
}

class _LibraryCardState extends State<_LibraryCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  static const double _w = 300;
  static const double _h = 170;
  static const double _focusScale = 1.12;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.focusId);
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    if (_focusNode.hasFocus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            duration: AppAnimations.medium,
            curve: Curves.easeOutCubic,
            alignment: 0.5);
      });
    }
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
        child: AnimatedScale(
          scale: _isFocused ? _focusScale : 1.0,
          duration: Duration(milliseconds: _isFocused ? 280 : 200),
          curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
          child: SizedBox(
            width: _w,
            height: _h,
            child: AnimatedContainer(
              duration: Duration(milliseconds: _isFocused ? 280 : 200),
              curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: _isFocused
                    ? Border.all(color: Colors.white, width: 2.5)
                    : Border.all(color: Colors.transparent, width: 2.5),
              ),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.backdropUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: widget.backdropUrl,
                              httpHeaders: widget.imageHeaders,
                              memCacheWidth: 600,
                              memCacheHeight: 340,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              errorWidget: (_, __, ___) =>
                                  Container(color: const Color(0xFF1E1E3A)),
                            )
                          : Container(color: const Color(0xFF1E1E3A)),
                      // 底部渐变保证文字可读
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                      ),
                      // 标题 + 条目数
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 6),
                                ],
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${widget.itemCount} 部',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
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
}

/// 继续观看 — 带集数信息和进度条的横幅卡片
class _ResumeCard extends StatefulWidget {
  final MediaItem item;
  final Map<String, String> imageHeaders;
  final String focusId;
  final VoidCallback onTap;

  const _ResumeCard({
    required this.item,
    required this.imageHeaders,
    required this.focusId,
    required this.onTap,
  });

  @override
  State<_ResumeCard> createState() => _ResumeCardState();
}

class _ResumeCardState extends State<_ResumeCard> {
  late FocusNode _focusNode;
  bool _isFocused = false;

  static const double _w = 300;
  static const double _h = 170;
  static const double _focusScale = 1.12;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: widget.focusId);
    _focusNode.addListener(_onFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    if (_focusNode.hasFocus && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(context,
            duration: AppAnimations.medium,
            curve: Curves.easeOutCubic,
            alignment: 0.5);
      });
    }
  }

  String get _subtitle {
    final item = widget.item;
    if (item.type == MediaType.episode) {
      final s = item.seasonNumber ?? 1;
      final e = item.episodeNumber ?? 0;
      final epTitle = item.title;
      return 'S$s:E$e - $epTitle';
    }
    if (item.year != null) return '${item.year}';
    return '';
  }

  String get _displayTitle {
    final item = widget.item;
    if (item.type == MediaType.episode && item.seriesTitle != null && item.seriesTitle!.isNotEmpty) {
      return item.seriesTitle!;
    }
    return item.title;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final imgUrl = (item.backdropUrl != null && item.backdropUrl!.isNotEmpty)
        ? item.backdropUrl!
        : item.posterUrl;
    final progress = (item.watchProgress ?? 0).clamp(0.0, 1.0);

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
        child: AnimatedScale(
          scale: _isFocused ? _focusScale : 1.0,
          duration: Duration(milliseconds: _isFocused ? 280 : 200),
          curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
          child: SizedBox(
            width: _w,
            height: _h,
            child: AnimatedContainer(
              duration: Duration(milliseconds: _isFocused ? 280 : 200),
              curve: _isFocused ? Curves.easeOutBack : Curves.easeOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: _isFocused
                    ? Border.all(color: Colors.white, width: 2.5)
                    : Border.all(color: Colors.transparent, width: 2.5),
              ),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      imgUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: imgUrl,
                              httpHeaders: widget.imageHeaders,
                              memCacheWidth: 600,
                              memCacheHeight: 340,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              errorWidget: (_, __, ___) =>
                                  Container(color: const Color(0xFF1E1E3A)),
                            )
                          : Container(color: const Color(0xFF1E1E3A)),
                      DecoratedBox(
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
                      ),
                      // 标题 + 集数信息
                      Positioned(
                        left: 14,
                        right: 14,
                        bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(color: Colors.black54, blurRadius: 4),
                                ],
                              ),
                            ),
                            if (_subtitle.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                _subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // 底部进度条
                      if (progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                            child: SizedBox(
                              height: 4,
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: Colors.white24,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFE50914)),
                              ),
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
}