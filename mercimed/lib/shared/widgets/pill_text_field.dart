import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PillTextField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final IconData? icon;
  final bool hasError;

  const PillTextField({
    required this.controller,
    this.focusNode,
    required this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.icon,
    this.hasError = false,
    super.key,
  });

  @override
  State<PillTextField> createState() => _PillTextFieldState();
}

class _PillTextFieldState extends State<PillTextField> {
  late final FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
    _focusNode.addListener(_onFocusChange);
    _obscure = widget.obscureText;
  }

  void _onFocusChange() {
    if (_focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.hasError
        ? const Color(0xFFD64B4B)
        : _focused
            ? AppTheme.teal
            : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: borderColor, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: _focused
                ? AppTheme.teal.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: _focused ? 22 : 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            const SizedBox(width: 18),
            Icon(
              widget.icon,
              size: 20,
              color: _focused ? AppTheme.teal : AppTheme.muted,
            ),
          ],
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              obscureText: widget.obscureText && _obscure,
              keyboardType: widget.keyboardType,
              textInputAction: widget.textInputAction,
              onSubmitted: widget.onSubmitted,
              autocorrect: false,
              style: const TextStyle(
                color: AppTheme.primaryDark,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 16,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.only(
                  left: widget.icon == null ? 22 : 14,
                  right: widget.obscureText ? 4 : 22,
                  top: 18,
                  bottom: 18,
                ),
              ),
            ),
          ),
          if (widget.obscureText)
            IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 20,
                color: AppTheme.muted,
              ),
              splashRadius: 22,
              onPressed: () => setState(() => _obscure = !_obscure),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
