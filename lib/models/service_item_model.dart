import 'package:cloud_firestore/cloud_firestore.dart';

import 'service_model.dart';

/// PART 1 (new file) — a single priced catalog row under a service
/// that prices `perItem` (see [ServiceModel.pricingType]).
///
/// [ServiceModel] holds one price for the whole service, which is
/// enough for Quick/Standard/Premium Wash and for Wash & Ironing
/// (both priced by weight — see [PricingType.perKg]). Dry Cleaning is
/// different: each garment has its own price (Suit ≠ Coat ≠ Barong),
/// so that price list needs its own catalog instead of overloading
/// [ServiceModel.price] with a single number.
///
/// Mirrors the Firestore subcollection at
/// `services/{serviceId}/items/{itemId}`. The [serviceType] is
/// duplicated onto each row (not just implied by the parent
/// document) so an admin/report screen can query "every Dry Cleaning
/// catalog row across all services" with a single `collectionGroup`
/// query if the shop ever manages more than one Dry Cleaning service
/// document.
///
/// This is intentionally a separate model from
/// `lib/models/laundry_item_model.dart`'s `LaundryItemModel` (Clothes,
/// Bedsheets, Blankets, Towels, ...), which represents an unpriced
/// *category* tag used for Wash & Ironing's "what's in the load"
/// checklist, not a priced product.
class ServiceItemModel {
  final String id;
  final String serviceId;
  final ServiceType serviceType;
  final String name;

  /// Price for one unit of this item. `0` for entries that exist only
  /// as a selectable label and are never individually priced (e.g.
  /// Wash & Ironing's garment checklist, where the order is actually
  /// priced by weight — see [ServiceModel.pricingType.perKg] — not by
  /// summing item prices).
  final double price;

  final bool isActive;

  /// Display order on the order screen (PART 2), lowest first. Not
  /// alphabetical, so "Other" can be pinned to the end the way the
  /// PART 1 spec lists it.
  final int sortOrder;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ServiceItemModel({
    required this.id,
    required this.serviceId,
    required this.serviceType,
    required this.name,
    this.price = 0,
    this.isActive = true,
    this.sortOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toMapForCreate() {
    return {
      'serviceId': serviceId,
      'serviceType': serviceType.value,
      'name': name,
      'price': price,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'price': price,
      'isActive': isActive,
      'sortOrder': sortOrder,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ServiceItemModel copyWith({
    String? name,
    double? price,
    bool? isActive,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return ServiceItemModel(
      id: id,
      serviceId: serviceId,
      serviceType: serviceType,
      name: name ?? this.name,
      price: price ?? this.price,
      isActive: isActive ?? this.isActive,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ServiceItemModel.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    final updatedTs = data['updatedAt'];
    return ServiceItemModel(
      id: doc.id,
      serviceId: data['serviceId'] as String? ?? '',
      serviceType: ServiceTypeParsing.fromValue(data['serviceType'] as String?) ??
          ServiceType.dryCleaning,
      name: data['name'] as String? ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0,
      isActive: data['isActive'] as bool? ?? true,
      sortOrder: (data['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: ts is Timestamp ? ts.toDate() : null,
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
    );
  }

  /// Value equality by id — matches every other catalog-style model
  /// in this project (`ServiceModel`, `LaundryItemModel`,
  /// `DetergentModel`), so a `Set<ServiceItemModel>` or quantity map
  /// keyed by the model itself behaves the same way theirs do.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ServiceItemModel && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServiceItemModel(id: $id, name: $name, price: $price)';
}

/// PART 1 — default Dry Cleaning price list, `name -> price`.
///
/// This exists purely as seed/fallback data for
/// `ServiceRepository`/`ServiceItemRepository` to write into
/// `services/{serviceId}/items` the first time a Dry Cleaning service
/// is created (or to fall back to if a fresh environment hasn't been
/// seeded yet). No widget in `features/user` or `features/admin`
/// should declare a price directly — they must always read it from a
/// [ServiceItemModel] loaded through the repository/datasource layer.
const Map<String, double> kDryCleaningDefaultCatalog = {
  'Suit': 150,
  'Coat': 130,
  'Blazer': 120,
  'Dress': 150,
  'Barong': 100,
  'Formal Pants': 90,
  'Skirt': 80,
  'Other': 0,
};

/// PART 1 — default Wash & Ironing garment checklist. Unlike the Dry
/// Cleaning catalog above, these have no individual price: Wash &
/// Ironing is priced by weight (`ServiceModel.price` × kg, see
/// `PriceCalculator` in PART 3), so every entry here maps to `0`.
const Map<String, double> kWashAndIroningDefaultCatalog = {
  'T-Shirt': 0,
  'Polo': 0,
  'Pants': 0,
  'Shorts': 0,
  'Dress': 0,
  'Bedsheet': 0,
  'Towel': 0,
  'Underwear': 0,
  'Other': 0,
};