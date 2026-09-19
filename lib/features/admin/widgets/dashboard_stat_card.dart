import 'package:flutter/material.dart';

import '../../../core/widgets/glass_container.dart';

/// One stat tile in the Admin Dashboard's stats grid (Total Users,
/// Total Orders, Pending Orders, Total Revenue).
///
/// ADMIN UI REFACTOR — PART 1: now a reusable *glass* stat card
/// (frosted [GlassContainer] instead of the flat Material [AppCard]
/// it used before) so it matches the same design system as the
/// existing User Dashboard.
///
/// Purely presentational: it never touches Firestore itself. The
/// screen that owns the data (`AdminDashboard`) computes [value] from
/// a live stream and passes it in, so this widget stays reusable for
/// any future stat tile without knowing anything about orders/users.
class DashboardStatCard extends StatelessWidget {
  const DashboardStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.iconColor,
    this.trend,
    this.onTap,
  });

  /// e.g. "Total Users".
  final String label;

  /// Pre-formatted display value, e.g. "128" or "₱4,320.00" — this
  /// widget does no number formatting of its own, so the caller
  /// decides currency vs. plain counts.
  final String value;

  final IconData icon;

  /// Defaults to the theme's primary color when omitted, so most call
  /// sites don't need to think about color at all.
  final Color? iconColor;

  /// Optional short trend/change label shown next to the icon (e.g.
  /// "+12%", "-3 today"). Kept optional and unused by the current
  /// dashboard so existing call sites need no changes; wired in here
  /// so a future call site can opt in without another widget change.
  final String? trend;

  /// Optional tap callback — e.g. jump to the relevant tab/section.
  /// Existing call sites don't pass one, so cards stay non-interactive
  /// by default exactly as before.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tint = iconColor ?? colors.primary;

    return GlassContainer(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      borderRadius: 20,
      blur: 18,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tint, size: 20),
              ),
              if (trend != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    trend!,
                    style: textTheme.bodySmall?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // FIX: wrapped in FittedBox(scaleDown) so the value shrinks
          // to fit the card's width instead of being cut off with an
          // ellipsis (e.g. "₱5,9..." now renders as "₱5,680" at a
          // slightly smaller size when the card is narrow).
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          // FIX: same treatment for the label so "Total Orders" /
          // "Pending Orders" render in full instead of "Total Ord..."
          // / "Pending ...".
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(color: Colors.black54),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}