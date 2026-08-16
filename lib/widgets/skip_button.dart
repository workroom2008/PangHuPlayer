import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

/// Netflix 风格 "跳过片头/片尾" 浮动按钮
/// 从右侧滑入，自动聚焦，10s 倒计时进度条走完后自动跳过
class SkipButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onAutoExpire;

  const SkipButton({
    super.key,
    required this.label,
    required this.onTap,
    this.onAutoExpire,
  });

  @override
  State<SkipButton> createState() => _SkipButtonState();
}

class _SkipButtonState extends State<SkipButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnim;
  late Animation<double> _opacityAnim;
  late Animation<double> _scaleAnim;
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  bool _cancelled = false;

  // 10s 倒计时
  static const int _countdownTotal = 10;
  int _countdownRemaining = _countdownTotal;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _opacityAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _scaleAnim = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();

    _focusNode.addListener(() {
      if (mounted) setState(() => _isFocused = _focusNode.hasFocus);
    });

    // 自动聚焦
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _focusNode.requestFocus();
    });

    // 10s 倒计时，每秒 tick
    _startCountdown();
  }

  @override
  void didUpdateWidget(covariant SkipButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label == widget.label) return;
    _countdownTimer?.cancel();
    _countdownRemaining = _countdownTotal;
    _cancelled = false;
    _controller
      ..reset()
      ..forward();
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _cancelled) return;
      setState(() => _countdownRemaining--);
      if (_countdownRemaining <= 0) {
        _countdownTimer?.cancel();
        widget.onTap();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    // OK/Enter → 立即跳过
    if (event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.gameButtonA) {
      _countdownTimer?.cancel();
      widget.onTap();
      return KeyEventResult.handled;
    }
    // LEFT/BACK → 取消自动跳过，按钮淡出
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.goBack ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _cancelled = true;
      _countdownTimer?.cancel();
      _controller.reverse().then((_) {
        if (mounted) widget.onAutoExpire?.call();
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final progress = _countdownTotal > 0
        ? (1.0 - _countdownRemaining / _countdownTotal).clamp(0.0, 1.0)
        : 0.0;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _opacityAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          child: Focus(
            focusNode: _focusNode,
          onKeyEvent: _onKey,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _isFocused ? Colors.white : Colors.white.withValues(alpha: 0.35),
                  width: _isFocused ? 2.5 : 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.label} (${_countdownRemaining}s)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.skip_next_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 倒计时进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 3,
                      width: 140,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: progress),
                        duration: const Duration(milliseconds: 1000),
                        curve: Curves.linear,
                        builder: (context, value, _) {
                          return LinearProgressIndicator(
                            value: value,
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(alpha: 0.2),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          );
                        },
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

/// 下一集自动播放倒计时卡片
class NextEpisodeCard extends StatefulWidget {
  final String title;
  final String? subtitle;
  final String? thumbnailUrl;
  final int totalSeconds;
  final int remainingSeconds;
  final VoidCallback onPlay;
  final VoidCallback onCancel;

  const NextEpisodeCard({
    super.key,
    required this.title,
    this.subtitle,
    this.thumbnailUrl,
    required this.totalSeconds,
    required this.remainingSeconds,
    required this.onPlay,
    required this.onCancel,
  });

  @override
  State<NextEpisodeCard> createState() => _NextEpisodeCardState();
}

class _NextEpisodeCardState extends State<NextEpisodeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _entranceCtrl;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    )..forward();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalSeconds > 0
        ? (1.0 - widget.remainingSeconds / widget.totalSeconds).clamp(0.0, 1.0)
        : 0.0;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.6, 0),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
      ),
      child: FadeTransition(
        opacity: _entranceCtrl,
        child: Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '下一集',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.remainingSeconds}s',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GestureDetector(
                    onTap: widget.onPlay,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: 0, end: progress),
                            duration: const Duration(milliseconds: 1000),
                            curve: Curves.linear,
                            builder: (context, value, _) {
                              return SizedBox(
                                width: 44,
                                height: 44,
                                child: CircularProgressIndicator(
                                  value: value,
                                  strokeWidth: 3,
                                  backgroundColor: Colors.white.withValues(alpha: 0.2),
                                  color: AppTheme.primary,
                                ),
                              );
                            },
                          ),
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.subtitle!,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text(
                        '取消自动播放',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
    );
  }
}
