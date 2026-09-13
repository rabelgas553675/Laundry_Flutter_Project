import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/utils/js_conversion_error_unwrapper.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dropoff_info_card.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../models/order_draft_model.dart';
import '../../../models/order_model.dart';

/// PART 11.2/11.3/12.4 — read-only review of a completed PART 10
/// order, priced using PART 11.1's [PriceCalculator], that actually
/// places the order via PART 12.3's [OrderRepository] once confirmed.
///
/// Takes a single [OrderDraft] (everything the customer already
/// chose) and shows it back to them, broken into three cards: what
/// they're ordering, how it's getting to/from them, and what it
/// costs.
///
/// "Back" simply pops back to the order form — every field the
/// customer filled in there is still exactly as they left it, since
/// nothing is cleared on navigation either direction (disabled while
/// an order is being submitted, so a customer can't leave mid-write).
///
/// "Confirm Order" re-validates the draft, shows a review dialog, and
/// — once the customer confirms that dialog — actually creates the
/// order in Firestore via [OrderRepository.createOrder]. From there:
/// a loading state guards against duplicate submissions, a success
/// dialog shows the generated order number and Pending status, and
/// Firebase/network failures surface a friendly retry-able message
/// instead of a raw exception.
class OrderSummaryScreen extends StatefulWidget {
  const OrderSummaryScreen({super.key, required this.order});

  final OrderDraft order;

  @override
  State<OrderSummaryScreen> createState() => _OrderSummaryScreenState();
}

class _OrderSummaryScreenState extends State<OrderSummaryScreen> {
  final OrderRepository _orderRepository = OrderRepository();

  /// PART 14.4 — fires the one-time "Order Successfully Placed"
  /// notification right after [OrderRepository.createOrder] succeeds
  /// below. Purely additive: the order-creation call itself
  /// (validation, pricing, Firestore write) is untouched, per this
  /// part's "do not change the existing order creation system"
  /// requirement — this only runs \after\ that call has already
  /// returned a created order.
  final NotificationService _notificationService = NotificationService();

  /// PART 12.4 — true while a createOrder() call is in flight.
  /// Doubles as the duplicate-submission guard: every entry point
  /// that could create an order checks this first, and both buttons
  /// are disabled while it's true.
  bool _isSubmitting = false;

  /// PART 11.3 — confirms every piece of information the summary
  /// screen (and PART 12.3's order creation) depends on is actually
  /// present, independent of whatever validation the PART 10 form
  /// already did. Returns a human-readable message describing what's
  /// missing, or null if the draft is complete.
  static String? _validate(OrderDraft order) {
    if (order.items.isEmpty) {
      return 'No laundry items were found on this order. Please go back and select at least one.';
    }
    if (order.weightKg <= 0) {
      return 'Order weight must be greater than 0 kg. Please go back and re-enter it.';
    }
    if (order.isPickup) {
      if ((order.pickupAddress ?? '').trim().isEmpty) {
        return 'Pickup address is missing. Please go back and fill it in.';
      }
      if ((order.pickupPhone ?? '').trim().isEmpty) {
        return 'Pickup phone number is missing. Please go back and fill it in.';
      }
      if ((order.pickupLandmark ?? '').trim().isEmpty) {
        return 'Pickup landmark is missing. Please go back and fill it in.';
      }
      if (order.pickupLocation == null) {
        return 'Pickup area is missing. Please go back and select one.';
      }
    }
    return null;
  }

  /// PART 12.4 — turns a caught error into the exact user-facing copy
  /// this part's spec asks for, without ever showing a raw
  /// Firebase/Firestore error message to the customer.
  ///
  /// Also logs the real error/stack to the console first — the
  /// previous version threw this away entirely, which is why the
  /// composite-index bug and whatever's failing now were both
  /// invisible from the UI. Check the terminal/DevTools console after
  /// a failed submit; the actual FirebaseException code will be
  /// printed there even though the customer only ever sees the
  /// friendly message below.
  ///
  /// [OrderDatasource]'s own timeout wrapper (PART 12.2) throws a
  /// [FirebaseException] with code deadline-exceeded whenever a
  /// Firestore call takes too long to respond — in practice, that (and
  /// codes like unavailable/network-request-failed, which the
  /// Firestore SDK itself uses for connectivity problems) is what a
  /// dropped connection looks like from here, so those three codes are
  /// treated as "no internet" rather than a generic Firebase failure.
  ///
  /// On Flutter Web, a rejected Firestore JS promise doesn't always
  /// arrive here as a proper [FirebaseException] — sometimes the
  /// package:js/dart:js_interop Promise→Future conversion wraps it
  /// instead, and error.toString() on THAT wrapper is just the fixed
  /// string "Dart exception thrown from converted Future. Use the
  /// properties 'error' to fetch the boxed error and 'stack' to
  /// recover the stack trace." — i.e. exactly the message that was
  /// showing up in the console with no FirebaseException code ever
  /// printed alongside it. [_unwrapJsConversionError] below does what
  /// that message says: reaches into the wrapper's own .error/
  /// .stack (via dynamic access, since the wrapper type isn't
  /// publicly exported) so the real Firestore error — almost always
  /// permission-denied from firestore.rules, or invalid-argument
  /// from a bad field value — actually gets logged and classified
  /// below, instead of silently falling through to the generic
  /// "Unable to place your order" message every single time.
  (Object, StackTrace) _unwrapJsConversionError(
    Object error,
    StackTrace stackTrace,
  ) {
    // Delegates to the interop-safe unwrapper in
    // js_conversion_error_unwrapper_web.dart, which reaches into the
    // JS wrapper's 'error'/'stack' properties via dart:js_interop's
    // JSObject.getProperty + JSBoxedDartObject.toDart — the only way
    // to actually read those properties off a JSObject. A plain
    // `dynamic` getter access (the previous approach here) has no
    // matching Dart member to dispatch to on a JSObject and just
    // throws, which is why the real error/stack were never recovered
    // and every failure fell through to this method's generic
    // fallback below. On non-web platforms (the _stub.dart branch)
    // this always returns null, so [error]/[stackTrace] pass through
    // unchanged, same as before.
    final unwrapped = tryUnwrapJsConversionError(error, stackTrace);
    return unwrapped ?? (error, stackTrace);
  }

