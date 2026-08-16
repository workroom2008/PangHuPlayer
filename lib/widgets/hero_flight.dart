import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Hero 共享元素飞行外观（卡片 → 详情页）。
///
/// 图一致性铁律：飞行全程锁定「起飞侧」的图（push = 卡片 poster，pop = 详情页
/// poster——两侧同一 URL），禁止 Hero 默认的 mid-flight 换图，杜绝两张不同图片
/// 交叉导致转场生硬。落地后的 backdrop 大图不是 Hero 的一部分，由详情页
/// `_heroLanded` 在完成态做交叉淡入。
///
/// 外观：
/// - 圆角 12px（卡片）→ 0（详情页全宽）随进度平滑过渡
/// - 中段轻微过冲（峰值 1.02，sin 波形）——「吸」过去的感觉
/// - 浮起阴影（飞行中悬浮在页面上方）
Widget heroFlightShuttle(
  BuildContext context,
  Animation<double> animation,
  HeroFlightDirection flightDirection,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  // 锁定起飞侧图：push 用卡片（from），pop 用详情（to）——两侧同一张图
  final hero = (flightDirection == HeroFlightDirection.push
          ? fromHeroContext
          : toHeroContext)
      .widget as Hero;
  final child = hero.child;
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = Curves.easeOutCubic.transform(animation.value);
      final radius = (12.0 * (1 - t)).clamp(0.0, 12.0);
      // 中段轻微过冲（峰值 1.02）
      final overshoot = 1.0 + 0.02 * math.sin(math.pi * t);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Transform.scale(scale: overshoot, child: child),
      );
    },
  );
}
