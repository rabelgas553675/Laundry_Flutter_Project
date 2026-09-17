import '../../core/utils/price_calculator.dart';
import '../../models/order_draft_model.dart';
import '../../models/order_item_model.dart';
import '../../models/order_model.dart';
import '../../models/promo_model.dart';
import '../datasources/order_datasource.dart';
import 'promo_repository.dart';

/// PART 12.3 — sits between the app (PART 12.4's Order Summary
/// screen) and [OrderDatasource]'s raw Firestore calls. Same split as
/// every other repository in this project (`ServiceRepository`,
/// `UserRepository`, ...): this is where business rules live —
/// pricing, order-number generation, defaulting `status` to pending —
/// while [OrderDatasource] stays a dumb read/write layer.
class OrderRepository {
  OrderRepository({OrderDatasource? datasource, PromoRepository? promoRepository})
      : _datasource = datasource ?? OrderDatasource(),
        _promoRepository = promoRepository ?? PromoRepository();

  final OrderDatasource _datasource;

  /// PART 3 — used by [createOrder] to re-check a draft's
  /// [OrderDraft.appliedPromo] one last time, right before the order
  /// is actually written to Firestore. See [_resolvePromo] below.
  final PromoRepository _promoRepository;

  /// PART 3 — the authoritative, last-moment check of whether
  /// [draft]'s selected promo (if any) is still usable, run
  /// immediately before persisting the order.
  ///
  /// [OrderSummaryScreen] already re-validates the same promo when it
  /// loads and again just before submitting, so in the normal case
  /// this simply confirms what the customer already saw. It exists
  /// as its own defense-in-depth check here — not just trusting
  /// whatever `draft.appliedPromo`/`draft.resolvedDiscount` say —
  /// because a promo can be deactivated, deleted, or expire in the
  /// gap between the customer opening Order Summary and actually
  /// tapping Confirm, and an order must never be saved with a
  /// discount that no longer corresponds to a real, currently-valid
  /// promo.
  ///
  /// Never throws: if the promo turns out to be invalid (or the
  /// check itself fails, e.g. offline), the order is still placed —
  /// just without that discount — rather than blocking checkout
  /// entirely. Returns the resolved `(discount, promoCode,
  /// promoDiscountLabel)` to actually persist.
  Future<(double discount, String? promoCode, String? promoLabel)> _resolvePromo(
    OrderDraft draft,
  ) async {
    final applied = draft.appliedPromo;
    if (applied == null) {
      return (draft.discount, null, null);
    }

    PromoModel? current;
    try {
      final result = await _promoRepository.validateCode(
        code: applied.code,
        orderSubtotal: draft.baseSubtotal,
      );
      if (!result.isValid) {
        // No longer valid (expired/disabled/deleted/below minimum
        // since it was selected) — drop it rather than persist a
        // stale discount.
        return (0.0, null, null);
      }
      current = result.promo;
    } catch (_) {
      // Couldn't re-check (e.g. offline) — fall back to the
      // already-computed snapshot on the draft rather than failing
      // the whole order over a connectivity blip.
      return (draft.resolvedDiscount, applied.code, applied.discountLabel);
    }

    final promo = current ?? applied;
    return (promo.discountFor(draft.baseSubtotal), promo.code, promo.discountLabel);
  }

  /// Safety ceiling for [_generateUniqueOrderNumber] — see that
  /// method's doc comment. 9999 also happens to be the largest value
  /// the `XXXX` segment of `ORD-YYYYMMDD-XXXX` can hold.
  static const _maxSequencePerDay = 9999;

  // -------------------- Order number generation --------------------

