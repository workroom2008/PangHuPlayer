import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// 媒体卡片 → 详情页的共享元素飞行（Hero）工具集。
///
/// 设计要点（Apple 空间一致性 §7）：
/// - 卡片海报 / 轮播背景 与详情页背景共享同一个 Hero tag，进入详情时
///   "从哪儿放大，就沿同一条路径飞"；返回时原路收回。
/// - tag 必须全局唯一：各来源用 focusId / 列表下标拼接，避免同一影片
///   出现在多行时重复 tag 触发 Flutter Hero 断言崩溃。
/// - 飞行画面（flightShuttleBuilder）只在详情页一侧定义：push 时 Flutter
///   取目标侧 shuttle，pop 时回退到来源侧 shuttle（即详情页的），
///   所以来源卡片只需提供 tag，无需重复实现。

/// 卡片来源的统一 tag（source 传各卡片的 focusId，天然唯一）
String mediaHeroTag(String source) => 'mh_$source';

/// 首页轮播（TvHero）背景与详情页共享的 tag
String carouselHeroTag(String itemId) => 'mh_carousel_$itemId';

/// 判断 tag 是否来自轮播（轮播的飞行起点是背景图而非海报）
bool isCarouselHeroTag(String? tag) =>
    tag != null && tag.startsWith('mh_carousel_');

/// 飞行画面：来源图（海报或轮播背景）交叉淡化到详情页背景，
/// 同时圆角从 [sourceRadius] 收拢到 0（卡片是圆角矩形，详情背景是整幅）。
/// push 时 animation 0→1（来源淡出、背景淡入），pop 时 1→0 自动反向。
HeroFlightShuttleBuilder mediaFlightShuttle({
  required String fromUrl,
  required String toUrl,
  Map<String, String>? headers,
  double sourceRadius = 8,
}) {
  return (flightContext, animation, flightDirection, fromHeroContext,
      toHeroContext) {
    final target = toUrl.isNotEmpty ? toUrl : fromUrl;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        return ClipRRect(
          borderRadius:
              BorderRadius.circular(sourceRadius * (1 - animation.value)),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (fromUrl.isNotEmpty)
                Opacity(
                  opacity: 1 - animation.value,
                  child: CachedNetworkImage(
                    imageUrl: fromUrl,
                    httpHeaders: headers,
                    memCacheWidth: 480,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorWidget: (_, __, ___) =>
                        Container(color: const Color(0xFF1E1E3A)),
                  ),
                ),
              Opacity(
                opacity: animation.value,
                child: CachedNetworkImage(
                  imageUrl: target,
                  httpHeaders: headers,
                  memCacheWidth: 960,
                  memCacheHeight: 540,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorWidget: (_, __, ___) =>
                      Container(color: const Color(0xFF0A0A0A)),
                ),
              ),
            ],
          ),
        );
      },
    );
  };
}
