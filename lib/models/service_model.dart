import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/service_unit.dart';

/// Whether a service is currently offered to customers. Admins toggle
/// this in Part 17 (Activate/deactivate service) instead of deleting
/// the document, so historical orders can still resolve a serviceId.
enum ServiceStatus { active, inactive }

extension ServiceStatusX on ServiceStatus {
  String get value => name; // 'active' or 'inactive'

  static ServiceStatus fromValue(String? value) {
    switch (value) {
      case 'inactive':
        return ServiceStatus.inactive;
      case 'active':
      default:
        return ServiceStatus.active;
    }
  }
}

/// PART 1 — what kind of laundry service this is.
///
/// This is a *category* on top of the existing [ServiceStatus] /
/// [ServiceUnit] pair, not a replacement for either. It lets the
/// order screen (PART 2) branch on "is this Dry Cleaning?" /
/// "is this Wash & Ironing?" by reading a real field instead of
/// string-matching `service.name`, the way [ServiceUnitParsing]
/// already warns against doing for [ServiceUnit].
enum ServiceType {
  quickWash,
  standardWash,
  premiumWash,
  dryCleaning,
  washAndIroning,
}

extension ServiceTypeX on ServiceType {
  /// Firestore-safe string written by [ServiceModel.toMapForCreate] /
  /// [ServiceModel.toEditableMap], e.g. `'dryCleaning'`.
  String get value => name;

  /// Human-readable label for admin/report screens, e.g. `'Dry
  /// Cleaning'`, `'Wash & Ironing'`.
  String get displayName {
    switch (this) {
      case ServiceType.quickWash:
        return 'Quick Wash';
      case ServiceType.standardWash:
        return 'Standard Wash';
      case ServiceType.premiumWash:
        return 'Premium Wash';
      case ServiceType.dryCleaning:
        return 'Dry Cleaning';
      case ServiceType.washAndIroning:
        return 'Wash & Ironing';
    }
  }

  /// Dry Cleaning is priced per garment (see [ServiceItemModel]),
  /// never per kg — used by the order screen (PART 2) to decide
  /// whether to render the itemized quantity list or a single
  /// weight/quantity field.
  bool get isItemized => this == ServiceType.dryCleaning;
}

/// Strict/fallback parsing for [ServiceType], mirroring
/// [ServiceUnitParsing] so a service document written before this
/// field existed still resolves to the right type instead of
/// silently defaulting.
class ServiceTypeParsing {
  ServiceTypeParsing._();

  static ServiceType? fromValue(String? value) {
    for (final type in ServiceType.values) {
      if (type.value == value) return type;
    }
    return null;
  }

  /// Migration-only fallback, matched case-insensitively by name —
  /// same heuristic [ServiceUnitParsing.fromServiceName] already uses
  /// for [ServiceUnit]. Must never be used to decide the type of a
  /// *new or edited* service (those always carry an explicit
  /// `serviceType`).
  static ServiceType fromServiceName(String name) {
    final n = name.toLowerCase();
    if (n.contains('dry clean')) return ServiceType.dryCleaning;
    if (n.contains('wash & iron') ||
        n.contains('wash and iron') ||
        n.contains('ironing')) {
      return ServiceType.washAndIroning;
    }
    if (n.contains('premium')) return ServiceType.premiumWash;
    if (n.contains('quick')) return ServiceType.quickWash;
    return ServiceType.standardWash;
  }

  /// What [ServiceModel.fromFirestore] actually calls: use the stored
  /// `serviceType` when present, otherwise infer it from the
  /// service's name.
  static ServiceType resolve(String? storedValue, String serviceName) {
    return fromValue(storedValue) ?? fromServiceName(serviceName);
  }
}

