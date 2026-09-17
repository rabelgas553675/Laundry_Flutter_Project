import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/service_unit.dart';
import '../features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'order_item_model.dart';

/// The lifecycle a placed order moves through, per PART 14's tracking
/// workflow:
///
///   pending → received → washing → drying → ready → completed
///
/// [cancelled] is a terminal state reachable from most of the above.
/// Declared here (rather than only in PART 14) since [OrderModel]
/// needs a concrete default value — [OrderStatus.pending] — the
/// moment an order is created in PART 12.3, well before PART 14's
/// tracker UI exists.
enum OrderStatus { pending, received, washing, drying, ready, completed, cancelled }

extension OrderStatusX on OrderStatus {
  String get value => name;

  static OrderStatus fromValue(String? value) {
    switch (value) {
      case 'received':
        return OrderStatus.received;
      case 'washing':
        return OrderStatus.washing;
      case 'drying':
        return OrderStatus.drying;
      case 'ready':
        return OrderStatus.ready;
      case 'completed':
        return OrderStatus.completed;
      case 'cancelled':
        return OrderStatus.cancelled;
      case 'pending':
      default:
        return OrderStatus.pending;
    }
  }
}

/// [DeliveryMethod] (`pickup` / `dropoff`) is reused from
/// `laundry_order_screen.dart` rather than redeclared here — same
/// reasoning as `OrderDraft` (PART 11.2): the order form and every
/// downstream model should never be able to drift out of sync on
/// what "Pickup" vs "Drop-off" means. This extension is what lets
/// [OrderModel] read/write that enum as a plain Firestore string.
extension DeliveryMethodX on DeliveryMethod {
  String get value => name; // 'pickup' or 'dropoff'

  static DeliveryMethod fromValue(String? value) {
    switch (value) {
      case 'dropoff':
        return DeliveryMethod.dropoff;
      case 'pickup':
      default:
        return DeliveryMethod.pickup;
    }
  }
}

/// PART 12.1 — mirrors the Firestore document that PART 12.2's
/// datasource will write to/read from at `orders/{orderId}`.
///
/// This is the persisted counterpart to PART 11.2's `OrderDraft`:
/// `OrderDraft` only ever lives in the order form's and summary
/// screen's memory, while [OrderModel] is what PART 12.3's repository
/// builds *from* a confirmed `OrderDraft` and actually saves. Nothing
/// in this file touches Firestore, Firebase, or the UI — it is pure
/// Dart, matching every other model in `models/`.
///
/// Field list matches the PART 12.1/12.2 spec exactly
/// (orderNumber, userId, serviceId, serviceName, weight, detergentId,
/// method, address, location, subtotal, detergentFee, pickupFee,
/// discount, total, status, createdAt, updatedAt), plus a handful of
/// additions kept intentionally minimal and clearly marked below —
/// without them, real information the customer already entered on
/// the PART 10 form would otherwise be silently dropped the moment
/// it's converted into a persisted order.
class OrderModel {
  /// Firestore document ID. Null until PART 12.3's repository
  /// actually creates the document — an [OrderModel] can be fully
  /// constructed and priced before it has one.
  final String? id;

  final String orderNumber;
  final String userId;

  final String serviceId;
  final String serviceName;

  /// Weight in kilograms, entered on the PART 10.1 order form.
  ///
  /// Kept as `weight` (not renamed) for the same reason
  /// `ServiceModel.pricePerKg` wasn't renamed: every existing call
  /// site — `PriceCalculator`, `pdf_service.dart`, PART 13/16's order
  /// screens — keeps reading this field unchanged. For a per-piece
  /// order (Part 2 onward) this holds the piece count instead of a
  /// weight; what it actually means is given by [serviceUnit], never
  /// by re-deriving it from [serviceName].
  final double weight;

  /// Part 1 (per-piece pricing) — the unit [weight] was priced under
  /// *at the moment this order was created*, captured here so a
  /// historical order keeps displaying correctly (e.g. `"3 pcs"`)
  /// even if an admin later changes that service's configured unit,
  /// renames it, or deactivates it. Order screens/receipts must
  /// always read this field instead of looking up the service's
  /// *current* unit from [ServiceRepository].
  ///
  /// This is deliberately the only model change Part 1 makes to
  /// [OrderModel] — actually setting a real piece quantity/validating
  /// it/rendering it as `"pcs"` throughout the ordering flow is Part
  /// 2's scope. For now, [OrderRepository.createOrder] simply copies
  /// the selected service's current [ServiceModel.unit] onto the
  /// order at creation time, exactly like it already does for
  /// [serviceName].
  final ServiceUnit serviceUnit;

