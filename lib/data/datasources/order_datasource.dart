// lib/data/datasources/order_datasource.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/order_model.dart';

/// PART 12.2 — raw Firestore access for the orders collection.
///
/// No business rules here — no price calculation, no order-number
/// generation, no auth checks — just reads/writes, same split as
/// every other \Datasource in this project (ServiceDatasource,
/// UserDatasource, ...). PART 12.3's OrderRepository is what
/// decides \what\ to save and \what number\ to give it; this class
/// only knows how to talk to Firestore once that's already decided.
class OrderDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _ordersRef =>
      FirebaseService.firestore.collection('orders');

  /// Backs [nextOrderSequence] — see that method's doc comment for why
  /// this exists instead of querying [_ordersRef] directly.
  CollectionReference<Map<String, dynamic>> get _countersRef =>
      FirebaseService.firestore.collection('counters');

  FirebaseException _timeoutException(String action) => FirebaseException(
    plugin: 'cloud_firestore',
    code: 'deadline-exceeded',
    message: 'Timed out $action — check your network connection.',
  );

  /// Saves [order] as a brand-new document with a Firestore
  /// auto-generated ID, then returns the same order back with that ID
  /// attached (via [OrderModel.copyWith]) so the caller never has to
  /// make a second round trip just to learn what ID it got.
  ///
  /// [OrderModel.toMap] already fills createdAt/updatedAt with
  /// [FieldValue.serverTimestamp] whenever the model's own
  /// createdAt/updatedAt are null (the normal case for a new
  /// order coming out of PART 12.3), so the very first write always
  /// gets a server-assigned timestamp rather than trusting the
  /// customer's device clock.
  ///
  /// Any [FirebaseException] thrown here (network failure, permission
  /// denied, timeout, ...) is intentionally left uncaught — per this
  /// part's requirement, it's PART 12.3's repository layer that turns
  /// this into something the UI can act on, not this class.
  Future<OrderModel> createOrder(OrderModel order) async {
    final docRef = _ordersRef.doc();
    await docRef
        .set(order.toMap())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('placing your order'));
    return order.copyWith(id: docRef.id);
  }

  /// Looks up a single order by its human-readable
  /// ORD-YYYYMMDD-XXXX number.
  ///
  /// NOTE — no longer used for order-number generation (see
  /// [nextOrderSequence] below for why), and not currently called
  /// from anywhere else in the app either; kept as a pass-through for
  /// any future entry point that has a number but not a document ID.
  /// Be aware before wiring it up to a customer-facing screen: this
  /// query filters only on orderNumber, not userId, and
  /// firestore.rules' orders read rule is scoped to
  /// resource.data.userId == request.auth.uid — Firestore rejects a
  /// \list\ query with permission-denied unless the query itself is
  /// provably restricted by every field the rule depends on. A plain
  /// (non-admin) customer calling this will always get
  /// permission-denied, the exact bug [nextOrderSequence] exists to
  /// avoid for the far more common order-creation path.
  Future<OrderModel?> getOrderByNumber(String orderNumber) async {
    final snapshot = await _ordersRef
        .where('orderNumber', isEqualTo: orderNumber)
        .limit(1)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking the order number'));

    if (snapshot.docs.isEmpty) return null;
    return OrderModel.fromFirestore(snapshot.docs.first);
  }

  /// ROOT-CAUSE FIX for "order creation failed:
  /// [cloud_firestore/permission-denied] Missing or insufficient
  /// permissions" — atomically allocates and returns the next
  /// available sequence number (1, 2, 3, ...) for [datePart]
  /// (YYYYMMDD), via a Firestore transaction on a single counter
  /// document at counters/orders_{datePart}.
  ///
  /// [OrderRepository._generateUniqueOrderNumber] used to do this by
  /// looping candidate numbers and calling [getOrderByNumber] to ask
  /// "does this already exist?" before trying the next one. That
  /// query — .where('orderNumber', isEqualTo: candidate) — has no
  /// userId filter, but firestore.rules' orders read rule
  /// requires resource.data.userId == request.auth.uid. Firestore
  /// can only allow a \list\ query when it can prove, from the
  /// query's structure alone, that every possible matching document
  /// satisfies the rule — it never evaluates rules against actual
  /// results before deciding whether to run the query at all. Since
  /// this query isn't restricted by userId, Firestore can't prove
  /// that, and rejects the ENTIRE query with permission-denied
  /// before it ever runs — for every plain customer, on every single
  /// order, 100% of the time (an admin's isAdmin() check happens to
  /// satisfy the rule without touching resource.data, which is why
  /// this wasn't caught by admin-only testing). The write immediately
  /// after (createOrder's own .set()) never even gets a chance to
  /// run.
  ///
  /// This transaction reads and writes only counters/orders_
  /// {datePart} — a small document containing nothing but the last
  /// sequence handed out, no order/customer data — so it needs its
  /// own permissive-but-safe rule (counters/{counterId}: any signed-
  /// in user may read/write) rather than inheriting orders'
  /// per-owner restriction. It also fixes a latent race the old
  /// loop-based check never fully closed: two customers checking out
  /// at the same moment could both read "not taken yet" for the same
  /// candidate before either one's write landed. A transaction's
  /// read+increment+write is atomic, so Firestore itself serializes
  /// concurrent callers instead of relying on who wins a network race.
  ///
  /// [OrderRepository._maxSequencePerDay] is still enforced by the
  /// caller, exactly as before — this method just returns whatever
  /// integer comes after the last one, however large.
  Future<int> nextOrderSequence(String datePart) {
    final counterRef = _countersRef.doc('orders_$datePart');

    return FirebaseService.firestore
        .runTransaction<int>((transaction) async {
          final snapshot = await transaction.get(counterRef);

          // ROOT-CAUSE FIX for "order creation failed: Error: Dart exception
          // thrown from converted Future" (every single order, not just an
          // edge case): on Flutter Web, Firestore's JS SDK has only one
          // numeric type, so a whole-number field like lastSequence can
          // come back as a Dart double even though it was written as an
          // int — the exact same "int or double" gotcha already called
          // out and handled in DetergentModel.fromFirestore/ServiceModel
          // for additionalPrice/pricePerKg. This was the one spot in
          // the codebase that cast straight as int? instead of going
          // through num? first, so the very first time this ran with an
          // existing counter document it hit a TypeError: type 'double' is
          // not a subtype of type 'int?' INSIDE this transaction's update
          // function.
          //
          // That callback isn't a normal Dart call site: cloud_firestore_web
          // bridges it into the underlying JS SDK's runTransaction via
          // dart:js_interop's Future.toJS, which — on any Dart exception —
          // boxes it into a generic JS Error (see
          // https://api.dart.dev/dart-js_interop/FutureOfJSAnyToJSPromise/toJS.html)
          // whose own message is literally "Dart exception thrown from
          // converted Future...". That's the exact string that was showing
          // up here and in OrderSummaryScreen's log — the real TypeError
          // was never a FirebaseException, so _unwrapJsConversionError's
          // dynamic .error access couldn't find a matching Dart getter on
          // the raw JS wrapper either, and both layers fell through to
          // their most generic message.
          //
          // Fixed at the source: normalize via num? first, exactly like
          // every other numeric Firestore field in this project, so no
          // exception is thrown inside the transaction in the first place.
          final current = (snapshot.data()?['lastSequence'] as num?)?.toInt() ?? 0;
          final next = current + 1;

          transaction.set(counterRef, {'lastSequence': next});
          return next;
        })
        .timeout(_timeout, onTimeout: () => throw _timeoutException('generating an order number'));
  }

  /// Looks up a single order by its Firestore document ID — e.g. for
  /// PART 13's order details screen, which navigates using the
  /// document ID rather than re-parsing the order number back into a
  /// query every time.
  Future<OrderModel?> getOrderByDocId(String docId) async {
    final doc = await _ordersRef
        .doc(docId)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading the order'));

    if (!doc.exists) return null;
    return OrderModel.fromFirestore(doc);
  }

  /// PART 13.1 — real-time stream of every order belonging to
  /// [userId], newest first, for "My Orders".
  ///
  /// This is a .snapshots() listener rather than a one-shot .get()
  /// like the methods above, deliberately: it's also the same query
  /// PART 14 reuses for live status tracking, so a customer sees an
  /// Admin-triggered status change (Pending → Received → ...) without
  /// ever pulling to refresh.
  ///
  /// NOTE: Sorts client-side rather than chaining
  /// .orderBy('createdAt', descending: true) after
  /// .where('userId', ...). That where()+orderBy() combination on
  /// different fields needs a Firestore composite index (userId +
  /// createdAt) that was never created — the resulting
  /// failed-precondition on this \listener\ was corrupting the
  /// Firestore web SDK's client state badly enough to break unrelated
  /// writes elsewhere in the app (e.g. placing a brand-new order).
  /// Same fix already applied to Service/LaundryItem/
  /// DetergentDatasource for the same reason.
  ///
  /// Unlike [createOrder]/[getOrderByNumber]/[getOrderByDocId], stream
  /// errors (e.g. a dropped connection) are surfaced through the
  /// stream's own error channel rather than a thrown [Future] —
  /// [OrderRepository] passes this straight through, and the screen's
  /// StreamBuilder is what reacts to snapshot.hasError.
  Stream<List<OrderModel>> streamOrdersForUser(String userId) {
    return _ordersRef.where('userId', isEqualTo: userId).snapshots().map((snapshot) {
      final orders = snapshot.docs.map((doc) => OrderModel.fromFirestore(doc)).toList();
      orders.sort(_byCreatedAtDescending);
      return orders;
    });
  }

  /// PART 15 — real-time stream of every order in the system, newest
  /// first, for the Admin Dashboard's stats (Total Orders, Pending
  /// Orders, Total Revenue), order status summary, and recent-orders
  /// list.
  ///
  /// Same shape as [streamOrdersForUser] minus the userId filter —
  /// intentionally unrestricted, since only an Admin-guarded screen
  /// ever calls this (enforced by [RoleGuard] wrapping the dashboard
  /// route, not by this query). PART 16's admin order management
  /// reuses this same stream rather than duplicating it.
  ///
  /// Left as a server-side .orderBy() — unlike [streamOrdersForUser],
  /// there's no .where() alongside it, so this is a single-field
  /// sort and Firestore indexes it automatically. No composite index
  /// needed, so no change needed here.
  Stream<List<OrderModel>> streamAllOrders() {
    return _ordersRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => OrderModel.fromFirestore(doc)).toList());
  }

  /// PART 14.1 — real-time stream of a single order document by its
  /// Firestore document ID, for [OrderStatusTracker].
  ///
  /// Unlike [getOrderByDocId] (a one-shot .get()), this is a
  /// .snapshots() listener: it's what lets a customer watching
  /// their order's tracker see an Admin-triggered status change
  /// (PART 16) the instant it's written to Firestore, with no pull-
  /// to-refresh or re-navigation needed — the same real-time pattern
  /// [streamOrdersForUser] already uses for the order list, just
  /// scoped to one document instead of a query.
  ///
  /// Emits null if the document doesn't exist (e.g. it was deleted
  /// out from under an open tracker), so callers can tell "genuinely
  /// gone" apart from "still loading" instead of only ever seeing a
  /// stream error.
  Stream<OrderModel?> streamOrderByDocId(String docId) {
    return _ordersRef.doc(docId).snapshots().map(
      (doc) => doc.exists ? OrderModel.fromFirestore(doc) : null,
    );
  }

  /// PART 16 — updates a single order's status field, stamping
  /// updatedAt with the server's clock via
  /// [FieldValue.serverTimestamp] rather than the Admin device's —
  /// same "server decides, never the device" rule [createOrder]
  /// already follows for createdAt/updatedAt.
  ///
  /// Uses Firestore's .update(), not .set(), so it can never
  /// touch any field on the order besides these two — no risk of
  /// accidentally overwriting pricing, items, or delivery info while
  /// changing a status.
  ///
  /// This is what makes PART 14.1's [OrderStatusTracker] (and PART
  /// 14.4's notification sync) update the instant an Admin acts here:
  /// both are already subscribed to this same document via
  /// [streamOrderByDocId]/[streamOrdersForUser], so a write here is
  /// all it takes — nothing needs to explicitly "push" anything to
  /// the customer.
  ///
  /// [OrderRepository.updateOrderStatus] is what validates \whether\
  /// [newStatus] is a legal transition before ever calling this — this
  /// datasource method trusts its caller completely, same as every
  /// other write in this class.
  Future<void> updateOrderStatus(String docId, OrderStatus newStatus) async {
    await _ordersRef
        .doc(docId)
        .update({'status': newStatus.value, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(_timeout, onTimeout: () => throw _timeoutException('updating the order status'));
  }

  /// PART 3 (Order Details → Change Address) — updates only the
  /// pickup-address fields of a single order document, stamping
  /// updatedAt with the server's clock exactly like
  /// [updateOrderStatus] does for status changes.
  ///
  /// [fields] is expected to be the subset of [OrderModel.toMap]'s
  /// keys that describe the pickup address (`address`, `pickupPhone`,
  /// `pickupFullName`, `pickupStreetAddress`, `pickupRegionName`,
  /// `pickupProvinceName`, `pickupCityName`, `pickupBarangayName`,
  /// `pickupPostalCode`) — built by
  /// [OrderRepository.updateOrderAddress], never the whole
  /// [OrderModel.toMap]. Using `.update()` with just that subset,
  /// not `.set()`, means this can never touch pricing, items,
  /// status, [OrderModel.location], [OrderModel.pickupLandmark], or
  /// anything else on the order — matching this part's "update only
  /// this order['s address]" and "do not modify other orders" rules.
  Future<void> updateOrderAddress(String docId, Map<String, dynamic> fields) async {
    await _ordersRef
        .doc(docId)
        .update({...fields, 'updatedAt': FieldValue.serverTimestamp()})
        .timeout(_timeout, onTimeout: () => throw _timeoutException('updating the pickup address'));
  }

  /// Newest first. createdAt can briefly be null immediately after
  /// [createOrder] writes (the local snapshot arrives before the
  /// server timestamp resolves), so nulls sort to the end rather than
  /// crashing the comparator.
  int _byCreatedAtDescending(OrderModel a, OrderModel b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }
}