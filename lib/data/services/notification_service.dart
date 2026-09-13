import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/notification_model.dart';
import '../../models/order_model.dart';

/// PART 14.3 — Firestore-backed notification system.
///
/// Sits directly on top of Firestore's `notifications` collection,
/// the same way [OrderDatasource] sits on top of `orders` — no
/// Flutter/UI imports, nothing here decides *what a screen shows*,
/// only how a [NotificationModel] gets created, fetched, streamed,
/// and marked read. PART 14.4's Notifications screen and its order-
/// status integration are the only things that call this class.
///
/// Unlike `OrderRepository`/`OrderDatasource`, this is deliberately a
/// single file rather than a split datasource+repository pair — the
/// spec for this part asks for one `notification_service.dart`, and
/// the "business rule" side of this service (which status maps to
/// which title/message, and refusing to create the same status
/// notification twice) is small enough to live next to the Firestore
/// calls themselves without the extra layer earning its keep.
class NotificationService {
  NotificationService();

  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _notificationsRef =>
      FirebaseService.firestore.collection('notifications');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  // -------------------- Status → title/message text --------------------

  /// Human-readable titles for each [NotificationType], matching this
  /// part's examples ("Order Received", etc.) and PART 14.4's
  /// "Order Washing" / "Order Drying" / "Order Ready" / "Order
  /// Completed" naming for the remaining statuses.
  static const Map<NotificationType, String> _titles = {
    NotificationType.orderCreated: 'Order Successfully Placed',
    NotificationType.received: 'Order Received',
    NotificationType.washing: 'Order Washing',
    NotificationType.drying: 'Order Drying',
    NotificationType.ready: 'Order Ready',
    NotificationType.completed: 'Order Completed',
  };

  /// Body text for each [NotificationType]. [orderNumber] is
  /// interpolated the same way this part's own "Order Received"
  /// example does ("Your laundry order ORD-20260902-0001 has been
  /// received.").
  String _messageFor(NotificationType type, String orderNumber) {
    switch (type) {
      case NotificationType.orderCreated:
        return 'Your order $orderNumber has been successfully placed.';
      case NotificationType.received:
        return 'Your laundry order $orderNumber has been received.';
      case NotificationType.washing:
        return 'Your laundry order $orderNumber is now being washed.';
      case NotificationType.drying:
        return 'Your laundry order $orderNumber is now drying.';
      case NotificationType.ready:
        return 'Your laundry order $orderNumber is ready for pickup.';
      case NotificationType.completed:
        return 'Your laundry order $orderNumber has been completed.';
    }
  }

  /// Builds the [NotificationModel] for [order] transitioning into (or
  /// starting at) [type] — pure data assembly, no Firestore call.
  /// Exposed as its own method (rather than folded into
  /// [createStatusNotification]) so PART 14.4 can preview/log the
  /// notification it's about to create without a network round trip.
  NotificationModel buildNotification({
    required OrderModel order,
    required NotificationType type,
  }) {
    final orderId = order.id;
    if (orderId == null) {
      throw ArgumentError(
        'Cannot build a notification for an order with no document ID.',
      );
    }
    return NotificationModel(
      userId: order.userId,
      orderId: orderId,
      orderNumber: order.orderNumber,
      title: _titles[type]!,
      message: _messageFor(type, order.orderNumber),
      type: type,
      isRead: false,
    );
  }

