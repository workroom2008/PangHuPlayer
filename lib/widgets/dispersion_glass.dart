import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../theme/app_theme.dart';
import '../utils/app_log.dart';
import '../utils/glass_quality.dart';

/// Streama「液态玻璃 · 透镜色散」—— 自定义 fragment shader 版。
///
/// 管线：
/// 1. 截取导航栏背后的内容条带（`backdropKey` 指向的 RepaintBoundary → toImage，
///    1x 逻辑分辨率 + 小区域，成本低）
/// 2. 用 [FragmentProgram]（shaders/nav_glass.frag）单次绘制：
///    圆角 SDF 边界掩码 + 3×3 模糊 + 径向 RGB 色散 + 真实彩色光晕（颜色来自背景
///    内容，亮边缘出现青/品红镶边）+ 玻璃底色 + 噪点
/// 3. shader 编译或截取失败 → 自动回退到原 BackdropFilter 玻璃（不假、不崩）
///
/// 刷新：`active=true` 时每 350ms 截取一次背景（导航可见期间），也可通过
/// `GlobalKey<DispersionGlassState>().refresh()` 在关键时机（切 tab）立即刷新。
class DispersionGlass extends StatefulWidget {
  /// 包裹导航栏背后内容的 RepaintBoundary 的 key
  final GlobalKey backdropKey;
  final Widget child;
  final double radius;

  /// 导航可见时开启周期截取；隐藏后停止（省电）
  final bool active;

  /// 玻璃底色（亮/暗主题由调用方传入）
  final Color tint;
  final double tintAlpha;
  final double blur;
  final double dispersion;
  final double edgeGlow;

  /// 饱和度提升（shader 内做，floatica saturationBoost 同款，默认 1.2）
  final double saturation;

  /// 光晕外扩量（左右/上下）
  static const double haloH = 16.0;
  static const double haloV = 16.0;

  /// 背景截取分辨率（逻辑像素倍数；玻璃区域小，1.5x 让边缘更锐利，成本可接受）
  static const double capturePixelRatio = 1.5;

  const DispersionGlass({
    super.key,
    required this.backdropKey,
    required this.child,
    this.radius = 24,
    this.active = true,
    required this.tint,
    this.tintAlpha = 0.45,
    this.blur = 1.2,
    this.dispersion = 2.2,
    this.edgeGlow = 1.0,
    this.saturation = 1.2,
  });

  @override
  State<DispersionGlass> createState() => DispersionGlassState();
}

class DispersionGlassState extends State<DispersionGlass> {
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _programLoading;

  ui.Image? _backdrop;
  Timer? _timer;
  bool _capturing = false;
  bool _pendingCapture = false;
  bool _glEnabled = true;

  // shader 几何参数
  double _stripW = 0;
  double _stripH = 0;
  double _pillW = 0;
  double _pillH = 0;
  Offset _pillInStrip = Offset.zero;

