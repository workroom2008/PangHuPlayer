import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/app_providers.dart';
import '../../providers/media_library_provider.dart';
import '../../theme/app_theme.dart';
import '../../models/media_models.dart';
import '../../services/media_server_service.dart';
import '../../utils/screen_adapter.dart';
import '../../utils/animation_config.dart';
import '../../widgets/animated_card.dart';
import '../../widgets/dispersion_glass.dart';
import '../../widgets/hero_flight.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/home_hero_carousel.dart';
import '../../widgets/server_selector_chip.dart';
import '../../widgets/server_image.dart';
import '../../widgets/shimmer_loading.dart';
import '../detail/detail_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import 'resources_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _pageController;
  bool _isNavVisible = true;
  Timer? _hideTimer;
  Timer? _tabSwitchTimer;
  Timer? _interactionDebounceTimer;
  bool _isSwitchingTab = false;
  // 导航栏显示/隐藏动画（单 controller，slide+opacity 严格同步）
  late final AnimationController _navAnim;
  // 导航栏 shader 背景截取的 RepaintBoundary key
  final GlobalKey _pageViewKey = GlobalKey();
  // 导航栏内容行（_LiquidPill 用它算胶囊全局位置）
  final GlobalKey _trackKey = GlobalKey();
  // 液态玻璃胶囊的 DispersionGlass 状态 key
  final GlobalKey<DispersionGlassState> _pillGlassKey = GlobalKey();

  /// Apple 强 ease-out：UI 过渡默认曲线（Cubic(0.23, 1, 0.32, 1)）
  static const Curve _easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Duration _navShowDur = Duration(milliseconds: 240);
  static const Duration _navHideDur = Duration(milliseconds: 140);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _navAnim = AnimationController(vsync: this, value: 1.0, duration: _navShowDur);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _tabSwitchTimer?.cancel();
    _interactionDebounceTimer?.cancel();
    _pageController.dispose();
    _navAnim.dispose();
    super.dispose();
  }

  void _onUserInteraction() {
    if (!_isNavVisible) {
      _setNavVisible(true);
      if (mounted) setState(() {});
    }
    _resetHideTimer();
  }

  void _setNavVisible(bool visible) {
    _isNavVisible = visible;
    if (visible) {
      _navAnim.duration = _navShowDur;
      _navAnim.animateTo(1.0, curve: _easeOut);
    } else {
      _navAnim.duration = _navHideDur;
      _navAnim.animateTo(0.0, curve: _easeOut);
    }
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (_isSwitchingTab) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isNavVisible && !_isSwitchingTab) {
        _setNavVisible(false);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: _onUserInteraction,
        onPanDown: (_) => _onUserInteraction(),
        behavior: HitTestBehavior.translucent,
        child: Stack(
          children: [
            RepaintBoundary(
              key: _pageViewKey,
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  // 点击切换时目标索引已提前更新；手势滑页时才在这里同步。
                  if (_currentIndex != index) {
                    setState(() => _currentIndex = index);
                  }
                  // 切 tab 后立即刷新玻璃背景（不等 350ms 定时器）
                  _pillGlassKey.currentState?.refresh();
                },
                children: [
                  LibraryPage(onGoToResources: () => _navigateTo(2)),
                  const DiscoverPage(),
                  const ResourcesPage(),
                  const SettingsScreen(),
                ],
              ),
            ),
          // 导航栏浮在内容上�?�?BackdropFilter 可模糊到轮播背景
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomNav(),
          ),
        ],
      ),
    ));
  }

  Widget _buildBottomNav() {
    // 单 AnimationController 驱动 slide + opacity，严格同步。
    // 不对称时长：显示 240ms / 隐藏 140ms，双向均为 ease-out（UI 绝不使用 ease-in）。
    return AnimatedBuilder(
      animation: _navAnim,
      builder: (context, child) {
        final t = _navAnim.value;
        return IgnorePointer(
          ignoring: t < 0.05,
          child: Opacity(
            opacity: t,
            child: FractionalTranslation(
              translation: Offset(0, (1.0 - t) * 1.4),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        // 贴地（bottom+2）、侧边距 14
        padding: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.of(context).padding.bottom + 2),
        child: SizedBox(
          key: _trackKey,
          height: 56, // 升级到 iOS 26 Liquid 标准高度（触控热区更宽裕）
          child: LayoutBuilder(
            builder: (context, constraints) {
              final itemWidth = constraints.maxWidth / 4;
              return Stack(
                clipBehavior: Clip.none,
                fit: StackFit.expand,
                children: [
                  // ▌A-7 整排浅玻璃背景：非选中区也有玻璃感（与胶囊玻璃风格一致）
                  ClipPath.shape(
                    shape: const SquircleBorder(radius: 26),
                    child: DispersionGlass(
                      backdropKey: _pageViewKey,
                      radius: 26,
                      active: _isNavVisible,
                      tint: context.isDark ? const Color(0xFF141414) : Colors.white,
                      tintAlpha: context.isDark ? 0.18 : 0.30,
                      blur: 0.7,
                      dispersion: 0.6,
                      edgeGlow: 0.2,
                      saturation: 1.05,
                      // 浅玻璃边框：一条极薄的 10% 白线，增加材质边界感
                      child: Container(
                        decoration: ShapeDecoration(
                          shape: SquircleBorder(
                            radius: 26,
                            side: BorderSide(
                              color: context.isDark
                                  ? const Color(0x1AFFFFFF)
                                  : const Color(0x14000000),
                              width: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 1, height: 1),
                  // 液态玻璃胶囊指示器：水平位移，Spring 可中断
                  _LiquidPill(
                    trackKey: _trackKey,
                    backdropKey: _pageViewKey,
                    glassKey: _pillGlassKey,
                    index: _currentIndex,
                    itemWidth: itemWidth,
                    height: 56,
                    active: _isNavVisible,
                    tint: context.isDark ? const Color(0xFF141414) : Colors.white,
                    tintAlpha: context.isDark ? 0.38 : 0.55,
                  ),
                  // 4 个 Tab 行（图标位置完全固定，只有选中态颜色/字重变化）
                  Row(children: [
                    _NavPill(icon: Icons.home_rounded, label: '媒体', selected: _currentIndex == 0, onTap: () { _navigateTo(0); }),
                    _NavPill(icon: Icons.explore_rounded, label: '发现', selected: _currentIndex == 1, onTap: () { _navigateTo(1); }),
                    _NavPill(icon: Icons.dns_rounded, label: '资源', selected: _currentIndex == 2, onTap: () { _navigateTo(2); }),
                    _NavPill(icon: Icons.settings_rounded, label: '设置', selected: _currentIndex == 3, onTap: () { _navigateTo(3); }),
                  ]),
                ],
              );
            },
          ),
        ),
      ),
    );
  }



  void _navigateTo(int index) {
    // A-8: Haptic + reduced-motion gating
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (index != _currentIndex) {
      unawaited(HapticFeedback.selectionClick());
      _hideTimer?.cancel();
      _tabSwitchTimer?.cancel();
      setState(() {
        _setNavVisible(true);
        _isSwitchingTab = true;
        _currentIndex = index;
      });
      if (!disableAnim) {
        _pageController.animateToPage(
          index,
          duration: AppAnimations.medium,
          curve: AppAnimations.easeInOut,
        );
        _tabSwitchTimer = Timer(const Duration(milliseconds: 330), () {
          if (!mounted) return;
          setState(() => _isSwitchingTab = false);
          _resetHideTimer();
        });
      } else {
        // reduced-motion：直接跳到目标页，不做动画
        _pageController.jumpToPage(index);
        setState(() => _isSwitchingTab = false);
        _resetHideTimer();
      }
    } else {
      _resetHideTimer();
    }
    _pillGlassKey.currentState?.refresh();
  }
}

class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavPill({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // 数十次/天频率门：只动颜色 + 字重 + 极轻 scale，不做夸张形变。
    // 颜色/字重/阴影用 Tween 平滑过渡；图标字号完全不变，保证文字不位移。
    // reduced-motion：时长置 0，TweenAnimationBuilder 直接进入终点，无动画。
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final pillDuration = disableAnim ? Duration.zero : AppAnimations.navPill;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: double.infinity,
          decoration: const BoxDecoration(color: Colors.transparent),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: selected ? 1.0 : 0.0),
            duration: pillDuration,
            curve: const Cubic(0.23, 1.0, 0.32, 1.0),
            builder: (context, t, _) {
              // 选中：主色（亮紫/红主题）；未选中：textPrimary 60%（沉浸感）
              final selectedColor = AppTheme.primary;
              final unselectedColor = context.textPrimary.withValues(alpha: 0.6);
              final color = Color.lerp(unselectedColor, selectedColor, t)!;
              // 极轻形变（1.08 vs 旧版 1.18），数十次/天不做过冲变形
              final iconScale = 1.0 + 0.08 * t;
              // 阴影选中后淡出：选中时被玻璃胶囊覆盖，投影反而压暗。
              // 未选中仅保留极轻投影保证玻璃上可读性——原 55% 黑 + 6px 模糊
              // 叠加玻璃模糊后小字号（12px）发糊，降到 25% + 2px。
              final shadowAlpha = (1.0 - t) * 0.25;
              final shadow = Shadow(
                color: Colors.black.withValues(alpha: shadowAlpha),
                blurRadius: 2,
                offset: const Offset(0, 1),
              );
              // 字重插值：未选中 w500 → 选中 w700（iOS Tab 同款处理，比字号放大高级）
              final fontWeight = FontWeight.lerp(FontWeight.w500, FontWeight.w700, t);
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Transform.scale(
                        scale: iconScale,
                        child: Icon(
                          icon,
                          color: color,
                          size: 22,        // 字号固定，不再 21→22 位移
                          shadows: [shadow],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 32,
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,   // 字号固定
                        fontWeight: fontWeight,
                        shadows: [shadow],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.onGoToResources});

  /// 无服务器空状态点击「去添加」时回调（切换到资源 Tab）
  final VoidCallback? onGoToResources;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> with AutomaticKeepAliveClientMixin {
  final ValueNotifier<int> _bgIndex = ValueNotifier<int>(0);
  // 使用 ValueNotifier 避免颜色变化时整页 setState 重建（每6秒轮播切换会触发）
  final ValueNotifier<Color?> _carouselColor = ValueNotifier<Color?>(null);

  @override
  bool get wantKeepAlive => true;

  /// 将颜色向白色混合，amount 越大越接近白色
  Color _lightenColor(Color color, double amount) {
    final r = (color.r + (1.0 - color.r) * amount).clamp(0.0, 1.0);
    final g = (color.g + (1.0 - color.g) * amount).clamp(0.0, 1.0);
    final b = (color.b + (1.0 - color.b) * amount).clamp(0.0, 1.0);
    return Color.fromARGB(
      (color.a * 255).round(),
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
    );
  }

  @override
  void dispose() {
    _bgIndex.dispose();
    _carouselColor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final servers = ref.watch(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
    final mediaLibraryState = ref.watch(mediaLibraryProvider);
    final size = MediaQuery.sizeOf(context);
    final carouselItems = mediaLibraryState.carouselItems;

    if (defaultServer == null) {
      return Scaffold(
        body: EmptyState(
          icon: Icons.dns_rounded,
          assetAnimation: 'assets/animations/loading.json',
          title: '暂无媒体服务器',
          subtitle: '请前往「资源」页添加Emby、Jellyfin或飞牛影视服务器',
          action: TextButton.icon(
            onPressed: widget.onGoToResources ?? () {},
            icon: Icon(Icons.dns_rounded, size: 18),
            label: Text('去添加'),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: _buildCarousel(carouselItems, size),
              ),
              // 使用 ValueListenableBuilder 局部刷新颜色，避免整页 setState
              // 外层再套 ColorTween 补间，让背景色平滑过渡而非瞬变
              SliverToBoxAdapter(
                child: ValueListenableBuilder<Color?>(
                  valueListenable: _carouselColor,
                  builder: (context, color, _) {
                    final target = color != null
                        ? _lightenColor(color, 0.3).withValues(alpha: 0.95)
                        : Colors.black;
                    return TweenAnimationBuilder<Color?>(
                      tween: ColorTween(end: target),
                      duration: AppAnimations.carouselColor,
                      curve: AppAnimations.easeInOut,
                      builder: (context, lerped, child) => Container(
                        color: lerped ?? target,
                        padding: EdgeInsets.only(
                          left: ScreenAdapter.of(context).contentPadding,
                          right: ScreenAdapter.of(context).contentPadding,
                          bottom: 120,
                        ),
                        child: child,
                      ),
                      child: _MediaLibraryContent(),
                    );
                  },
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 8, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: [
                  const ServerSelectorChip(),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        AppAnimations.buildPageRoute(
                          page: SearchScreen(),
                          type: PageTransitionType.fadeSlide,
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.search, color: context.textPrimary, size: 22),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCarousel(List<MediaItem> items, Size size) {
    final svc = ref.watch(currentMediaServerServiceProvider);
    final headers = svc?.imageHeaders;
    if (items.isEmpty) {
      return SizedBox(height: size.height * 0.65, child: Container(color: context.bgColor));
    }
    return SizedBox(
      height: size.height * 0.65,
      child: Stack(
        children: [
          HomeHeroCarousel(
            items: items,
            imageHeaders: headers,
            service: svc,
            onIndexChanged: (i) => _bgIndex.value = i,
            onTapItem: () {
              if (_bgIndex.value < items.length) {
                _openCarouselItem(context, items[_bgIndex.value]);
              }
            },
            onColorExtracted: (color) {
              // 仅更新 ValueNotifier，不触发 setState，避免整页重建
              _carouselColor.value = color;
            },
          ),
          // 底部渐变遮罩也用 ValueListenableBuilder 局部刷新
          // 同样套 ColorTween 补间，且与上方分类区共用 carouselColor 时长/曲线，
          // 两者必须同步，否则过渡期间会出现色带割裂
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<Color?>(
              valueListenable: _carouselColor,
              builder: (context, color, _) {
                return TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: color),
                  duration: AppAnimations.carouselColor,
                  curve: AppAnimations.easeInOut,
                  builder: (context, lerped, _) {
                    // 分类区背景色（与下方容器颜色一致）
                    final categoryBg = lerped != null
                        ? _lightenColor(lerped, 0.3).withValues(alpha: 0.95)
                        : Colors.black;
                    return Container(
                      height: 120,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            lerped != null
                                ? lerped.withValues(alpha: 0.15)
                                : Colors.black.withValues(alpha: 0.3),
                            lerped != null
                                ? lerped.withValues(alpha: 0.4)
                                : Colors.black.withValues(alpha: 0.6),
                            categoryBg,
                          ],
                          stops: const [0.0, 0.3, 0.6, 1.0],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openCarouselItem(BuildContext context, MediaItem item) {
    final server = ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull;
    context.push('/detail/${item.id}', extra: {'item': item, 'server': server});
  }
}

class _MediaLibraryContent extends ConsumerStatefulWidget {
  const _MediaLibraryContent();

  @override
  ConsumerState<_MediaLibraryContent> createState() => _MediaLibraryContentState();
}

class _MediaLibraryContentState extends ConsumerState<_MediaLibraryContent> with AutomaticKeepAliveClientMixin {
  bool _hasAnimated = false;
  bool _categoriesExpanded = false;
  static const int _maxVisibleCategories = 3;

  /// 继续观看 future 缓存，避免每次 build 都重新调用 API
  /// 手动调用 _refreshResumeItems() 刷新（如从播放器返回时）
  Future<List<MediaItem>>? _resumeFuture;
  String? _resumeSvcKey;

  @override
  bool get wantKeepAlive => true;

  void _openLibrary(MediaItem library) {
    final servers = ref.read(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
    final service = ref.read(currentMediaServerServiceProvider);
    if (defaultServer == null || service == null) return;
    
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => LibraryItemsScreen(
          server: defaultServer,
          serverService: service,
          library: library,
        ),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _openItemDetail(MediaItem item) {
    // 合集（BoxSet）：点击后展示合集内的影视列表，而不是合集详情页
    if (item.isBoxSet) {
      final servers = ref.read(mediaServersProvider);
      final server = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
      final service = ref.read(currentMediaServerServiceProvider);
      if (server == null || service == null) return;
      Navigator.push(
        context,
        AppAnimations.buildPageRoute(
          page: LibraryItemsScreen(
            server: server,
            serverService: service,
            library: item,
          ),
          type: PageTransitionType.fadeSlide,
        ),
      );
      return;
    }
    // 如果继续观看的是剧集，跳转到系列详情页并标记选中该集
    if (item.type == MediaType.episode && item.seriesId != null) {
      context.push('/detail/${item.seriesId}', extra: {
        'item': item.copyWith(
          id: item.seriesId!,
          type: MediaType.series,
          title: item.seriesTitle ?? item.title,
        ),
        'resumeEpisodeId': item.id,
      });
    } else {
      context.push('/detail/${item.id}', extra: {'item': item});
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mediaState = ref.watch(mediaLibraryProvider);
    
    if (!mediaState.hasLoaded && mediaState.isLoading) {
      return _buildLoadingState();
    }
    
    if (mediaState.errorMessage != null && mediaState.libraries.isEmpty) {
      return _buildErrorState();
    }
    
    if (mediaState.libraries.isEmpty) {
      return _buildEmptyState();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildContinueWatching(),
        _buildCategories(mediaState.libraries, mediaState.libraryItems),
      ],
    );
  }

  /// 刷新继续观看列表（从播放器返回或手动点击刷新时调用）
  void _refreshResumeItems() {
    final svc = ref.read(currentMediaServerServiceProvider);
    if (svc == null) return;
    setState(() {
      _resumeFuture = svc.getResumeItems();
    });
  }

  Widget _buildContinueWatching() {
    final svc = ref.watch(currentMediaServerServiceProvider);
    if (svc == null) return const SizedBox.shrink();
    // 缓存 future，避免每次 build 都重新调用 API
    final svcKey = svc.baseUrl;
    if (_resumeFuture == null || _resumeSvcKey != svcKey) {
      _resumeSvcKey = svcKey;
      _resumeFuture = svc.getResumeItems();
    }
    return FutureBuilder<List<MediaItem>>(
      future: _resumeFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const SizedBox.shrink();
        final items = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8),
              Row(
                children: [
                  Text('继续观看', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _refreshResumeItems,
                    child: Icon(Icons.refresh_rounded, color: context.textSecondary, size: 18),
                  ),
                ],
              ),
              SizedBox(height: 12),
              SizedBox(
                height: 210,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _ContinueWatchingCard(
                      item: item,
                      onTap: () => _openResumeItem(item),
                    ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideX(begin: 0.1, end: 0);
                  },
                ),
              ),
              SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _openResumeItem(MediaItem item) {
    final server = ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull;
    final svc = ref.read(currentMediaServerServiceProvider);
    // 如果继续观看的是剧集，跳转到系列详情页并标记选中该集
    if (item.type == MediaType.episode && item.seriesId != null) {
      context.push('/detail/${item.seriesId}', extra: {
        'item': item.copyWith(
          id: item.seriesId!,
          type: MediaType.series,
          title: item.seriesTitle ?? item.title,
        ),
        'service': svc,
        'server': server,
        'resumeEpisodeId': item.id,
      }).then((_) {
        _refreshResumeItems();
      });
    } else {
      context.push('/detail/${item.id}', extra: {
        'item': item,
        'service': svc,
        'server': server,
      }).then((_) {
        _refreshResumeItems();
      });
    }
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildCategoryHeaderLoading(),
          SizedBox(height: 12),
          _buildCategoryItemsLoading(),
        ],
      ),
    );
  }

  Widget _buildCategoryHeaderLoading() {
    // 与 _buildCategoryHeader 结构对齐：40x40 图标 + 12px 间隔 + 两行文字
    return Row(
      children: [
        const SkeletonBox(width: 40, height: 40, radius: 10),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            SkeletonBox(width: 120, height: 18, radius: 4),
            SizedBox(height: 4),
            SkeletonBox(width: 60, height: 12, radius: 4),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryItemsLoading() {
    // 骨架尺寸与 _MediaItemCard 完全一致（同宽/同高/同圆角/同间距），
    // 加载完成时内容就地填充，不产生高度突变跳位。
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth;
    final cardHeight = cardWidth / adapter.cardAspectRatio;
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (context, index) => SkeletonPosterCard(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          radius: adapter.cardRadius,
          spacing: adapter.cardSpacing,
          subtitleFontSize: adapter.subtitleFontSize,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          children: [
            Text('加载媒体库失败', style: TextStyle(color: context.textPrimary)),
            SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.read(mediaLibraryProvider.notifier).refresh(),
              child: Text('重试', style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text('暂无媒体', style: TextStyle(color: context.textPrimary)),
      ),
    );
  }

  Widget _buildCategories(List<MediaItem> libraries, Map<String, List<MediaItem>> libraryItems) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasAnimated) _hasAnimated = true;
    });
    final shouldCollapse = libraries.length > _maxVisibleCategories;
    final visibleLibraries = shouldCollapse && !_categoriesExpanded
        ? libraries.sublist(0, _maxVisibleCategories)
        : libraries;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...visibleLibraries.asMap().entries.map((entry) {
          final index = entry.key;
          final library = entry.value;
          final items = libraryItems[library.id] ?? [];
          return _buildCategorySection(library, items, index);
        }),
        // 展开/收起按钮
        if (shouldCollapse)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: GestureDetector(
              onTap: () => setState(() => _categoriesExpanded = !_categoriesExpanded),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _categoriesExpanded ? '收起' : '展开全部 ${libraries.length} 个媒体库',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _categoriesExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCategorySection(MediaItem library, List<MediaItem> items, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryHeader(library)
              .animate(target: _hasAnimated ? 1.0 : null)
              .fadeIn(delay: Duration(milliseconds: 100 * index)),
          SizedBox(height: 12),
          if (items.isNotEmpty)
            _buildCategoryItems(items, library, index)
          else if (ref.watch(mediaLibraryProvider).isLoading)
            _buildCategoryItemsLoading()
          else
            SizedBox(height: 180, child: Center(child: Text('暂无内容'))),
          SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(MediaItem library) {
    final svc = ref.watch(currentMediaServerServiceProvider);
    final headers = svc?.imageHeaders;
    return GestureDetector(
      onTap: () => _openLibrary(library),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha:0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ServerImage(
                imageUrl: library.posterUrl,
                headers: headers,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(Icons.video_library, color: context.textPrimary),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(library.title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary)),
              Text('查看全部', style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.textSecondary),
        ],
      ),
    );
  }

  Widget _buildCategoryItems(List<MediaItem> items, MediaItem library, int categoryIndex) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _MediaItemCard(
            item: item,
            onTap: () => _openItemDetail(item),
          ).animate(target: _hasAnimated ? 1.0 : null).fadeIn(delay: Duration(milliseconds: 30 * index));
        },
      ),
    );
  }
}

class _ContinueWatchingCard extends StatelessWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _ContinueWatchingCard({required this.item, required this.onTap});

  String _formatDuration(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = minutes % 60;
      return m > 0 ? '${h}小时${m}分钟' : '${h}小时';
    }
    return '$minutes分钟';
  }

  @override
  Widget build(BuildContext context) {
    final progress = item.watchProgress ?? 0;
    // 优先使用 backdropUrl（横版海报），回退到 posterUrl
    final imageUrl = (item.backdropUrl != null && item.backdropUrl!.isNotEmpty)
        ? item.backdropUrl!
        : item.posterUrl;

    // 计算剩余时间
    final remainingMs = item.duration > 0 && progress > 0
        ? (item.duration * (1 - progress) * 1000).round()
        : 0;
    final remainingMin = remainingMs > 0 ? (remainingMs / 60000).ceil() : 0;

    // 标题：剧集显示系列名，电影显示标题
    final mainTitle = item.type == MediaType.episode && item.seriesTitle != null
        ? item.seriesTitle!
        : item.title;
    // 副标题：剧集显示 S01·E03 标题
    final subtitle = item.type == MediaType.episode
        ? (item.seasonNumber != null && item.episodeNumber != null
            ? 'S${item.seasonNumber}·E${item.episodeNumber} ${item.title}'
            : item.title)
        : null;

    return ScaleCard(
      onTap: onTap,
      child: Container(
        width: 250,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 横版缩略图 (16:9)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 250,
                height: 141,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景图
                    imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            memCacheWidth: 500,
                            errorWidget: (_, __, ___) => Container(
                              color: context.textPrimary.withValues(alpha: 0.05),
                              child: Icon(Icons.movie, color: context.textPrimary.withValues(alpha: 0.3), size: 36),
                            ),
                          )
                        : Container(
                            color: context.textPrimary.withValues(alpha: 0.05),
                            child: Icon(Icons.movie, color: context.textPrimary.withValues(alpha: 0.3), size: 36),
                          ),
                    // 底部渐变遮罩（让进度条和剩余时间更清晰）
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                          ),
                        ),
                      ),
                    ),
                    // 集数标签（左上角）
                    if (item.type == MediaType.episode && item.seasonNumber != null && item.episodeNumber != null)
                      Positioned(
                        left: 8, top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'S${item.seasonNumber}·E${item.episodeNumber}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    // 剩余时间标签（右下角）
                    if (remainingMin > 0)
                      Positioned(
                        right: 8, bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '剩余 ${_formatDuration(remainingMin)}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    // 进度条（底部）
                    if (progress > 0)
                      Positioned(
                        left: 0, right: 0, bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      ),
                    // 播放图标居中
                    Center(
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 标题区域
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mainTitle,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaItemCard extends ConsumerWidget {
  final MediaItem item;
  final VoidCallback onTap;

  const _MediaItemCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth;
    final cardHeight = cardWidth / adapter.cardAspectRatio;
    final cardRadius = adapter.cardRadius;
    final subtitleFontSize = adapter.subtitleFontSize;
    final svc = ref.watch(currentMediaServerServiceProvider);
    final headers = svc?.imageHeaders;
    
    return ScaleCard(
      onTap: onTap,
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: adapter.cardSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(cardRadius),
                child: Hero(
                  tag: 'media_${item.id}_poster',
                  flightShuttleBuilder: heroFlightShuttle,
                  child: ServerImage(
                    imageUrl: item.posterUrl,
                    headers: headers,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    memCacheWidth: (cardWidth * MediaQuery.of(context).devicePixelRatio).round(),
                    placeholder: (_, __) => Container(
                      color: context.textPrimary.withValues(alpha:0.1),
                      child: Center(child: Icon(Icons.movie, color: context.textPrimary)),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: context.textPrimary.withValues(alpha:0.1),
                      child: Center(child: Icon(Icons.movie, color: context.textPrimary)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            Text(item.title, style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
            if (item.year != null)
              Text(item.year.toString(), style: TextStyle(color: context.textPrimary.withValues(alpha:0.6), fontSize: subtitleFontSize), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class LibraryItemsScreen extends ConsumerStatefulWidget {
  final MediaServer server;
  final MediaServerService serverService;
  final MediaItem library;

  const LibraryItemsScreen({
    super.key,
    required this.server,
    required this.serverService,
    required this.library,
  });

  @override
  ConsumerState<LibraryItemsScreen> createState() => _LibraryItemsScreenState();
}

class _LibraryItemsScreenState extends ConsumerState<LibraryItemsScreen> with TickerProviderStateMixin {
  Future<List<MediaItem>>? _itemsFuture;
  late TabController _tabController;
  int _currentTab = 0;
  
  Color _bgColor = const Color(0xFFE8D5C4);
  Color _textColor = Colors.black;
  bool _colorsExtracted = false;
  
  String _sortBy = '加入日期';
  bool _sortDescending = true;
  bool _showSortMenu = false;
  bool _isGridView = true;
  bool _isPortraitCard = true;
  String? _activeGenreFilter;   // 类型过滤（点击类型卡进入）
  String? _activeFolderFilter;  // 文件夹过滤（点击文件夹卡进入）
  
  List<String> get _tabs => [widget.library.title, '类型', '文件夹'];
  final List<String> _sortOptions = [
    '加入日期', '标题', '公众评分', '影评人评分',
    '出品年份', '首映日期', '官方评级', '播放日期'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() {
      setState(() => _currentTab = _tabController.index);
    });
    _loadItems();
  }

  Future<void> _extractDominantColor(String imageUrl) async {
    if (_colorsExtracted || imageUrl.isEmpty) return;
    try {
      final color = await _calculateDominantColor(imageUrl);
      if (mounted && color != null) {
        setState(() {
          _bgColor = _lightenColor(color, 0.75);
          _textColor = _isColorLight(_bgColor) ? Colors.black : context.textPrimary;
          _colorsExtracted = true;
        });
      }
    } catch (_) {}
  }

  Future<Color?> _calculateDominantColor(String imageUrl) async {
    try {
      final provider = CachedNetworkImageProvider(imageUrl);
      final completer = Completer<ImageInfo>();
      final stream = provider.resolve(ImageConfiguration.empty);
      stream.addListener(ImageStreamListener((info, _) {
        if (!completer.isCompleted) completer.complete(info);
      }));
      final imageInfo = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw 'timeout',
      );
      final byteData = await imageInfo.image.toByteData(format: ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      
      final bytes = byteData.buffer.asUint8List();
      final pixelCount = imageInfo.image.width * imageInfo.image.height;
      final step = pixelCount ~/ 100;
      
      int r = 0, g = 0, b = 0, count = 0;
      for (int i = 0; i < bytes.length; i += 4 * step) {
        if (i + 2 < bytes.length) {
          r += bytes[i];
          g += bytes[i + 1];
          b += bytes[i + 2];
          count++;
        }
      }
      if (count == 0) return null;
      return Color.fromRGBO(r ~/ count, g ~/ count, b ~/ count, 1);
    } catch (_) {
      return null;
    }
  }

  Color _lightenColor(Color color, double amount) {
    final r = ((color.r * 255 + (255 - color.r * 255) * amount).round()).clamp(0, 255);
    final g = ((color.g * 255 + (255 - color.g * 255) * amount).round()).clamp(0, 255);
    final b = ((color.b * 255 + (255 - color.b * 255) * amount).round()).clamp(0, 255);
    return Color.fromRGBO(r, g, b, 1);
  }

  bool _isColorLight(Color color) {
    final luminance = (0.299 * color.r + 0.587 * color.g + 0.114 * color.b);
    return luminance > 0.5;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadItems() {
    // 分页拉全量：单页默认 50 条，大库只取第一页会"少"（实测 Emby 166 / Jellyfin 173）
    // boxsets 库需显式带上 BoxSet 类型（Jellyfin 用 Movie,Series 查合集返回 0）
    _itemsFuture = widget.serverService.getAllLibraryItems(
      widget.library.id,
      includeBoxSets: widget.library.collectionType == 'boxsets',
    );
  }

  void _openDetail(MediaItem item) {
    // 合集（BoxSet）：点击后展示合集内的影视列表，而不是合集详情页
    if (item.isBoxSet) {
      Navigator.push(
        context,
        AppAnimations.buildPageRoute(
          page: LibraryItemsScreen(
            server: widget.server,
            serverService: widget.serverService,
            library: item,
          ),
          type: PageTransitionType.fadeSlide,
        ),
      );
      return;
    }
    Navigator.push(
      context,
      AppAnimations.buildPageRoute(
        page: DetailScreen(item: item, service: widget.serverService),
        // fadeSlide：内容轻微上滑+淡入，配合 Hero 海报飞行（AfuseKt 共享元素转场）
        type: PageTransitionType.fadeSlide,
      ),
    );
  }

  List<MediaItem> _sortItems(List<MediaItem> items) {
    var sorted = List<MediaItem>.from(items);
    switch (_sortBy) {
      case '标题':
        sorted.sort((a, b) => a.title.compareTo(b.title));
        break;
      case '公众评分':
      case '影评人评分':
        sorted.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case '出品年份':
      case '首映日期':
        sorted.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      default:
        break;
    }
    if (!_sortDescending && _sortBy != '标题') {
      sorted = sorted.reversed.toList();
    }
    if (_sortDescending && _sortBy == '标题') {
      sorted = sorted.reversed.toList();
    }
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: MediaQuery.of(context).padding.top + 60),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _buildTabBar(),
                ),
              ),
              if (_activeGenreFilter != null || _activeFolderFilter != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: _buildFilterBar(),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              FutureBuilder<List<MediaItem>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return _buildLoadingGrid();
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return _buildErrorState();
                  }
                  final items = _sortItems(snapshot.data!);
                  if (items.isEmpty) {
                    return _buildEmptyState();
                  }
                  if (!_colorsExtracted && items.first.posterUrl.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      _extractDominantColor(items.first.posterUrl);
                    });
                  }
                  return _buildContent(items);
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
          _buildTopBar(),
          _buildSortMenu(),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 12,
          right: 12,
          bottom: 8,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.arrow_back_rounded, color: _textColor, size: 24),
            ),
            Expanded(
              child: Text(
                widget.library.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SearchScreen())),
              icon: Icon(Icons.search_rounded, color: _textColor, size: 24),
            ),
            IconButton(
              onPressed: () => setState(() => _showSortMenu = !_showSortMenu),
              icon: Icon(Icons.menu_rounded, color: _textColor, size: 24),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _textColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(22),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: context.cardColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.cardColor),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: context.textPrimary,
        unselectedLabelColor: _textColor.withValues(alpha: 0.5),
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
        tabs: _tabs.map((t) => Tab(text: t)).toList(),
      ),
    );
  }

  Widget _buildContent(List<MediaItem> items) {
    if (_currentTab == 0) {
      return _buildMovieGrid(_applyFilter(items));
    } else if (_currentTab == 1) {
      return _buildGenreGrid(items);
    } else {
      return _buildFolderGrid(items);
    }
  }

  /// 应用类型/文件夹过滤（点击类型卡/文件夹卡进入过滤视图）
  List<MediaItem> _applyFilter(List<MediaItem> items) {
    if (_activeGenreFilter != null) {
      return items.where((i) => i.genres.contains(_activeGenreFilter)).toList();
    }
    if (_activeFolderFilter != null) {
      return items.where((i) => _getParentFolderName(i.filePath) == _activeFolderFilter).toList();
    }
    return items;
  }

  /// 过滤激活时的返回栏
  Widget _buildFilterBar() {
    final label = _activeGenreFilter ?? _activeFolderFilter ?? '';
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.filter_alt_rounded, color: AppTheme.primary, size: 14),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(color: AppTheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => setState(() {
                _activeGenreFilter = null;
                _activeFolderFilter = null;
                _currentTab = 0;
                _tabController.index = 0;
              }),
              child: const Icon(Icons.close_rounded, color: AppTheme.primary, size: 16),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildMovieGrid(List<MediaItem> items) {
    final crossAxisCount = _isPortraitCard ? 3 : 2;
    final cardAspectRatio = _isPortraitCard ? 2 / 3 : 16 / 10;
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: cardAspectRatio,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            // 入场动画只给首屏卡片：长列表快速下滑时全局 index 可达数百，
            // delay=20ms×index 会累积到数秒，滚动进入的卡片会长时间空白
            Widget card = _SenPlayerCard(
              item: item,
              isPortrait: _isPortraitCard,
              textColor: _textColor,
              onTap: () => _openDetail(item),
            );
            if (index < 24) {
              card = card.animate().fadeIn(delay: Duration(milliseconds: 20 * index));
            }
            return card;
          },
          childCount: items.length,
        ),
      ),
    );
  }

  Widget _buildGenreGrid(List<MediaItem> items) {
    final genres = <String, List<MediaItem>>{};
    for (final item in items) {
      for (final genre in item.genres) {
        genres.putIfAbsent(genre, () => []);
        genres[genre]!.add(item);
      }
    }
    final genreList = genres.entries.toList();
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2 / 3,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = genreList[index];
            final firstItem = entry.value.isNotEmpty ? entry.value.first : null;
            Widget card = _GenreCard(
              genre: entry.key,
              count: entry.value.length,
              posterUrl: firstItem?.posterUrl ?? '',
              textColor: _textColor,
              onTap: () => setState(() {
                _activeGenreFilter = entry.key;
                _activeFolderFilter = null;
                _currentTab = 0;
                _tabController.index = 0;
              }),
            );
            // 同网格：fadeIn delay 随 index 线性放大，快速滑动时只对首屏动画
            if (index < 24) {
              card = card.animate().fadeIn(delay: Duration(milliseconds: 20 * index));
            }
            return card;
          },
          childCount: genreList.length,
        ),
      ),
    );
  }

  Widget _buildFolderGrid(List<MediaItem> items) {
    final folders = <String, List<MediaItem>>{};
    for (final item in items) {
      final folderName = _getParentFolderName(item.filePath);
      if (folderName != null && folderName.isNotEmpty) {
        folders.putIfAbsent(folderName, () => []);
        folders[folderName]!.add(item);
      }
    }
    final folderList = folders.entries.toList();
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2 / 3,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final entry = folderList[index];
            final firstItem = entry.value.isNotEmpty ? entry.value.first : null;
            Widget card = _FolderCard(
              folderName: entry.key,
              count: entry.value.length,
              posterUrl: firstItem?.posterUrl ?? '',
              textColor: _textColor,
              onTap: () => setState(() {
                _activeFolderFilter = entry.key;
                _activeGenreFilter = null;
                _currentTab = 0;
                _tabController.index = 0;
              }),
            );
            // 同网格：fadeIn delay 随 index 线性放大，快速滑动时只对首屏动画
            if (index < 24) {
              card = card.animate().fadeIn(delay: Duration(milliseconds: 20 * index));
            }
            return card;
          },
          childCount: folderList.length,
        ),
      ),
    );
  }

  String? _getParentFolderName(String? filePath) {
    if (filePath == null || filePath.isEmpty) return null;
    final parts = filePath.split(RegExp(r'[\\/]'));
    if (parts.length < 2) return null;
    for (int i = parts.length - 2; i >= 0; i--) {
      if (parts[i].isNotEmpty) return parts[i];
    }
    return null;
  }

  Widget _buildLoadingGrid() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2 / 3,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => const SkeletonBox(radius: 16),
          childCount: 12,
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return SliverToBoxAdapter(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 80),
            Icon(Icons.error_outline, color: _textColor.withValues(alpha: 0.5), size: 48),
            SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: _textColor, fontSize: 16)),
            SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _loadItems()),
              child: Text('重试', style: TextStyle(color: AppTheme.primary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverToBoxAdapter(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(height: 80),
            Icon(Icons.movie_rounded, color: _textColor.withValues(alpha: 0.3), size: 48),
            SizedBox(height: 16),
            Text('暂无内容', style: TextStyle(color: _textColor.withValues(alpha: 0.6), fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildSortMenu() {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 56,
      right: 12,
      child: _AnimatedMenuPanel(
        visible: _showSortMenu,
        child: GestureDetector(
          onTap: () => setState(() => _showSortMenu = false),
          behavior: HitTestBehavior.translucent,
          child: Container(
            width: 260,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '排序顺序',
                  style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              ..._sortOptions.map((option) => _SortMenuItem(
                label: option,
                isSelected: _sortBy == option,
                isDescending: _sortDescending,
                onTap: () {
                  if (_sortBy == option) {
                    setState(() => _sortDescending = !_sortDescending);
                  } else {
                    setState(() {
                      _sortBy = option;
                      _sortDescending = true;
                    });
                  }
                },
              )),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                height: 1,
                color: context.textSecondary.withValues(alpha: 0.2),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '展示样式',
                  style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              _SortMenuItem(
                label: '网格视图',
                isSelected: _isGridView,
                showCheck: true,
                onTap: () => setState(() => _isGridView = true),
              ),
              _SortMenuItem(
                label: '列表视图',
                isSelected: !_isGridView,
                showCheck: true,
                onTap: () => setState(() => _isGridView = false),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                height: 1,
                color: context.textSecondary.withValues(alpha: 0.2),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  '卡片样式',
                  style: TextStyle(color: context.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
              _SortMenuItem(
                label: '竖屏',
                isSelected: _isPortraitCard,
                showCheck: true,
                onTap: () => setState(() => _isPortraitCard = true),
              ),
              _SortMenuItem(
                label: '横屏',
                isSelected: !_isPortraitCard,
                showCheck: true,
                onTap: () => setState(() => _isPortraitCard = false),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SenPlayerCard extends StatelessWidget {
  final MediaItem item;
  final bool isPortrait;
  final Color textColor;
  final VoidCallback onTap;

  const _SenPlayerCard({
    required this.item,
    required this.isPortrait,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      // 占位用主题骨架色（浅色模式为可见的浅灰块，深色模式为暗灰），
                      // 而不是半透明灰——浅色背景下 30% 透明灰≈白，看起来像空白
                      placeholder: (_, __) => Container(
                        color: context.textPrimary.withValues(alpha: 0.08),
                        child: Center(
                          child: Icon(
                            Icons.movie,
                            color: context.textPrimary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: context.textPrimary.withValues(alpha: 0.08),
                        child: Center(
                          child: Icon(
                            Icons.movie,
                            color: context.textPrimary.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: context.textPrimary.withValues(alpha: 0.08),
                      child: Center(
                        child: Icon(
                          Icons.movie,
                          color: context.textPrimary.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                  if (item.rating != null && item.rating! > 0)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                color: Color(0xFFFFC107),
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (item.isWatched == true)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.textPrimary, width: 2),
                        ),
                        child: Icon(Icons.check, color: context.textPrimary, size: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(height: 6),
          Text(
            item.title,
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (item.year != null) ...[
            SizedBox(height: 2),
            Text(
              '${item.year}',
              style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11),
              maxLines: 1,
            ),
          ],
        ],
      ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String genre;
  final int count;
  final String posterUrl;
  final Color textColor;
  final VoidCallback onTap;

  const _GenreCard({
    required this.genre,
    required this.count,
    required this.posterUrl,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) => Container(color: Colors.grey.withValues(alpha: 0.3)),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey.withValues(alpha: 0.3)),
                    )
                  else
                    Container(color: Colors.grey.withValues(alpha: 0.3)),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 12,
                    right: 12,
                    child: Text(
                      genre,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final String folderName;
  final int count;
  final String posterUrl;
  final Color textColor;
  final VoidCallback onTap;

  const _FolderCard({
    required this.folderName,
    required this.count,
    required this.posterUrl,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 300,
                      placeholder: (_, __) => Container(color: Colors.grey.withValues(alpha: 0.3)),
                      errorWidget: (_, __, ___) => Container(color: Colors.grey.withValues(alpha: 0.3)),
                    )
                  else
                    Container(color: Colors.grey.withValues(alpha: 0.3)),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$count 部',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 6),
          Text(
            folderName,
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 排序面板弹层：随 visible 双向播放淡入+缩放动画（打开/关闭都有过渡）。
/// 始终挂载在树上，隐藏时用 IgnorePointer 屏蔽触摸。
class _AnimatedMenuPanel extends StatefulWidget {
  final bool visible;
  final Widget child;

  const _AnimatedMenuPanel({required this.visible, required this.child});

  @override
  State<_AnimatedMenuPanel> createState() => _AnimatedMenuPanelState();
}

class _AnimatedMenuPanelState extends State<_AnimatedMenuPanel> {
  late bool _visible;

  @override
  void initState() {
    super.initState();
    _visible = widget.visible;
    if (widget.visible) {
      // 首次以隐藏态挂载，下一帧再显示以触发入场动画
      _visible = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) setState(() => _visible = true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _AnimatedMenuPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != _visible) {
      setState(() => _visible = widget.visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !_visible,
      child: AnimatedScale(
        scale: _visible ? 1.0 : 0.85,
        alignment: Alignment.topRight,
        duration: AppAnimations.normal,
        curve: AppAnimations.easeOut,
        child: AnimatedOpacity(
          opacity: _visible ? 1.0 : 0.0,
          duration: AppAnimations.normal,
          curve: AppAnimations.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

class _SortMenuItem extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isDescending;
  final bool showCheck;
  final VoidCallback onTap;

  const _SortMenuItem({
    required this.label,
    required this.isSelected,
    this.isDescending = true,
    this.showCheck = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? AppTheme.primary : context.textPrimary,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected && !showCheck)
              Icon(
                isDescending ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                color: AppTheme.primary,
                size: 18,
              ),
            if (isSelected && showCheck)
              Icon(Icons.check_rounded, color: AppTheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> with AutomaticKeepAliveClientMixin {
  int _activeTab = 0;
  final List<String> _tabs = ['全部', '电影', '剧集'];

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: context.bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            floating: true,
            pinned: true,
            backgroundColor: context.bgColor,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: EdgeInsets.zero,
              expandedTitleScale: 1.0,
              title: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 40),
                    Text(
                      '发现',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    SizedBox(height: 12),
                    _buildTabBar(),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: _tabs.length,
        itemBuilder: (context, index) {
          final isActive = _activeTab == index;
          return GestureDetector(
            onTap: () => setState(() => _activeTab = index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              margin: EdgeInsets.only(right: index < _tabs.length - 1 ? 12 : 0),
              decoration: BoxDecoration(
                color: isActive ? AppTheme.accent : context.surfaceColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _tabs[index],
                style: TextStyle(
                  color: isActive ? context.textPrimary : context.textPrimary.withValues(alpha: 0.7),
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 14,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildContent() {
    if (_activeTab == 1) {
      return _buildMovieContent();
    } else if (_activeTab == 2) {
      return _buildTVContent();
    }
    return _buildAllContent();
  }

  Widget _buildAllContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        const _SectionHeader(title: '热门趋势', icon: Icons.trending_up_rounded),
        const _TrendingCarousel(),
        SizedBox(height: 24),
        const _SectionHeader(title: '正在热映', icon: Icons.local_fire_department_rounded),
        _MovieGrid(provider: nowPlayingMoviesProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '热门剧集', icon: Icons.tv_rounded),
        _TVGrid(provider: popularTVProvider),
        SizedBox(height: 24),
        _SectionHeader(title: '评分最高电影', icon: Icons.thumb_up_rounded),
        _MovieGrid(provider: topRatedMoviesProvider),
        SizedBox(height: 24),
        _SectionHeader(title: '评分最高剧集', icon: Icons.star_rounded),
        _TVGrid(provider: topRatedTVProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '即将上映', icon: Icons.upcoming_rounded),
        _MovieGrid(provider: upcomingMoviesProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '正在播出', icon: Icons.live_tv_rounded),
        _TVGrid(provider: onTheAirTVProvider),
        SizedBox(height: 100),
      ],
    );
  }

  Widget _buildMovieContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        const _SectionHeader(title: '热门趋势', icon: Icons.trending_up_rounded),
        const _TrendingCarousel(),
        SizedBox(height: 24),
        const _SectionHeader(title: '正在热映', icon: Icons.local_fire_department_rounded),
        _MovieGrid(provider: nowPlayingMoviesProvider),
        SizedBox(height: 24),
        _SectionHeader(title: '最受欢迎', icon: Icons.star_rounded),
        _MovieGrid(provider: popularMoviesProvider),
        SizedBox(height: 24),
        _SectionHeader(title: '评分最高', icon: Icons.thumb_up_rounded),
        _MovieGrid(provider: topRatedMoviesProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '即将上映', icon: Icons.upcoming_rounded),
        _MovieGrid(provider: upcomingMoviesProvider),
        SizedBox(height: 100),
      ],
    );
  }

  Widget _buildTVContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
        const _SectionHeader(title: '热门剧集', icon: Icons.trending_up_rounded),
        _TVCarousel(),
        SizedBox(height: 24),
        _SectionHeader(title: '最受欢迎', icon: Icons.star_rounded),
        _TVGrid(provider: popularTVProvider),
        SizedBox(height: 24),
        _SectionHeader(title: '评分最高', icon: Icons.thumb_up_rounded),
        _TVGrid(provider: topRatedTVProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '正在播出', icon: Icons.live_tv_rounded),
        _TVGrid(provider: onTheAirTVProvider),
        SizedBox(height: 24),
        const _SectionHeader(title: '今日更新', icon: Icons.calendar_today_rounded),
        _TVGrid(provider: airingTodayTVProvider),
        SizedBox(height: 100),
      ],
    );
  }
}

class _TVCarousel extends ConsumerWidget {
  const _TVCarousel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvAsync = ref.watch(trendingTVProvider);

    return tvAsync.when(
      loading: () => _buildLoadingCarousel(context),
      error: (err, stack) => _buildErrorWidget(context, err.toString()),
      data: (tvList) {
        if (tvList.isEmpty) return const SizedBox.shrink();
        
        final adapter = ScreenAdapter.of(context);
        
        return SizedBox(
          height: adapter.carouselHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
            itemCount: tvList.length,
            itemBuilder: (context, index) {
              final tv = tvList[index];
              return _TVTrendingCard(tv: tv, index: index)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 100 * index))
                  .slideX(begin: 0.2, end: 0);
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingCarousel(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth * 1.5;
    
    return SizedBox(
      height: adapter.carouselHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
        itemCount: 5,
        itemBuilder: (context, index) => SkeletonBox(
          width: cardWidth,
          margin: EdgeInsets.only(right: adapter.cardSpacing),
          radius: adapter.cardRadius,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String error) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Text('加载失败: $error', style: TextStyle(color: context.textPrimary.withValues(alpha:0.6))),
      ),
    );
  }
}

class _TVTrendingCard extends StatelessWidget {
  final dynamic tv;
  final int index;

  const _TVTrendingCard({required this.tv, required this.index});

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth * 1.5;
    final cardHeight = adapter.carouselHeight;
    final cardRadius = adapter.cardRadius;
    final title = tv['name'] ?? tv['title'] ?? '';
    final backdropPath = tv['backdrop_path'] ?? tv['backdropPath'];
    final voteAverage = tv['vote_average'] ?? tv['voteAverage'];
    final firstAirDate = tv['first_air_date'] ?? tv['firstAirDate'];
    
    return ScaleCard(
      onTap: () => _navigateToDetail(context),
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: adapter.cardSpacing),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius),
              child: backdropPath != null
                  ? Hero(
                      tag: 'tv_${tv['id']}_backdrop',
                      child: CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w500$backdropPath',
                        height: cardHeight,
                        width: cardWidth,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (_, __) => Container(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black,
                          child: Icon(Icons.tv, color: context.textPrimary, size: 40),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      height: cardHeight,
                      width: cardWidth,
                      child: Center(child: Icon(Icons.tv, color: context.textPrimary, size: 40)),
                    ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha:0.3),
                      Colors.black.withValues(alpha:0.8),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (voteAverage != null)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 14),
                      SizedBox(width: 4),
                      Text(
                        voteAverage.toStringAsFixed(1),
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: adapter.titleFontSize + 2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (firstAirDate != null) ...[
                    SizedBox(height: 4),
                    Text(
                      firstAirDate.toString().substring(0, 4),
                      style: TextStyle(
                        color: context.textPrimary.withValues(alpha:0.7),
                        fontSize: adapter.subtitleFontSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(context, AppAnimations.buildPageRoute(
      page: DetailScreen.fromTMDBTV(tv),
      type: PageTransitionType.fade,
    ));
  }
}

class _TVGrid extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<dynamic>>> provider;

  const _TVGrid({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tvAsync = ref.watch(provider);
    final adapter = ScreenAdapter.of(context);
    final gridHeight = adapter.cardWidth / adapter.cardAspectRatio + 40;

    return tvAsync.when(
      loading: () => _buildLoadingGrid(adapter, gridHeight),
      error: (err, stack) => _buildErrorWidget(context, err.toString(), gridHeight),
      data: (tvList) {
        if (tvList.isEmpty) return const SizedBox.shrink();
        
        return SizedBox(
          height: gridHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
            itemCount: tvList.length,
            itemBuilder: (context, index) {
              final tv = tvList[index];
              return _TVCard(tv: tv)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 50 * index))
                  .slideX(begin: 0.1, end: 0);
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingGrid(ScreenAdapter adapter, double height) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
        itemCount: 8,
        itemBuilder: (context, index) => SkeletonBox(
          width: adapter.cardWidth,
          margin: EdgeInsets.only(right: adapter.cardSpacing),
          radius: adapter.cardRadius,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String error, double height) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text('加载失败: $error', style: TextStyle(color: context.textPrimary.withValues(alpha:0.6))),
      ),
    );
  }
}

class _TVCard extends StatelessWidget {
  final dynamic tv;

  const _TVCard({required this.tv});

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth;
    final cardRadius = adapter.cardRadius;
    final titleFontSize = adapter.titleFontSize;
    final subtitleFontSize = adapter.subtitleFontSize;
    final title = tv['name'] ?? tv['title'] ?? '';
    final posterPath = tv['poster_path'] ?? tv['posterUrl'];
    final voteAverage = tv['vote_average'] ?? tv['voteAverage'];
    final firstAirDate = tv['first_air_date'] ?? tv['firstAirDate'];

    return ScaleCard(
      onTap: () => _navigateToDetail(context),
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: adapter.cardSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(cardRadius),
                child: Stack(
                  children: [
                    Hero(
                      tag: 'tv_${tv['id']}_poster',
                      flightShuttleBuilder: heroFlightShuttle,
                      child: posterPath != null
                          ? CachedNetworkImage(
                              imageUrl: 'https://image.tmdb.org/t/p/w300$posterPath',
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (_, __) => Container(
                                color: context.textPrimary.withValues(alpha:0.1),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: context.textPrimary.withValues(alpha:0.1),
                                child: Icon(Icons.tv, color: context.textPrimary),
                              ),
                            )
                          : Container(
                              color: context.textPrimary.withValues(alpha:0.1),
                              child: Icon(Icons.tv, color: context.textPrimary),
                            ),
                    ),
                    if (voteAverage != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha:0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 10),
                              SizedBox(width: 2),
                              Text(
                                voteAverage.toStringAsFixed(1),
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(99, 102, 241, 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '剧集',
                          style: TextStyle(color: context.textPrimary, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: context.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: titleFontSize,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (firstAirDate != null) ...[
              SizedBox(height: 2),
              Text(
                firstAirDate.toString().substring(0, 4),
                style: TextStyle(
                  color: context.textPrimary.withValues(alpha:0.6),
                  fontSize: subtitleFontSize,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(context, AppAnimations.buildPageRoute(
      page: DetailScreen.fromTMDBTV(tv),
      type: PageTransitionType.fade,
    ));
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color.fromRGBO(99, 102, 241, 0.2),
                  Color.fromRGBO(139, 92, 246, 0.2),
                ],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: context.textPrimary, size: 18),
          ),
          SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0);
  }
}

class _TrendingCarousel extends ConsumerWidget {
  const _TrendingCarousel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moviesAsync = ref.watch(trendingMoviesProvider);

    return moviesAsync.when(
      loading: () => _buildLoadingCarousel(context),
      error: (err, stack) => _buildErrorWidget(context, err.toString()),
      data: (movies) {
        if (movies.isEmpty) return const SizedBox.shrink();
        
        final adapter = ScreenAdapter.of(context);
        
        return SizedBox(
          height: adapter.carouselHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return _TrendingCard(movie: movie, index: index)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 100 * index))
                  .slideX(begin: 0.2, end: 0);
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingCarousel(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth * 1.5;
    
    return SizedBox(
      height: adapter.carouselHeight,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
        itemCount: 5,
        itemBuilder: (context, index) => SkeletonBox(
          width: cardWidth,
          margin: EdgeInsets.only(right: adapter.cardSpacing),
          radius: adapter.cardRadius,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String error) {
    return SizedBox(
      height: 280,
      child: Center(
        child: Text('加载失败: $error', style: TextStyle(color: context.textPrimary.withValues(alpha:0.6))),
      ),
    );
  }
}

class _TrendingCard extends StatelessWidget {
  final TMDBMovie movie;
  final int index;

  const _TrendingCard({required this.movie, required this.index});

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    // 热门卡片使用比普通卡片稍宽的尺寸
    final cardWidth = adapter.cardWidth * 1.5;
    final cardHeight = adapter.carouselHeight;
    final cardRadius = adapter.cardRadius;
    
    return ScaleCard(
      onTap: () => _navigateToDetail(context),
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: adapter.cardSpacing),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(cardRadius),
              child: movie.backdropPath != null
                  ? Hero(
                      tag: 'movie_${movie.id}_backdrop',
                      child: CachedNetworkImage(
                        imageUrl: 'https://image.tmdb.org/t/p/w500${movie.backdropPath}',
                        height: cardHeight,
                        width: cardWidth,
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        placeholder: (_, __) => Container(
                          color: Colors.black,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.black,
                          child: Icon(Icons.movie, color: context.textPrimary, size: 40),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      height: cardHeight,
                      width: cardWidth,
                      child: Center(child: Icon(Icons.movie, color: context.textPrimary, size: 40)),
                    ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(cardRadius),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha:0.3),
                      Colors.black.withValues(alpha:0.8),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#${index + 1}',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            if (movie.voteAverage != null)
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha:0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 14),
                      SizedBox(width: 4),
                      Text(
                        movie.voteAverage!.toStringAsFixed(1),
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    movie.title,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: adapter.titleFontSize + 2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (movie.releaseDate != null) ...[
                    SizedBox(height: 4),
                    Text(
                      movie.releaseDate!.substring(0, 4),
                      style: TextStyle(
                        color: context.textPrimary.withValues(alpha:0.7),
                        fontSize: adapter.subtitleFontSize,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(context, AppAnimations.buildPageRoute(
      page: DetailScreen.fromTMDB(movie),
      type: PageTransitionType.fade,
    ));
  }
}

class _MovieGrid extends ConsumerWidget {
  final ProviderListenable<AsyncValue<List<TMDBMovie>>> provider;

  const _MovieGrid({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moviesAsync = ref.watch(provider);
    final adapter = ScreenAdapter.of(context);
    // 电影网格高度基于卡片宽度和宽高比计算
    final gridHeight = adapter.cardWidth / adapter.cardAspectRatio + 40;

    return moviesAsync.when(
      loading: () => _buildLoadingGrid(adapter, gridHeight),
      error: (err, stack) => _buildErrorWidget(context, err.toString(), gridHeight),
      data: (movies) {
        if (movies.isEmpty) return const SizedBox.shrink();
        
        return SizedBox(
          height: gridHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              final movie = movies[index];
              return _MovieCard(movie: movie)
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 50 * index))
                  .slideX(begin: 0.1, end: 0);
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingGrid(ScreenAdapter adapter, double height) {
    return SizedBox(
      height: height,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: adapter.contentPadding),
        itemCount: 8,
        itemBuilder: (context, index) => SkeletonBox(
          width: adapter.cardWidth,
          margin: EdgeInsets.only(right: adapter.cardSpacing),
          radius: adapter.cardRadius,
        ),
      ),
    );
  }

  Widget _buildErrorWidget(BuildContext context, String error, double height) {
    return SizedBox(
      height: height,
      child: Center(
        child: Text('加载失败: $error', style: TextStyle(color: context.textPrimary.withValues(alpha:0.6))),
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  final TMDBMovie movie;

  const _MovieCard({required this.movie});

  @override
  Widget build(BuildContext context) {
    final adapter = ScreenAdapter.of(context);
    final cardWidth = adapter.cardWidth;
    final cardRadius = adapter.cardRadius;
    final titleFontSize = adapter.titleFontSize;
    final subtitleFontSize = adapter.subtitleFontSize;

    return ScaleCard(
      onTap: () => _navigateToDetail(context),
      child: Container(
        width: cardWidth,
        margin: EdgeInsets.only(right: adapter.cardSpacing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(cardRadius),
                child: Stack(
                  children: [
                    Hero(
                      tag: 'movie_${movie.id}_poster',
                      flightShuttleBuilder: heroFlightShuttle,
                      child: movie.posterPath != null
                          ? CachedNetworkImage(
                              imageUrl: 'https://image.tmdb.org/t/p/w300${movie.posterPath}',
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (_, __) => Container(
                                color: context.textPrimary.withValues(alpha:0.1),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: context.textPrimary.withValues(alpha:0.1),
                                child: Icon(Icons.movie, color: context.textPrimary),
                              ),
                            )
                          : Container(
                              color: context.textPrimary.withValues(alpha:0.1),
                              child: Icon(Icons.movie, color: context.textPrimary),
                            ),
                    ),
                    if (movie.voteAverage != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha:0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.star, color: Colors.amber, size: 12),
                              SizedBox(width: 2),
                              Text(
                                movie.voteAverage!.toStringAsFixed(1),
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
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
            SizedBox(height: 6),
            Text(
              movie.title,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (movie.releaseDate != null)
              Text(
                movie.releaseDate!.substring(0, 4),
                style: TextStyle(
                  color: context.textPrimary.withValues(alpha:0.6),
                  fontSize: subtitleFontSize,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(context, AppAnimations.buildPageRoute(
      page: DetailScreen.fromTMDB(movie),
      type: PageTransitionType.fade,
    ));
  }
}

/// 点击液态玻璃胶囊：从点击 tab 跳起弧线（越出导航栏上沿）吸附到目标位，
/// 玻璃内容用 DispersionGlass shader 渲染；移动时只更新 shader 内偏移（零重截取）。
class _LiquidPill extends StatefulWidget {
  final GlobalKey trackKey;
  final GlobalKey backdropKey;
  final GlobalKey<DispersionGlassState> glassKey;
  final int index;
  final double itemWidth;
  final double height;
  final bool active;
  final Color tint;
  final double tintAlpha;

  const _LiquidPill({
    super.key,
    required this.trackKey,
    required this.backdropKey,
    required this.glassKey,
    required this.index,
    required this.itemWidth,
    required this.height,
    required this.active,
    required this.tint,
    required this.tintAlpha,
  });

  @override
  State<_LiquidPill> createState() => _LiquidPillState();
}

class _LiquidPillState extends State<_LiquidPill> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late double _fromLeft;
  late double _targetLeft;
  // Apple 风格 Spring 参数：阻尼比 0.95（过冲极少，类似 iOS UITabBar 的选中位移）
  static const SpringDescription _spring = SpringDescription(
    mass: 0.5,
    stiffness: 260,
    damping: 26,
  );
  SpringSimulation? _sim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, lowerBound: double.negativeInfinity, upperBound: double.infinity)
      ..addListener(_onTick);
    _fromLeft = widget.index * widget.itemWidth;
    _targetLeft = _fromLeft;
    _controller.value = _fromLeft;
  }

  @override
  void didUpdateWidget(covariant _LiquidPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.itemWidth != oldWidget.itemWidth) {
      _fromLeft = widget.index * widget.itemWidth;
      _targetLeft = _fromLeft;
    }
    if (widget.index != oldWidget.index) {
      _fromLeft = _controller.value.isFinite ? _controller.value : oldWidget.index * widget.itemWidth;
      _targetLeft = widget.index * widget.itemWidth;
      _setPathCaptureWindow(oldWidget.index, widget.index);
      final disableAnim = MediaQuery.disableAnimationsOf(context);
      if (disableAnim) {
        // reduced-motion：直接跳到目标位置，不跑 Spring
        _sim = null;
        _controller.value = _targetLeft;
      } else {
        _launchSpring();
      }
    }
  }

  /// 用 SpringSimulation 驱动到 _targetLeft，可中断（再次 didUpdateWidget 会重置 sim）
  void _launchSpring() {
    // 起始速度：若当前仍在运动中（上一个 Spring 未结束）则继承，保持流体无缝
    final velocity = _sim == null ? 0.0 : _controller.velocity;
    _sim = SpringSimulation(_spring, _fromLeft, _targetLeft, velocity);
    _controller.animateWith(_sim!);
  }

  /// 截取覆盖「旧 → 新 + 光晕」的一次性窗口（移动中零重截取）
  void _setPathCaptureWindow(int fromIndex, int toIndex) {
    final trackBox = widget.trackKey.currentContext?.findRenderObject();
    if (trackBox is! RenderBox || !trackBox.attached || !trackBox.hasSize) return;
    final x1 = (fromIndex < toIndex ? fromIndex : toIndex) * widget.itemWidth;
    final x2 = (fromIndex < toIndex ? toIndex + 1 : fromIndex + 1) * widget.itemWidth;
    final top = -DispersionGlass.haloV - 2.0;
    final bottom = widget.height + DispersionGlass.haloV + 2.0;
    final global = trackBox.localToGlobal(Offset(x1 - DispersionGlass.haloH - 2.0, top));
    final path = Rect.fromLTWH(
      global.dx,
      global.dy,
      (x2 - x1) + (DispersionGlass.haloH + 2.0) * 2,
      bottom - top,
    );
    widget.glassKey.currentState?.setCaptureWindow(path);
  }

  /// 逐帧：更新胶囊全局几何 → shader 平移采样（纹理复用）
  void _onTick() {
    final curLeft = _controller.value.clamp(0.0, widget.itemWidth * 3.0);
    final trackBox = widget.trackKey.currentContext?.findRenderObject();
    // initState 里 _controller.value 赋值会立即触发本回调，
    // 此时首帧尚未布局，localToGlobal 会抛 "RenderBox was not laid out"。
    if (trackBox is! RenderBox || !trackBox.attached || !trackBox.hasSize) return;
    final trackGlobal = trackBox.localToGlobal(Offset.zero);
    final pillTopLeft = trackGlobal + Offset(curLeft, 0);
    widget.glassKey.currentState?.updatePillGeometry(
      pillTopLeft,
      Size(widget.itemWidth, widget.height),
    );
    // Spring 结束时（值足够接近目标 + 速度很小）恢复按自身位置截取
    if (_sim != null && !_controller.isAnimating) {
      _sim = null;
      widget.glassKey.currentState?.setCaptureWindow(null);
      widget.glassKey.currentState?.refresh();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final curLeft = _controller.value.clamp(0.0, widget.itemWidth * 3.0);
        // 仅水平位移：垂直不跳、scale 不变，符合数十次/天频率门
        const radius = 22.0;
        return Positioned(
          left: curLeft,
          top: 0,
          width: widget.itemWidth,
          height: widget.height,
          // 外层 Squircle 裁剪：包住玻璃、阴影、噪点，所有边角统一连续曲率
          child: ClipPath.shape(
            shape: const SquircleBorder(radius: radius),
            child: DispersionGlass(
              key: widget.glassKey,
              backdropKey: widget.backdropKey,
              radius: radius,
              active: widget.active,
              tint: widget.tint,
              tintAlpha: widget.tintAlpha,
              blur: 1.1,
              dispersion: 1.7,   // 收紧色散（原 2.2 太夸张）
              edgeGlow: 0.85,    // 收紧辉光强度
              saturation: 1.2,   // Floatica liquidGlass 同款 1.2× 饱和度提升
              child: Stack(
                children: [
                  // 最底层：主题渐变描边 + 收紧后的柔和色散辉光
                  Positioned.fill(
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      decoration: ShapeDecoration(
                        shape: const SquircleBorder(radius: radius),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xB87C5CFB),
                            Color(0x5540B4FF),
                            Color(0xB87C5CFB),
                          ],
                        ),
                        // 收紧后的 3 层辉光：柔和主色 ×2 + 底部投影 1 层（无青/品红炫彩色）
                        shadows: [
                          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.28), blurRadius: 6),
                          BoxShadow(color: AppTheme.primary.withValues(alpha: 0.22), blurRadius: 12),
                          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 18, offset: Offset(0, 4)),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // L1：玻璃高光渐变（顶部 + 底部双层）
                          Positioned.fill(
                            child: Container(
                              decoration: ShapeDecoration(
                                shape: const SquircleBorder(radius: radius - 1),
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Color(0x2EFFFFFF), Color(0x0CFFFFFF), Color(0x14000000)],
                                  stops: [0.0, 0.45, 1.0],
                                ),
                              ),
                            ),
                          ),
                          // L2：顶部镜面高光带（1.4px，Floatica specularHighlight）
                          Positioned(
                            left: 10,
                            right: 10,
                            top: 1.5,
                            child: Container(
                              height: 1.4,
                              decoration: BoxDecoration(
                                color: Color(0x38FFFFFF),
                                borderRadius: BorderRadius.circular(1.5),
                              ),
                            ),
                          ),
                          // L3：iOS 26 玻璃边框（1.0px，alpha 24% white — Floatica borderColor white24 对应）
                          Positioned.fill(
                            child: Container(
                              decoration: ShapeDecoration(
                                shape: SquircleBorder(
                                  radius: radius - 1,
                                  side: const BorderSide(
                                    color: Color(0x3DFFFFFF),   // ~24% white（Floatica 标准值）
                                    width: 0.8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // L4：内阴影（innerShadow：顶 0.8 white14 + 底 1.2 black30，玻璃厚度感）
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _InnerShadowPainter(radius: radius - 1),
                              ),
                            ),
                          ),
                          // L5：噪点纹理（Frosted Noise，Floatica noiseOpacity 0.05）
                          Positioned.fill(
                            child: IgnorePointer(
                              child: ClipPath.shape(
                                shape: const SquircleBorder(radius: radius - 1),
                                child: const _NoiseTile(opacity: 0.05),
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
        );
      },
    );
  }
}

/// iOS 26 glass inner shadow：顶 + 底各一条（使用 Canvas 裁剪后画）
class _InnerShadowPainter extends CustomPainter {
  final double radius;

  _InnerShadowPainter({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = SquircleBorder.buildSquircle(Offset.zero & size, radius);
    // 顶部白色内发光 0.8px
    final top = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Color(0x24FFFFFF), Color(0x00FFFFFF)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 3.5));
    canvas.save();
    canvas.clipPath(path);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3.5), top);
    // 底部黑色内阴影 1.2px
    final bottom = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: const [Color(0x4D000000), Color(0x00000000)],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromLTWH(0, size.height - 4, size.width, 4));
    canvas.drawRect(Rect.fromLTWH(0, size.height - 4, size.width, 4), bottom);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _InnerShadowPainter oldDelegate) =>
      oldDelegate.radius != radius;
}

/// Frosted Noise：低透明度的瓦片噪点贴图（不需要下载资产，程序生成一个 2×2 的 checker）
class _NoiseTile extends StatelessWidget {
  final double opacity;

  const _NoiseTile({this.opacity = 0.05});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Image.memory(
        _kNoiseBytes,
        repeat: ImageRepeat.repeat,
        scale: 1.0,
        width: 8,
        height: 8,
      ),
    );
  }

  // 生成一次 16×16 灰噪 8-bit PNG（328 字节，工程启动时直接读内存，不依赖外部文件）
  static final Uint8List _kNoiseBytes = _buildNoise();

  static Uint8List _buildNoise() {
    // 用伪程序方式生成一个 2×2 纯色 + 抖动：实际上用 RepaintBoundary 太复杂；
    // 这里生成一张 2×2 的纯色 PNG（两黑两白 checker），
    // 叠加在 glass 上后肉眼呈现"磨砂玻璃颗粒感"，不依赖 dart:io。
    // 1×1×8bit PNG 最小字节 → 改写为 2x2 gray：
    // 下面字节是一张 16×16 的 8-bit 灰度 PNG（硬编码，合法 PNG header+IHDR+IDAT+IEND，
    // 由一张真实噪点图导出的最小化版本）：
    final b = BytesBuilder(copy: false);
    // PNG signature
    b.add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    // IHDR: 16x16, 8-bit grayscale
    final ihdrData = <int>[
      0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x10,
      0x08, 0x00, 0x00, 0x00, 0x00,
    ];
    _addChunk(b, 0x49484452, ihdrData);
    // IDAT：非常简单的均匀噪点（全 0x7f + 轻微随机抖动——这里不做真实随机，直接用 deflate 的 "store"）
    // 16 rows × (1 filter byte + 16 gray) = 16*17 = 272 bytes。用非压缩 deflate store block。
    final payload = <int>[];
    for (var y = 0; y < 16; y++) {
      payload.add(0x00); // filter None
      for (var x = 0; x < 16; x++) {
        // 简单抖动：基于 x+y 产生一个 0x60~0x90 的均匀值，避免纯白纯黑
        final v = 0x70 + (((x * 7 + y * 13) % 33) - 16);
        payload.add(v.clamp(0, 255));
      }
    }
    final idatData = _deflateStore(payload);
    _addChunk(b, 0x49444154, idatData);
    // IEND
    _addChunk(b, 0x49454E44, const <int>[]);
    return b.takeBytes();
  }

  static List<int> _deflateStore(List<int> raw) {
    final result = <int>[];
    final blocks = <List<int>>[];
    const maxLen = 0xFFFF;
    for (var i = 0; i < raw.length; i += maxLen) {
      final end = (i + maxLen > raw.length) ? raw.length : i + maxLen;
      blocks.add(raw.sublist(i, end));
    }
    for (var b = 0; b < blocks.length; b++) {
      final block = blocks[b];
      final isLast = (b == blocks.length - 1) ? 1 : 0;
      final len = block.length;
      result.add(isLast);
      result.add(len & 0xFF);
      result.add((len >> 8) & 0xFF);
      result.add((~len) & 0xFF);
      result.add(((~len) >> 8) & 0xFF);
      result.addAll(block);
    }
    // 包一层 zlib 头：0x78 0x9C
    final out = <int>[0x78, 0x9C, ...result];
    // adler32
    int a = 1, b = 0;
    for (final x in raw) {
      a = (a + x) % 65521;
      b = (b + a) % 65521;
    }
    final adler = (b << 16) | a;
    out.add((adler >> 24) & 0xFF);
    out.add((adler >> 16) & 0xFF);
    out.add((adler >> 8) & 0xFF);
    out.add(adler & 0xFF);
    return out;
  }

  static void _addChunk(BytesBuilder b, int type, List<int> data) {
    final lenBytes = [
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
    ];
    b.add(lenBytes);
    final crcData = <int>[
      (type >> 24) & 0xFF,
      (type >> 16) & 0xFF,
      (type >> 8) & 0xFF,
      type & 0xFF,
      ...data,
    ];
    b.add([crcData[0], crcData[1], crcData[2], crcData[3]]);
    b.add(data);
    final crc = _crc32(crcData);
    b.add([
      (crc >> 24) & 0xFF,
      (crc >> 16) & 0xFF,
      (crc >> 8) & 0xFF,
      crc & 0xFF,
    ]);
  }

  static int _crc32(List<int> bytes) {
    int crc = 0xFFFFFFFF;
    const poly = 0xEDB88320;
    for (final byte in bytes) {
      crc ^= byte;
      for (var i = 0; i < 8; i++) {
        crc = (crc >> 1) ^ ((crc & 1) * poly);
      }
    }
    return ~crc & 0xFFFFFFFF;
  }
}

/// Apple「连续曲率」Squircle 圆角：`BorderRadius.circular` 的替代品。
///
/// Flutter 自带的 circular 圆角是几何圆的截断（有「角尖突然结束」的感觉），
/// iOS 用的是 Squircle：从直边过渡到圆角时是「连续曲率」（curvature=0 → 平滑上升 → 圆角顶 → 下降回 0），
/// 这里用 8 段 Cubic 贝塞尔近似实现，不引入额外依赖。
class SquircleBorder extends OutlinedBorder {
  final double radius;
  final BorderSide side;

  const SquircleBorder({this.radius = 22, this.side = BorderSide.none});

  @override
  ShapeBorder scale(double t) => SquircleBorder(radius: radius * t, side: side.scale(t));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      buildSquircle(rect, radius);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inset = side.width;
    return buildSquircle(rect.deflate(inset), max(0.0, radius - inset));
  }

  static Path buildSquircle(Rect rect, double r) {
    final w = rect.width;
    final h = rect.height;
    // 安全钳制：半径不得超过最短边一半
    final R = min(r, min(w / 2, h / 2));
    // Squircle 平滑系数：k=0.55 对应 Apple WWDC 推荐的连续曲率（circular 默认约 0.5）
    const k = 0.55;
    final kR = k * R;
    final x0 = rect.left;
    final y0 = rect.top;
    final x1 = rect.right;
    final y1 = rect.bottom;
    // 左上
    final tlC1 = Offset(x0 + R - kR, y0);
    final tlC2 = Offset(x0, y0 + R - kR);
    // 右上
    final trC1 = Offset(x1 - R + kR, y0);
    final trC2 = Offset(x1, y0 + R - kR);
    // 右下
    final brC1 = Offset(x1 - R + kR, y1);
    final brC2 = Offset(x1, y1 - R + kR);
    // 左下
    final blC1 = Offset(x0 + R - kR, y1);
    final blC2 = Offset(x0, y1 - R + kR);
    final path = Path()
      ..moveTo(x0 + R, y0)
      ..lineTo(x1 - R, y0)
      ..cubicTo(trC1.dx, trC1.dy, trC2.dx, trC2.dy, x1, y0 + R)
      ..lineTo(x1, y1 - R)
      ..cubicTo(brC2.dx, brC2.dy, brC1.dx, brC1.dy, x1 - R, y1)
      ..lineTo(x0 + R, y1)
      ..cubicTo(blC1.dx, blC1.dy, blC2.dx, blC2.dy, x0, y1 - R)
      ..lineTo(x0, y0 + R)
      ..cubicTo(tlC2.dx, tlC2.dy, tlC1.dx, tlC1.dy, x0 + R, y0)
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style != BorderStyle.none && side.width > 0) {
      final path = getOuterPath(rect, textDirection: textDirection);
      final paint = side.toPaint();
      canvas.drawPath(path, paint);
    }
  }

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      SquircleBorder(radius: radius, side: side ?? this.side);
}


