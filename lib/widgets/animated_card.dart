import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/animation_config.dart';

/// 带点击动画效果的卡片组件
/// 按下时缩放 + 阴影变化，提供流畅的交互反馈
class AnimatedCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleOnPress;
  final Duration animationDuration;
  final BorderRadius? borderRadius;
  final double pressedShadowElevation;
  final double normalShadowElevation;

  const AnimatedCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleOnPress = 0.96,
    this.animationDuration = const Duration(milliseconds: 150),
    this.borderRadius,
    this.pressedShadowElevation = 12,
    this.normalShadowElevation = 4,
  });

  @override
  State<AnimatedCard> createState() => _AnimatedCardState();
}

class _AnimatedCardState extends State<AnimatedCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _onPressStart(),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: () => _onPressEnd(),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleOnPress : 1.0,
        duration: widget.animationDuration,
        curve: AppAnimations.easeOut,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: widget.animationDuration,
          curve: AppAnimations.easeOut,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isPressed ? 0.4 : 0.2),
                blurRadius: _isPressed ? widget.pressedShadowElevation : widget.normalShadowElevation,
                spreadRadius: _isPressed ? 2 : 0,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: widget.child,
        ),
      ),
    );
  }

  void _onPressStart() {
    setState(() => _isPressed = true);
  }

  void _onPressEnd() {
    setState(() => _isPressed = false);
  }
}

/// 轻量版点击动画卡片，只包含缩放效果
/// 用于列表项等不需要阴影的场景
class ScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleOnPress;
  final Duration animationDuration;

  const ScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleOnPress = 0.95,
    this.animationDuration = const Duration(milliseconds: 120),
  });

  @override
  State<ScaleCard> createState() => _ScaleCardState();
}

class _ScaleCardState extends State<ScaleCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleOnPress : 1.0,
        duration: widget.animationDuration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

/// Hero卡片 - 带Hero动画的点击卡片
/// 用于点击跳转详情页时的流畅过渡
class HeroAnimatedCard extends StatefulWidget {
  final String heroTag;
  final Widget heroChild;
  final Widget? overlay;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius? borderRadius;

  const HeroAnimatedCard({
    super.key,
    required this.heroTag,
    required this.heroChild,
    this.overlay,
    this.onTap,
    this.onLongPress,
    this.borderRadius,
  });

  @override
  State<HeroAnimatedCard> createState() => _HeroAnimatedCardState();
}

class _HeroAnimatedCardState extends State<HeroAnimatedCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap?.call();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
              child: Hero(
                tag: widget.heroTag,
                child: widget.heroChild,
              ),
            ),
            if (widget.overlay != null)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
                  child: widget.overlay!,
                ),
              ),
            // 按下时的视觉反馈层
            if (_isPressed)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: widget.borderRadius ?? BorderRadius.circular(12),
                  child: Container(
                    color: context.textPrimary.withValues(alpha:0.1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

