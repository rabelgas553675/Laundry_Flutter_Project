import 'laundry_item_model.dart';

/// PART 12.1 — a single laundry item category attached to an order.
///
/// Denormalized ([itemId] + [itemName] + [icon]), not just an
/// itemId reference — the same reasoning [ServiceModel] already
/// applies by storing `serviceName` alongside `serviceId` on
/// [OrderModel]: PART 13's order history and PART 16's admin order
/// list should be able to display what a past order contained
/// without an extra Firestore read per item, and even if an admin
/// later renames a [LaundryItemModel] (or deactivates it), a
/// historical order keeps showing exactly what the customer saw and
/// picked at the time.
///
/// One [OrderItemModel] is created per category the customer checked
/// in PART 10.1's `LaundryItemSelection` (Clothes, Bedsheets,
/// Blankets, Towels, ...). There's no quantity/count field, because
/// per [LaundryItemModel]'s own doc comment the order form only lets
/// a customer flag *which* categories apply, not how many of each —
/// that can be added later without breaking this shape.
class OrderItemModel {
  final String itemId;
  final String itemName;

  /// Name of a Material icon (mirrors [LaundryItemModel.icon]) so
  /// PART 13's order details / PART 16's admin order card can render
  /// the same icon the customer saw on the order form, again without
  /// an extra Firestore read.
  final String icon;

  const OrderItemModel({
    required this.itemId,
    required this.itemName,
    this.icon = 'checkroom',
  });

  /// Builds an [OrderItemModel] straight from a PART 09
  /// [LaundryItemModel] — the normal way one of these gets created,
  /// at the moment PART 12.3's repository turns a confirmed
  /// `OrderDraft` (PART 11) into a persisted [OrderModel].
  factory OrderItemModel.fromLaundryItem(LaundryItemModel item) {
    return OrderItemModel(itemId: item.id, itemName: item.name, icon: item.icon);
  }

  /// Firestore-shaped map. This model has no Timestamp/DocumentReference
  /// fields, so [toMap] and [toJson] are identical — [toJson] is kept
  /// as its own method (rather than a bare alias) so callers that
  /// only ever touch JSON never need to know that's the case.
  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'icon': icon,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    return OrderItemModel(
      itemId: map['itemId'] as String? ?? '',
      itemName: map['itemName'] as String? ?? '',
      icon: map['icon'] as String? ?? 'checkroom',
    );
  }

  factory OrderItemModel.fromJson(Map<String, dynamic> json) => OrderItemModel.fromMap(json);

  /// Convenience for serializing/deserializing the whole
  /// `List<OrderItemModel>` that lives on [OrderModel.items], since
  /// Firestore stores it as a plain array of maps under the order
  /// document (no separate `orderItems` subcollection/document — the
  /// list is always small and always read together with its order).
  static List<Map<String, dynamic>> listToMap(List<OrderItemModel> items) {
    return items.map((item) => item.toMap()).toList();
  }

  static List<OrderItemModel> listFromMap(List<dynamic>? list) {
    if (list == null) return [];
    return list
        .whereType<Map>()
        .map((map) => OrderItemModel.fromMap(Map<String, dynamic>.from(map)))
        .toList();
  }

  OrderItemModel copyWith({String? itemId, String? itemName, String? icon}) {
    return OrderItemModel(
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      icon: icon ?? this.icon,
    );
  }

  /// Value equality by [itemId] — matches [LaundryItemModel], so a
  /// `List<OrderItemModel>` can be compared/deduped the same way the
  /// PART 10.1 selection widget already compares laundry items.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is OrderItemModel && other.itemId == itemId);

  @override
  int get hashCode => itemId.hashCode;

  @override
  String toString() => 'OrderItemModel(itemId: $itemId, itemName: $itemName)';
}