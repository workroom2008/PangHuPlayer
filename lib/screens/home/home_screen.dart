import 'package:flutter/services.dart';
import 'dart:async';
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
import '../../utils/screen_adapter.dart';
import '../../utils/animation_config.dart';
import '../../widgets/animated_card.dart';
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
import '../media_library/media_library_items_screen.dart';
export '../media_library/media_library_items_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late PageController _pageController;
  bool _isNavVisible = true;
  bool _suppressPageChange = false; // 抑制 animateToPage 期间的 onPageChanged
  // 导航栏显示/隐藏动画（单 controller，slide+opacity 严格同步）
  late final AnimationController _navAnim;

  /// Apple 强 ease-out：UI 过渡默认曲线（Cubic(0.23, 1, 0.32, 1)）
  static const Curve _easeOut = Cubic(0.23, 1.0, 0.32, 1.0);
  static const Duration _navShowDur = Duration(milliseconds: 200);
  static const Duration _navHideDur = Duration(milliseconds: 160);

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _navAnim =
        AnimationController(vsync: this, value: 1.0, duration: _navShowDur);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _navAnim.dispose();
    super.dispose();
  }

  /// 滚动感知显隐：下滑隐藏、上滑唤出、回顶强制显示（Safari 式）。
  /// 监听 PageView 内各页列表的纵向滚动（depth>=1）；PageView 自身的横向翻页
  /// 由 axis != vertical 排除（它的 depth 是 0）。
  bool _handleScrollNotification(ScrollNotification n) {
    if (n is! ScrollUpdateNotification) return false;
    if (n.metrics.axis != Axis.vertical) return false;
    final delta = n.scrollDelta ?? 0.0;
    final pixels = n.metrics.pixels;
    if (delta > 4 && pixels > 80) {
      _setNavVisible(false);
    } else if (delta < -4) {
      _setNavVisible(true);
    } else if (pixels < 8) {
      _setNavVisible(true);
    }
    return false;
  }

  void _setNavVisible(bool visible) {
    if (visible == _isNavVisible) return;
    _isNavVisible = visible;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (disableAnim) {
      // reduced-motion：直接跳到目标，不做动画
      _navAnim.value = visible ? 1.0 : 0.0;
    } else {
      _navAnim.animateTo(
        visible ? 1.0 : 0.0,
        duration: visible ? _navShowDur : _navHideDur,
        curve: _easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _currentIndex != 0) {
          // 不是最首页时，后退回到媒体tab
          _navigateTo(0);
        }
      },
      child: Scaffold(
        body: GestureDetector(
      onTap: () {
        // 内容被点按时唤出导航栏（滚动感知的主通道是 ScrollNotification）
        if (!_isNavVisible) _setNavVisible(true);
      },
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: RepaintBoundary(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  // 抑制 animateToPage 期间的中间页回调，避免胶囊跳动
                  if (_suppressPageChange) return;
                  // 手势滑页时同步导航栏
                  if (_currentIndex != index) {
                    setState(() => _currentIndex = index);
                  }
                },
                children: [
                  LibraryPage(onGoToResources: () => _navigateTo(2)),
                  const DiscoverPage(),
                  const ResourcesPage(),
                  const SettingsScreen(),
                ],
              ),
            ),
          ),
          // 导航栏浮在内容上�?�?BackdropFilter 可模糊到轮播背景
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomNav(),
          ),
        ],
      ),
    ),
    ),
  );
  }

  Widget _buildBottomNav() {
    // 滚动显隐由 _navAnim 驱动（slide + opacity 严格同步），
    // 玻璃条/胶囊/条目的弹簧物理由 _NavBar 自管。
    return AnimatedBuilder(
      animation: _navAnim,
      builder: (context, child) {
        final t = _navAnim.value;
        return IgnorePointer(
          ignoring: t < 0.05,
          child: Opacity(
            opacity: t,
            child: FractionalTranslation(
              translation: Offset(0, (1.0 - t) * 1.2),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        // 悬浮：底部安全区 + 16
        padding: EdgeInsets.fromLTRB(
            16, 0, 16, MediaQuery.paddingOf(context).bottom + 16),
        child: _NavBar(
          currentIndex: _currentIndex,
          disableAnim: MediaQuery.disableAnimationsOf(context),
          onSelect: _navigateTo,
        ),
      ),
    );
  }

  void _navigateTo(int index) {
    if (index == _currentIndex) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() => _currentIndex = index);
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    if (disableAnim) {
      _pageController.jumpToPage(index);
    } else {
      // 抑制 animateToPage 过程中的 onPageChanged 回调
      _suppressPageChange = true;
      _pageController
          .animateToPage(index,
              duration: AppAnimations.medium, curve: AppAnimations.easeInOut)
          .whenComplete(() => _suppressPageChange = false);
    }
  }
}

/// 导航栏响应式尺寸（Streama/Miuix 同款断点：600dp / 840dp）。
/// 紧凑：56 胶囊/64 条；中等：60/68；展开：64/72，图标同步放大。
({double barH, double pillH, double tabW, double iconS, double labelS})
    _navSizes(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 840) return (barH: 72, pillH: 64, tabW: 96, iconS: 28, labelS: 13);
  if (w >= 600) return (barH: 68, pillH: 60, tabW: 88, iconS: 26, labelS: 12);
  return (barH: 64, pillH: 56, tabW: 80, iconS: 24, labelS: 11);
}

