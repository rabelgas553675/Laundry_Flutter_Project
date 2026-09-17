import 'laundry_item_model.dart';
import 'service_item_model.dart';

/// PART 12.1 / PART 1 — a single line on an order.
///
/// Two things build one of these:
///
/// - [OrderItemModel.fromLaundryItem]: a Wash & Ironing category tag
///   (Clothes, Bedsheets, ...) with no price of its own — the order
///   is priced by weight, not by summing these. [quantity] stays `1`
///   and [unitPrice] stays `0` for these.
/// - [OrderItemModel.priced]: a Dry Cleaning line — one catalog
///   [ServiceItemModel] (e.g. "Suit") at a customer-chosen
///   [quantity], carrying its own [unitPrice] so the order total can
///   be computed as Σ(quantity × unitPrice) without a second lookup
///   against the catalog later.
///
/// Denormalized ([itemId] + [itemName] + [icon] + [unitPrice]), not
/// just an itemId reference — the same reasoning [ServiceModel]
/// already applies by storing `serviceName` alongside `serviceId` on
/// [OrderModel]: order history and the admin order list should be
/// able to display exactly what a past order contained and what it
/// was charged, without an extra Firestore read per item, and even if
/// an admin later renames or reprices a [ServiceItemModel]/
/// [LaundryItemModel], a historical order keeps showing exactly what
/// the customer saw and paid at the time.
class OrderItemModel {
  /// Identifier for this *line* on the order (not the catalog item —
  /// see [itemId] for that). Two lines can reference the same catalog
  /// item id if that ever becomes needed, without colliding, because
  /// each line gets its own [id]. Defaults to [itemId] when not given
  /// explicitly, which keeps every existing call site (that only ever
  /// set one item per catalog entry per order) working unchanged.
  final String id;

  final String itemId;
  final String itemName;

  /// Name of a Material icon (mirrors [LaundryItemModel.icon]) so
  /// order details / the admin order card can render the same icon
  /// the customer saw on the order form, again without an extra
  /// Firestore read. Unused (kept at its default) for priced Dry
  /// Cleaning lines, which render from [itemName] and [unitPrice]
  /// instead.
  final String icon;

  /// How many of [itemId] were ordered. `1` for a Wash & Ironing
  /// category tag (there's nothing to count); the customer-entered
  /// count for a Dry Cleaning line (e.g. `2` Suits).
  final int quantity;

  /// Price for one unit of [itemId] at the time the order was placed
  /// — copied from [ServiceItemModel.price], never re-read from the
  /// catalog afterward, so a later price change never rewrites a past
  /// order's total. `0` for entries with no individual price (Wash &
  /// Ironing category tags).
  final double unitPrice;

  const OrderItemModel({
    String? id,
    required this.itemId,
    required this.itemName,
    this.icon = 'checkroom',
    this.quantity = 1,
    this.unitPrice = 0,
  }) : id = id ?? itemId;

  /// `quantity × unitPrice`. A getter, not a stored field — so a line
  /// can never be saved with a [totalPrice] that has drifted from its
  /// own [quantity]/[unitPrice] (the PART 1 spec's `totalPrice` field
  /// is honored as a computed, always-consistent value rather than a
  /// second number that could get out of sync).
  double get totalPrice => quantity * unitPrice;

  /// Builds an [OrderItemModel] straight from a PART 09
  /// [LaundryItemModel] — the normal way a Wash & Ironing category
  /// tag gets created, at the moment the order draft (PART 11) is
  /// built from the order form (PART 2).
  factory OrderItemModel.fromLaundryItem(LaundryItemModel item) {
    return OrderItemModel(itemId: item.id, itemName: item.name, icon: item.icon);
  }

  /// PART 1/2 — builds a priced Dry Cleaning line from a catalog
  /// [ServiceItemModel] and the quantity the customer picked on the
  /// order screen's `[-] N [+]` stepper.
  factory OrderItemModel.priced({
    required ServiceItemModel catalogItem,
    required int quantity,
  }) {
    return OrderItemModel(
      itemId: catalogItem.id,
      itemName: catalogItem.name,
      quantity: quantity,
      unitPrice: catalogItem.price,
    );
  }

  /// Firestore-shaped map. This model has no Timestamp/DocumentReference
  /// fields, so [toMap] and [toJson] are identical — [toJson] is kept
  /// as its own method (rather than a bare alias) so callers that
  /// only ever touch JSON never need to know that's the case.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'itemId': itemId,
      'itemName': itemName,
      'icon': icon,
      'quantity': quantity,
      'unitPrice': unitPrice,
    };
  }

  Map<String, dynamic> toJson() => toMap();

  factory OrderItemModel.fromMap(Map<String, dynamic> map) {
    final itemId = map['itemId'] as String? ?? '';
    return OrderItemModel(
      id: map['id'] as String? ?? itemId,
      itemId: itemId,
      itemName: map['itemName'] as String? ?? '',
      icon: map['icon'] as String? ?? 'checkroom',
      // Older documents saved before PART 1 have neither field; both
      // default exactly the way the pre-PART-1 model behaved (a
      // single unpriced category tag).
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (map['unitPrice'] as num?)?.toDouble() ?? 0,
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

  /// Sums [totalPrice] across a list of lines — what a Dry Cleaning
  /// order's subtotal is: Σ(quantity × unitPrice) across every
  /// selected garment. Used by PART 3's `PriceCalculator` rather than
  /// duplicated there, so this stays the single definition of "what a
  /// list of order items costs".
  static double subtotalOf(List<OrderItemModel> items) {
    var sum = 0.0;
    for (final item in items) {
      sum += item.totalPrice;
    }
    return sum;
  }

  OrderItemModel copyWith({
    String? id,
    String? itemId,
    String? itemName,
    String? icon,
    int? quantity,
    double? unitPrice,
  }) {
    return OrderItemModel(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      itemName: itemName ?? this.itemName,
      icon: icon ?? this.icon,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
    );
  }

  /// Value equality by [id] (a line's own identity), not [itemId] —
  /// PART 1 onward, a Dry Cleaning order can in principle hold more
  /// than one line, and two distinct lines must never compare equal
  /// just because they reference the same catalog item.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is OrderItemModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'OrderItemModel(id: $id, itemId: $itemId, itemName: $itemName, '
      'quantity: $quantity, unitPrice: $unitPrice, totalPrice: $totalPrice)';
}