  /// Maps an [OrderStatus] to the [NotificationType] that should fire
  /// when an order *enters* that status, per PART 14.4's transition
  /// table (pending→received, received→washing, washing→drying,
  /// drying→ready, ready→completed). Returns null for
  /// [OrderStatus.pending] (that moment is [NotificationType
  /// .orderCreated], fired once at creation — see
  /// [notifyOrderCreated] — not a status-change notification) and for
  /// [OrderStatus.cancelled] (out of scope until PART 16's admin
  /// cancellation flow exists, same reasoning as
  /// [NotificationModel]'s doc comment).
  static NotificationType? notificationTypeForStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.received:
        return NotificationType.received;
      case OrderStatus.washing:
        return NotificationType.washing;
      case OrderStatus.drying:
        return NotificationType.drying;
      case OrderStatus.ready:
        return NotificationType.ready;
      case OrderStatus.completed:
        return NotificationType.completed;
      case OrderStatus.pending:
      case OrderStatus.cancelled:
        return null;
    }
  }

  // -------------------- Duplicate prevention --------------------

  /// True if a notification of [type] already exists for [orderId].
  ///
  /// This is what makes repeated Firestore snapshot events for the
  /// same status (e.g. `washing → washing → washing`, the exact case
  /// called out in this part's spec) produce exactly one "Order
  /// Washing" notification instead of one per event: PART 14.4's
  /// integration calls [createStatusNotification] on every snapshot,
  /// and this check is what turns the ones that aren't a genuine new
  /// status into no-ops.
  ///
  /// Scoped to one order at a time (`orderId` + `type`) rather than
  /// checked globally, so it can never mistake *this* order's
  /// "Washing" notification for a different order's, and doesn't
  /// require an extra composite index beyond the one Firestore
  /// suggests the first time this query runs.
  Future<bool> _hasNotification({
    required String orderId,
    required NotificationType type,
  }) async {
    final snapshot = await _notificationsRef
        .where('orderId', isEqualTo: orderId)
        .where('type', isEqualTo: type.value)
        .limit(1)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking notifications'));
    return snapshot.docs.isNotEmpty;
  }

  // -------------------- Create --------------------

  /// Creates [notification] in Firestore, unless one of the same
  /// [NotificationModel.type] already exists for its
  /// [NotificationModel.orderId] — in which case this is a no-op and
  /// returns null, per this part's duplicate-safety requirement.
  ///
  /// Returns the created [NotificationModel] with its new
  /// [NotificationModel.notificationId] attached (mirroring
  /// [OrderDatasource.createOrder]'s "hand the ID straight back"
  /// shape) so a caller never needs a second read just to learn what
  /// ID it got.
  ///
  /// Throws [ArgumentError] for missing required data (empty
  /// [NotificationModel.orderId]/[NotificationModel.userId]) rather
  /// than silently writing a half-empty document — this is this
  /// part's "missing notification data" error case. Any
  /// [FirebaseException] (network failure, permission denied,
  /// timeout) is left uncaught, same as every datasource-level method
  /// elsewhere in this project: the caller decides what the UI says.
  Future<NotificationModel?> createNotification(NotificationModel notification) async {
    if (notification.orderId.isEmpty || notification.userId.isEmpty) {
      throw ArgumentError(
        'Cannot create a notification without an orderId and userId.',
      );
    }

    final alreadyExists = await _hasNotification(
      orderId: notification.orderId,
      type: notification.type,
    );
    if (alreadyExists) {
      // Same status seen again on a repeated stream event — not a new
      // transition, so nothing to create.
      return null;
    }

    final docRef = _notificationsRef.doc();
    await docRef
        .set(notification.toMap())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the notification'));
    return notification.copyWith(notificationId: docRef.id);
  }

  /// Convenience wrapper: builds and creates the one-time "Order
  /// Successfully Placed" notification for a just-created [order].
  /// Meant to be called once, right after `OrderRepository.createOrder`
  /// returns — PART 14.4 wires this in without changing the order
  /// creation flow itself (this part's "do not change the existing
  /// order creation system" requirement stays satisfied: this is an
  /// additive call *after* creation, not a change to it).
  Future<NotificationModel?> notifyOrderCreated(OrderModel order) {
    return createNotification(
      buildNotification(order: order, type: NotificationType.orderCreated),
    );
  }

  /// Convenience wrapper: builds and creates the notification for
  /// [order] having just moved into [type]. Duplicate-safe via
  /// [createNotification] — safe to call on every status-changed
  /// event PART 14.4's integration observes, not just the first one.
  Future<NotificationModel?> notifyStatusChange({
    required OrderModel order,
    required NotificationType type,
  }) {
    return createNotification(buildNotification(order: order, type: type));
  }

  // -------------------- Read --------------------

  /// One-shot fetch of every notification belonging to [userId],
  /// newest first. Mirrors [OrderDatasource.getOrderByNumber]'s
  /// "single [FirebaseException] left uncaught" contract — PART
  /// 14.4's screen decides how a fetch failure is shown.
  ///
  /// NOTE: Filters by [userId] only and sorts client-side, rather
  /// than chaining `.orderBy('createdAt', descending: true)` after
  /// `.where('userId', ...)` — see [streamUserNotifications] below
  /// for why that combination is dangerous here.
  Future<List<NotificationModel>> getUserNotifications(String userId) async {
    final snapshot = await _notificationsRef
        .where('userId', isEqualTo: userId)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading notifications'));
    final notifications = snapshot.docs.map(NotificationModel.fromFirestore).toList();
    notifications.sort(_byCreatedAtDescending);
    return notifications;
  }

  /// Real-time stream of every notification belonging to [userId],
  /// newest first — the same `.snapshots()` shape
  /// [OrderDatasource.streamOrdersForUser] uses for orders, so PART
  /// 14.4's Notifications screen sees a brand-new notification the
  /// instant [createNotification] writes it, with no manual refresh.
  ///
  /// NOTE: Sorts client-side rather than chaining
  /// `.orderBy('createdAt', descending: true)` after
  /// `.where('userId', ...)`. That where()+orderBy() combination on
  /// different fields needs a Firestore composite index (userId +
  /// createdAt) — if that index isn't fully deployed/built yet, the
  /// resulting `failed-precondition` on this *listener* corrupts the
  /// Firestore web SDK's client state badly enough to break unrelated
  /// writes elsewhere in the app (e.g. placing a brand-new order),
  /// and this listener starts the instant the User Dashboard mounts
  /// (it backs the bottom-nav unread badge on every tab), so it can
  /// wedge the whole session before the customer does anything else.
  /// Same fix already applied to Order/Service/LaundryItem/
  /// DetergentDatasource for the same reason.
  Stream<List<NotificationModel>> streamUserNotifications(String userId) {
    return _notificationsRef.where('userId', isEqualTo: userId).snapshots().map((snapshot) {
      final notifications = snapshot.docs.map(NotificationModel.fromFirestore).toList();
      notifications.sort(_byCreatedAtDescending);
      return notifications;
    });
  }

  /// Newest first. `createdAt` can briefly be null immediately after
  /// [createNotification] writes (the local snapshot arrives before
  /// the server timestamp resolves), so nulls sort to the end rather
  /// than crashing the comparator — mirrors
  /// [OrderDatasource._byCreatedAtDescending].
  int _byCreatedAtDescending(NotificationModel a, NotificationModel b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return bTime.compareTo(aTime);
  }

  // -------------------- Update --------------------

  /// Marks a single notification as read. Only touches `isRead` —
  /// never rewrites `createdAt`/content — so PART 14.4's "tap a
  /// notification to mark it read" action can never accidentally
  /// alter what the notification says or when it happened.
  ///
  /// Throws [ArgumentError] for a blank [notificationId] (this part's
  /// "missing notification data" case) instead of sending a
  /// malformed Firestore call. Any [FirebaseException] is left
  /// uncaught, same contract as every write above.
  Future<void> markAsRead(String notificationId) async {
    if (notificationId.isEmpty) {
      throw ArgumentError('Cannot mark a notification as read without an ID.');
    }
    await _notificationsRef
        .doc(notificationId)
        .update({'isRead': true}).timeout(
          _timeout,
          onTimeout: () => throw _timeoutException('updating the notification'),
        );
  }
}