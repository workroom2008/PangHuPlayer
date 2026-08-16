import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_theme.dart';
import '../../utils/animation_config.dart';

class FocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double? width;
  final double? height;
  final double borderRadius;
  final String focusId;
  final bool autoFocus;
  final Color? focusColor;
  final double focusScale;
  final EdgeInsetsGeometry? padding;
  final Decoration? decoration;

  const FocusableCard({
    super.key,
    required this.child,
    required this.focusId,
    this.onTap,
    this.width,
    this.height,
    this.borderRadius = 12,
    this.autoFocus = false,
    this.focusColor,
    this.focusScale = 1.05,
    this.padding,
    this.decoration,
  });

  @override
  State<FocusableCard> createState() => _FocusableCardState();
}

class _FocusableCardState extends State<FocusableCard> {
  bool _isFocused = false;
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
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
      if (_isFocused) {
        // 方向键连按时平滑滚动到焦点卡片，取代跳变滚动
        Scrollable.ensureVisible(
          context,
          duration: AppAnimations.normal,
          curve: AppAnimations.easeOut,
          alignment: 0.2,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autoFocus,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.gameButtonA)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        // 焦点缩放改用 AnimatedScale：只在 paint 层做变换，不触发 layout。
        // 旧实现用 AnimatedContainer 的 transform（Matrix4..scale），
        // 每帧都走完整 layout 流程，是 TV 盒子上方向键连按掉帧的主因。
        // 外层 RepaintBoundary 把重绘隔离在单卡片内。
        child: RepaintBoundary(
          child: AnimatedScale(
            scale: _isFocused ? widget.focusScale : 1.0,
            duration: AppAnimations.normal,
            curve: AppAnimations.easeOut,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: AppAnimations.normal,
              curve: AppAnimations.easeOut,
              width: widget.width,
              height: widget.height,
              padding: widget.padding,
              decoration: widget.decoration ??
                  BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: _isFocused
                          ? (widget.focusColor ?? AppTheme.primary)
                          : Colors.transparent,
                      width: _isFocused ? 3 : 0,
                    ),
                    boxShadow: _isFocused
                        ? [
                            BoxShadow(
                              color: (widget.focusColor ?? AppTheme.primary)
                                  .withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TvButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool autoFocus;
  final String focusId;
  final Color? color;

  const TvButton({
    super.key,
    required this.label,
    required this.focusId,
    this.onPressed,
    this.icon,
    this.autoFocus = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableCard(
      focusId: focusId,
      autoFocus: autoFocus,
      onTap: onPressed,
      borderRadius: 12,
      focusColor: color ?? AppTheme.primary,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: color ?? AppTheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 20),
            SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统一弹簧缩放（TV 焦点语言的核心动效）。
///
/// 对齐顶栏导航已有的手感：
/// - 聚焦进入：[focusScale]（默认 1.08），easeOutBack 微弹（≈欠阻尼弹簧），280ms
/// - 聚焦离开：回到 1.0，easeOut（临界阻尼），200ms
/// - 按下：[pressScale]（默认 0.94），80ms 瞬时反馈
///
/// 该组件只负责缩放动效，焦点/按压状态由外部传入，
/// 方便既有复杂焦点 UI 的卡片（如主页媒体卡）复用同一套曲线参数。
class SpringScale extends StatelessWidget {
  final bool focused;
  final bool pressed;
  final double focusScale;
  final double pressScale;
  final Alignment alignment;
  final Widget child;

  const SpringScale({
    super.key,
    required this.focused,
    required this.child,
    this.pressed = false,
    this.focusScale = 1.08,
    this.pressScale = 0.94,
    this.alignment = Alignment.center,
  });

  @override
  Widget build(BuildContext context) {
    final double scale = pressed ? pressScale : (focused ? focusScale : 1.0);
    final int ms = pressed ? 80 : (focused ? 280 : 200);
    final Curve curve =
        pressed ? Curves.easeOut : (focused ? Curves.easeOutBack : Curves.easeOut);
    return AnimatedScale(
      scale: scale,
      duration: Duration(milliseconds: ms),
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}

/// 统一焦点组件： owns FocusNode + 按键处理 + 按压态 + 弹簧缩放 + 边框/发光。
///
/// 用于替换各处不一致的焦点实现（按钮、选集卡、播放器控制键等）。
/// 按下 select/enter/A 时立即反馈（Apple：反馈在按下那一刻），
/// 聚焦时缩放 + 边框 + 发光同步出现。
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String focusId;
  final bool autoFocus;
  final double focusScale;
  final double pressScale;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  /// 未聚焦装饰；为 null 时使用透明底。
  final Decoration? decoration;

  /// 聚焦装饰；为 null 时使用默认「白色描边 + 发光」。
  final Decoration? focusedDecoration;

  /// 是否用 ClipRRect 裁剪 child（圆角内容需要时开启）。
  final bool clipChild;

  const TvFocusable({
    super.key,
    required this.child,
    required this.focusId,
    this.onTap,
    this.autoFocus = false,
    this.focusScale = 1.08,
    this.pressScale = 0.94,
    this.borderRadius = 12,
    this.padding,
    this.width,
    this.height,
    this.decoration,
    this.focusedDecoration,
    this.clipChild = false,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _focusNode;
  bool _isFocused = false;
  bool _isPressed = false;

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
    if (mounted) {
      setState(() => _isFocused = _focusNode.hasFocus);
      if (_isFocused) {
        Scrollable.ensureVisible(
          context,
          duration: AppAnimations.normal,
          curve: AppAnimations.easeOut,
          alignment: 0.2,
        );
      }
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final isSelect = event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA;
    if (!isSelect) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      setState(() => _isPressed = true);
      widget.onTap?.call();
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _isPressed = false);
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final Decoration base = widget.decoration ??
        BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          color: Colors.transparent,
        );
    final Decoration focused = widget.focusedDecoration ??
        BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.25),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        );

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autoFocus,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SpringScale(
          focused: _isFocused,
          pressed: _isPressed,
          focusScale: widget.focusScale,
          pressScale: widget.pressScale,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: widget.width,
            height: widget.height,
            padding: widget.padding,
            decoration: _isFocused ? focused : base,
            child: widget.clipChild
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    child: widget.child,
                  )
                : widget.child,
          ),
        ),
      ),
    );
  }
}


