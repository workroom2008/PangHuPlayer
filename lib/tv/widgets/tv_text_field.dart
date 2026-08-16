import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// TV 端专用 TextField — 两阶段交互
///
/// 阶段 1：导航聚焦（focused 但未编辑）
///   - 边框高亮，D-pad 可上下左右移动焦点
///   - 此时按方向键是移动焦点，不会输入
///
/// 阶段 2：编辑模式（editing）
///   - 按 Select/Enter 键进入编辑模式
///   - 弹出输入法，可输入文字
///   - 按返回键/确认键退出编辑模式，回到导航聚焦状态
class TvTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool obscureText;
  final bool autoFocus;
  final String focusId;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onEditingComplete;

  const TvTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.focusId,
    this.hintText,
    this.obscureText = false,
    this.autoFocus = false,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onEditingComplete,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  late FocusNode _navFocusNode; // 导航聚焦
  late FocusNode _editFocusNode; // 编辑聚焦
  bool _isNavFocused = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _navFocusNode = FocusNode(debugLabel: '${widget.focusId}_nav');
    _editFocusNode = FocusNode(debugLabel: '${widget.focusId}_edit');
    _navFocusNode.addListener(_onNavFocusChange);
    if (widget.autoFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navFocusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _navFocusNode.removeListener(_onNavFocusChange);
    _navFocusNode.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  void _onNavFocusChange() {
    if (!mounted) return;
    setState(() => _isNavFocused = _navFocusNode.hasFocus);
  }

  /// 进入编辑模式
  void _enterEditMode() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      // 强制唤起输入法
      SystemChannels.textInput.invokeMethod('TextInput.show');
    });
  }

  /// 退出编辑模式，回到导航聚焦
  void _exitEditMode() {
    _editFocusNode.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    setState(() => _isEditing = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navFocusNode.requestFocus();
    });
    widget.onEditingComplete?.call();
  }

  @override
  Widget build(BuildContext context) {
    // 编辑模式：实际的 TextField，可以输入
    if (_isEditing) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 2.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: KeyboardListener(
          focusNode: _editFocusNode,
          onKeyEvent: (event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.escape ||
                 event.logicalKey == LogicalKeyboardKey.goBack ||
                 event.logicalKey == LogicalKeyboardKey.keyZ)) {
              _exitEditMode();
            }
          },
          child: TextField(
            key: Key('${widget.focusId}_editor'),
            controller: widget.controller,
            autofocus: true,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              labelText: widget.label,
              labelStyle: const TextStyle(color: Colors.white, fontSize: 14),
              hintText: widget.hintText,
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onSubmitted: (_) => _exitEditMode(),
          ),
        ),
      );
    }

    // 导航模式：聚焦高亮，但不能输入
    return Focus(
      focusNode: _navFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          // 按确认键/回车键 → 进入编辑模式
          if (event.logicalKey == LogicalKeyboardKey.select ||
              event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.gameButtonA) {
            _enterEditMode();
            return KeyEventResult.handled;
          }
          // 方向键：交给上层焦点系统处理（移动焦点）
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _enterEditMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _isNavFocused ? 0.1 : 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isNavFocused ? Colors.white : Colors.white24,
              width: _isNavFocused ? 2.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: _isNavFocused ? Colors.white : Colors.white54,
                  fontSize: 13,
                  fontWeight: _isNavFocused ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: widget.controller.text.isEmpty
                        ? Text(
                            widget.hintText ?? '',
                            style: const TextStyle(color: Colors.white38, fontSize: 16),
                          )
                        : Text(
                            widget.obscureText
                                ? '•' * widget.controller.text.length
                                : widget.controller.text,
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                  ),
                  if (_isNavFocused)
                    const Icon(Icons.edit_rounded, color: Colors.white70, size: 18),
                ],
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
