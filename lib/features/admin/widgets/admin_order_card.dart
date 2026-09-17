import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_card.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import '../../user/widgets/order_list_tile.dart' show OrderStatusStyle, formatOrderDate;

/// PART 16 — a single row in [ManageOrdersScreen]'s order list.
///
/// Deliberately its own widget (rather than reusing PART 13's
/// [OrderListTile]) because an Admin needs to see *whose* order this
/// is at a glance — [OrderListTile] has no concept of a customer,
/// since a customer viewing "My Orders" already knows it's theirs.
/// Everything else (status pill, formatted date, formatted currency)
/// intentionally reuses the exact same helpers as the customer-facing
/// tile so a status/date/amount always looks identical everywhere in
/// the app.
///
/// Purely presentational — it never touches Firestore. The customer
/// lookup ([customer]) is done once by [ManageOrdersScreen] from its
/// joined orders+users streams, not per-card, so scrolling a long
/// order list never triggers extra reads.
class AdminOrderCard extends StatelessWidget {
  const AdminOrderCard({
    super.key,
    required this.order,
    required this.customer,
    required this.onTap,
  });

  final OrderModel order;

  /// Null when the customer's user document couldn't be matched
  /// (e.g. the account was deleted after placing the order) — the
  /// card falls back to showing the raw [OrderModel.userId] instead
  /// of silently hiding who placed the order.
  final UserModel? customer;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final status = OrderStatusStyle.of(order.status);
    final customerLabel = customer?.name.isNotEmpty == true
        ? customer!.name
        : (customer?.email ?? 'Unknown customer (${order.userId})');

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colors.primaryContainer,
              backgroundImage: customer?.profileImageUrl != null
                  ? NetworkImage(customer!.profileImageUrl!)
                  : null,
              child: customer?.profileImageUrl == null
                  ? Text(customerLabel.isNotEmpty ? customerLabel[0].toUpperCase() : '?')
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber,
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    customerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    // PART 3/5 fix — same "0 pcs" bug as
                    // `order_list_tile.dart`'s customer-facing tile:
                    // an itemized (Dry Cleaning) order's `weight` is
                    // always 0, so show the garment count instead.
                    '${order.serviceName} · '
                    '${order.isItemized ? '${order.items.length} item type(s)' : ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight)}',
                    style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatOrderDate(order.createdAt),
                    style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  PriceCalculator.formatCurrency(order.total),
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _StatusPill(style: status),
                const SizedBox(height: 6),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.style});

  final OrderStatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        style.label,
        style: TextStyle(color: style.color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}