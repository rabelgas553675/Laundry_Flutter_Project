import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_card.dart';
import '../../../models/order_model.dart';

/// PART 13 — a single row in "My Orders": order number, service,
/// weight, total, date, and a status pill. Tapping it is the only
/// way into [OrderDetailsScreen]; the tap callback is owned by the
/// parent screen so navigation stays out of this widget.
class OrderListTile extends StatelessWidget {
  const OrderListTile({super.key, required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final status = OrderStatusStyle.of(order.status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.orderNumber,
                    style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.serviceName} · ${order.weight.toStringAsFixed(1)} kg',
                    style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// PART 13 — maps an [OrderStatus] to a label and color, shared by
/// the list tile and the details screen so both always agree on what
/// each status looks like.
class OrderStatusStyle {
  const OrderStatusStyle(this.label, this.color);

  final String label;
  final Color color;

  static OrderStatusStyle of(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const OrderStatusStyle('Pending', Colors.orange);
      case OrderStatus.received:
        return const OrderStatusStyle('Received', Colors.blue);
      case OrderStatus.washing:
        return const OrderStatusStyle('Washing', Colors.indigo);
      case OrderStatus.drying:
        return const OrderStatusStyle('Drying', Colors.teal);
      case OrderStatus.ready:
        return const OrderStatusStyle('Ready', Colors.green);
      case OrderStatus.completed:
        return const OrderStatusStyle('Completed', Colors.grey);
      case OrderStatus.cancelled:
        return const OrderStatusStyle('Cancelled', Colors.red);
    }
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
        style: TextStyle(
          color: style.color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// Manual date formatting to avoid pulling in `intl` for one line of
/// text — "Sep 12, 2026 · 3:45 PM". [date] is nullable because
/// [OrderModel.createdAt] is null for the brief moment between a
/// write and the server timestamp round-tripping back down; shared
/// with `order_details_screen.dart` so both fall back identically.
String formatOrderDate(DateTime? date) {
  if (date == null) return 'Just now';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
  final period = date.hour >= 12 ? 'PM' : 'AM';
  final minute = date.minute.toString().padLeft(2, '0');
  return '${months[date.month - 1]} ${date.day}, ${date.year} · $hour12:$minute $period';
}