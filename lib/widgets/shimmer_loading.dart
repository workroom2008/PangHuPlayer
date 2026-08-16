import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_theme.dart';
import '../utils/animation_config.dart';

/// 骨架屏统一底色（低对比度，避免暗色主题下出现纯白闪块）
Color _skeletonBase(BuildContext context) =>
    context.textPrimary.withValues(alpha: 0.06);
Color _skeletonHighlight(BuildContext context) =>
    context.textPrimary.withValues(alpha: 0.14);

/// 骨架块 — 参数化的单个占位矩形
///
/// 尺寸/圆角由调用方传入，便于与真实内容 1:1 对齐，
/// 避免加载完成时因高度不一致导致页面跳位。
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 12,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: _skeletonBase(context),
      highlightColor: _skeletonHighlight(context),
      child: Container(
        width: width,
        height: height,
        margin: margin,
        decoration: BoxDecoration(
          color: _skeletonBase(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// 海报卡片骨架 — 与 _MediaItemCard 结构 1:1 对应
///
/// 真实卡片结构：海报(cardWidth × cardWidth/cardAspectRatio) + 6px 间隔
/// + 标题两行 + 年份一行。骨架保持相同尺寸，加载完成时内容就地填充。
class SkeletonPosterCard extends StatelessWidget {
  final double cardWidth;
  final double cardHeight;
  final double radius;
  final double spacing;
  final double subtitleFontSize;

  const SkeletonPosterCard({
    super.key,
    required this.cardWidth,
    required this.cardHeight,
    required this.radius,
    required this.spacing,
    required this.subtitleFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: cardWidth,
      margin: EdgeInsets.only(right: spacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SkeletonBox(width: cardWidth, height: cardHeight, radius: radius),
          const SizedBox(height: 6),
          // 标题（真实为 fontSize 12，maxLines 2 → 首行占位）
          SkeletonBox(width: cardWidth * 0.85, height: 12, radius: 4),
          const SizedBox(height: 4),
          // 年份
          SkeletonBox(
            width: cardWidth * 0.4,
            height: subtitleFontSize,
            radius: 4,
          ),
        ],
      ),
    );
  }
}

/// 列表加载骨架屏
class ShimmerList extends StatelessWidget {
  final int count;
  final double height;
  final EdgeInsets margin;
  final double radius;

  const ShimmerList({
    super.key,
    this.count = 6,
    this.height = 200,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        count,
        (i) => SkeletonBox(height: height, margin: margin, radius: radius),
      ),
    );
  }
}

/// Stagger 错峰渐显动画包装
///
/// 通过 [Interval] 把 index 对应的延迟折进曲线，实现真正的逐项错峰。
/// 旧实现把 delay 只喂给一个 FutureBuilder、透明度却用与 delay 无关的
/// 插值值，导致错峰从未生效，且每次重建都会新建 Future.delayed 定时器。
class StaggerItem extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration delayPerItem;
  final Duration duration;
  final double offsetY;

  const StaggerItem({
    super.key,
    required this.index,
    required this.child,
    this.delayPerItem = const Duration(milliseconds: 60),
    this.duration = AppAnimations.slow,
    this.offsetY = 20,
  });

  @override
  Widget build(BuildContext context) {
    // 累计延迟上限 800ms，避免长列表末尾等待过久
    final delayMs =
        (index * delayPerItem.inMilliseconds).clamp(0, 800).toInt();
    final totalMs = delayMs + duration.inMilliseconds;
    // 把延迟折进 Interval：[delay/total, 1.0] 区间内才执行渐显曲线
    final begin = totalMs == 0 ? 0.0 : (delayMs / totalMs).clamp(0.0, 0.99);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: totalMs),
      curve: Interval(begin, 1.0, curve: AppAnimations.easeOut),
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, (1 - v) * offsetY),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
