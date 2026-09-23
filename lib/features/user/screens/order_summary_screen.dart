import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/utils/js_conversion_error_unwrapper.dart';
import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/dropoff_info_card.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../data/services/notification_service.dart';
import '../../../models/order_draft_model.dart';
import '../../../models/order_model.dart';
import '../widgets/order_items_breakdown.dart';

/// Brand blue used across the app's glass UI (dashboard app bar/nav,
/// the order form's Stepper shell). Kept local to this file, same as
/// `laundry_order_screen.dart` does with its own `_kBrandBlue`, so
/// this screen matches without introducing a shared constant this
/// part isn't scoped to touch.
const Color _kBrandBlue = Color(0xff0D47A1);
const Color _kBrandBlueLight = Color(0xff8EC5FC);

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
///
/// The visual shell (app bar, blurred-blob background, white content
/// sheet) was restyled to match `laundry_order_screen.dart` and
/// `user_dashboard.dart`'s frosted-glass look — see [_buildShell] at
/// the bottom of [build]. None of the submission logic, validation,
/// or state below was touched.
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
    // PART 3 fix — an itemized draft (Dry Cleaning) never populates
    // `order.items`/`order.weightKg` (it's priced from
    // `order.selectedItems` instead — see `OrderDraft.items`'s doc
    // comment), so checking those two fields for every draft meant
    // this always returned an error for Dry Cleaning: "Confirm
    // Order" could never actually succeed for it. Branch on
    // `order.isItemized` and validate the fields that service type
    // actually uses.
    if (order.isItemized) {
      if (order.selectedItems.isEmpty) {
        return 'No items were selected for this order. Please go back and select at least one item.';
      }
      if (order.selectedItems.any((item) => item.quantity <= 0)) {
        return 'Every selected item needs a quantity greater than 0. Please go back and check your items.';
      }
    } else {
      if (order.items.isEmpty) {
        return 'No laundry items were found on this order. Please go back and select at least one.';
      }
      // Part 2 (per-piece pricing) — unit-aware, and re-checks the
      // whole-number rule independently of whatever the order form
      // already validated (same reasoning as every other check in
      // this method: this runs again here regardless). The actual
      // rule lives in `ServiceUnitValidation`, never duplicated here.
      final quantityError = ServiceUnitValidation.validateQuantityValue(order.unit, order.weightKg);
      if (quantityError != null) {
        return '$quantityError Please go back and re-enter it.';
      }
    }
    if (order.isPickup) {
      if ((order.pickupAddress ?? '').trim().isEmpty) {
        return 'Pickup address is missing. Please go back and fill it in.';
      }
      if ((order.pickupPhone ?? '').trim().isEmpty) {
        return 'Pickup phone number is missing. Please go back and fill it in.';
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

    // PART 2B — `OrderRepository.createOrder`'s own pickup-address
    // validation (a defense-in-depth backstop behind [_validate]
    // above) throws this with the exact customer-facing copy already
    // baked in — e.g. "Please select a pickup address." — so it's
    // shown verbatim instead of falling through to the generic
    // "Unable to place your order" message below.
    if (error is OrderValidationException) {
      return error.message;
    }

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
          '${widget.order.service.name} · '
          // PART 3 — an itemized order (Dry Cleaning) has nothing
          // meaningful to show via `weightKg` (always 0 for these
          // drafts); show the garment count instead of "0 pcs".
          '${widget.order.isItemized ? '${widget.order.selectedItems.length} item type(s)' : ServiceUnitFormat.formatQuantity(widget.order.unit, widget.order.weightKg)}\n'
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

  // -------------------- Build --------------------

  @override
  Widget build(BuildContext context) {
    // Local Theme override, same trick as `laundry_order_screen.dart`:
    // AppButton's FilledButton/OutlinedButton styling reads
    // `colorScheme.primary` by default, so this keeps "Confirm Order"
    // and "Back" the same brand blue as the rest of the glass UI
    // without touching theme.dart.
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(
          primary: _kBrandBlue,
          secondary: _kBrandBlue,
        ),
      ),
      child: Builder(builder: _buildShell),
    );
  }

  /// The actual screen shell: glass app bar + blurred-blob background
  /// (matching `user_dashboard.dart` / `laundry_order_screen.dart`)
  /// with the three summary cards and action buttons sitting on a
  /// rounded white sheet for contrast. [context] here already carries
  /// the blue-primary [Theme] override from [build].
  Widget _buildShell(BuildContext context) {
    // PART 3 fix — a Dry Cleaning draft (`order.isItemized`) is
    // priced from `order.itemsSubtotal` (Σ quantity × item price),
    // never from `service.pricePerKg × weightKg` (which is always 0
    // for an itemized draft, since it isn't priced by weight at
    // all). Every other service keeps pricing the original way.
    final breakdown = PriceCalculator.calculate(
      servicePricePerKg: widget.order.service.pricePerKg,
      weightKg: widget.order.weightKg,
      itemsSubtotal: widget.order.isItemized ? widget.order.itemsSubtotal : null,
      detergentFee: widget.order.detergent.additionalPrice,
      pickupFee: widget.order.pickupFee,
      // PART 3 fix — this used to read `widget.order.discount`, the
      // legacy flat field that's always 0 once a promo is attached
      // (see `OrderDraft.resolvedDiscount`'s doc comment). That meant
      // a customer who selected a promo on the Offers screen saw it
      // silently vanish here: no discount row, wrong total. Reading
      // `resolvedDiscount` instead always reflects `appliedPromo` when
      // one is set, and falls back to the flat `discount` field when
      // it isn't — so this is a strict superset of the old behavior.
      discount: widget.order.resolvedDiscount,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const _GlassSummaryAppBar(title: 'Order Summary'),
      body: Stack(
        children: [
          const Positioned.fill(child: _SummaryScreenBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: Colors.white.withValues(alpha: 0.96),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _OrderDetailsCard(order: widget.order),
                      const SizedBox(height: 12),
                      _DeliveryCard(order: widget.order),
                      const SizedBox(height: 12),
                      _PriceSummaryCard(order: widget.order, breakdown: breakdown),
                      const SizedBox(height: 16),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass app bar for the summary screen — same recipe as
/// `_GlassOrderAppBar` in `laundry_order_screen.dart` (blurred
/// translucent bar, rounded bottom corners, accent stripe, back
/// arrow), duplicated locally rather than imported since that class
/// is private to its own file.
class _GlassSummaryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassSummaryAppBar({required this.title});

  final String title;

  static const double _contentHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_contentHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: _kBrandBlue.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _contentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 18, 0),
                child: Row(
                  children: [
                    _GlassSummaryBackButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _kBrandBlue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
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
    );
  }
}

class _GlassSummaryBackButton extends StatelessWidget {
  const _GlassSummaryBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// Same blurred-blob backdrop as `_OrderScreenBackground` in
/// `laundry_order_screen.dart` — two blobs, since this is also a
/// secondary screen sitting mostly behind a white content sheet.
class _SummaryScreenBackground extends StatelessWidget {
  const _SummaryScreenBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kBrandBlue, Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrandBlueLight.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
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
            value: order.isItemized
                ? order.service.name
                : '${order.service.name} '
                    '(${ServiceUnitFormat.formatPricePerUnit(order.unit, '₱${order.service.pricePerKg.toStringAsFixed(0)}')})',
          ),
          const SizedBox(height: 4),
          // PART 3 — Dry Cleaning (`order.isItemized`) has no single
          // "weight" to show; it's priced per garment, so show the
          // `2 × Suit  ₱300` style breakdown instead of the Chips +
          // weight row every other service uses.
          if (order.isItemized) ...[
            Text(
              'Items',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            OrderItemsBreakdown(items: order.selectedItems),
          ] else ...[
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
            _SummaryRow(
              // "Weight" for a kg-based service, "Quantity" for a
              // piece-based one — never hard-coded, per Part 1's
              // `ServiceUnit.quantityFieldLabel`.
              label: order.unit.quantityFieldLabel,
              value: ServiceUnitFormat.formatQuantity(order.unit, order.weightKg),
            ),
          ],
          _SummaryRow(label: 'Detergent', value: order.detergent.name),
          if ((order.specialInstructions ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Special Instructions',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(order.specialInstructions!.trim(), style: textTheme.bodyMedium),
          ],
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
          if (order.isItemized) ...[
            // PART 3 — Dry Cleaning: the per-garment breakdown was
            // already shown in full on `_OrderDetailsCard` above, so
            // this just carries the already-summed subtotal forward
            // into the running total, with a plain "Subtotal" label
            // instead of a "₱150/pc × 0 pcs"-style one that would be
            // meaningless for an itemized order.
            _SummaryRow(
              label: 'Subtotal '
                  '(${order.selectedItems.length} item type${order.selectedItems.length == 1 ? '' : 's'})',
              value: PriceCalculator.formatCurrency(breakdown.subtotal),
            ),
          ] else
            _SummaryRow(
              // e.g. "Subtotal (₱150/pc × 3 pcs)" for a piece
              // service, "Subtotal (₱80/kg × 3 kg)" for a kg-based
              // one — built entirely through `ServiceUnitFormat`,
              // never hard-coded "/kg" here.
              label: 'Subtotal '
                  '(${ServiceUnitFormat.formatPricePerUnit(order.unit, '₱${order.service.pricePerKg.toStringAsFixed(0)}')} × '
                  '${ServiceUnitFormat.formatQuantity(order.unit, order.weightKg)})',
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
          // PART 3 — "Promo: 20% OFF" line, shown whenever a promo is
          // actually attached to this draft (regardless of whether it
          // ends up affecting the total — a below-minimum-order promo
          // still shows here so the customer sees it's attached, with
          // the Discount row below making clear it isn't taking
          // anything off yet).
          if (order.appliedPromo != null)
            _SummaryRow(
              label: 'Promo (${order.appliedPromo!.code})',
              value: order.appliedPromo!.discountLabel,
              valueColor: colors.primary,
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