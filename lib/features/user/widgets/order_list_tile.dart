import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../models/order_model.dart';

/// PART 13 — a single row in "My Orders": order number, service,
/// weight, total, date, and a status pill.
///
/// Redesigned to match the dashboard's frosted-glass language
/// (see `user_dashboard.dart`): a blurred translucent-white card with
/// a soft border, drop shadow, and a colored accent stripe on the
/// left, instead of a plain [AppCard]. Tapping it is the only way
/// into [OrderDetailsScreen]; the tap callback is owned by the parent
/// screen so navigation stays out of this widget.
class OrderListTile extends StatelessWidget {
  const OrderListTile({super.key, required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final status = OrderStatusStyle.of(order.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Material(
            color: Colors.white.withValues(alpha: 0.22),
            child: InkWell(
              onTap: onTap,
              splashColor: colors.primary.withValues(alpha: 0.08),
              highlightColor: colors.primary.withValues(alpha: 0.04),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Accent stripe — mirrors the app bar's left
                      // accent bar, colored by order status so the
                      // whole list reads at a glance.
                      Container(
                        width: 4,
                        decoration: BoxDecoration(
                          color: status.color,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            bottomLeft: Radius.circular(20),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      order.orderNumber,
                                      style: textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      // PART 3/5 fix — an itemized
                                      // (Dry Cleaning) order's
                                      // `weight` is always 0 (it's
                                      // priced per garment, not by
                                      // weight — see
                                      // `OrderRepository.createOrder`),
                                      // so running it through
                                      // `formatQuantity` would show
                                      // every Dry Cleaning order as
                                      // "Dry Cleaning · 0 pcs". Show
                                      // the garment count instead,
                                      // matching the same fix already
                                      // applied in
                                      // `order_summary_screen.dart`'s
                                      // confirm dialog and
                                      // `order_details_screen.dart`.
                                      '${order.serviceName} · '
                                      '${order.isItemized ? '${order.items.length} item type(s)' : ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight)}',
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: Colors.black54,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      formatOrderDate(order.createdAt),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: Colors.black45,
                                      ),
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
                                    style: textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  _StatusPill(style: status),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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

/// Solid-fill pill (rather than the previous tinted-background style)
/// so it reads clearly against the new translucent glass card, where
/// a low-opacity tint tends to wash out.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.style});

  final OrderStatusStyle style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: style.color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        style.label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
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