import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../services/media_server_service.dart';

/// Netflix 风格自定义进度条
/// 常态细线 → 触摸膨胀 → 拖动时显示缩略图预览 + 时间气泡
class CustomProgressBar extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final Duration buffer;
  final bool canSeek;
  final ValueChanged<double> onSeekStart;
  final ValueChanged<double> onSeekUpdate;
  final ValueChanged<double> onSeekEnd;
  final String Function(Duration) formatTime;
  final int? seasonNumber;
  final int? episodeNumber;

  /// 章节标记（毫秒位置），在进度条上绘制 tick 标记点
  final List<int> chapterMarkers;

  /// 弹幕热力图密度（已归一化 0~1，按 [heatmapBucketMs] 分桶的缓存数组）。
  /// 数据在弹幕加载时预计算一次，绘制时 O(1) 查桶 —— 不逐帧重算
  final List<double>? heatmap;
  final int heatmapBucketMs;

  /// Trickplay 缩略图提供者
  /// 入参: 当前 seek 时间（毫秒）
  /// 返回: TrickplayTile（精灵图 URL + 网格定位），null 表示无缩略图
  final TrickplayTile? Function(int positionMs)? thumbnailProvider;

  const CustomProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    required this.canSeek,
    required this.onSeekStart,
    required this.onSeekUpdate,
    required this.onSeekEnd,
    required this.formatTime,
    this.seasonNumber,
    this.episodeNumber,
    this.chapterMarkers = const [],
    this.heatmap,
    this.heatmapBucketMs = 10000,
    this.thumbnailProvider,
  });

  @override
  State<CustomProgressBar> createState() => CustomProgressBarState();
}