/// 液态玻璃导航栏：内容宽度居中悬浮条 + 弹簧滑动胶囊 + 按压缩放/拖拽磁吸。
///
/// 手势（点按/横向拖动）由本组件自行消费；滚动显隐由外层 _HomeScreenState
/// 通过 _navAnim 驱动，本组件不感知滚动。
class _NavBar extends StatefulWidget {
  final int currentIndex;
  final bool disableAnim;
  final ValueChanged<int> onSelect;

  const _NavBar({
    required this.currentIndex,
    required this.disableAnim,
    required this.onSelect,
  });

  @override
  State<_NavBar> createState() => _NavBarState();
}

class _NavBarState extends State<_NavBar> with TickerProviderStateMixin {
  /// Miuix LiquidGlass 示例的按压缩放（pressedScale = 78/56 ≈ 1.39）
  static const double _pressScale = 1.39;

  /// 点击脉冲：放大 160ms → easeOutBack 缩回 260ms，一次完整的放大缩小
  static const Duration _pulseIn = Duration(milliseconds: 160);
  static const Duration _pulseOut = Duration(milliseconds: 260);

  late final AnimationController _posCtrl; // 胶囊左偏移（0..(n-1)*tabW）
  late final AnimationController _scaleCtrl; // 0..1 按压缩放进度
  double _tabW = 0;
  int? _pressedIndex;
  double _stretchX = 1, _stretchY = 1; // 拖拽速度拉伸

