import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'animation_config.dart';

/// 全局统一的页面转场工厂。
///
/// 背景：改造前手机端 15 条 GoRoute 全部用裸 `builder`，走 Android 平台默认
/// 转场（Zoom/FadeUpwards）；但同一个 App 里 `Navigator.push` 又用
/// `AppAnimations.buildPageRoute` 的淡入上滑 —— 同一次操作路径上会出现两种
/// 不同的转场语言。TV 端也只有 `/library/:id` 一条做了精心的镜像转场。
///
/// 这里把转场按层级语义分档，两个 router 共用同一套实现：
///
/// | 语义                | 效果                                  |
/// |---------------------|---------------------------------------|
/// | [slideRight]        | 右入右出镜像（层级导航：设置/日志/服务器） |
/// | [fadeSlideUp]       | 下方淡入上滑（覆盖式面板：搜索）          |
/// | [immersive]         | 淡入 + 轻微放大（进入内容：详情/播放器）    |
/// | [fade]              | 纯淡入（首页等根级页面）                  |
class PageTransitions {
  PageTransitions._();

  /// 右入右出镜像转场。
  ///
  /// 新页从右侧 8% 滑入 + 淡入，返回时沿同一路径滑出
  /// （animation 反向 + reverseCurve 保证进出对称）。
  /// 该实现原本内联在 TV 端 `/library/:id` 路由里，现提取为公共实现。
  static CustomTransitionPage<T> slideRight<T>({
    required Widget child,
    required LocalKey key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppAnimations.pageTransition,
      reverseTransitionDuration: AppAnimations.normal,
      child: child,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.easeOut,
          reverseCurve: AppAnimations.easeIn,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  /// 从下方淡入 + 上滑（覆盖式面板，如搜索页）。
  static CustomTransitionPage<T> fadeSlideUp<T>({
    required Widget child,
    required LocalKey key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppAnimations.pageTransition,
      reverseTransitionDuration: AppAnimations.normal,
      child: child,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.easeOut,
          reverseCurve: AppAnimations.easeIn,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.1),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  /// 沉浸式进入：淡入 + 从 1.04 收到 1.0 的轻微放大。
  ///
  /// 用于「进入内容」的场景（详情页、播放器）。配合 Hero 共享元素时，
  /// 缩放幅度刻意做得很小，避免与飞行中的海报打架。
  /// 时长比普通转场更长（500ms），给 Hero 海报飞行留够视觉追踪时间。
  static CustomTransitionPage<T> immersive<T>({
    required Widget child,
    required LocalKey key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 350),
      child: child,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.easeOut,
          reverseCurve: AppAnimations.easeIn,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.04, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 纯淡入（根级页面，无方向感）。
  static CustomTransitionPage<T> fade<T>({
    required Widget child,
    required LocalKey key,
  }) {
    return CustomTransitionPage<T>(
      key: key,
      transitionDuration: AppAnimations.normal,
      reverseTransitionDuration: AppAnimations.fast,
      child: child,
      transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: AppAnimations.easeOut,
            reverseCurve: AppAnimations.easeIn,
          ),
          child: child,
        );
      },
    );
  }
}