class CustomProgressBarState extends State<CustomProgressBar>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _isHovering = false;
  double _dragValue = 0;
  double _hoverValue = 0;
  TrickplayTile? _thumbnailTile;

  static const double _thumbWidth = 160;
  static const double _thumbHeight = 90;

  late AnimationController _expandController;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _expandAnim = CurvedAnimation(
      parent: _expandController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    super.dispose();
  }

  void _expand() => _expandController.forward();
  void _shrink() {
    if (!_isDragging) _expandController.reverse();
  }

  double _calcValue(Offset local, double width) {
    final dx = local.dx.clamp(0.0, width);
    return width > 0 ? dx / width : 0.0;
  }

  void _onDragStart(DragStartDetails d, double width) {
    if (!widget.canSeek) return;
    setState(() => _isDragging = true);
    _expand();
    _dragValue = _calcValue(d.localPosition, width);
    _updateThumbnailUrl(_dragValue);
    widget.onSeekStart(_dragValue);
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (!widget.canSeek || !_isDragging) return;
    _dragValue = _calcValue(d.localPosition, width);
    _updateThumbnailUrl(_dragValue);
    widget.onSeekUpdate(_dragValue);
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    _shrink();
    widget.onSeekEnd(_dragValue);
  }

  Duration get _displayDuration {
    if (_isDragging && widget.duration > Duration.zero) {
      return Duration(
        milliseconds: (_dragValue * widget.duration.inMilliseconds).round(),
      );
    }
    return widget.position;
  }

  void _updateThumbnailUrl(double value) {
    if (widget.thumbnailProvider == null || widget.duration <= Duration.zero) return;
    final positionMs = (value * widget.duration.inMilliseconds).round();
    final tile = widget.thumbnailProvider!(positionMs);
    if (tile?.spriteSheetUrl != _thumbnailTile?.spriteSheetUrl ||
        tile?.col != _thumbnailTile?.col ||
        tile?.row != _thumbnailTile?.row) {
      setState(() => _thumbnailTile = tile);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.duration.inMilliseconds > 0
        ? (_isDragging
            ? _dragValue
            : (widget.position.inMilliseconds / widget.duration.inMilliseconds)
                .clamp(0.0, 1.0))
        : 0.0;
    final buffered = widget.duration.inMilliseconds > 0
        ? (widget.buffer.inMilliseconds / widget.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    final showThumbnail = _isDragging &&
        _thumbnailTile != null &&
        widget.thumbnailProvider != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── 时间标签 + 进度条 + 时长 ──
        Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                widget.formatTime(widget.position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.left,
              ),
            ),
            if (widget.seasonNumber != null && widget.episodeNumber != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'S${widget.seasonNumber}\u00B7E${widget.episodeNumber}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
            const SizedBox(width: 8),
            // 进度条主体
            Expanded(
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final barWidth = constraints.maxWidth;
                  // 拖拽/悬停位置：缩略图与时间气泡跟随该位置（Netflix/Streama 式）
                  final dragX = _isDragging ? _dragValue * barWidth : _hoverValue * barWidth;
                  final thumbHalf = _thumbWidth / 2;
                  final thumbLeft = barWidth < _thumbWidth
                      ? (barWidth - _thumbWidth) / 2
                      : (dragX - thumbHalf).clamp(-thumbHalf * 0.5, barWidth - thumbHalf * 1.5);
                  const bubbleWidth = 72.0;
                  final bubbleLeft = barWidth <= bubbleWidth
                      ? 0.0
                      : (dragX - bubbleWidth / 2).clamp(0.0, barWidth - bubbleWidth);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GestureDetector(
                        onHorizontalDragStart: (d) => _onDragStart(d, barWidth),
                        onHorizontalDragUpdate: (d) => _onDragUpdate(d, barWidth),
                        onHorizontalDragEnd: _onDragEnd,
                        onTapDown: (d) {
                          if (!widget.canSeek) return;
                          final v = _calcValue(d.localPosition, barWidth);
                          _dragValue = v;
                          _updateThumbnailUrl(v);
                          widget.onSeekStart(v);
                          widget.onSeekUpdate(v);
                        },
                        onTapUp: (d) {
                          if (!widget.canSeek) return;
                          final v = _calcValue(d.localPosition, barWidth);
                          widget.onSeekEnd(v);
                        },
                        child: MouseRegion(
                          onEnter: (_) {
                            setState(() => _isHovering = true);
                            _expand();
                          },
                          onExit: (_) {
                            setState(() => _isHovering = false);
                            _shrink();
                          },
                          onHover: (d) {
                            _hoverValue = _calcValue(d.localPosition, barWidth);
                          },
                          child: AnimatedBuilder(
                            animation: _expandAnim,
                            builder: (_, __) => CustomPaint(
                              size: const Size(double.infinity, 24),
                              painter: _ProgressBarPainter(
                                progress: progress,
                                buffered: buffered,
                                expandProgress: _expandAnim.value,
                                isDragging: _isDragging,
                                isHovering: _isHovering,
                                hoverValue: _hoverValue,
                                dragValue: _dragValue,
                                markers: widget.duration.inMilliseconds > 0
                                    ? widget.chapterMarkers
                                        .map((ms) => (ms / widget.duration.inMilliseconds).clamp(0.0, 1.0))
                                        .toList()
                                    : const <double>[],
                                heatmap: widget.heatmap,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── 缩略图预览：跟随拖拽位置，向上浮出到画面 ──
                      if (showThumbnail)
                        Positioned(
                          left: thumbLeft,
                          bottom: 64,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              width: _thumbWidth,
                              height: _thumbHeight,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: _TrickplayTileWidget(
                                tile: _thumbnailTile!,
                                width: _thumbWidth,
                                height: _thumbHeight,
                              ),
                            ),
                          ),
                        ),
                      // ── 时间气泡：跟随拖拽位置（默认 0 透明度，不拦截触摸）──
                      Positioned(
                        left: bubbleLeft,
                        bottom: 30,
                        child: AnimatedOpacity(
                          opacity: _isDragging ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: Text(
                              widget.formatTime(_displayDuration),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                widget.formatTime(widget.duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double progress;
  final double buffered;
  final double expandProgress;
  final bool isDragging;
  final bool isHovering;
  final double hoverValue;
  final double dragValue;
  final List<double> markers;
  final List<double>? heatmap;

  _ProgressBarPainter({
    required this.progress,
    required this.buffered,
    required this.expandProgress,
    required this.isDragging,
    required this.isHovering,
    required this.hoverValue,
    required this.dragValue,
    this.markers = const [],
    this.heatmap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackWidth = size.width;

    // 轨道高度: 常态 3px 细线 → 触摸/悬停膨胀 8px（Netflix 交互细节）
    final trackHeight = 3.0 + 5.0 * expandProgress;
    // 缩略点半径: 常态 0 (隐藏) → 膨胀 7px → 拖拽 9px
    final thumbRadius = isDragging ? 9.0 : 7.0 * expandProgress;
    final top = centerY - trackHeight / 2;

    // 1. 背景轨道
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, trackWidth, trackHeight),
        Radius.circular(trackHeight / 2),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.2),
    );

    // 2. 缓冲进度
    if (buffered > 0) {
      final bufW = trackWidth * buffered.clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, bufW, trackHeight),
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.35),
      );
    }

    // 3. 已播放进度
    final activeW = trackWidth * progress.clamp(0.0, 1.0);
    if (activeW > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, activeW, trackHeight),
          Radius.circular(trackHeight / 2),
        ),
        Paint()..color = AppTheme.primary,
      );
    }

    // 4. 缩略点
    if (thumbRadius > 0.5) {
      final thumbX = (progress * trackWidth).clamp(0.0, trackWidth);
      // 白色填充
      canvas.drawCircle(
        Offset(thumbX, centerY),
        thumbRadius,
        Paint()..color = Colors.white,
      );
      // 拖拽时的外圈光晕
      if (isDragging) {
        canvas.drawCircle(
          Offset(thumbX, centerY),
          thumbRadius + 4,
          Paint()..color = AppTheme.primary.withValues(alpha: 0.3),
        );
      }
    }

    // 4.5 弹幕热力色带（进度条上方；密度分桶缓存，O(1) 查表 + 一次渐变绘制，
    //      不逐帧重算。低密度=淡紫，高密度=亮紫，B 站/DFM 式密度提示）
    final hm = heatmap;
    if (hm != null && hm.isNotEmpty && trackWidth > 0) {
      final bandTop = centerY - trackHeight / 2 - 7.0;
      const bandHeight = 3.0;
      final lastIdx = hm.length - 1;
      final colors = <Color>[];
      final stops = <double>[];
      for (int i = 0; i < hm.length; i++) {
        colors.add(Color.lerp(
          AppTheme.primary.withValues(alpha: 0.10),
          AppTheme.primary,
          hm[i],
        )!);
        stops.add(lastIdx > 0 ? i / lastIdx : 0.0);
      }
      final shader = ui.Gradient.linear(
        Offset.zero,
        Offset(trackWidth, 0),
        colors,
        stops,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, bandTop, trackWidth, bandHeight),
          Radius.circular(bandHeight / 2),
        ),
        Paint()..shader = shader,
      );
    }

    // 5. 章节标记点（竖线 tick，参考 Streama 进度条标记）
    for (final m in markers) {
      final mx = (m * trackWidth).clamp(0.0, trackWidth);
      canvas.drawLine(
        Offset(mx, centerY - 6),
        Offset(mx, centerY + 6),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.75)
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round,
      );
    }

    // 6. 悬停指示线
    if (isHovering && !isDragging) {
      final hx = hoverValue * trackWidth;
      canvas.drawLine(
        Offset(hx, centerY - 8),
        Offset(hx, centerY + 8),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressBarPainter old) =>
      old.progress != progress ||
      old.buffered != buffered ||
      old.expandProgress != expandProgress ||
      old.isDragging != isDragging ||
      old.isHovering != isHovering ||
      old.hoverValue != hoverValue ||
      old.dragValue != dragValue ||
      old.markers.length != markers.length ||
      old.heatmap != heatmap;
}

/// 从精灵图中裁剪出单张缩略图进行渲染
///
/// 原理：将完整精灵图放大到 (gridWidth * tileWidth) x (gridHeight * tileHeight)
/// 然后通过 ClipRect 裁剪出 (col, row) 位置的单张缩略图
class _TrickplayTileWidget extends StatelessWidget {
  final TrickplayTile tile;
  final double width;
  final double height;

  const _TrickplayTileWidget({
    required this.tile,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: SizedBox(
        width: width,
        height: height,
        child: OverflowBox(
          maxWidth: width * tile.gridWidth,
          maxHeight: height * tile.gridHeight,
          alignment: Alignment(
            tile.gridWidth > 1
                ? (tile.col * 2.0 / (tile.gridWidth - 1) - 1)
                : 0,
            tile.gridHeight > 1
                ? (tile.row * 2.0 / (tile.gridHeight - 1) - 1)
                : 0,
          ),
          child: CachedNetworkImage(
            imageUrl: tile.spriteSheetUrl,
            width: width * tile.gridWidth,
            height: height * tile.gridHeight,
            fit: BoxFit.fill,
            memCacheWidth: (320 * tile.gridWidth),
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
