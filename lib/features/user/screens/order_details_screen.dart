// lib/features/user/screens/order_details_screen.dart
import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../../../models/user_model.dart';
import 'address_selection_screen.dart';
import '../widgets/order_items_breakdown.dart';
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
///
/// PART 3 (Order Details → Change Address) — this screen is now
/// stateful, holding its own mutable [_order] seeded from
/// [OrderDetailsScreen.order]. Everything else about it is exactly as
/// before; the only reason for the extra state is so
/// [_DeliveryInfoCard]'s "Change Address" action
/// (only shown for a still-[OrderStatus.pending] Pickup order — see
/// [OrderRepository.isAddressEditable]) can update what's on screen
/// immediately after a successful change, without leaving this screen
/// or waiting on a second Firestore read.
class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, required this.order});

  final OrderModel order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final OrderRepository _orderRepository = OrderRepository();
  late OrderModel _order;
  bool _isChangingAddress = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colorScheme.error : colorScheme.inverseSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
          content: Text(
            message,
            style: TextStyle(
              color: isError ? colorScheme.onError : colorScheme.onInverseSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
  }

  /// PART 3, steps 3–5 — "Change Address": opens the same reusable
  /// [AddressSelectionScreen] Part 1 built for Profile → Address (in
  /// its `forOrderSelection` mode, exactly like the Pickup Checkout
  /// flow in `laundry_order_screen.dart` already reuses it), then —
  /// only if the customer actually confirms a pick there — shows the
  /// "Change Pickup Address?" confirmation dialog before writing
  /// anything. Backing out of either the address list or the dialog
  /// leaves this order untouched.
  Future<void> _changeAddress() async {
    final user = AuthState.instance.userModel;
    if (user == null) return;

    // Step 3 — "Open Address Selection". Pops with the chosen
    // `SavedAddress` only if the customer taps "Use this Address";
    // `null` (back arrow / OS back) means "cancelled".
    final picked = await Navigator.push<SavedAddress>(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSelectionScreen(user: user, forOrderSelection: true),
      ),
    );
    if (picked == null || !mounted) return;

    // Step 5 — confirm before writing anything. This is the *only*
    // gate between picking an address and it actually being saved —
    // backing out here (Cancel / the dialog's own back handling)
    // leaves `_order` exactly as it was.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change Pickup Address?'),
        content: const Text(
          'This address will be used for this order.\n'
          'Your saved Profile Address will not be changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isChangingAddress = true);
    try {
      // Step 4 — updates only this order's own address snapshot.
      // `OrderRepository.updateOrderAddress` re-checks
      // `isAddressEditable` itself (defense-in-depth, same as every
      // other write in that repository) and never touches the
      // customer's saved addresses, Profile default, or any other
      // order.
      final updated = await _orderRepository.updateOrderAddress(
        order: _order,
        address: picked,
      );
      if (!mounted) return;
      // Refresh the order and display the new address immediately.
      setState(() => _order = updated);
      _showMessage('Pickup address updated for this order.');
    } on AppException catch (e) {
      _showMessage(e.message, isError: true);
    } on OrderValidationException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not update the pickup address. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isChangingAddress = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
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
            _DeliveryInfoCard(
              order: order,
              // PART 3, step 6 — only offered while
              // `OrderRepository.isAddressEditable` says this order's
              // address can still change; hidden otherwise (already
              // being processed, picked up, completed, or cancelled)
              // per this part's spec, using the existing order-status
              // workflow rather than a new one.
              canChangeAddress: OrderRepository.isAddressEditable(order),
              isChangingAddress: _isChangingAddress,
              onChangeAddress: _changeAddress,
            ),
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
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Details', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _Row(label: 'Order Number', value: order.orderNumber),
          _Row(label: 'Service', value: order.serviceName),
          // PART 3 — a Dry Cleaning order (`order.isItemized`) was
          // priced per garment, not by weight/piece-count: showing
          // `order.weight` here would just be "0 pcs" (that field is
          // never set for an itemized order — see
          // `OrderRepository.createOrder`). Show the itemized
          // `2 × Suit  ₱300` breakdown instead, same widget/format as
          // the pre-confirm Order Summary screen used.
          if (order.isItemized) ...[
            const SizedBox(height: 4),
            Text(
              'Items',
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            OrderItemsBreakdown(items: order.items),
          ] else
            // The unit this order was actually placed under
            // (`order.serviceUnit`), not the service's current
            // configuration, so a historical order keeps showing
            // exactly what the customer ordered.
            _Row(
              label: order.serviceUnit.quantityFieldLabel,
              value: ServiceUnitFormat.formatQuantity(order.serviceUnit, order.weight),
            ),
          if (order.detergentName.isNotEmpty)
            _Row(label: 'Detergent', value: order.detergentName),
          if (!order.isItemized && order.items.isNotEmpty)
            _Row(
              label: 'Laundry Items',
              value: order.items.map((item) => item.itemName).join(', '),
            ),
          if (order.specialInstructions != null && order.specialInstructions!.trim().isNotEmpty)
            _Row(label: 'Special Instructions', value: order.specialInstructions!),
          _Row(label: 'Placed On', value: formatOrderDate(order.createdAt)),
          _Row(label: 'Last Updated', value: formatOrderDate(order.updatedAt)),
        ],
      ),
    );
  }
}

class _DeliveryInfoCard extends StatelessWidget {
  const _DeliveryInfoCard({
    required this.order,
    this.canChangeAddress = false,
    this.isChangingAddress = false,
    this.onChangeAddress,
  });

  final OrderModel order;

  /// PART 3 — whether the "Change Address" action below the address
  /// fields should be shown at all for this (Pickup-only) order. See
  /// [OrderRepository.isAddressEditable].
  final bool canChangeAddress;

  /// PART 3 — true while a change is being confirmed/saved, so the
  /// button can show a loading state and disable itself instead of
  /// allowing a second tap mid-save.
  final bool isChangingAddress;

  final VoidCallback? onChangeAddress;

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
            // PART 3, step 2 — underneath the current address, only
            // while this order is still editable (step 6). Kept out
            // of the way of the plain read-only rows above so this
            // card still renders exactly as before for a non-editable
            // order (e.g. one already being processed).
            if (canChangeAddress) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Change Address',
                variant: AppButtonVariant.outlined,
                isLoading: isChangingAddress,
                onPressed: onChangeAddress,
              ),
            ],
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