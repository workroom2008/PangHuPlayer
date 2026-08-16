import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../models/media_models.dart';

class ServerSelectorChip extends ConsumerStatefulWidget {
  const ServerSelectorChip({super.key});

  @override
  ConsumerState<ServerSelectorChip> createState() => _ServerSelectorChipState();
}

class _ServerSelectorChipState extends ConsumerState<ServerSelectorChip> with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _showOverlay();
      _animationController.forward();
    } else {
      _animationController.reverse().then((_) {
        _hideOverlay();
      });
    }
  }

  void _showOverlay() {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // 点击空白区域关闭
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleExpanded,
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(
            left: position.dx,
            top: position.dy + size.height + 8,
            child: Material(
              color: Colors.transparent,
              child: _buildServerList(),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    setState(() => _isExpanded = false);
  }

  Widget _buildServerList() {
    final servers = ref.watch(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull;

    // 计算面板宽度（取最长的服务器名称）
    double maxWidth = 160.0;
    for (final s in servers) {
      final textWidth = _calculateTextWidth(s.name);
      maxWidth = max<double>(maxWidth, textWidth + 60.0);
    }

    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          alignment: Alignment.topLeft,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(16),
              color: Theme.of(context).cardColor,
              child: SizedBox(
                width: maxWidth,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      final isSelected = server.id == defaultServer?.id;
                      return InkWell(
                        onTap: () {
                          ref.read(mediaServersProvider.notifier).setDefaultServer(server.id);
                          _toggleExpanded();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                server.type == ServerType.emby
                                    ? Icons.language
                                    : server.type == ServerType.jellyfin
                                        ? Icons.video_library
                                        : server.type == ServerType.fnos
                                            ? Icons.dns
                                            : server.type == ServerType.plex
                                                ? Icons.cast
                                                : Icons.movie,
                                size: 18,
                                color: isSelected ? AppTheme.primary : Theme.of(context).textTheme.bodySmall?.color,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  server.name,
                                  style: TextStyle(
                                    color: isSelected ? Theme.of(context).textTheme.bodyLarge?.color : Theme.of(context).textTheme.bodySmall?.color,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check, size: 18, color: AppTheme.primary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _calculateTextWidth(String text) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return textPainter.width;
  }

  @override
  Widget build(BuildContext context) {
    final servers = ref.watch(mediaServersProvider);
    final defaultServer = servers.where((s) => s.isDefault).firstOrNull ?? servers.firstOrNull;

    // 计算按钮宽度
    final textWidth = defaultServer != null ? _calculateTextWidth(defaultServer.name) : 80.0;
    final computedWidth = max<double>(60.0, textWidth + 48.0);

    return CompositedTransformTarget(
      link: _layerLink,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
        width: computedWidth,
        child: GestureDetector(
          onTap: _toggleExpanded,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).textTheme.bodyLarge!.color!.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  defaultServer?.name ?? '选择服务器',
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
