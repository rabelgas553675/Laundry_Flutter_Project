import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';

/// PART 15 — one stat tile in the Admin Dashboard's stats grid
/// (Total Users, Total Orders, Pending Orders, Total Revenue).
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: iconColor ?? colors.primary, size: 26),
          const SizedBox(height: 10),
          Text(
            value,
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}