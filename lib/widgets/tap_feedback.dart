import 'package:flutter/material.dart';
import '../utils/animation_config.dart';

/// 按压反馈包装组件。
///
/// 按需提供缩放 + 底色微亮反馈，**不使用 Material 涟漪**（圆形波纹太"安卓"，
/// 不符 Forward/VidHub 风格）。
///
/// 用法：
/// ```dart
/// TapFeedback(
///   onTap: () => _handleTap(),
///   child: Text('按钮'),
/// )
/// ```
class TapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleOnPress;
  final Color? highlightColor;
  final BorderRadius? borderRadius;

  /// 抬起时用 elasticOut 弹回（轻微过冲再回落），形成"回弹"手感
  final bool springBack;

  const TapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleOnPress = 0.96,
    this.highlightColor,
    this.borderRadius,
    this.springBack = false,
  });

  @override
  State<TapFeedback> createState() => _TapFeedbackState();
}

class _TapFeedbackState extends State<TapFeedback> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: _isPressed ? widget.scaleOnPress : 1.0,
        duration: _isPressed
            ? AppAnimations.fast
            : (widget.springBack ? const Duration(milliseconds: 380) : AppAnimations.fast),
        curve: _isPressed
            ? AppAnimations.easeOut
            : (widget.springBack ? Curves.elasticOut : AppAnimations.easeOut),
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          curve: AppAnimations.easeOut,
          decoration: BoxDecoration(
            color: _isPressed
                ? (widget.highlightColor ??
                    Colors.white.withValues(alpha: 0.06))
                : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }

  void _onTapDown(_) {
    // 完全禁用（onTap/onLongPress 均为 null）时不产生按压视觉
    if (widget.onTap == null && widget.onLongPress == null) return;
    setState(() => _isPressed = true);
  }

  void _onTapUp(_) => setState(() => _isPressed = false);
  void _onTapCancel() => setState(() => _isPressed = false);
}

/// 媒体卡片专用按压反馈（缩放 + 阴影，不改变底色）。
///
/// 用于海报/剧集等有图片的卡片，底色变化会干扰图片显示。
class CardTapFeedback extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleOnPress;

  const CardTapFeedback({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleOnPress = 0.95,
  });

  @override
  State<CardTapFeedback> createState() => _CardTapFeedbackState();
}

class _CardTapFeedbackState extends State<CardTapFeedback> {
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
        duration: AppAnimations.fast,
        curve: AppAnimations.easeOut,
        child: widget.child,
      ),
    );
  }
}