  String _formatDatePart(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Generates a unique `ORD-YYYYMMDD-XXXX` order number for right
  /// now (PART 12.3's spec format, e.g. `ORD-20260902-0001`).
  ///
  /// ROOT-CAUSE FIX — this used to loop candidate numbers and ask
  /// [OrderDatasource.getOrderByNumber] "does this already exist?"
  /// before trying the next one. That query filters `orders` by
  /// `orderNumber` only, with no `userId` filter, but the `orders`
  /// collection's Firestore read rule is scoped to
  /// `resource.data.userId == request.auth.uid`. Firestore rejects
  /// any *list* query outright — with `permission-denied`, before it
  /// ever runs — unless it can prove from the query's own structure
  /// that every possible match satisfies the rule; a query with no
  /// `userId` filter can never be proven that way. So every plain
  /// customer got `permission-denied` on this very first step of
  /// every single order, and [OrderDatasource.createOrder]'s actual
  /// write never even ran.
  ///
  /// Fixed by asking [OrderDatasource.nextOrderSequence] for an
  /// atomically-allocated sequence number instead — that reads/writes
  /// a small `counters/orders_{datePart}` document (no order/customer
  /// data, and no per-owner restriction to run into) via a Firestore
  /// transaction, so it needs no query against `orders` at all. This
  /// also fully closes the "two customers checking out at once" race
  /// the old comment here only partially mitigated: a transaction's
  /// read+increment+write is atomic, so Firestore serializes
  /// concurrent callers itself rather than two clients racing to
  /// separately read "not taken yet" for the same candidate.
  Future<String> _generateUniqueOrderNumber() async {
    final datePart = _formatDatePart(DateTime.now());
    final sequence = await _datasource.nextOrderSequence(datePart);

    if (sequence > _maxSequencePerDay) {
      // Practically unreachable (9999 orders in one calendar day),
      // but fail loudly rather than silently handing out a number
      // that doesn't fit the `XXXX` segment's format.
      throw StateError(
        'Could not generate a unique order number for today. Please try again.',
      );
    }

    return 'ORD-$datePart-${sequence.toString().padLeft(4, '0')}';
  }

  // -------------------- Order creation --------------------

  /// Turns a confirmed PART 11 [OrderDraft] into a persisted
  /// [OrderModel].
  ///
  /// 1. Receives the completed order information from PART 11 (the
  ///    [draft] parameter — exactly what the customer reviewed on
  ///    [OrderSummaryScreen]) plus the signed-in customer's [userId].
  /// 2. Generates a unique order number via
  ///    [_generateUniqueOrderNumber].
  /// 3. Prices the order via [PriceCalculator] — recomputed here from
  ///    scratch rather than trusting a pre-computed total passed in
  ///    from the UI, so the persisted amount is always exactly what
  ///    the calculator says for these inputs, never something a
  ///    caller could pass in stale or tampered.
  ///
  ///    PART 3 fix: an itemized [draft] (Dry Cleaning) always has
  ///    `weightKg == 0` — it isn't priced by weight at all — so this
  ///    now passes [OrderDraft.itemsSubtotal] (Σ quantity × item
  ///    price across [OrderDraft.selectedItems]) through as
  ///    [PriceCalculator.calculate]'s `itemsSubtotal` for those
  ///    drafts. Previously this always priced by
  ///    `servicePricePerKg × weightKg`, which silently produced a
  ///    ₱0 subtotal — and therefore a ₱0 total — for every Dry
  ///    Cleaning order.
  /// 4. Defaults `status` to [OrderStatus.pending].
  /// 5–6. Leaves `createdAt`/`updatedAt` unset (null) on the
  ///    [OrderModel] it builds, rather than stamping `DateTime.now()`
  ///    here — [OrderModel.toMap] (PART 12.1) already substitutes
  ///    [FieldValue.serverTimestamp] whenever those fields are null,
  ///    which is exactly PART 12.2's "use Firestore server timestamps
  ///    where appropriate" requirement: the *server's* clock decides
  ///    when the order was created, never the customer's device clock.
  /// 7. Sends the model to [OrderDatasource.createOrder], which
  ///    returns it back with its new document ID attached.
  ///
  /// Throws whatever [OrderDatasource.createOrder] throws (a
  /// [FirebaseException] on a Firestore/network problem) — PART
  /// 12.4's Order Summary screen is where that becomes a
  /// customer-facing message; this layer deliberately doesn't catch
  /// it, so it doesn't have to guess what the UI should say.
  Future<OrderModel> createOrder({
    required OrderDraft draft,
    required String userId,
  }) async {
    // PART 3 — resolve the applied promo (if any) one last time
    // against Firestore before pricing/persisting this order. See
    // [_resolvePromo]'s doc comment for why this can't just trust
    // `draft.resolvedDiscount` blindly.
    final (discount, promoCode, promoLabel) = await _resolvePromo(draft);

    final breakdown = PriceCalculator.calculate(
      servicePricePerKg: draft.service.pricePerKg,
      weightKg: draft.weightKg,
      itemsSubtotal: draft.isItemized ? draft.itemsSubtotal : null,
      detergentFee: draft.detergent.additionalPrice,
      pickupFee: draft.pickupFee,
      discount: discount,
    );

    final orderNumber = await _generateUniqueOrderNumber();

    final order = OrderModel(
      orderNumber: orderNumber,
      userId: userId,
      serviceId: draft.service.id,
      serviceName: draft.service.name,
      weight: draft.weightKg,
      // Part 1 — captured at creation time so this order keeps
      // displaying/calculating under the unit it was actually placed
      // with, even if this service's configured unit changes later.
      // See the doc comment on `OrderModel.serviceUnit`.
      serviceUnit: draft.service.unit,
      detergentId: draft.detergent.id,
      detergentName: draft.detergent.name,
      // PART 3 fix: an itemized draft's priced garment lines live on
      // `draft.selectedItems` (already `OrderItemModel`s, each with
      // its own `quantity`/`unitPrice`) — `draft.items` stays empty
      // for these (see `OrderDraft.items`'s doc comment), so mapping
      // it here would silently persist an order with no line items
      // at all. Every other service keeps mapping its unpriced
      // `LaundryItemModel` category tags exactly as before.
      items: draft.isItemized
          ? draft.selectedItems
          : draft.items.map(OrderItemModel.fromLaundryItem).toList(),
      method: draft.deliveryMethod,
      address: draft.pickupAddress,
      location: draft.pickupLocation?.label,
      pickupPhone: draft.pickupPhone,
      pickupLandmark: draft.pickupLandmark,
      // PART 3 fix — previously dropped entirely; see the doc
      // comment on `OrderModel.specialInstructions`.
      specialInstructions: draft.specialInstructions,
      subtotal: breakdown.subtotal,
      detergentFee: breakdown.detergentFee,
      pickupFee: breakdown.pickupFee,
      discount: breakdown.discount,
      total: breakdown.total,
      // PART 3 — snapshot of which promo (if any) actually produced
      // `breakdown.discount` above, so the order keeps showing "Promo:
      // 20% OFF" forever, independent of that promo's later fate.
      promoCode: promoCode,
      promoDiscountLabel: promoLabel,
      status: OrderStatus.pending,
      // Intentionally null — see step 5–6 above.
      createdAt: null,
      updatedAt: null,
    );

    return _datasource.createOrder(order);
  }

  /// Looks up a single order by its `ORD-YYYYMMDD-XXXX` number.
  /// Thin pass-through to [OrderDatasource.getOrderByNumber] — no
  /// business rules needed on the read side, unlike [createOrder].
  Future<OrderModel?> getOrderByNumber(String orderNumber) {
    return _datasource.getOrderByNumber(orderNumber);
  }

  /// Looks up a single order by its Firestore document ID. Thin
  /// pass-through to [OrderDatasource.getOrderByDocId] — PART 13's
  /// order details screen already has the full [OrderModel] in hand
  /// (from [streamOrdersForUser]'s list), so this mainly exists for
  /// any future entry point that only has a document ID (e.g. a deep
  /// link or a notification payload) and needs to re-fetch the order.
  Future<OrderModel?> getOrderByDocId(String docId) {
    return _datasource.getOrderByDocId(docId);
  }

  /// PART 13.1 — real-time stream of every order belonging to
  /// [userId], newest first, for "My Orders".
  ///
  /// No business rules needed here beyond the pass-through itself:
  /// "own orders only" is already enforced by the `userId` filter
  /// inside [OrderDatasource.streamOrdersForUser]'s query, so this
  /// repository has nothing to add on top of it — same shape as
  /// [getOrderByNumber] above. Tab filtering (Pending / Processing /
  /// Ready / Completed) is deliberately left to the UI layer rather
  /// than done here, so one Firestore listener can back every tab on
  /// the My Orders screen instead of running four separate queries.
  Stream<List<OrderModel>> streamOrdersForUser(String userId) {
    return _datasource.streamOrdersForUser(userId);
  }

  /// PART 15 — thin pass-through to [OrderDatasource.streamAllOrders].
  /// No business rules to add on top: the Admin Dashboard computes its
  /// own stats/summaries from the raw list, same as [MyOrdersScreen]
  /// already does with [streamOrdersForUser].
  Stream<List<OrderModel>> streamAllOrders() {
    return _datasource.streamAllOrders();
  }

  /// PART 14.1 — thin pass-through to
  /// [OrderDatasource.streamOrderByDocId]. Backs [OrderStatusTracker]'s
  /// real-time single-order view; no business rules needed on top,
  /// same as every other read-side method in this repository.
  Stream<OrderModel?> streamOrderById(String docId) {
    return _datasource.streamOrderByDocId(docId);
  }

  // -------------------- PART 16: Admin status updates --------------------

  /// The only status changes an Admin is allowed to make, keyed by
  /// the order's *current* status. Matches this part's spec exactly:
  /// the normal forward workflow (pending → received → washing →
  /// drying → ready → completed) one step at a time — never skipping
  /// a step — plus cancellation, allowed from any non-terminal status.
  /// [OrderStatus.completed] and [OrderStatus.cancelled] are both
  /// terminal: neither maps to any further allowed status.
  static const Map<OrderStatus, Set<OrderStatus>> _allowedTransitions = {
    OrderStatus.pending: {OrderStatus.received, OrderStatus.cancelled},
    OrderStatus.received: {OrderStatus.washing, OrderStatus.cancelled},
    OrderStatus.washing: {OrderStatus.drying, OrderStatus.cancelled},
    OrderStatus.drying: {OrderStatus.ready, OrderStatus.cancelled},
    OrderStatus.ready: {OrderStatus.completed, OrderStatus.cancelled},
    OrderStatus.completed: {},
    OrderStatus.cancelled: {},
  };

  /// The set of statuses [order] may legally move to next, from its
  /// *current* status — empty for a terminal order. PART 16's Admin
  /// Order Details screen calls this to decide which action buttons
  /// to even show, rather than showing every status and letting a tap
  /// fail; [updateOrderStatus] below is what actually enforces the
  /// same rule server-side-of-the-call, so a caller that ignores this
  /// list still can't force an illegal transition through.
  static Set<OrderStatus> allowedNextStatuses(OrderStatus current) {
    return _allowedTransitions[current] ?? const {};
  }

  /// Moves [order] to [newStatus], after confirming that's actually a
  /// legal transition from [order]'s current status.
  ///
  /// Throws a [StateError] (never a raw Firestore call) for an
  /// illegal transition — e.g. `pending → drying`, skipping steps, or
  /// any change starting from [OrderStatus.completed]/[OrderStatus
  /// .cancelled] — so PART 16's screen can show a clear message
  /// instead of a confusing Firestore failure. Throws [ArgumentError]
  /// if [order] has no document ID yet (shouldn't be reachable for an
  /// order already loaded from Firestore).
  ///
  /// Any [FirebaseException] from the write itself (network failure,
  /// permission denied, timeout) is left uncaught, same contract as
  /// every other write in this repository — the calling screen
  /// decides what the Admin sees.
  Future<void> updateOrderStatus({
    required OrderModel order,
    required OrderStatus newStatus,
  }) async {
    final orderId = order.id;
    if (orderId == null) {
      throw ArgumentError('Cannot update the status of an order with no document ID.');
    }

    final allowed = allowedNextStatuses(order.status);
    if (!allowed.contains(newStatus)) {
      throw StateError(
        'Cannot change status from "${order.status.value}" to "${newStatus.value}".',
      );
    }

    await _datasource.updateOrderStatus(orderId, newStatus);
  }
}