  // ── 胶囊模式（方案A：玻璃面板 = 移动中的胶囊）──
  // 外部指定的截取窗口（全局坐标，覆盖胶囊动画全程路径）；null = 按自身位置截取
  Rect? _captureWindowGlobal;
  // 最近一次截取窗口的全局左上角（updatePillGeometry 用它算 shader 内偏移）
  Offset _clipGlobalOrigin = Offset.zero;
  // 几何变化通知（动画逐帧更新位置，不 setState 整树重建）
  final ValueNotifier<int> _geometryTick = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _loadProgram();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
      _timer = Timer.periodic(const Duration(milliseconds: 350), (_) => _capture());
    }
  }

  @override
  void didUpdateWidget(DispersionGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _capture());
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(milliseconds: 350), (_) => _capture());
    } else if (!widget.active && oldWidget.active) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _backdrop?.dispose();
    _geometryTick.dispose();
    super.dispose();
  }

  Future<void> _loadProgram() async {
    _programLoading ??= ui.FragmentProgram.fromAsset('shaders/nav_glass.frag');
    try {
      final p = await _programLoading;
      _program = p;
      AppLog.i('Glass', 'DispersionGlass: 自定义透镜色散 shader 生效 (nav_glass.frag v2)');
      if (mounted) setState(() {});
    } catch (e) {
      // shader 编译失败（老设备/降级环境）→ 回退 BackdropFilter 玻璃
      _glEnabled = false;
      AppLog.w('Glass', 'DispersionGlass: shader 加载失败，回退 BackdropFilter 玻璃: $e');
      if (mounted) setState(() {});
    }
  }

  /// 外部调用：立即刷新背景截取（切 tab / 导航出现时）
  void refresh() {
    _capture();
  }

  /// 设置胶囊动画的截取窗口（全局坐标，覆盖胶囊移动/跳起全程路径）。
  /// 之后胶囊移动时只更新 shader 偏移（updatePillGeometry），纹理不重新截取。
  /// 传 null 恢复为按自身位置截取。
  void setCaptureWindow(Rect? globalRect) {
    _captureWindowGlobal = globalRect;
    if (globalRect != null) _capture();
  }

  /// 动画逐帧更新胶囊几何（位置 + 尺寸），shader 内平移采样，零重新截取。
  void updatePillGeometry(Offset globalTopLeft, Size size) {
    _pillW = size.width;
    _pillH = size.height;
    _pillInStrip = Offset(
      globalTopLeft.dx - _clipGlobalOrigin.dx,
      globalTopLeft.dy - _clipGlobalOrigin.dy,
    );
    _geometryTick.value++;
  }

  Future<void> _capture() async {
    if (!mounted) return;
    // 截图进行中时，新请求标记 pending；当前截图完成后立即补一次最新窗口。
    // 避免点击/切 Tab 触发的路径截图被静默丢弃，导致胶囊玻璃显示旧页面内容。
    if (_capturing) {
      _pendingCapture = true;
      return;
    }
    final backdropBox = widget.backdropKey.currentContext?.findRenderObject();
    if (backdropBox is! RenderRepaintBoundary) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;

    // 面板全局矩形
    final pillGlobal = box.localToGlobal(Offset.zero) & box.size;
    // 截取条带：外部指定窗口优先（胶囊动画路径），否则按自身位置外扩光晕余量
    final strip = _captureWindowGlobal ??
        Rect.fromLTRB(
          pillGlobal.left - DispersionGlass.haloH,
          pillGlobal.top - DispersionGlass.haloV,
          pillGlobal.right + DispersionGlass.haloH,
          pillGlobal.bottom + DispersionGlass.haloV,
        );
    final backdropOrigin = backdropBox.localToGlobal(Offset.zero);
    final backdropRect = backdropOrigin & backdropBox.size;
    final clipped = strip.intersect(backdropRect);
    if (clipped.width <= 0 || clipped.height <= 0) return;
    final local = clipped.shift(-backdropOrigin);
    _clipGlobalOrigin = clipped.topLeft;

    _capturing = true;
    try {
      // 本版 SDK 的 RenderRepaintBoundary.toImage 不支持区域参数，
      // 直接走 OffsetLayer.toImage(bounds)（SDK 内部实现同样如此）
      // ignore: invalid_use_of_protected_member
      final layer = backdropBox.layer;
      if (layer is! OffsetLayer) return;
      final image = await layer.toImage(local, pixelRatio: DispersionGlass.capturePixelRatio);
      if (!mounted) {
        image.dispose();
        return;
      }
      _backdrop?.dispose();
      _backdrop = image;
      _pillW = box.size.width;
      _pillH = box.size.height;
      _pillInStrip = Offset(
        pillGlobal.left - clipped.left,
        pillGlobal.top - clipped.top,
      );
      _stripW = clipped.width;
      _stripH = clipped.height;
      setState(() {});
      _geometryTick.value++;
      AppLog.d('Glass',
          'DispersionGlass: 背景截取 ${_stripW.toStringAsFixed(0)}x${_stripH.toStringAsFixed(0)} @1.5x');
    } catch (_) {
      // 截取失败：保留旧帧（或保持回退态）
    } finally {
      _capturing = false;
      if (_pendingCapture && mounted) {
        // 期间有新请求：立即补一次最新截图，再清除 pending。
        _pendingCapture = false;
        _capture();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final useShader = _glEnabled &&
        _program != null &&
        _backdrop != null &&
        _stripW > 0 &&
        _stripH > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ── 玻璃层（几何逐帧更新走 ValueListenableBuilder，不整树重建）──
        if (useShader)
          Positioned(
            left: -DispersionGlass.haloH,
            top: -DispersionGlass.haloV,
            right: -DispersionGlass.haloH,
            bottom: -DispersionGlass.haloV,
            child: ValueListenableBuilder<int>(
              valueListenable: _geometryTick,
              builder: (_, __, ___) => CustomPaint(
                painter: _DispersionPainter(
                  program: _program!,
                  texture: _backdrop!,
                  texSize: Size(_stripW, _stripH),
                  pillSize: Size(_pillW, _pillH),
                  pillInStrip: _pillInStrip,
                  radius: widget.radius,
                  blur: widget.blur,
                  dispersion: widget.dispersion,
                  edgeGlow: widget.edgeGlow,
                  tint: widget.tint,
                  tintAlpha: widget.tintAlpha,
                  saturation: widget.saturation,
                ),
              ),
            ),
          ),
        // ── 回退玻璃（shader 不可用）：原 BackdropFilter 实现 ──
        if (!useShader)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.radius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(
                  sigmaX: GlassQuality.scaleBlur(24, context),
                  sigmaY: GlassQuality.scaleBlur(24, context),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        widget.tint.withValues(alpha: widget.tintAlpha),
                        widget.tint.withValues(alpha: widget.tintAlpha * 0.82),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: context.surfaceColor),
                  ),
                ),
              ),
            ),
          ),
        // ── 面板内容（圆角裁剪）──
        ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: widget.child,
        ),
      ],
    );
  }
}

