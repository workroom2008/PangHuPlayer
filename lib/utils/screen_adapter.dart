import 'package:flutter/material.dart';

/// 屏幕适配工具类
/// 支持多种屏幕尺寸：小屏手机、标准手机、大屏手机、小平板、大平板
/// 支持横竖屏切换
class ScreenAdapter {
  final BuildContext context;
  late final double _screenWidth;
  late final double _screenHeight;
  late final Orientation _orientation;

  /// 全局卡片尺寸系数（用户可调三档：小 0.85 / 标准 1.0 / 大 1.15）
  /// 由设置页修改并持久化，全 App 卡片/网格/间距统一缩放
  static double cardScale = 1.0;
  
  ScreenAdapter(this.context) {
    final size = MediaQuery.of(context).size;
    _screenWidth = size.width;
    _screenHeight = size.height;
    _orientation = MediaQuery.of(context).orientation;
  }
  
  /// 获取屏幕宽度
  double get screenWidth => _screenWidth;
  
  /// 获取屏幕高度
  double get screenHeight => _screenHeight;
  
  /// 获取屏幕方向
  Orientation get orientation => _orientation;
  
  /// 是否是横屏
  bool get isLandscape => _orientation == Orientation.landscape;
  
  /// 是否是竖屏
  bool get isPortrait => _orientation == Orientation.portrait;
  
  /// 屏幕类型枚举
  ScreenType get screenType {
    // 横屏时使用高度来判断，竖屏时使用宽度来判断
    final effectiveWidth = isLandscape ? _screenHeight : _screenWidth;
    
    if (effectiveWidth < 360) return ScreenType.compact;      // 小屏手机（如旧款iPhone SE）
    if (effectiveWidth < 480) return ScreenType.small;        // 标准手机（如iPhone 6-8）
    if (effectiveWidth < 600) return ScreenType.medium;       // 大屏手机（如iPhone Plus/Max）
    if (effectiveWidth < 800) return ScreenType.large;        // 小平板（如iPad Mini）
    return ScreenType.extraLarge;                              // 大平板（如iPad Pro）
  }
  
  /// 获取卡片宽度（用于横向列表），乘用户卡片尺寸系数
  double get cardWidth {
    return _baseCardWidth * ScreenAdapter.cardScale;
  }

  /// 基础卡片宽度（未乘用户系数）
  double get _baseCardWidth {
    switch (screenType) {
      case ScreenType.compact:
        return 85.0;
      case ScreenType.small:
        return 100.0;
      case ScreenType.medium:
        return 115.0;
      case ScreenType.large:
        return 130.0;
      case ScreenType.extraLarge:
        return 150.0;
    }
  }
  
  /// 获取网格列数（用于网格列表）
  int get crossAxisCount {
    // 横屏时增加列数
    final baseCount = switch (screenType) {
      ScreenType.compact => 2,
      ScreenType.small => 3,
      ScreenType.medium => 4,
      ScreenType.large => 6,
      ScreenType.extraLarge => 8,
    };
    
    return isLandscape ? baseCount + 2 : baseCount;
  }
  
  /// 获取卡片宽高比（海报通常是 2:3 = 0.67）
  double get cardAspectRatio {
    // 大屏幕时卡片可以更宽一些
    switch (screenType) {
      case ScreenType.compact:
        return 0.65;
      case ScreenType.small:
        return 0.67;
      case ScreenType.medium:
        return 0.68;
      case ScreenType.large:
        return 0.70;
      case ScreenType.extraLarge:
        return 0.72;
    }
  }
  
  /// 获取卡片间距（随卡片尺寸系数缩放）
  double get cardSpacing {
    return _baseCardSpacing * ScreenAdapter.cardScale;
  }

  double get _baseCardSpacing {
    switch (screenType) {
      case ScreenType.compact:
        return 8.0;
      case ScreenType.small:
        return 10.0;
      case ScreenType.medium:
        return 12.0;
      case ScreenType.large:
        return 14.0;
      case ScreenType.extraLarge:
        return 16.0;
    }
  }
  
  /// 获取卡片圆角（随卡片尺寸系数缩放）
  double get cardRadius {
    return _baseCardRadius * ScreenAdapter.cardScale;
  }

  double get _baseCardRadius {
    switch (screenType) {
      case ScreenType.compact:
        return 8.0;
      case ScreenType.small:
        return 10.0;
      case ScreenType.medium:
        return 12.0;
      case ScreenType.large:
        return 14.0;
      case ScreenType.extraLarge:
        return 16.0;
    }
  }
  
  /// 获取标题字体大小
  double get titleFontSize {
    switch (screenType) {
      case ScreenType.compact:
        return 10.0;
      case ScreenType.small:
        return 11.0;
      case ScreenType.medium:
        return 12.0;
      case ScreenType.large:
        return 14.0;
      case ScreenType.extraLarge:
        return 16.0;
    }
  }
  
  /// 获取副标题字体大小
  double get subtitleFontSize {
    switch (screenType) {
      case ScreenType.compact:
        return 9.0;
      case ScreenType.small:
        return 10.0;
      case ScreenType.medium:
        return 11.0;
      case ScreenType.large:
        return 12.0;
      case ScreenType.extraLarge:
        return 14.0;
    }
  }
  
  /// 获取轮播图高度
  double get carouselHeight {
    // 横屏时轮播图高度相对较小
    final baseHeight = switch (screenType) {
      ScreenType.compact => 200.0,
      ScreenType.small => 240.0,
      ScreenType.medium => 280.0,
      ScreenType.large => 320.0,
      ScreenType.extraLarge => 400.0,
    };
    
    return isLandscape ? baseHeight * 0.6 : baseHeight;
  }
  
  /// 获取内容区域padding
  double get contentPadding {
    switch (screenType) {
      case ScreenType.compact:
        return 12.0;
      case ScreenType.small:
        return 14.0;
      case ScreenType.medium:
        return 16.0;
      case ScreenType.large:
        return 20.0;
      case ScreenType.extraLarge:
        return 24.0;
    }
  }
  
  /// 快捷方法：获取适配器实例
  static ScreenAdapter of(BuildContext context) => ScreenAdapter(context);
}

/// 屏幕类型枚举
enum ScreenType {
  compact,       // < 360dp (小屏手机)
  small,         // 360-480dp (标准手机)
  medium,        // 480-600dp (大屏手机)
  large,         // 600-800dp (小平板)
  extraLarge,    // > 800dp (大平板)
}

