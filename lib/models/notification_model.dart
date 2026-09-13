import 'package:cloud_firestore/cloud_firestore.dart';

/// PART 14.2 — the six moments in an order's lifecycle that generate
/// an in-app notification (PART 14.3's `NotificationService`).
///
/// Deliberately excludes `pending`/`cancelled` as notification
/// *types*: [orderCreated] covers the "order placed" moment instead
/// of a raw `pending` notification (a customer doesn't need telling
/// their own just-placed order is pending), and a cancellation
/// notification type is out of scope until an Admin cancellation flow
/// exists (PART 16) to actually trigger one.
enum NotificationType { orderCreated, received, washing, drying, ready, completed }

extension NotificationTypeX on NotificationType {
  /// Firestore-safe string form — `order_created`, not `orderCreated`,
  /// matching the spec's snake_case type values exactly.
  String get value {
    switch (this) {
      case NotificationType.orderCreated:
        return 'order_created';
      case NotificationType.received:
        return 'received';
      case NotificationType.washing:
        return 'washing';
      case NotificationType.drying:
        return 'drying';
      case NotificationType.ready:
        return 'ready';
      case NotificationType.completed:
        return 'completed';
    }
  }

  /// Inverse of [value]. Falls back to [NotificationType.orderCreated]
  /// for `null`/unrecognized values — same "safe default over a
  /// thrown exception" choice [OrderStatusX.fromValue] makes for
  /// [OrderStatus], so a malformed/legacy document renders as
  /// *something* sensible instead of crashing PART 14.4's list.
  static NotificationType fromValue(String? value) {
    switch (value) {
      case 'received':
        return NotificationType.received;
      case 'washing':
        return NotificationType.washing;
      case 'drying':
        return NotificationType.drying;
      case 'ready':
        return NotificationType.ready;
      case 'completed':
        return NotificationType.completed;
      case 'order_created':
      default:
        return NotificationType.orderCreated;
    }
  }
}

/// PART 14.2 — a single in-app notification tied to one order's
/// status history and the customer who should see it.
///
/// Pure Dart, no Flutter imports (only [Timestamp]/[FieldValue] for
/// Firestore's date shape, the same trade-off [OrderModel] makes) —
/// mirrors every other model in `models/`: independent from the UI,
/// and independent from PART 14.3's `NotificationService`, which is
/// the only thing that will actually read/write these to Firestore.
/// Nothing here decides *when* a notification should be created —
/// that duplicate-prevention logic belongs to PART 14.3, not this
/// model.
class NotificationModel {
  /// Firestore document ID. Null until PART 14.3's service actually
  /// creates the document — mirrors [OrderModel.id].
  final String? notificationId;

  /// Whose "Notifications" tab this belongs to — every Firestore
  /// query in PART 14.3 filters on this, the same "own data only"
  /// pattern as [OrderModel.userId].
  final String userId;

  /// The order this notification is about. Kept alongside
  /// [orderNumber] for the same reason [OrderModel] keeps both
  /// `serviceId` and `serviceName`: PART 14.4's Notifications screen
  /// can show/link to the order without an extra Firestore read, and
  /// the human-readable number stays meaningful to the customer even
  /// though [orderId] alone wouldn't be.
  final String orderId;
  final String orderNumber;

  final String title;
  final String message;

  final NotificationType type;

  final bool isRead;

  final DateTime? createdAt;

  const NotificationModel({
    this.notificationId,
    required this.userId,
    required this.orderId,
    required this.orderNumber,
    required this.title,
    required this.message,
    required this.type,
    this.isRead = false,
    this.createdAt,
  });

  /// Same shape as [OrderModel]'s private date parser — a single date
  /// field that may arrive as a Firestore [Timestamp] (the normal
  /// case, reading from Firestore), an ISO-8601 [String] ([toJson]'s
  /// shape), or already a [DateTime] (defensive, for a hand-built
  /// map). Returns null for anything else, including the transient
  /// null [FieldValue.serverTimestamp()] leaves right after a write,
  /// before the server timestamp round-trips back down.
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Firestore-shaped map — [createdAt] is written as a [Timestamp]
  /// (or [FieldValue.serverTimestamp] when not yet set), matching
  /// [OrderModel.toMap]'s "the server's clock decides, never the
  /// device's" rule. This is what PART 14.3's service passes to a
  /// Firestore write, not `jsonEncode`.
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'orderId': orderId,
      'orderNumber': orderNumber,
      'title': title,
      'message': message,
      'type': type.value,
      'isRead': isRead,
      'createdAt':
          createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  /// Builds a [NotificationModel] from a Firestore-shaped map (i.e.
  /// what [toMap] produces, or `doc.data()`). [notificationId] is
  /// passed separately because a raw Firestore map never contains its
  /// own document ID — see [NotificationModel.fromFirestore], which
  /// supplies it automatically.
  factory NotificationModel.fromMap(Map<String, dynamic> map, {String? notificationId}) {
    return NotificationModel(
      notificationId: notificationId,
      userId: map['userId'] as String? ?? '',
      orderId: map['orderId'] as String? ?? '',
      orderNumber: map['orderNumber'] as String? ?? '',
      title: map['title'] as String? ?? '',
      message: map['message'] as String? ?? '',
      type: NotificationTypeX.fromValue(map['type'] as String?),
      isRead: map['isRead'] as bool? ?? false,
      createdAt: _parseDate(map['createdAt']),
    );
  }

  /// Convenience wrapper around [fromMap] for the common case of
  /// reading straight off a Firestore snapshot — matches every other
  /// model's `fromFirestore` factory ([OrderModel], `UserModel`,
  /// ...). This is what PART 14.3's service will use for both the
  /// one-shot "get user notifications" call and the real-time stream.
  factory NotificationModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return NotificationModel.fromMap(doc.data() ?? {}, notificationId: doc.id);
  }

  /// Plain-JSON shape — unlike [toMap], [createdAt] is written as an
  /// ISO-8601 string (never [FieldValue.serverTimestamp], which only
  /// means something inside a Firestore write) so the result is safe
  /// to pass to `jsonEncode` or log directly.
  Map<String, dynamic> toJson() {
    return {
      'notificationId': notificationId,
      'userId': userId,
      'orderId': orderId,
      'orderNumber': orderNumber,
      'title': title,
      'message': message,
      'type': type.value,
      'isRead': isRead,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      notificationId: json['notificationId'] as String?,
      userId: json['userId'] as String? ?? '',
      orderId: json['orderId'] as String? ?? '',
      orderNumber: json['orderNumber'] as String? ?? '',
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
      type: NotificationTypeX.fromValue(json['type'] as String?),
      isRead: json['isRead'] as bool? ?? false,
      createdAt: _parseDate(json['createdAt']),
    );
  }

  /// Used by PART 14.3's service once it has a real document ID to
  /// return to the caller, and by PART 14.4's "mark notification as
  /// read" action — both only ever need to change one of these two
  /// fields, never the notification's content.
  NotificationModel copyWith({
    String? notificationId,
    bool? isRead,
  }) {
    return NotificationModel(
      notificationId: notificationId ?? this.notificationId,
      userId: userId,
      orderId: orderId,
      orderNumber: orderNumber,
      title: title,
      message: message,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationModel &&
          other.notificationId != null &&
          other.notificationId == notificationId);

  @override
  int get hashCode => notificationId?.hashCode ?? identityHashCode(this);

  @override
  String toString() =>
      'NotificationModel(title: $title, type: ${type.value}, isRead: $isRead)';
}