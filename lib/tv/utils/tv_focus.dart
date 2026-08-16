import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvFocusManager {
  static final Map<String, FocusNode> _nodes = {};
  static String? _currentGroup;

  static FocusNode getNode(String id) {
    if (!_nodes.containsKey(id)) {
      _nodes[id] = FocusNode(debugLabel: id);
    }
    return _nodes[id]!;
  }

  static void disposeNode(String id) {
    _nodes[id]?.dispose();
    _nodes.remove(id);
  }

  static void setGroup(String group) {
    _currentGroup = group;
  }

  static String? get currentGroup => _currentGroup;

  static void clearGroup() {
    _currentGroup = null;
  }
}

class TvFocusScope extends StatelessWidget {
  final String groupId;
  final Widget child;
  final String? initialFocusId;
  final bool autoFocus;

  const TvFocusScope({
    super.key,
    required this.groupId,
    required this.child,
    this.initialFocusId,
    this.autoFocus = true,
  });

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      child: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (autoFocus && initialFocusId != null) {
              TvFocusManager.setGroup(groupId);
              final node = TvFocusManager.getNode(initialFocusId!);
              node.requestFocus();
            }
          });
          return child;
        },
      ),
    );
  }
}

class TvShortcuts extends StatelessWidget {
  final Widget child;
  final VoidCallback? onSelect;
  final VoidCallback? onBack;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final VoidCallback? onPlayPause;
  final VoidCallback? onFastForward;
  final VoidCallback? onRewind;

  /// 按键拦截器：在具体处理器之前调用。返回 true 表示已消费该按键（不再触发后续处理）。
  /// 典型用途：播放器控制条隐藏时，任意按键先唤出控制条。
  final bool Function(LogicalKeyboardKey key)? onAnyKey;

  const TvShortcuts({
    super.key,
    required this.child,
    this.onSelect,
    this.onBack,
    this.onUp,
    this.onDown,
    this.onLeft,
    this.onRight,
    this.onPlayPause,
    this.onFastForward,
    this.onRewind,
    this.onAnyKey,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;

        // 优先交给拦截器（如：控制条隐藏时任意键唤出）
        if (onAnyKey != null && onAnyKey!(event.logicalKey)) {
          return KeyEventResult.handled;
        }

        switch (event.logicalKey) {
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.gameButtonA:
            onSelect?.call();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.goBack:
          case LogicalKeyboardKey.escape:
          case LogicalKeyboardKey.gameButtonB:
            onBack?.call();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowUp:
            if (onUp == null) return KeyEventResult.ignored;
            onUp!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowDown:
            if (onDown == null) return KeyEventResult.ignored;
            onDown!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowLeft:
            if (onLeft == null) return KeyEventResult.ignored;
            onLeft!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.arrowRight:
            if (onRight == null) return KeyEventResult.ignored;
            onRight!();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.mediaPlayPause:
            onPlayPause?.call();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.mediaFastForward:
            onFastForward?.call();
            return KeyEventResult.handled;
          case LogicalKeyboardKey.mediaRewind:
            onRewind?.call();
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: child,
    );
  }
}