  final String detergentId;

  /// Not in the literal PART 12.1 field list, but added for the same
  /// reason [serviceName] sits next to [serviceId]: PART 13/16 order
  /// screens should be able to show what detergent was used without
  /// an extra Firestore read, and it stays accurate even if an admin
  /// later renames or deactivates the detergent.
  final String detergentName;

  /// The individual laundry item categories on this order (PART
  /// 12.1's other new model). Stored as a plain array of maps on the
  /// order document — see [OrderItemModel.listToMap]/[listFromMap].
  final List<OrderItemModel> items;

  final DeliveryMethod method;

  /// Pickup street address. Null for Drop-off.
  final String? address;

  /// Pickup area/zone label (PART 10.3's `LocationAreaModel.label`).
  /// Null for Drop-off.
  final String? location;

  /// Not in the literal PART 12.1 field list. The PART 10.2 form also
  /// collects a pickup phone number and landmark — dropping them here
  /// would mean an admin (PART 16) could never see how to actually
  /// reach the customer for their pickup, so they're kept as optional
  /// extras alongside [address]/[location]. Null for Drop-off.
  final String? pickupPhone;
  final String? pickupLandmark;

  /// PART 3 fix — the customer's optional free-text note
  /// (`OrderDraft.specialInstructions`, e.g. "Handle carefully")
  /// was collected on the PART 10.2 form but never actually made it
  /// onto a persisted order: this field didn't exist, so
  /// `OrderRepository.createOrder` had nowhere to put it and it was
  /// silently discarded. Both this screen's Order Details and the
  /// admin's order view need to show it (per this part's spec), so
  /// it's added here, in [toMap]/[fromMap]/[toJson]/[fromJson], and
  /// wired through by `OrderRepository.createOrder`. `null`/empty for
  /// every order placed before this fix, and for any order where the
  /// customer left it blank.
  final String? specialInstructions;

  final double subtotal;
  final double detergentFee;
  final double pickupFee;
  final double discount;
  final double total;

  /// PART 3 — the promo code applied to this order (e.g. "WELCOME20"),
  /// if the customer selected/redeemed one on the Offers screen before
  /// checking out. `null` for an order placed without any promo.
  ///
  /// This is captured as a plain string snapshot, not a live reference
  /// to a `promos/{id}` document: a historical order must keep showing
  /// exactly what code was used and how much it took off ([discount])
  /// even if that promo is later edited, deactivated, or deleted by an
  /// admin. [discount] itself is always the authoritative amount that
  /// was actually taken off this order's [subtotal] — [promoCode] is
  /// purely a label for "why", never re-derived to recompute pricing.
  final String? promoCode;

  /// Human-readable summary of what [promoCode] was worth at the time
  /// this order was placed (e.g. "20% off" or "₱50 off") — see
  /// `PromoModel.discountLabel`. Stored alongside [promoCode] for the
  /// same reason: so "Promo: 20% OFF" keeps displaying correctly on
  /// this order forever, even if the promo's own discount value is
  /// changed or the promo is deleted later. `null` when [promoCode]
  /// is `null`.
  final String? promoDiscountLabel;

  final OrderStatus status;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const OrderModel({
    this.id,
    required this.orderNumber,
    required this.userId,
    required this.serviceId,
    required this.serviceName,
    required this.weight,
    this.serviceUnit = ServiceUnit.kilogram,
    required this.detergentId,
    this.detergentName = '',
    this.items = const [],
    required this.method,
    this.address,
    this.location,
    this.pickupPhone,
    this.pickupLandmark,
    this.specialInstructions,
    required this.subtotal,
    this.detergentFee = 0,
    this.pickupFee = 0,
    this.discount = 0,
    required this.total,
    this.promoCode,
    this.promoDiscountLabel,
    this.status = OrderStatus.pending,
    this.createdAt,
    this.updatedAt,
  });

  bool get isPickup => method == DeliveryMethod.pickup;

