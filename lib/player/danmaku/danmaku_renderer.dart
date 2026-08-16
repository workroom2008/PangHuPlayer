import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../theme/app_theme.dart';
import '../../services/danmaku_service.dart';
import 'danmaku_models.dart';

/// 弹幕渲染层（StatefulWidget，内部持有 painter 并监听 tickNotifier）
///
/// 性能优化：
/// - 不通过 ValueListenableBuilder 重建 widget 树，直接调用 painter.notifyListeners() 触发重绘
/// - RepaintBoundary 隔离重绘区域，避免影响视频和控制层
/// - 屏幕外的弹幕跳过绘制
class DanmakuRenderer extends StatefulWidget {
  final ValueListenable<int> tickNotifier;
  final List<ActiveDanmaku> Function() getActiveDanmaku;
  final double screenWidth;
  final double screenHeight;
  final double displayArea; // 弹幕显示区域（0.5~1.0）

  const DanmakuRenderer({
    super.key,
    required this.tickNotifier,
    required this.getActiveDanmaku,
    required this.screenWidth,
    required this.screenHeight,
    this.displayArea = 1.0,
  });

  @override
  State<DanmakuRenderer> createState() => _DanmakuRendererState();
}

class _DanmakuRendererState extends State<DanmakuRenderer> {
  late final DanmakuPainter _painter;
  final _repaintNotifier = ChangeNotifier();

  @override
  void initState() {
    super.initState();
    _painter = DanmakuPainter(
      getActiveDanmaku: widget.getActiveDanmaku,
      screenWidth: widget.screenWidth,
      screenHeight: widget.screenHeight,
      displayArea: widget.displayArea,
      repaint: _repaintNotifier,
    );
    widget.tickNotifier.addListener(_onTick);
  }

  @override
  void didUpdateWidget(DanmakuRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tickNotifier != widget.tickNotifier) {
      oldWidget.tickNotifier.removeListener(_onTick);
      widget.tickNotifier.addListener(_onTick);
    }
    _painter.screenWidth = widget.screenWidth;
    _painter.screenHeight = widget.screenHeight;
    _painter.displayArea = widget.displayArea;
  }

  void _onTick() {
    _repaintNotifier.notifyListeners();
  }

  @override
  void dispose() {
    widget.tickNotifier.removeListener(_onTick);
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _painter,
        size: Size(widget.screenWidth, widget.screenHeight),
      ),
    );
  }
}

/// 弹幕画笔
///
/// 直接从 controller 回调获取活动弹幕列表，通过 notifyListeners() 触发重绘。
/// 屏幕外的弹幕跳过绘制以减少 GPU 填充率开销。
class DanmakuPainter extends CustomPainter {
  final List<ActiveDanmaku> Function() getActiveDanmaku;
  double screenWidth;
  double screenHeight;
  double displayArea;

  DanmakuPainter({
    required this.getActiveDanmaku,
    required this.screenWidth,
    required this.screenHeight,
    this.displayArea = 1.0,
    Listenable? repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final activeDanmaku = getActiveDanmaku();
    if (activeDanmaku.isEmpty) return;

    final w = screenWidth > 0 ? screenWidth : size.width;
    final h = screenHeight > 0 ? screenHeight : size.height;

    // 弹幕显示区域：限制在屏幕上部 displayArea 比例内（0.5~1.0）
    final area = displayArea.clamp(0.5, 1.0);
    final areaBottom = h * area;
    final areaTop = h - areaBottom;

    for (final d in activeDanmaku) {
      final trackHeight = d.fontSize * AppTheme.danmakuTrackHeightRatio;
      double left;
      double top;

      switch (d.danmaku.type) {
        case DanmakuType.top:
          left = (w - d.width) / 2;
          top = 40 + d.track * trackHeight;
          if (top + trackHeight > areaBottom) continue;
          break;
        case DanmakuType.bottom:
          left = (w - d.width) / 2;
          top = h - 40 - (d.track + 1) * trackHeight;
          // 底部弹幕只在显示区域内绘制（区域缩小时从底部向上收窄）
          if (top < areaTop || top < h * 0.5) continue;
          break;
        case DanmakuType.scroll:
          left = d.offset;
          top = 40 + d.track * trackHeight;
          if (top + trackHeight > areaBottom) continue;
          // 完全在屏幕外的跳过绘制（减少 GPU 填充率）
          if (left + d.width < 0 || left > w) continue;
          break;
      }

      canvas.save();
      canvas.translate(left, top);
      d.painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant DanmakuPainter oldDelegate) {
    return false;
  }
}
