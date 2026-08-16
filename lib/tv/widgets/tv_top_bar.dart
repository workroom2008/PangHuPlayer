import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../providers/app_providers.dart';
import '../../../models/media_models.dart';
import '../../../utils/animation_config.dart';

class _NavTab {
  final String label;
  final IconData? icon;
  const _NavTab(this.label, [this.icon]);
}

class TvTopBar extends ConsumerStatefulWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback? onSearch;
  final double scrollOffset;
  final FocusNode? selectedTabFocusNode;

  const TvTopBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.onSearch,
    this.scrollOffset = 0,
    this.selectedTabFocusNode,
  });

  @override
  ConsumerState<TvTopBar> createState() => _TvTopBarState();
}

class _TvTopBarState extends ConsumerState<TvTopBar>
    with TickerProviderStateMixin {
  static const List<_NavTab> _tabs = [
    _NavTab('首页', Icons.home_rounded),
    _NavTab('电影', Icons.movie_rounded),
    _NavTab('剧集', Icons.tv_rounded),
    _NavTab('我的片单', Icons.bookmark_rounded),
  ];

  late List<FocusNode> _focusNodes;
  late FocusNode _searchFocusNode;
  late FocusNode _settingsFocusNode;
  late FocusNode _serverFocusNode;

  // ── Apple-style sliding indicator ──
  final GlobalKey _navTabsKey = GlobalKey();
  late List<GlobalKey> _tabKeys;
  late AnimationController _indicatorController;
  double _indicatorLeft = 0;
  double _indicatorWidth = 0;
  double _fromLeft = 0;
  double _fromWidth = 0;
  double _targetLeft = 0;
  double _targetWidth = 0;
  bool _indicatorReady = false;

  @override
  void initState() {
    super.initState();
    _focusNodes = List.generate(_tabs.length, (_) => FocusNode());
    _searchFocusNode = FocusNode();
    _settingsFocusNode = FocusNode();
    _serverFocusNode = FocusNode();
    _serverFocusNode.addListener(() { if (mounted) setState(() {}); });
    _tabKeys = List.generate(_tabs.length, (_) => GlobalKey());
    _indicatorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..addListener(_onIndicatorTick);
  }

  @override
  void dispose() {
    _indicatorController.removeListener(_onIndicatorTick);
    _indicatorController.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _searchFocusNode.dispose();
    _settingsFocusNode.dispose();
    _serverFocusNode.dispose();
    super.dispose();
  }

  /// 每帧插值指示器位置（从 _from → _target，easeOutQuint 曲线）
  void _onIndicatorTick() {
    if (!mounted) return;
    final t = Curves.easeOutQuint.transform(_indicatorController.value);
    setState(() {
      _indicatorLeft = _fromLeft + (_targetLeft - _fromLeft) * t;
      _indicatorWidth = _fromWidth + (_targetWidth - _fromWidth) * t;
    });
  }

  @override
  void didUpdateWidget(TvTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex && _indicatorReady) {
      _animateIndicatorTo(widget.selectedIndex);
    }
  }

  /// 首次布局后初始化指示器位置（无动画）
  void _measureAndInit() {
    if (_indicatorReady) return;
    _measureTab(widget.selectedIndex, (left, width) {
      _indicatorReady = true;
      setState(() {
        _fromLeft = _targetLeft = _indicatorLeft = left;
        _fromWidth = _targetWidth = _indicatorWidth = width;
      });
    });
  }

  /// 动画滑动指示器到目标 Tab（从当前呈现值出发，可打断）
  void _animateIndicatorTo(int index) {
    _measureTab(index, (left, width) {
      _fromLeft = _indicatorLeft; // 从当前位置出发（可打断）
      _fromWidth = _indicatorWidth;
      _targetLeft = left;
      _targetWidth = width;
      _indicatorController.forward(from: 0);
    });
  }

  /// 测量指定 Tab 相对于导航容器的位置和宽度
  void _measureTab(int index, void Function(double left, double width) cb) {
    final navCtx = _navTabsKey.currentContext;
    final tabCtx = _tabKeys[index].currentContext;
    if (navCtx == null || tabCtx == null) return;
    final navBox = navCtx.findRenderObject() as RenderBox?;
    final tabBox = tabCtx.findRenderObject() as RenderBox?;
    if (navBox == null || tabBox == null) return;
    final pos = tabBox.localToGlobal(Offset.zero, ancestor: navBox);
    // 指示器居中于 Tab 文字区域（左右各缩进 20%）
    cb(pos.dx + tabBox.size.width * 0.2, tabBox.size.width * 0.6);
  }

  /// 指示器拉伸效果：滑动中途 scaleX 峰值 1.8（方向暗示 §8）
  double get _indicatorScaleX {
    final t = _indicatorController.value;
    if (t <= 0.0 || t >= 1.0) return 1.0;
    return 1.0 + 0.8 * sin(t * pi);
  }

  double get _bgOpacity {
    final offset = widget.scrollOffset;
    if (offset <= 0) return 0.0;
    if (offset >= 200) return 0.85;
    return offset / 200 * 0.85;
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mediaServersProvider);
    final defaultServer =
        servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;

    // 首帧后初始化指示器
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureAndInit());

    return AnimatedContainer(
      duration: AppAnimations.medium,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: _bgOpacity + 0.15),
            Colors.black.withValues(alpha: _bgOpacity * 0.5),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: [
              const SizedBox(width: 48),
              _buildServerSelector(defaultServer),
              const SizedBox(width: 32),
              _buildNavTabs(),
              const Spacer(),
              _buildIconButton(
                focusNode: _searchFocusNode,
                icon: Icons.search_rounded,
                onTap: widget.onSearch,
                focusId: 'top_search',
              ),
              const SizedBox(width: 8),
              _buildIconButton(
                focusNode: _settingsFocusNode,
                icon: Icons.settings_rounded,
                onTap: () => context.push('/settings'),
                focusId: 'top_settings',
                isProfile: true,
              ),
              const SizedBox(width: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServerSelector(MediaServer? server) {
    return Focus(
      focusNode: _serverFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _showServerSelector();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = _serverFocusNode.hasFocus;
          return GestureDetector(
            onTap: _showServerSelector,
            child: AnimatedScale(
              scale: isFocused ? 1.08 : 1.0,
              duration: Duration(milliseconds: isFocused ? 280 : 200),
              curve: isFocused ? Curves.easeOutBack : Curves.easeOut,
              child: AnimatedContainer(
              duration: AppAnimations.normal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isFocused
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isFocused ? Colors.white : Colors.white30,
                  width: isFocused ? 2.5 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    server?.type == ServerType.emby
                        ? Icons.language
                        : server?.type == ServerType.jellyfin
                            ? Icons.video_library
                            : server?.type == ServerType.fnos
                                ? Icons.dns
                                : Icons.movie,
                    size: 16,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    server?.name ?? '选择服务器',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white54, size: 16),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  void _showServerSelector() {
    final servers = ref.read(mediaServersProvider);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('选择媒体服务器',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        contentPadding: const EdgeInsets.all(20),
        content: SizedBox(
          width: 320,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: servers.length,
            itemBuilder: (context, index) {
              final server = servers[index];
              final isSelected = server.isDefault;
              return FocusableCard(
                focusId: 'server_select_${server.id}',
                onTap: () {
                  ref
                      .read(mediaServersProvider.notifier)
                      .setDefaultServer(server.id);
                  Navigator.pop(context);
                },
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                borderRadius: BorderRadius.circular(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? Colors.white : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      server.type == ServerType.emby
                          ? Icons.language
                          : server.type == ServerType.jellyfin
                              ? Icons.video_library
                              : server.type == ServerType.fnos
                                  ? Icons.dns
                                  : Icons.movie,
                      size: 20,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        server.name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          FocusableCard(
            focusId: 'close_server_dialog',
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(8),
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white30),
            ),
            child: const Text('关闭', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  // ── 导航 Tab 区域（含滑动指示器）──

  Widget _buildNavTabs() {
    return Container(
      key: _navTabsKey,
      padding: const EdgeInsets.only(bottom: 4),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 滑动指示器（Apple 风格：位移 + 中途拉伸）
          if (_indicatorReady)
            Positioned(
              bottom: 0,
              left: _indicatorLeft,
              child: Transform(
                transform: Matrix4.diagonal3Values(
                    _indicatorScaleX, 1.0, 1.0),
                alignment: Alignment.center,
                child: Container(
                  width: _indicatorWidth,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withValues(alpha: 0.3),
                        blurRadius: 6,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // Tab 项
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final isSelected = widget.selectedIndex == index;
              final focusNode = (isSelected && widget.selectedTabFocusNode != null)
                  ? widget.selectedTabFocusNode!
                  : _focusNodes[index];
              return Container(
                key: _tabKeys[index],
                child: _NavTabItem(
                  label: tab.label,
                  isSelected: isSelected,
                  focusNode: focusNode,
                  onTap: () => widget.onSelect(index),
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
                          index > 0) {
                        final target = index - 1;
                        final targetNode = (target == widget.selectedIndex && widget.selectedTabFocusNode != null)
                            ? widget.selectedTabFocusNode!
                            : _focusNodes[target];
                        targetNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey ==
                              LogicalKeyboardKey.arrowRight &&
                          index < _tabs.length - 1) {
                        final target = index + 1;
                        final targetNode = (target == widget.selectedIndex && widget.selectedTabFocusNode != null)
                            ? widget.selectedTabFocusNode!
                            : _focusNodes[target];
                        targetNode.requestFocus();
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.select ||
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.gameButtonA) {
                        widget.onSelect(index);
                        return KeyEventResult.handled;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required FocusNode focusNode,
    required IconData icon,
    required VoidCallback? onTap,
    required String focusId,
    bool isProfile = false,
  }) {
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final isFocused = focusNode.hasFocus;
          focusNode.addListener(() {
            if (mounted) setState(() {});
          });
          return GestureDetector(
            onTap: onTap,
            child: AnimatedScale(
              scale: isFocused ? 1.1 : 1.0,
              duration: Duration(milliseconds: isFocused ? 280 : 200),
              curve: isFocused ? Curves.easeOutBack : Curves.easeOut,
              child: AnimatedContainer(
                duration: AppAnimations.normal,
                curve: Curves.easeOut,
                width: isProfile ? 44 : 40,
                height: isProfile ? 44 : 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isFocused
                      ? Colors.white.withValues(alpha: 0.25)
                      : Colors.transparent,
                  border: Border.all(
                    color: isFocused ? Colors.white : Colors.white24,
                    width: isFocused ? 2.5 : 1,
                  ),
                ),
                child: Icon(
                  icon,
                  color: isFocused ? Colors.white : Colors.white70,
                  size: isProfile ? 22 : 24,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Apple 风格 Tab 项：弹簧聚焦 + 按压反馈 + 文字发光 ──

class _NavTabItem extends StatefulWidget {
  final String label;
  final bool isSelected;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final FocusOnKeyEventCallback onKeyEvent;

  const _NavTabItem({
    required this.label,
    required this.isSelected,
    required this.focusNode,
    required this.onTap,
    required this.onKeyEvent,
  });

  @override
  State<_NavTabItem> createState() => _NavTabItemState();
}

class _NavTabItemState extends State<_NavTabItem> {
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _NavTabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChange);
      widget.focusNode.addListener(_onFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) setState(() {});
  }

  /// 按压反馈：瞬时缩小 → 弹回（Apple §1 即时响应）
  void _triggerPress() {
    setState(() => _isPressed = true);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _isPressed = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.focusNode.hasFocus;
    final selected = widget.isSelected;

    // 按压 0.94（80ms 瞬时）→ 聚焦 1.08（easeOutBack 微弹）→ 常态 1.0
    final double scale =
        _isPressed ? 0.94 : (focused ? 1.08 : 1.0);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (node, event) {
        // 在父级处理前触发按压动画
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          _triggerPress();
        }
        return widget.onKeyEvent(node, event);
      },
      child: GestureDetector(
        onTap: () {
          _triggerPress();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: scale,
          duration: _isPressed
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 280),
          curve: _isPressed ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedDefaultTextStyle(
            duration: AppAnimations.normal,
            style: TextStyle(
              color: selected || focused ? Colors.white : Colors.white70,
              fontSize: selected || focused ? 17 : 16,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              // 聚焦时文字发光（Apple TV 焦点光晕）
              shadows: focused
                  ? [
                      Shadow(
                        color: Colors.white.withValues(alpha: 0.35),
                        blurRadius: 14,
                      ),
                    ]
                  : null,
            ),
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

// ── FocusableCard（保持不变）──

class FocusableCard extends StatefulWidget {
  final String focusId;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final BoxDecoration? decoration;
  final double? focusScale;

  const FocusableCard({
    super.key,
    required this.focusId,
    required this.onTap,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.decoration,
    this.focusScale = 1.05,
  });

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  late FocusNode _focusNode;

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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isFocused = _focusNode.hasFocus;
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
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: widget.decoration,
          transform: isFocused
              ? Matrix4.diagonal3Values(
                  widget.focusScale!, widget.focusScale!, 1)
              : Matrix4.identity(),
          child: widget.child,
        ),
      ),
    );
  }
}