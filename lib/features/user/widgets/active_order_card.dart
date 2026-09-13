import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/status_badge.dart';

/// Placeholder shape only — the real order model arrives in Part 12.
/// Kept intentionally tiny so nothing here has to change when that
/// model lands; this widget will just start receiving real data.
class PlaceholderActiveOrder {
  const PlaceholderActiveOrder({
    required this.orderNumber,
    required this.serviceName,
    required this.status,
    required this.weightKg,
  });

  final String orderNumber;
  final String serviceName;
  final String status;
  final double weightKg;
}

class ActiveOrderCard extends StatefulWidget {
  const ActiveOrderCard({super.key, required this.order, this.onViewDetails});

  /// Null → no active order, shows an empty state instead.
  final PlaceholderActiveOrder? order;
  final VoidCallback? onViewDetails;

  @override
  State<ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<ActiveOrderCard> {
  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final order = widget.order;

    if (order == null) {
      return AppCard(
        child: EmptyState(
          icon: Icons.local_laundry_service_outlined,
          title: 'No active order',
          message: 'Place a new order to see its live status here.',
        ),
      );
    }

    return AppCard(
      onTap: widget.onViewDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Active Order', style: textTheme.titleMedium),
              ),
              StatusBadge(status: order.status),
            ],
          ),
          const SizedBox(height: 12),
          Text(order.orderNumber, style: textTheme.bodyLarge),
          const SizedBox(height: 4),
          Text(
            '${order.serviceName} · ${order.weightKg.toStringAsFixed(1)} kg',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onViewDetails,
              child: const Text('View details'),
            ),
          ),
        ],
      ),
    );
  }
}