  /// PART 3 — whether this order was priced per line (Dry Cleaning-
  /// style: `2 × Suit = ₱300`, summed across [items]) rather than by
  /// weight/piece-count against a single `pricePerKg`.
  ///
  /// True when at least one persisted [OrderItemModel] line carries
  /// its own [OrderItemModel.unitPrice] — exactly what
  /// `OrderRepository.createOrder` writes into [items] for a
  /// `ServiceType.isItemized` service (see `OrderDraft.isItemized`/
  /// `OrderDraft.selectedItems`), and never writes for a weight-based
  /// one (those items are plain, unpriced `LaundryItemModel` tags
  /// with `unitPrice == 0`). Computed from the persisted data itself
  /// — not from [serviceName] or a separately-stored flag — so it
  /// works for every historical order without a migration, and can
  /// never drift out of sync with what was actually charged.
  bool get isItemized => items.any((item) => item.unitPrice > 0);

  /// Reads a single date field that may arrive as any of:
  /// - a Firestore [Timestamp] (normal case, reading from Firestore),
  /// - an ISO-8601 [String] (the shape [toJson] writes, for plain
  ///   non-Firestore JSON — e.g. logging, tests, a future export),
  /// - already a [DateTime] (defensive — in case a caller builds the
  ///   map by hand instead of via [toMap]/[toJson]).
  ///
  /// Returns null for anything else, including
  /// [FieldValue.serverTimestamp()]'s transient null right after a
  /// write (before the server timestamp round-trips back down).
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  /// Firestore-shaped map — [createdAt]/[updatedAt] are written as
  /// [Timestamp]s (or [FieldValue.serverTimestamp()] when not yet
  /// set, e.g. before PART 12.3 first creates the document), so this
  /// method is meant to be passed to Firestore, not `jsonEncode`.
  Map<String, dynamic> toMap() {
    return {
      'orderNumber': orderNumber,
      'userId': userId,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'weight': weight,
      'serviceUnit': serviceUnit.value,
      'detergentId': detergentId,
      'detergentName': detergentName,
      'items': OrderItemModel.listToMap(items),
      'method': method.value,
      'address': address,
      'location': location,
      'pickupPhone': pickupPhone,
      'pickupLandmark': pickupLandmark,
      'specialInstructions': specialInstructions,
      'subtotal': subtotal,
      'detergentFee': detergentFee,
      'pickupFee': pickupFee,
      'discount': discount,
      'total': total,
      'promoCode': promoCode,
      'promoDiscountLabel': promoDiscountLabel,
      'status': status.value,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : FieldValue.serverTimestamp(),
    };
  }