  String _friendlyErrorMessage(Object rawError, StackTrace rawStackTrace) {
    final (error, stackTrace) = _unwrapJsConversionError(rawError, rawStackTrace);

    debugPrint('OrderSummaryScreen: order creation failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    if (error is FirebaseException) {
      debugPrint(
        'OrderSummaryScreen: FirebaseException code = ${error.code}, '
        'plugin = ${error.plugin}, message = ${error.message}',
      );

      const networkCodes = {'unavailable', 'deadline-exceeded', 'network-request-failed'};
      if (networkCodes.contains(error.code)) {
        return 'No internet connection. Please check your connection and try again.';
      }
      if (error.code == 'permission-denied') {
        return 'You don\'t have permission to place this order. Please log in again.';
      }
      return 'Unable to place your order. Please try again.';
    }

    return 'Unable to place your order. Please try again.';
  }

  void _handleConfirmOrder(BuildContext context, PriceBreakdown breakdown) {
    if (_isSubmitting) return; // duplicate-tap guard

    final validationError = _validate(widget.order);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError), duration: const Duration(seconds: 4)),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 40),
        title: const Text('Confirm this order?'),
        content: Text(
          '${widget.order.service.name} · ${widget.order.weightKg.toStringAsFixed(1)} kg\n'
          '${widget.order.isPickup ? 'Pickup' : 'Drop-off'}\n\n'
          'Total: ${PriceCalculator.formatCurrency(breakdown.total)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _submitOrder(context);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  /// PART 12.4 — the actual Firestore write, via
  /// [OrderRepository.createOrder]. Guarded at the top by
  /// [_isSubmitting] so this can never run twice concurrently, no
  /// matter how it gets triggered.
  Future<void> _submitOrder(BuildContext context) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    final userId = AuthState.instance.firebaseUser?.uid;
    if (userId == null) {
      // Shouldn't be reachable — this screen sits behind a RoleGuard —
      // but fail safely with a clear message rather than a null crash
      // if the session somehow drops mid-checkout.
      setState(() => _isSubmitting = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your session has expired. Please log in again.')),
      );
      return;
    }

    try {
      final createdOrder = await _orderRepository.createOrder(
        draft: widget.order,
        userId: userId,
      );

      // Fire-and-forget: a notification failure (e.g. a transient
      // Firestore hiccup) must never block or roll back an order that
      // has already been successfully placed — the customer still
      // sees their success dialog either way.
      unawaited(
        _notificationService.notifyOrderCreated(createdOrder).catchError((Object e) {
          debugPrint('OrderSummaryScreen: notifyOrderCreated failed (non-fatal): $e');
          return null;
        }),
      );

      if (!context.mounted) return;
      _showSuccessDialog(context, createdOrder);
    } catch (error, stackTrace) {
      // Deliberately broad: both a thrown FirebaseException (network/
      // Firestore problem) and anything else unexpected end up with a
      // friendly, retry-able message — the completed OrderDraft is
      // untouched either way, so the customer can just tap Confirm
      // again without re-entering anything.
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyErrorMessage(error, stackTrace)),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// PART 12.4 — "✓ Order Successfully Placed", with the real
  /// generated order number and Pending status. barrierDismissible:
  /// false so a customer can't tap outside and lose track of whether
  /// their order actually went through.
  void _showSuccessDialog(BuildContext context, OrderModel createdOrder) {
    final colors = Theme.of(context).colorScheme;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(Icons.check_circle, color: colors.primary, size: 48),
        title: const Text('Order Successfully Placed'),
        // Plain Text rows, deliberately not [_SummaryRow] — that
        // widget relies on Expanded/Flexible, which needs a bounded
        // width to lay out safely, and AlertDialog sizes its content
        // intrinsically rather than giving it one.
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Order Number: ${createdOrder.orderNumber}',
              textAlign: TextAlign.center,
              style: Theme.of(
                dialogContext,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              'Status: Pending',
              textAlign: TextAlign.center,
              style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(); // close the dialog
              // The order is done — nothing useful is left on either
              // the summary screen or the order form behind it, so
              // pop both and return the customer to wherever they
              // started (PART 13's My Orders screen is where they'll
              // eventually be able to look this order up again).
              final navigator = Navigator.of(context);
              navigator.pop(); // close Order Summary
              if (navigator.canPop()) {
                navigator.pop(); // close the Laundry Order form
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final breakdown = PriceCalculator.calculate(
      servicePricePerKg: widget.order.service.pricePerKg,
      weightKg: widget.order.weightKg,
      detergentFee: widget.order.detergent.additionalPrice,
      pickupFee: widget.order.pickupFee,
      discount: widget.order.discount,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Order Summary')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _OrderDetailsCard(order: widget.order),
            _DeliveryCard(order: widget.order),
            _PriceSummaryCard(order: widget.order, breakdown: breakdown),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Back',
                    variant: AppButtonVariant.outlined,
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    label: _isSubmitting ? 'Placing Order...' : 'Confirm Order',
                    icon: _isSubmitting ? null : Icons.check_circle_outline,
                    isLoading: _isSubmitting,
                    onPressed: _isSubmitting
                        ? null
                        : () => _handleConfirmOrder(context, breakdown),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple label/value row shared by all three cards below, so the
/// left column of labels always lines up the same way.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.valueWeight,
    this.valueFontSize,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final FontWeight? valueWeight;
  final double? valueFontSize;

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
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: textTheme.bodyMedium?.copyWith(
                color: valueColor,
                fontWeight: valueWeight ?? FontWeight.w600,
                fontSize: valueFontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Service, laundry items, weight, and detergent — everything from
/// PART 10.1 and the detergent half of PART 10.2.
class _OrderDetailsCard extends StatelessWidget {
  const _OrderDetailsCard({required this.order});

  final OrderDraft order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Details', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _SummaryRow(
            label: 'Service',
            value: '${order.service.name} (₱${order.service.pricePerKg.toStringAsFixed(0)}/kg)',
          ),
          const SizedBox(height: 4),
          Text(
            'Laundry Items',
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: order.items
                .map((item) => Chip(label: Text(item.name), visualDensity: VisualDensity.compact))
                .toList(),
          ),
          const SizedBox(height: 4),
          _SummaryRow(label: 'Weight', value: '${order.weightKg.toStringAsFixed(1)} kg'),
          _SummaryRow(label: 'Detergent', value: order.detergent.name),
        ],
      ),
    );
  }
}

/// Pickup (Address, Phone, Landmark, Location) or Drop-off (shop
/// location, business hours) — reuses the same [DropoffInfoCard] the
/// PART 10.2 order form already shows for Drop-off, so the shop's
/// info is never described in two different places.
class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.order});

  final OrderDraft order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                order.isPickup ? Icons.delivery_dining_outlined : Icons.storefront_outlined,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(order.isPickup ? 'Pickup' : 'Drop-off', style: textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          if (order.isPickup) ...[
            _SummaryRow(label: 'Address', value: order.pickupAddress ?? '—'),
            _SummaryRow(label: 'Phone', value: order.pickupPhone ?? '—'),
            _SummaryRow(label: 'Landmark', value: order.pickupLandmark ?? '—'),
            _SummaryRow(label: 'Location', value: order.pickupLocation?.label ?? '—'),
          ] else
            const DropoffInfoCard(),
        ],
      ),
    );
  }
}

