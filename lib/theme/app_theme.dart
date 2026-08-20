import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ── 品牌色 ──
  static const primary = Color(0xFF6366F1);
  static const secondary = Color(0xFF8B5CF6);
  static const accent = Color(0xFFEC4899);
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);

  // ── Surface 层级（深色：从底到上依次升高） ──
  static const darkBg = Color(0xFF0A0A14);
  static const darkSurface = Color(0xFF12122A);
  static const darkSurfaceHigh = Color(0xFF1A1A36);
  static const darkCard = Color(0xFF1E1E3A);
  static const darkDivider = Color(0x1FFFFFFF);
  static const darkText = Color(0xFFFFFFFF);
  static const darkTextSec = Color(0xFF9CA3AF);
  static const darkTextTertiary = Color(0xFF6B7280);

  // ── Surface 层级（浅色） ──
  static const lightBg = Color(0xFFF8F9FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceHigh = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightDivider = Color(0x0F000000);
  static const lightText = Color(0xFF111827);
  static const lightTextSec = Color(0xFF6B7280);
  static const lightTextTertiary = Color(0xFF9CA3AF);

  // ── 渐变色 ──
  static const primaryGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF818CF8), primary, Color(0xFF6D28D9)],
  );
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFF472B6), accent, Color(0xFFDB2777)],
  );
  static const surfaceGradient = LinearGradient(
    begin: Alignment.topCenter, end: Alignment.bottomCenter,
    colors: [darkSurface, darkBg],
  );

  // ============================================================
  // 播放器专用常量 — 统一管理，禁止硬编码
  // ============================================================

  // 控制面板样式
  static const playerControlBgOpacity = 0.55;          // 控制栏背景透明度
  static const playerControlBgBlur = 20.0;             // 毛玻璃模糊强度
  static const playerControlBorderOpacity = 0.12;      // 边框透明度
  static const playerControlRadius = 20.0;             // 控制栏圆角
  static const playerControlPadding = 16.0;            // 控制栏内边距

  // 进度条样式
  static const playerProgressHeight = 4.0;             // 进度条轨道高度
  static const playerProgressThumbRadius = 6.0;        // 进度条滑块半径
  static const playerProgressThumbRadiusDrag = 10.0;   // 拖拽时滑块半径
  static const playerProgressActiveColor = primary;    // 播放进度颜色
  static const playerProgressInactiveColor = Color(0x3DFFFFFF); // 未播放区域颜色
  static const playerProgressBufferColor = Color(0x66FFFFFF);   // 缓冲进度颜色
  static const playerProgressBufferHeight = 3.0;       // 缓冲条高度

  // 音量/亮度滑块样式
  static const playerVolumeSliderWidth = 180.0;        // 音量滑块宽度
  static const playerVolumeSliderHeight = 36.0;        // 音量滑块高度
  static const playerBrightnessSliderHeight = 36.0;    // 亮度滑块高度
  static const playerSliderTrackHeight = 4.0;          // 滑块轨道高度
  static const playerSliderThumbRadius = 8.0;          // 滑块半径

  // 控制按钮尺寸
  static const playerButtonSize = 44.0;                // 普通按钮尺寸
  static const playerButtonIconSize = 22.0;            // 普通按钮图标尺寸
  static const playerPlayButtonSize = 56.0;            // 播放按钮尺寸
  static const playerPlayIconSize = 28.0;              // 播放图标尺寸
  static const playerButtonSpacing = 12.0;             // 按钮间距
  static const playerButtonRadius = 12.0;              // 按钮圆角

  // 手势控制区域
  static const playerGestureZoneWidthRatio = 0.33;     // 左/右手势区域宽度比例
  static const playerGestureSeekSeconds = 10;          // 双击快进/快退秒数
  static const playerGestureSeekLongSeconds = 30;      // 长按快进秒数

  // 动画时长
  static const playerControlShowDuration = 300;        // 控制栏显示动画 ms
  static const playerControlHideDuration = 300;        // 控制栏隐藏动画 ms
  static const playerControlAutoHideDelay = 4000;      // 控制栏自动隐藏延迟 ms
  static const playerSeekAnimDuration = 200;           // 拖拽进度动画 ms
  static const playerVolumeAnimDuration = 150;         // 音量变化动画 ms

  // 加载/错误态
  static const playerLoadingSize = 48.0;               // 加载动画尺寸
  static const playerLoadingStrokeWidth = 3.0;         // 加载动画线条宽度
  static const playerLoadingColor = primary;           // 加载动画颜色
  static const playerErrorIconSize = 64.0;             // 错误图标尺寸
  static const playerErrorTextColor = Color(0x99FFFFFF); // 错误文字颜色
  static const playerErrorButtonRadius = 12.0;         // 错误页按钮圆角

  // 弹幕样式
  static const danmakuDefaultFontSize = 24.0;          // 弹幕默认字号
  static const danmakuMinFontSize = 16.0;              // 弹幕最小字号
  static const danmakuMaxFontSize = 36.0;              // 弹幕最大字号
  static const danmakuDefaultOpacity = 1.0;            // 弹幕默认透明度
  static const danmakuDefaultSpeed = 8.0;              // 弹幕默认速度（秒穿越屏幕，越小越快）
  static const danmakuTrackHeightRatio = 1.5;          // 弹幕轨道高度倍数
  static const danmakuMaxTracks = 14;                  // 最大弹幕轨道数
  static const danmakuShadowBlur = 2.0;                // 弹幕阴影模糊（性能与可读性平衡）
  static const danmakuMaxActive = 50;                  // 最大同时活动弹幕数（性能上限）

  // 弹窗/面板样式
  static const playerPanelRadius = 24.0;               // 弹窗圆角
  static const playerPanelPadding = 20.0;              // 弹窗内边距
  static const playerPanelMargin = 24.0;               // 弹窗边距
  static const playerPanelItemRadius = 12.0;           // 弹窗内项目圆角
  static const playerPanelItemHeight = 48.0;           // 弹窗内项目高度

  // 画中画/悬浮窗
  static const pipDefaultWidth = 240.0;                // PIP 默认宽度
  static const pipDefaultHeight = 135.0;               // PIP 默认高度
  static const pipCornerRadius = 12.0;                 // PIP 圆角
  static const pipControlButtonSize = 32.0;            // PIP 控制按钮尺寸

  // 锁屏通知
  static const mediaNotificationIconSize = 48.0;       // 媒体通知图标尺寸
  static const mediaNotificationArtworkSize = 256.0;   // 媒体通知封面尺寸

  static ThemeData darkTheme = _build(Brightness.dark);
  static ThemeData lightTheme = _build(Brightness.light);

  static ThemeData _build(Brightness b) {
    final d = b == Brightness.dark;
    final bg = d ? darkBg : lightBg;
    final surf = d ? darkSurface : lightSurface;
    final surfHigh = d ? darkSurfaceHigh : lightSurfaceHigh;
    final card = d ? darkCard : lightCard;
    final divider = d ? darkDivider : lightDivider;
    final txt = d ? darkText : lightText;
    final txtSec = d ? darkTextSec : lightTextSec;

    return ThemeData(
      useMaterial3: true, brightness: b, primaryColor: primary, scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: primary, brightness: b).copyWith(
        surface: surf,
        surfaceContainerLow: d ? darkBg : const Color(0xFFF2F2F7),
        surfaceContainer: surf,
        surfaceContainerHigh: surfHigh,
        surfaceContainerHighest: card,
      ),
      // 全局关闭 Material 涟漪（Forward / VidHub 风格），改用 TapFeedback 组件
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      dividerTheme: DividerThemeData(color: divider, thickness: 0.5, space: 0.5),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent, elevation: 0, scrolledUnderElevation: 0,
        systemOverlayStyle: d ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(color: txt, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        iconTheme: IconThemeData(color: txt)),
      cardTheme: CardThemeData(
        color: card, elevation: 0, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
      elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(
        backgroundColor: primary, foregroundColor: Colors.white, elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: -0.2))),
      chipTheme: ChipThemeData(
        backgroundColor: surfHigh,
        selectedColor: primary,
        disabledColor: surfHigh,
        labelStyle: TextStyle(color: txt, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: Colors.white, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        showCheckmark: false,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: TextStyle(color: txt, fontSize: 18, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: txtSec, fontSize: 14),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        showDragHandle: true,
        dragHandleColor: divider,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: d ? const Color(0xFF2A2A3E) : const Color(0xFF1A1A2E),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return d ? const Color(0xFF9CA3AF) : const Color(0xFFD1D5DB);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return d ? const Color(0xFF374151) : const Color(0xFFD1D5DB);
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: d ? darkSurfaceHigh : const Color(0xFFF2F2F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 1.5)),
        hintStyle: TextStyle(color: txtSec, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      textTheme: TextTheme(
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: txt, letterSpacing: -0.5, height: 1.2),
        titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: txt, letterSpacing: -0.3),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: txt, letterSpacing: -0.2),
        bodyLarge: TextStyle(fontSize: 16, color: txt, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, color: txt, height: 1.4),
        bodySmall: TextStyle(fontSize: 12, color: txtSec, height: 1.3),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: txt, letterSpacing: -0.1),
        labelSmall: TextStyle(fontSize: 11, color: txtSec, letterSpacing: 0.3),
      ),
    );
  }
}