  /// Builds an [OrderModel] from a Firestore-shaped map (i.e. what
  /// [toMap] produces, or `doc.data()`). [id] is passed separately
  /// because a raw Firestore map never contains its own document ID —
  /// see [OrderModel.fromFirestore], which supplies it automatically.
  factory OrderModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final serviceName = map['serviceName'] as String? ?? '';
    return OrderModel(
      id: id,
      orderNumber: map['orderNumber'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      serviceId: map['serviceId'] as String? ?? '',
      serviceName: serviceName,
      weight: (map['weight'] as num?)?.toDouble() ?? 0,
      // Backwards-compatible, same as `ServiceModel.fromFirestore`:
      // orders written before this field existed fall back to
      // inferring the unit from `serviceName` rather than silently
      // becoming kilogram-based.
      serviceUnit: ServiceUnitParsing.resolve(map['serviceUnit'] as String?, serviceName),
      detergentId: map['detergentId'] as String? ?? '',
      detergentName: map['detergentName'] as String? ?? '',
      items: OrderItemModel.listFromMap(map['items'] as List<dynamic>?),
      method: DeliveryMethodX.fromValue(map['method'] as String?),
      address: map['address'] as String?,
      location: map['location'] as String?,
      pickupPhone: map['pickupPhone'] as String?,
      pickupLandmark: map['pickupLandmark'] as String?,
      specialInstructions: map['specialInstructions'] as String?,
      subtotal: (map['subtotal'] as num?)?.toDouble() ?? 0,
      detergentFee: (map['detergentFee'] as num?)?.toDouble() ?? 0,
      pickupFee: (map['pickupFee'] as num?)?.toDouble() ?? 0,
      discount: (map['discount'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      promoCode: map['promoCode'] as String?,
      promoDiscountLabel: map['promoDiscountLabel'] as String?,
      status: OrderStatusX.fromValue(map['status'] as String?),
      createdAt: _parseDate(map['createdAt']),
      updatedAt: _parseDate(map['updatedAt']),
    );
  }

  /// Convenience wrapper around [fromMap] for the common case of
  /// reading straight off a Firestore snapshot — matches every other
  /// model's `fromFirestore` factory (`ServiceModel`, `UserModel`,
  /// ...). This is what PART 12.2's datasource will use for
  /// "retrieve an order by order number/document ID".
  factory OrderModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return OrderModel.fromMap(doc.data() ?? {}, id: doc.id);
  }

  /// Plain-JSON shape — unlike [toMap], [createdAt]/[updatedAt] are
  /// written as ISO-8601 strings (never [FieldValue.serverTimestamp],
  /// which only means something inside a Firestore write) so the
  /// result is safe to pass to `jsonEncode` or log directly. Fields
  /// that are simple/primitive already are identical to [toMap].
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderNumber': orderNumber,
      'userId': userId,
      'serviceId': serviceId,
      'serviceName': serviceName,
      'weight': weight,
      'serviceUnit': serviceUnit.value,
      'detergentId': detergentId,
      'detergentName': detergentName,
      'items': OrderItemModel.listToMap(items),
      'method': method.value,
      'address': address,
      'location': location,
      'pickupPhone': pickupPhone,
      'pickupLandmark': pickupLandmark,
      'specialInstructions': specialInstructions,
      'subtotal': subtotal,
      'detergentFee': detergentFee,
      'pickupFee': pickupFee,
      'discount': discount,
      'total': total,
      'promoCode': promoCode,
      'promoDiscountLabel': promoDiscountLabel,
      'status': status.value,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    final serviceName = json['serviceName'] as String? ?? '';
    return OrderModel(
      id: json['id'] as String?,
      orderNumber: json['orderNumber'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      serviceId: json['serviceId'] as String? ?? '',
      serviceName: serviceName,
      weight: (json['weight'] as num?)?.toDouble() ?? 0,
      serviceUnit: ServiceUnitParsing.resolve(json['serviceUnit'] as String?, serviceName),
      detergentId: json['detergentId'] as String? ?? '',
      detergentName: json['detergentName'] as String? ?? '',
      items: OrderItemModel.listFromMap(json['items'] as List<dynamic>?),
      method: DeliveryMethodX.fromValue(json['method'] as String?),
      address: json['address'] as String?,
      location: json['location'] as String?,
      pickupPhone: json['pickupPhone'] as String?,
      pickupLandmark: json['pickupLandmark'] as String?,
      specialInstructions: json['specialInstructions'] as String?,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      detergentFee: (json['detergentFee'] as num?)?.toDouble() ?? 0,
      pickupFee: (json['pickupFee'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      promoCode: json['promoCode'] as String?,
      promoDiscountLabel: json['promoDiscountLabel'] as String?,
      status: OrderStatusX.fromValue(json['status'] as String?),
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  /// Used by PART 12.3's repository once it has a real document ID
  /// and/or server-confirmed timestamps to return to the caller,
  /// and by PART 16's admin status updates (`status`/`updatedAt`)
  /// later on.
  OrderModel copyWith({
    String? id,
    String? orderNumber,
    OrderStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return OrderModel(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      userId: userId,
      serviceId: serviceId,
      serviceName: serviceName,
      weight: weight,
      serviceUnit: serviceUnit,
      detergentId: detergentId,
      detergentName: detergentName,
      items: items,
      method: method,
      address: address,
      location: location,
      pickupPhone: pickupPhone,
      pickupLandmark: pickupLandmark,
      specialInstructions: specialInstructions,
      subtotal: subtotal,
      detergentFee: detergentFee,
      pickupFee: pickupFee,
      discount: discount,
      total: total,
      promoCode: promoCode,
      promoDiscountLabel: promoDiscountLabel,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderModel && other.id != null && other.id == id);

  @override
  int get hashCode => id?.hashCode ?? identityHashCode(this);

  @override
  String toString() =>
      'OrderModel(orderNumber: $orderNumber, status: ${status.value}, total: $total)';
}