/// PART 1 — how a service's [ServiceModel.price] is applied.
///
/// This mirrors [ServiceUnit] (kilogram/piece) but is named and
/// shaped the way the PART 1 spec asks for, and adds [fixed] for any
/// future flat-fee service that isn't priced by weight or by item.
/// [ServiceUnit] is not removed — see the doc comment on
/// [ServiceModel.unit] for why both are kept.
enum PricingType { perItem, perKg, fixed }

extension PricingTypeX on PricingType {
  String get value => name;

  String get displayName {
    switch (this) {
      case PricingType.perItem:
        return 'Per Item';
      case PricingType.perKg:
        return 'Per Kg';
      case PricingType.fixed:
        return 'Fixed';
    }
  }

  /// The unit a quantity is measured in for this pricing type.
  /// Dry Cleaning (perItem) is never fractional; per-kg and fixed
  /// pricing don't require a whole-number quantity.
  bool get requiresWholeNumberQuantity => this == PricingType.perItem;
}

class PricingTypeParsing {
  PricingTypeParsing._();

  static PricingType? fromValue(String? value) {
    for (final type in PricingType.values) {
      if (type.value == value) return type;
    }
    return null;
  }

  /// Default derived from the existing [ServiceUnit] when no explicit
  /// `pricingType` has been stored yet — keeps every service created
  /// before this field existed working without a migration script.
  static PricingType defaultForUnit(ServiceUnit unit) {
    return unit.isPiece ? PricingType.perItem : PricingType.perKg;
  }

  static PricingType resolve(String? storedValue, ServiceUnit unit) {
    return fromValue(storedValue) ?? defaultForUnit(unit);
  }
}

/// Mirrors the Firestore document at `services/{serviceId}`.
///
/// Per PART 08: prices/turnaround live here only — nothing in the UI
/// layer should ever hard-code a price. PART 1 adds [serviceType],
/// [pricingType], [imageUrl] and [updatedAt] on top of that, plus the
/// [price] / [isActive] getters the PART 1 spec asks for by name.
///
/// Compatibility note: the canonical stored fields keep their
/// original names — [pricePerKg] and [status] — because every
/// existing call site (`PriceCalculator`, `pdf_service.dart`,
/// `order_repository.dart`, every admin/report screen) already reads
/// them. [price] and [isActive] are read-only aliases over those same
/// fields, not new stored state, so there is exactly one source of
/// truth for a service's price and a service's active/inactive
/// status — never two fields that could drift apart.
class ServiceModel {
  final String id;
  final String name;
  final String description;

  /// Price per unit. Kept as `pricePerKg` (not renamed to something
  /// more generic like `pricePerUnit`) so every existing call site —
  /// `PriceCalculator`, `pdf_service.dart`, every screen that already
  /// reads this field — keeps working unchanged. What the number
  /// actually means (per kilogram, per item, or a flat fee) is given
  /// explicitly by [pricingType] (and, for the kg/piece distinction
  /// specifically, by [unit]) instead of being assumed.
  final double pricePerKg;
  final String estimatedTime;
  final ServiceStatus status;
  final DateTime? createdAt;

  /// PART 1 — last time this service document was edited. `null` for
  /// a service that has never been edited since creation.
  final DateTime? updatedAt;

  /// How this service is priced/measured — see `service_unit.dart`.
  /// Defaults to [ServiceUnit.kilogram] so every existing call site
  /// that constructs a [ServiceModel] without passing this (tests,
  /// `kDefaultServices` entries not yet updated, etc.) keeps its
  /// current per-kg behavior unchanged.
  final ServiceUnit unit;

  /// PART 1 — which customer-facing service this is (Quick Wash,
  /// Dry Cleaning, Wash & Ironing, ...). Defaults to
  /// [ServiceType.standardWash]; real values are always resolved via
  /// [ServiceTypeParsing.resolve] when reading from Firestore.
  final ServiceType serviceType;

  /// PART 1 — how [price] is applied (per item / per kg / fixed).
  /// Defaults to whatever [unit] already implies, via
  /// [PricingTypeParsing.defaultForUnit].
  final PricingType pricingType;