  @override
  void initState() {
    super.initState();
    _posCtrl = AnimationController(
      vsync: this,
      lowerBound: double.negativeInfinity,
      upperBound: double.infinity,
    );
    _scaleCtrl = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _posCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _NavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex && _tabW > 0) {
      // 用户要求：点哪个胶囊就直接到位，不滑动经过中间项
      _posCtrl.stop();
      _posCtrl.value = widget.currentIndex * _tabW;
    }
  }



  /// 尺寸随断点变化时直接归位，不播放滑动
  void _syncSize(double tabW) {
    if (_tabW == tabW) return;
    _tabW = tabW;
    _posCtrl.value = widget.currentIndex * tabW;
  }

  int _indexAt(double localX) => (((localX - 4) / _tabW).floor()).clamp(0, 3);

  /// 点击脉冲：按下播放一次 0→1 放大（160ms），播完自动 1→0 缩小（260ms easeOutBack）。
  /// 动画与手指状态解耦——即使手指停在屏幕上，脉冲也会完整播放一次。
  void _pressStart(double localX) {
    final idx = _indexAt(localX);
    setState(() => _pressedIndex = idx);
    if (widget.disableAnim) {
      _scaleCtrl.value = 0.0;
      _pressedIndex = null;
    } else {
      // 中断上一轮未播完的脉冲（其 whenComplete 不会再动新动画）
      _scaleCtrl.stop();
      final pulse = _scaleCtrl.animateTo(1.0,
          duration: _pulseIn, curve: AppAnimations.easeOut);
      unawaited(pulse.whenComplete(() {
        if (mounted) {
          _scaleCtrl.animateTo(0.0,
              duration: _pulseOut, curve: Curves.easeOutBack);
        }
      }));
    }
    // 胶囊移动只由 didUpdateWidget（currentIndex 变化）驱动。
  }

  void _pressEnd() {
    // 只复位触控状态；缩放脉冲由 _scaleCtrl 自动播完（放大→缩小），不在此打断
    setState(() {
      _pressedIndex = null;
      _stretchX = 1;
      _stretchY = 1;
    });
  }

  void _dragUpdate(double deltaX) {
    _posCtrl.stop();
    final maxX = _tabW * 3;
    _posCtrl.value = (_posCtrl.value + deltaX).clamp(0.0, maxX);
    // 速度拉伸：按拖拽增量近似速度（scaleX = 1/(1-v)，纵向反向压缩）
    final s = (deltaX * 0.03).clamp(-0.18, 0.18);
    setState(() {
      _stretchX = 1 / (1 - s);
      _stretchY = 1 - s.abs() * 0.4;
    });
  }

  void _dragEnd() {
    _pressEnd();
    final idx = ((_posCtrl.value / _tabW).round()).clamp(0, 3);
    if (idx != widget.currentIndex) widget.onSelect(idx);
    // 拖拽结束 snap 到最近 tab，用 easeOut 过渡
    final target = idx * _tabW;
    _posCtrl.stop();
    _posCtrl.animateTo(target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final sizes = _navSizes(context);
    final tabW = sizes.tabW;
    _syncSize(tabW);
    final barW = tabW * 4 + 8;
    final pillH = sizes.pillH;
    final radius = pillH / 2;
    final isDark = context.isDark;

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _pressStart(d.localPosition.dx),
        onTapUp: (d) {
          _pressEnd();
          final idx = _indexAt(d.localPosition.dx);
          if (idx != widget.currentIndex) widget.onSelect(idx);
        },
        onTapCancel: _pressEnd,
        onHorizontalDragStart: (d) => _pressStart(d.localPosition.dx),
        onHorizontalDragUpdate: (d) => _dragUpdate(d.delta.dx),
        onHorizontalDragEnd: (_) => _dragEnd(),
        onHorizontalDragCancel: _pressEnd,
        child: SizedBox(
          width: barW,
          height: sizes.barH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              _buildBar(radius, isDark),
              _buildPill(tabW, pillH, radius, isDark),
              _buildTabs(sizes, tabW, pillH),
            ],
          ),
        ),
      ),
    );
  }

  /// 悬浮磨砂条：BackdropFilter 模糊 + 表面色 + 细边框 + 投影
  Widget _buildBar(double radius, bool isDark) {
    return Positioned.fill(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0x8C141414) : const Color(0x8CFFFFFF),
              border: Border.all(
                color:
                    isDark ? const Color(0x26FFFFFF) : const Color(0x1F000000),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 滑动玻璃胶囊：弹簧位置 + 按压缩放 + 速度拉伸
  Widget _buildPill(double tabW, double pillH, double radius, bool isDark) {
    return AnimatedBuilder(
      animation: Listenable.merge([_posCtrl, _scaleCtrl]),
      builder: (context, _) {
        final press = 1.0 + (_pressScale - 1.0) * _scaleCtrl.value;
        final sx = press * _stretchX;
        final sy = press * _stretchY;
        return Positioned(
          left: 0,
          top: 4,
          width: tabW,
          height: pillH,
          child: Transform.translate(
            offset: Offset(_posCtrl.value, 0),
            child: Transform.scale(
              scaleX: sx,
              scaleY: sy,
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? const [Color(0x55FFFFFF), Color(0x22FFFFFF)]
                          : const [Color(0xD9FFFFFF), Color(0x8CFFFFFF)],
                    ),
                    border: Border.all(
                      color: isDark
                          ? const Color(0x80FFFFFF)
                          : const Color(0xE6FFFFFF),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                      // 顶部内高光（液态玻璃 specular 带）
                      const BoxShadow(
                        color: Color(0x33FFFFFF),
                        blurRadius: 1,
                        offset: Offset(0, -1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTabs(
      ({
        double barH,
        double pillH,
        double tabW,
        double iconS,
        double labelS
      }) sizes,
      double tabW,
      double pillH) {
    return Row(
      children: [
        _NavPill(
          icon: Icons.home_rounded,
          label: '媒体',
          selected: widget.currentIndex == 0,
          pressed: _pressedIndex == 0,
          width: tabW,
          height: pillH,
          iconSize: sizes.iconS,
          labelSize: sizes.labelS,
        ),
        _NavPill(
          icon: Icons.explore_rounded,
          label: '发现',
          selected: widget.currentIndex == 1,
          pressed: _pressedIndex == 1,
          width: tabW,
          height: pillH,
          iconSize: sizes.iconS,
          labelSize: sizes.labelS,
        ),
        _NavPill(
          icon: Icons.dns_rounded,
          label: '资源',
          selected: widget.currentIndex == 2,
          pressed: _pressedIndex == 2,
          width: tabW,
          height: pillH,
          iconSize: sizes.iconS,
          labelSize: sizes.labelS,
        ),
        _NavPill(
          icon: Icons.settings_rounded,
          label: '设置',
          selected: widget.currentIndex == 3,
          pressed: _pressedIndex == 3,
          width: tabW,
          height: pillH,
          iconSize: sizes.iconS,
          labelSize: sizes.labelS,
        ),
      ],
    );
  }
}

/// 单个导航条目：选中态颜色/字重插值 + 按压缩放（图标 1.2 / 文字 1.08）。
/// 手势由外层 _NavBar 统一消费，本组件纯展示。
class _NavPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool pressed;
  final double width;
  final double height;
  final double iconSize;
  final double labelSize;

  const _NavPill({
    required this.icon,
    required this.label,
    required this.selected,
    required this.pressed,
    required this.width,
    required this.height,
    required this.iconSize,
    required this.labelSize,
  });

  @override
  Widget build(BuildContext context) {
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final dur = disableAnim ? Duration.zero : AppAnimations.navPill;
    final pressDur =
        disableAnim ? Duration.zero : const Duration(milliseconds: 140);
    const selectedColor = AppTheme.primary;
    final unselectedColor = context.textPrimary.withValues(alpha: 0.6);

    return SizedBox(
      width: width,
      height: height,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: pressed ? 1.2 : 1.0,
            duration: pressDur,
            curve: AppAnimations.easeOut,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: selected ? 1.0 : 0.0),
              duration: dur,
              curve: AppAnimations.easeOut,
              builder: (context, t, _) => Icon(
                icon,
                size: iconSize,
                color: Color.lerp(unselectedColor, selectedColor, t),
              ),
            ),
          ),
          AnimatedScale(
            scale: pressed ? 1.08 : 1.0,
            duration: pressDur,
            curve: AppAnimations.easeOut,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: selected ? 1.0 : 0.0),
              duration: dur,
              curve: AppAnimations.easeOut,
              builder: (context, t, _) => Text(
                label,
                style: TextStyle(
                  fontSize: labelSize,
                  color: Color.lerp(unselectedColor, selectedColor, t),
                  fontWeight:
                      FontWeight.lerp(FontWeight.w500, FontWeight.w700, t),
                ),
              ),
            ),
          ),
        ],
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

class _LibraryPageState extends ConsumerState<LibraryPage>
    with AutomaticKeepAliveClientMixin {
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
    final defaultServer =
        servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
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
              padding: EdgeInsets.fromLTRB(
                  16, MediaQuery.paddingOf(context).top + 8, 16, 16),
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
                  const ServerSelectorChip(compact: true),
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
                      child: Icon(Icons.search,
                          color: context.textPrimary, size: 22),
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
    // 竖屏用较小比例，横屏用较大比例，避免竖屏时轮播占满屏幕
    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final carouselRatio = isPortrait ? 0.42 : 0.65;
    final carouselH = size.height * carouselRatio;
    if (items.isEmpty) {
      return SizedBox(
          height: carouselH, child: Container(color: context.bgColor));
    }
    return SizedBox(
      height: carouselH,
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
    final server =
        ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull;
    context.push('/detail/${item.id}', extra: {'item': item, 'server': server});
  }
}

class _MediaLibraryContent extends ConsumerStatefulWidget {
  const _MediaLibraryContent();

  @override
  ConsumerState<_MediaLibraryContent> createState() =>
      _MediaLibraryContentState();
}

class _MediaLibraryContentState extends ConsumerState<_MediaLibraryContent>
    with AutomaticKeepAliveClientMixin {
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
    final defaultServer =
        servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
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
      final server =
          servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;
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
        if (!snapshot.hasData || snapshot.data!.isEmpty)
          return const SizedBox.shrink();
        final items = snapshot.data!;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 8),
              Row(
                children: [
                  Text('继续观看',
                      style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _refreshResumeItems,
                    child: Icon(Icons.refresh_rounded,
                        color: context.textSecondary, size: 18),
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
                    )
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 50 * index))
                        .slideX(begin: 0.1, end: 0);
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
    final server =
        ref.read(mediaServersProvider).where((s) => s.isDefault).firstOrNull;
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
      height: _categoryItemsHeight(context, hasYear: true),
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
              onPressed: () =>
                  ref.read(mediaLibraryProvider.notifier).refresh(),
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

  Widget _buildCategories(
      List<MediaItem> libraries, Map<String, List<MediaItem>> libraryItems) {
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
              onTap: () =>
                  setState(() => _categoriesExpanded = !_categoriesExpanded),
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
                      _categoriesExpanded
                          ? '收起'
                          : '展开全部 ${libraries.length} 个媒体库',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _categoriesExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
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

  Widget _buildCategorySection(
      MediaItem library, List<MediaItem> items, int index) {
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
              color: AppTheme.primary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ServerImage(
                imageUrl: library.posterUrl,
                headers: headers,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    Icon(Icons.video_library, color: context.textPrimary),
              ),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(library.title,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary)),
              Text('查看全部',
                  style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ]),
          ),
          Icon(Icons.chevron_right_rounded, color: context.textSecondary),
        ],
      ),
    );
  }

  Widget _buildCategoryItems(
      List<MediaItem> items, MediaItem library, int categoryIndex) {
    return SizedBox(
      // 大屏海报高度较大，标题和年份需要额外的纵向空间。
      height: _categoryItemsHeight(
        context,
        hasYear: items.any((item) => item.year != null),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return _MediaItemCard(
            item: item,
            onTap: () => _openItemDetail(item),
          )
              .animate(target: _hasAnimated ? 1.0 : null)
              .fadeIn(delay: Duration(milliseconds: 30 * index));
        },
      ),
    );
  }

  double _categoryItemsHeight(
    BuildContext context, {
    required bool hasYear,
  }) {
    final adapter = ScreenAdapter.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final cardHeight = adapter.cardWidth / adapter.cardAspectRatio;
    final titleLineHeight = textScaler.scale(12) * 1.2;
    final subtitleLineHeight =
        textScaler.scale(adapter.subtitleFontSize) * 1.2;
    final requiredHeight = cardHeight +
        6 +
        titleLineHeight * 2 +
        (hasYear ? subtitleLineHeight : 0) +
        4;

    // 保留手机端原有高度，大屏端按卡片和文字实际高度扩展。
    return requiredHeight > 220 ? requiredHeight : 220;
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

    // 竖屏时卡片宽度自适应屏幕（占65%），横屏保持250
    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final cardW = isPortrait
        ? (MediaQuery.sizeOf(context).width * 0.65).clamp(180.0, 250.0)
        : 250.0;
    final cardH = cardW * 9 / 16; // 16:9 比例

    return ScaleCard(
      onTap: onTap,
      child: Container(
        width: cardW,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 横版缩略图 (16:9)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: cardW,
                height: cardH,
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
                              color:
                                  context.textPrimary.withValues(alpha: 0.05),
                              child: Icon(Icons.movie,
                                  color: context.textPrimary
                                      .withValues(alpha: 0.3),
                                  size: 36),
                            ),
                          )
                        : Container(
                            color: context.textPrimary.withValues(alpha: 0.05),
                            child: Icon(Icons.movie,
                                color:
                                    context.textPrimary.withValues(alpha: 0.3),
                                size: 36),
                          ),
                    // 底部渐变遮罩（让进度条和剩余时间更清晰）
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.7)
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 集数标签（左上角）
                    if (item.type == MediaType.episode &&
                        item.seasonNumber != null &&
                        item.episodeNumber != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'S${item.seasonNumber}·E${item.episodeNumber}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    // 剩余时间标签（右下角）
                    if (remainingMin > 0)
                      Positioned(
                        right: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '剩余 ${_formatDuration(remainingMin)}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    // 进度条（底部）
                    if (progress > 0)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.2),
                            valueColor:
                                AlwaysStoppedAnimation<Color>(AppTheme.primary),
                          ),
                        ),
                      ),
                    // 播放图标居中
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 24),
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
                      style:
                          TextStyle(color: context.textSecondary, fontSize: 11),
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
                    memCacheWidth:
                        (cardWidth * MediaQuery.of(context).devicePixelRatio)
                            .round(),
                    placeholder: (_, __) => Container(
                      color: context.textPrimary.withValues(alpha: 0.1),
                      child: Center(
                          child: Icon(Icons.movie, color: context.textPrimary)),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: context.textPrimary.withValues(alpha: 0.1),
                      child: Center(
                          child: Icon(Icons.movie, color: context.textPrimary)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 6),
            Text(item.title,
                style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.2),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            if (item.year != null)
              Text(item.year.toString(),
                  style: TextStyle(
                      color: context.textPrimary.withValues(alpha: 0.6),
                      fontSize: subtitleFontSize,
                      height: 1.2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
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

class _DiscoverPageState extends ConsumerState<DiscoverPage>
    with AutomaticKeepAliveClientMixin {
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  color: isActive
                      ? context.textPrimary
                      : context.textPrimary.withValues(alpha: 0.7),
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
        const _SectionHeader(
            title: '正在热映', icon: Icons.local_fire_department_rounded),
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
        const _SectionHeader(
            title: '正在热映', icon: Icons.local_fire_department_rounded),
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
        child: Text('加载失败: $error',
            style:
                TextStyle(color: context.textPrimary.withValues(alpha: 0.6))),
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
                        imageUrl:
                            'https://image.tmdb.org/t/p/w500$backdropPath',
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
                          child: Icon(Icons.tv,
                              color: context.textPrimary, size: 40),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      height: cardHeight,
                      width: cardWidth,
                      child: Center(
                          child: Icon(Icons.tv,
                              color: context.textPrimary, size: 40)),
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
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
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
                        color: context.textPrimary.withValues(alpha: 0.7),
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
    Navigator.push(
        context,
        AppAnimations.buildPageRoute(
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
      error: (err, stack) =>
          _buildErrorWidget(context, err.toString(), gridHeight),
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
        child: Text('加载失败: $error',
            style:
                TextStyle(color: context.textPrimary.withValues(alpha: 0.6))),
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
                              imageUrl:
                                  'https://image.tmdb.org/t/p/w300$posterPath',
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (_, __) => Container(
                                color:
                                    context.textPrimary.withValues(alpha: 0.1),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color:
                                    context.textPrimary.withValues(alpha: 0.1),
                                child:
                                    Icon(Icons.tv, color: context.textPrimary),
                              ),
                            )
                          : Container(
                              color: context.textPrimary.withValues(alpha: 0.1),
                              child: Icon(Icons.tv, color: context.textPrimary),
                            ),
                    ),
                    if (voteAverage != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(99, 102, 241, 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '剧集',
                          style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
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
                  color: context.textPrimary.withValues(alpha: 0.6),
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
    Navigator.push(
        context,
        AppAnimations.buildPageRoute(
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
        child: Text('加载失败: $error',
            style:
                TextStyle(color: context.textPrimary.withValues(alpha: 0.6))),
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
                        imageUrl:
                            'https://image.tmdb.org/t/p/w500${movie.backdropPath}',
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
                          child: Icon(Icons.movie,
                              color: context.textPrimary, size: 40),
                        ),
                      ),
                    )
                  : Container(
                      color: Colors.black,
                      height: cardHeight,
                      width: cardWidth,
                      child: Center(
                          child: Icon(Icons.movie,
                              color: context.textPrimary, size: 40)),
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
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.8),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
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
                        color: context.textPrimary.withValues(alpha: 0.7),
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
    Navigator.push(
        context,
        AppAnimations.buildPageRoute(
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
      error: (err, stack) =>
          _buildErrorWidget(context, err.toString(), gridHeight),
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
        child: Text('加载失败: $error',
            style:
                TextStyle(color: context.textPrimary.withValues(alpha: 0.6))),
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
                              imageUrl:
                                  'https://image.tmdb.org/t/p/w300${movie.posterPath}',
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              width: double.infinity,
                              height: double.infinity,
                              placeholder: (_, __) => Container(
                                color:
                                    context.textPrimary.withValues(alpha: 0.1),
                                child: Center(
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color:
                                    context.textPrimary.withValues(alpha: 0.1),
                                child: Icon(Icons.movie,
                                    color: context.textPrimary),
                              ),
                            )
                          : Container(
                              color: context.textPrimary.withValues(alpha: 0.1),
                              child:
                                  Icon(Icons.movie, color: context.textPrimary),
                            ),
                    ),
                    if (movie.voteAverage != null)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
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
                  color: context.textPrimary.withValues(alpha: 0.6),
                  fontSize: subtitleFontSize,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    Navigator.push(
        context,
        AppAnimations.buildPageRoute(
          page: DetailScreen.fromTMDB(movie),
          type: PageTransitionType.fade,
        ));
  }
}
