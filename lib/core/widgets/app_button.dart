import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, outlined, text }

class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.fullWidth = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final bool fullWidth;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onPressed == null || widget.isLoading;

    final child = widget.isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.variant == AppButtonVariant.outlined ||
                        widget.variant == AppButtonVariant.text
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );

    Widget button;
    switch (widget.variant) {
      case AppButtonVariant.primary:
        button = ElevatedButton(onPressed: disabled ? null : widget.onPressed, child: child);
        break;
      case AppButtonVariant.secondary:
        button = ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.secondary,
            foregroundColor: Theme.of(context).colorScheme.onSecondary,
          ),
          onPressed: disabled ? null : widget.onPressed,
          child: child,
        );
        break;
      case AppButtonVariant.outlined:
        button = OutlinedButton(onPressed: disabled ? null : widget.onPressed, child: child);
        break;
      case AppButtonVariant.text:
        button = TextButton(onPressed: disabled ? null : widget.onPressed, child: child);
        break;
    }

    return widget.fullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}