/// 透镜色散绘制器：把背景纹理 + shader 画到条带区域
class _DispersionPainter extends CustomPainter {
  final ui.FragmentProgram program;
  final ui.Image texture;
  final Size texSize;
  final Size pillSize;
  final Offset pillInStrip;
  final double radius;
  final double blur;
  final double dispersion;
  final double edgeGlow;
  final Color tint;
  final double tintAlpha;
  final double saturation;

  _DispersionPainter({
    required this.program,
    required this.texture,
    required this.texSize,
    required this.pillSize,
    required this.pillInStrip,
    required this.radius,
    required this.blur,
    required this.dispersion,
    required this.edgeGlow,
    required this.tint,
    required this.tintAlpha,
    required this.saturation,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final shader = program.fragmentShader()
      // 按 shaders/nav_glass.frag 声明顺序绑定 uniform（先 float，sampler 最后）
      ..setFloat(0, texSize.width)
      ..setFloat(1, texSize.height)
      ..setFloat(2, pillSize.width)
      ..setFloat(3, pillSize.height)
      ..setFloat(4, pillInStrip.dx)
      ..setFloat(5, pillInStrip.dy)
      ..setFloat(6, radius)
      ..setFloat(7, blur)
      ..setFloat(8, dispersion)
      ..setFloat(9, edgeGlow)
      ..setFloat(10, 0.0) // u_time（噪点抖动可留 0）
      ..setFloat(11, tint.r / 255.0)
      ..setFloat(12, tint.g / 255.0)
      ..setFloat(13, tint.b / 255.0)
      ..setFloat(14, tintAlpha)
      ..setFloat(15, saturation)
      ..setImageSampler(16, texture);
    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _DispersionPainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.texSize != texSize ||
        oldDelegate.pillSize != pillSize ||
        oldDelegate.pillInStrip != pillInStrip ||
        oldDelegate.radius != radius ||
        oldDelegate.blur != blur ||
        oldDelegate.dispersion != dispersion ||
        oldDelegate.edgeGlow != edgeGlow ||        oldDelegate.tint != tint ||
        oldDelegate.tintAlpha != tintAlpha ||
        oldDelegate.saturation != saturation;
}
}
