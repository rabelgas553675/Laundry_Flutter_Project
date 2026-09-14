import 'package:flutter/material.dart';

enum AppButtonVariant { primary, secondary, outlined, text }

/// Shared button used across every form (Login, Register, Forgot
/// Password, etc.).
///
/// Visual approach: the primary variant now sits on a subtle
/// gradient (brand color → a slightly deeper step of the same hue)
/// with a soft colored glow beneath it, so it reads as the one
/// clearly "liftable" action on the screen rather than a flat block
/// of color. Secondary/outlined/text stay understated by comparison,
/// which keeps the visual hierarchy clear.
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
    final colorScheme = Theme.of(context).colorScheme;

    final child = widget.isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.variant == AppButtonVariant.outlined ||
                        widget.variant == AppButtonVariant.text
                    ? colorScheme.primary
                    : colorScheme.onPrimary,
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
        button = _GradientButton(
          onPressed: disabled ? null : widget.onPressed,
          disabled: disabled,
          baseColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          child: child,
        );
        break;
      case AppButtonVariant.secondary:
        button = _GradientButton(
          onPressed: disabled ? null : widget.onPressed,
          disabled: disabled,
          baseColor: colorScheme.secondary,
          foregroundColor: colorScheme.onSecondary,
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

/// Wraps an [ElevatedButton] in a gradient + soft glow shadow rather
/// than relying on the flat Material fill. The button itself stays
/// transparent with zero elevation so the outer gradient shows
/// through cleanly.
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.onPressed,
    required this.disabled,
    required this.baseColor,
    required this.foregroundColor,
    required this.child,
  });

  final VoidCallback? onPressed;
  final bool disabled;
  final Color baseColor;
  final Color foregroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: disabled
            ? null
            : LinearGradient(
                colors: [baseColor, Color.lerp(baseColor, Colors.black, 0.18)!],
              ),
        color: disabled ? baseColor.withValues(alpha: 0.35) : null,
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: baseColor.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: foregroundColor,
          disabledForegroundColor: foregroundColor.withValues(alpha: 0.7),
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: const StadiumBorder(),
        ),
        child: child,
      ),
    );
  }
}