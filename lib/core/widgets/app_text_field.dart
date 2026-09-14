import 'package:flutter/material.dart';

import '../../app/constants.dart';

/// Shared text field used across every form in the app (Login,
/// Register, Forgot Password, profile editing, etc.).
///
/// Visual approach: rather than a flat outlined pill, the field sits
/// on its own soft shadow ("floating card") with no border in its
/// resting state — the shadow alone defines its edges. A teal ring
/// appears only on focus, and the label/prefix icon pick up the brand
/// color so filled-in forms feel a little more considered than plain
/// gray-bordered inputs.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.isPassword = false,
    this.keyboardType,
    this.validator,
    this.prefixIcon,
    this.maxLines = 1,
    this.enabled = true,
    this.textInputAction,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final bool isPassword;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  final int maxLines;
  final bool enabled;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppConstants.radiusLg);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: _isFocused
                ? colorScheme.primary.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: _isFocused ? 18 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: TextFormField(
          controller: widget.controller,
          obscureText: widget.isPassword ? _obscure : false,
          keyboardType: widget.keyboardType,
          validator: widget.validator,
          maxLines: widget.isPassword ? 1 : widget.maxLines,
          enabled: widget.enabled,
          textInputAction: widget.textInputAction,
          onChanged: widget.onChanged,
          style: const TextStyle(fontSize: 15.5),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            filled: true,
            fillColor: colorScheme.surface,
            prefixIcon: widget.prefixIcon != null
                ? Icon(
                    widget.prefixIcon,
                    size: 20,
                    color: _isFocused
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  )
                : null,
            suffixIcon: widget.isPassword
                ? IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colorScheme.error, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: colorScheme.error, width: 1.6),
            ),
          ),
        ),
      ),
    );
  }
}