/// Subtotal, fees, discount, and total — computed by
/// [PriceCalculator], never by this widget. Formatted in Philippine
/// Peso via [PriceCalculator.formatCurrency].
class _PriceSummaryCard extends StatelessWidget {
  const _PriceSummaryCard({required this.order, required this.breakdown});

  final OrderDraft order;
  final PriceBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Price Summary', style: textTheme.titleMedium),
          const SizedBox(height: 8),
          _SummaryRow(
            label:
                'Subtotal (₱${order.service.pricePerKg.toStringAsFixed(0)}/kg × '
                '${order.weightKg.toStringAsFixed(1)} kg)',
            value: PriceCalculator.formatCurrency(breakdown.subtotal),
          ),
          _SummaryRow(
            label: 'Detergent Fee',
            value: PriceCalculator.formatCurrency(breakdown.detergentFee),
          ),
          if (order.isPickup)
            _SummaryRow(
              label: 'Pickup Fee',
              value: PriceCalculator.formatCurrency(breakdown.pickupFee),
            ),
          if (breakdown.discount > 0)
            _SummaryRow(
              label: 'Discount',
              value: '-${PriceCalculator.formatCurrency(breakdown.discount)}',
              valueColor: colors.primary,
            ),
          const Divider(height: 20),
          _SummaryRow(
            label: 'Total',
            value: PriceCalculator.formatCurrency(breakdown.total),
            valueFontSize: 18,
            valueWeight: FontWeight.w700,
            valueColor: colors.primary,
          ),
        ],
      ),
    );
  }
}