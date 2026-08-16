import 'package:flutter/material.dart';

class AppAnimations {
  AppAnimations._();

  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration pageTransition = Duration(milliseconds: 350);

  /// 底部导航栏：药丸滑动与图标/文字插值共用同一时长，保证作为整体动作完成
  static const Duration navPill = Duration(milliseconds: 220);

  /// 轮播取色背景过渡：分类区背景色与底部渐变遮罩共用，两者必须同步否则出现色带割裂
  static const Duration carouselColor = Duration(milliseconds: 400);

  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve easeIn = Curves.easeInCubic;
  static const Curve easeInOut = Curves.easeInOutCubic;
  static const Curve bouncy = Curves.easeOutBack;
  static const Curve elastic = Curves.easeOutQuart;

  /// 胶囊吸附弹跳曲线：末端控制点 y>1 产生过冲再回弹（约 35%），
  /// iOS 26 spring 手感。用户反馈 5% 太收敛，调大后跳起弧线 + 吸附都更明显
  static const Curve navSnap = Cubic(0.22, 0.95, 0.3, 1.35);

  static Widget fadeTransition({
    required Animation<double> animation,
    required Widget child,
    Curve curve = easeOut,
  }) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: curve),
      child: child,
    );
  }

  static Widget slideTransition({
    required Animation<double> animation,
    required Widget child,
    Offset begin = const Offset(0, 0.2),
    Offset end = Offset.zero,
    Curve curve = easeOut,
  }) {
    return SlideTransition(
      position: Tween<Offset>(begin: begin, end: end).animate(
        CurvedAnimation(parent: animation, curve: curve),
      ),
      child: child,
    );
  }

  static Widget fadeSlideTransition({
    required Animation<double> animation,
    required Widget child,
    Offset begin = const Offset(0, 0.2),
    Offset end = Offset.zero,
    Curve curve = easeOut,
  }) {
    final curvedAnimation = CurvedAnimation(parent: animation, curve: curve);
    return FadeTransition(
      opacity: curvedAnimation,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: end).animate(curvedAnimation),
        child: child,
      ),
    );
  }

  static Route<T> buildPageRoute<T>({
    required Widget page,
    PageTransitionType type = PageTransitionType.fade,
  }) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionDuration: pageTransition,
      reverseTransitionDuration: normal,
      transitionsBuilder: (_, animation, __, child) {
        switch (type) {
          case PageTransitionType.fade:
            return fadeTransition(animation: animation, child: child);
          case PageTransitionType.slideRight:
            return slideTransition(
              animation: animation,
              begin: const Offset(1, 0),
              child: child,
            );
          case PageTransitionType.slideUp:
            return slideTransition(
              animation: animation,
              begin: const Offset(0, 1),
              child: child,
            );
          case PageTransitionType.fadeSlide:
            return fadeSlideTransition(
              animation: animation,
              begin: const Offset(0, 0.1),
              child: child,
            );
        }
      },
    );
  }
}

enum PageTransitionType {
  fade,
  slideRight,
  slideUp,
  fadeSlide,
}

