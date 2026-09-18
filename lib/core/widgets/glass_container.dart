import 'dart:ui';

import 'package:flutter/material.dart';

/// Shared frosted-glass surface: a blurred, low-alpha white panel with
/// a soft border and a floating shadow.
///
/// ADMIN UI REFACTOR — PART 1. Several screens already hand-roll this
/// exact recipe as private, near-identical widgets (e.g.
/// `UserDashboard`'s `_DashboardAppBar`/`_DashboardBottomNav`,
/// `CurrentOffersSection`'s `_GlassPanel`, `ServiceSelectionCard`'s
/// own panel). This is the first *shared* version of that recipe —
/// one reusable component instead of another one-off copy — starting
/// with the Admin section's dashboard and, in later parts, its
/// orders/services/users/promos/reports screens.
///
/// Kept deliberately generic (child/padding/margin/radius/blur/
/// background/border/shadow, plus an optional [onTap]) so it can
/// stand in for a plain [Card] pretty much anywhere: a stat tile, a
/// list row, a section panel, a dialog surface, etc.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 20,
    this.blur = 20,
    this.backgroundColor,
    this.backgroundOpacity = 0.28,
    this.gradientOpacity,
    this.borderColor,
    this.borderOpacity = 0.5,
    this.borderWidth = 1,
    this.shadow = true,
    this.onTap,
  });

  /// Content shown inside the glass panel.
  final Widget child;

  /// Padding applied *inside* the glass panel, around [child].
  final EdgeInsetsGeometry padding;

  /// Space around the outside of the glass panel itself.
  final EdgeInsetsGeometry? margin;

  /// Corner radius of the panel, its clip, and its ripple (when
  /// [onTap] is set).
  final double borderRadius;

  /// Backdrop blur strength (sigma, both axes). Kept moderate by
  /// default — see PERFORMANCE note in the Part 1 spec: avoid
  /// excessive blur, especially in scrolling lists.
  final double blur;

  /// Base tint color for the glass fill. Defaults to white, which is
  /// what every existing glass surface in this app uses; a non-white
  /// tint stays available for e.g. status-colored panels later.
  final Color? backgroundColor;

  /// Alpha of [backgroundColor] at the panel's top-left corner.
  final double backgroundOpacity;

  /// Alpha of [backgroundColor] at the panel's bottom-right corner.
  /// Defaults to a fraction of [backgroundOpacity] so the fill reads
  /// as a soft diagonal gradient rather than a flat tint, matching
  /// the existing hand-rolled glass panels. Pass equal to
  /// [backgroundOpacity] for a flat fill instead.
  final double? gradientOpacity;

  /// Border tint. Defaults to white, same reasoning as
  /// [backgroundColor].
  final Color? borderColor;

  final double borderOpacity;
  final double borderWidth;

  /// Whether to draw the soft drop shadow beneath the panel. Panels
  /// stacked closely together (e.g. grid cells) may want this off to
  /// avoid muddy overlapping shadows.
  final bool shadow;

  /// When set, the whole panel becomes tappable with a Material ink
  /// ripple clipped to [borderRadius].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = backgroundColor ?? Colors.white;
    final border = borderColor ?? Colors.white;
    final radius = BorderRadius.circular(borderRadius);

    final decoration = BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          base.withValues(alpha: backgroundOpacity),
          base.withValues(alpha: gradientOpacity ?? (backgroundOpacity * 0.42)),
        ],
      ),
      borderRadius: radius,
      border: Border.all(
        color: border.withValues(alpha: borderOpacity),
        width: borderWidth,
      ),
      boxShadow: shadow
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 26,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );

    final content = Padding(padding: padding, child: child);

    Widget panel = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: decoration,
          child: onTap == null
              ? content
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onTap,
                    borderRadius: radius,
                    child: content,
                  ),
                ),
        ),
      ),
    );

    if (margin != null) {
      panel = Padding(padding: margin!, child: panel);
    }

    return panel;
  }
}