  /// PART 1 — optional service thumbnail/banner shown on the service
  /// selection grid. `null` falls back to the existing icon-based
  /// card treatment.
  final String? imageUrl;

  const ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePerKg,
    required this.estimatedTime,
    this.status = ServiceStatus.active,
    this.createdAt,
    this.updatedAt,
    this.unit = ServiceUnit.kilogram,
    this.serviceType = ServiceType.standardWash,
    this.pricingType = PricingType.perKg,
    this.imageUrl,
  });

  /// PART 1 spec alias: the same value as [pricePerKg], named `price`
  /// so code written against the PART 1 model shape (and Dry
  /// Cleaning/Wash & Ironing calculations built on top of it) can use
  /// `service.price` regardless of whether the service is priced per
  /// item, per kg, or as a fixed fee.
  double get price => pricePerKg;

  /// PART 1 spec alias: the same value as `status == ServiceStatus.active`.
  bool get isActive => status == ServiceStatus.active;

  /// Used when seeding/creating a new service document. createdAt is
  /// left to Firestore's server timestamp, same pattern as UserModel.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'description': description,
      'pricePerKg': pricePerKg,
      'estimatedTime': estimatedTime,
      'status': status.value,
      'unit': unit.value,
      'serviceType': serviceType.value,
      'pricingType': pricingType.value,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Part 17 — Admin edits (price, description, estimated time,
  /// active/inactive, type, pricing type, image). Excludes
  /// createdAt, which never changes; stamps `updatedAt`.
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'description': description,
      'pricePerKg': pricePerKg,
      'estimatedTime': estimatedTime,
      'status': status.value,
      'unit': unit.value,
      'serviceType': serviceType.value,
      'pricingType': pricingType.value,
      'imageUrl': imageUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  ServiceModel copyWith({
    String? name,
    String? description,
    double? pricePerKg,
    String? estimatedTime,
    ServiceStatus? status,
    ServiceUnit? unit,
    ServiceType? serviceType,
    PricingType? pricingType,
    String? imageUrl,
    DateTime? updatedAt,
  }) {
    return ServiceModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      pricePerKg: pricePerKg ?? this.pricePerKg,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      unit: unit ?? this.unit,
      serviceType: serviceType ?? this.serviceType,
      pricingType: pricingType ?? this.pricingType,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  /// [unit] is resolved via [ServiceUnitParsing.resolve]: it reads the
  /// stored `unit` field when present, and otherwise falls back to
  /// inferring it from [name] — so a service document written before
  /// this field existed still deserializes into the correct unit
  /// (e.g. a pre-existing "Dry Cleaning" service still comes back as
  /// [ServiceUnit.piece]) instead of silently defaulting to
  /// kilogram. [serviceType] and [pricingType] are resolved the same
  /// migration-safe way.
  factory ServiceModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    final updatedTs = data['updatedAt'];
    final name = data['name'] ?? '';
    final resolvedUnit = ServiceUnitParsing.resolve(data['unit'] as String?, name);
    return ServiceModel(
      id: doc.id,
      name: name,
      description: data['description'] ?? '',
      pricePerKg: (data['pricePerKg'] as num?)?.toDouble() ?? 0,
      estimatedTime: data['estimatedTime'] ?? '',
      status: ServiceStatusX.fromValue(data['status']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      updatedAt: updatedTs is Timestamp ? updatedTs.toDate() : null,
      unit: resolvedUnit,
      serviceType: ServiceTypeParsing.resolve(data['serviceType'] as String?, name),
      pricingType: PricingTypeParsing.resolve(data['pricingType'] as String?, resolvedUnit),
      imageUrl: data['imageUrl'] as String?,
    );
  }

  /// Value equality by id — matches DetergentModel/LaundryItemModel,
  /// and lets PART 10.1's ServiceSelection compare/select services
  /// safely (e.g. `selected == service`) without relying on default
  /// identity equality.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ServiceModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}