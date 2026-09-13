import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_card.dart';
import '../../../models/order_model.dart';
import '../widgets/order_list_tile.dart' show OrderStatusStyle, formatOrderDate;
import '../widgets/order_status_tracker.dart';

/// PART 13 — full read-only detail view for a single order, reached
/// only from [MyOrdersScreen]. Every field shown here comes straight
/// from the [OrderModel] passed in — no extra Firestore read is
/// needed since the list screen's stream already has the complete
/// document.
///
/// PART 14.1 — the top of the screen is now [OrderStatusTracker]
/// rather than a static status label: it opens its own live Firestore
/// listener on this order's document ID, so if an Admin changes the
/// status (PART 16) while this screen is open, the customer sees the
/// update — and the full step-by-step progress line — without
/// re-opening the screen. Everything below the tracker is still the
/// plain snapshot [order] passed in from [MyOrdersScreen]'s list,
/// since only the *status* needs to be real-time here.
class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final orderId = order.id;

    return Scaffold(
      appBar: AppBar(title: Text(order.orderNumber)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // orderId should never actually be null here — every order
            // reaching this screen came from a Firestore-backed stream
            // (PART 13.1's streamOrdersForUser), which always supplies
            // a document ID. The static fallback below only exists so
            // a malformed/legacy document can't crash this screen.
            if (orderId != null)
              OrderStatusTracker(orderId: orderId)
            else
              _StatusCard(status: OrderStatusStyle.of(order.status)),
            const SizedBox(height: 12),
            _OrderInfoCard(order: order),
            const SizedBox(height: 12),
            _DeliveryInfoCard(order: order),
            const SizedBox(height: 12),
            _PriceBreakdownCard(order: order),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.valueColor, this.valueWeight});

  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueWeight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueWeight ?? FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final OrderStatusStyle status;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.local_shipping_outlined, color: status.color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Status',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  status.label,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderInfoCard extends StatelessWidget {
  const _OrderInfoCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Details', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(label: 'Order Number', value: order.orderNumber),
          _Row(label: 'Service', value: order.serviceName),
          _Row(label: 'Weight', value: '${order.weight.toStringAsFixed(1)} kg'),
          if (order.detergentName.isNotEmpty)
            _Row(label: 'Detergent', value: order.detergentName),
          if (order.items.isNotEmpty)
            _Row(
              label: 'Laundry Items',
              value: order.items.map((item) => item.itemName).join(', '),
            ),
          _Row(label: 'Placed On', value: formatOrderDate(order.createdAt)),
          _Row(label: 'Last Updated', value: formatOrderDate(order.updatedAt)),
        ],
      ),
    );
  }
}

class _DeliveryInfoCard extends StatelessWidget {
  const _DeliveryInfoCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final isPickup = order.isPickup;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isPickup ? Icons.delivery_dining_outlined : Icons.storefront_outlined, size: 20),
              const SizedBox(width: 8),
              Text(isPickup ? 'Pickup' : 'Drop-off', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (isPickup) ...[
            _Row(label: 'Address', value: order.address ?? '—'),
            _Row(label: 'Phone', value: order.pickupPhone ?? '—'),
            _Row(label: 'Landmark', value: order.pickupLandmark ?? '—'),
            _Row(label: 'Location', value: order.location ?? '—'),
          ] else
            const _Row(label: 'Method', value: 'Drop-off at shop'),
        ],
      ),
    );
  }
}

class _PriceBreakdownCard extends StatelessWidget {
  const _PriceBreakdownCard({required this.order});

  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price Summary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(label: 'Subtotal', value: PriceCalculator.formatCurrency(order.subtotal)),
          _Row(label: 'Detergent Fee', value: PriceCalculator.formatCurrency(order.detergentFee)),
          if (order.isPickup)
            _Row(label: 'Pickup Fee', value: PriceCalculator.formatCurrency(order.pickupFee)),
          if (order.discount > 0)
            _Row(
              label: 'Discount',
              value: '-${PriceCalculator.formatCurrency(order.discount)}',
              valueColor: colors.primary,
            ),
          const Divider(height: 20),
          _Row(
            label: 'Total',
            value: PriceCalculator.formatCurrency(order.total),
            valueColor: colors.primary,
            valueWeight: FontWeight.w700,
          ),
        ],
      ),
    );
  }
}