extension ThemeColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get textPrimary => isDark ? AppTheme.darkText : AppTheme.lightText;
  Color get textPrimary70 => textPrimary.withValues(alpha: 0.7);
  Color get textPrimary50 => textPrimary.withValues(alpha: 0.5);
  Color get textPrimary38 => textPrimary.withValues(alpha: 0.38);
  Color get textPrimary30 => textPrimary.withValues(alpha: 0.3);
  Color get textPrimary24 => textPrimary.withValues(alpha: 0.24);
  Color get textPrimary10 => textPrimary.withValues(alpha: 0.1);
  Color get textPrimary60 => textPrimary.withValues(alpha: 0.6);
  Color get textSecondary => isDark ? AppTheme.darkTextSec : AppTheme.lightTextSec;
  Color get textTertiary => isDark ? AppTheme.darkTextTertiary : AppTheme.lightTextTertiary;
  Color get surfaceColor => isDark ? AppTheme.darkSurface : AppTheme.lightSurface;
  Color get surfaceHighColor => isDark ? AppTheme.darkSurfaceHigh : AppTheme.lightSurfaceHigh;
  Color get cardColor => isDark ? AppTheme.darkCard : AppTheme.lightCard;
  Color get bgColor => isDark ? AppTheme.darkBg : AppTheme.lightBg;
  Color get dividerColor => isDark ? AppTheme.darkDivider : AppTheme.lightDivider;

  /// 分组卡片背景（设置页等使用）
  Color get groupBg => isDark ? AppTheme.darkSurfaceHigh.withValues(alpha: 0.6) : const Color(0xFFF2F2F7);
}


