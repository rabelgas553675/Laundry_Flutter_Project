import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a detergent is currently selectable by customers.
/// Mirrors [ServiceStatus] / [LaundryItemStatus] so admins can later
/// toggle availability without deleting the document, keeping past
/// orders able to resolve a detergentId.
enum DetergentStatus { active, inactive }

extension DetergentStatusX on DetergentStatus {
  String get value => name; // 'active' or 'inactive'

  static DetergentStatus fromValue(String? value) {
    switch (value) {
      case 'inactive':
        return DetergentStatus.inactive;
      case 'active':
      default:
        return DetergentStatus.active;
    }
  }
}

/// Mirrors the Firestore document at `detergents/{detergentId}`.
///
/// Unlike [LaundryItemModel], a detergent DOES carry its own price —
/// [additionalPrice] is a flat fee added on top of the service price
/// when this detergent is chosen (see PART 11's price calculator:
/// Service Price × Weight + Detergent Fee + Pickup Fee - Discount).
/// Per PART 08's rule, this value must be read from Firestore and
/// must never be hard-coded in a widget.
class DetergentModel {
  final String id;
  final String name;
  final String description;

  /// Flat additional fee charged when this detergent is selected.
  /// e.g. Regular = 0, Premium = 30, Hypoallergenic = 50.
  final double additionalPrice;

  final DetergentStatus status;
  final DateTime? createdAt;

  const DetergentModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.additionalPrice,
    this.status = DetergentStatus.active,
    this.createdAt,
  });

  /// Used when seeding/creating a new detergent document. createdAt is
  /// left to Firestore's server timestamp, same pattern as
  /// ServiceModel/LaundryItemModel.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'description': description,
      'additionalPrice': additionalPrice,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Reserved for future admin editing of detergents, kept in the same
  /// shape as ServiceModel/LaundryItemModel's editable maps.
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'description': description,
      'additionalPrice': additionalPrice,
      'status': status.value,
    };
  }

  DetergentModel copyWith({
    String? name,
    String? description,
    double? additionalPrice,
    DetergentStatus? status,
  }) {
    return DetergentModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      additionalPrice: additionalPrice ?? this.additionalPrice,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory DetergentModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return DetergentModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      // Firestore numbers can come back as int or double — always
      // normalize via num? then .toDouble(), same as
      // ServiceModel.pricePerKg.
      additionalPrice: (data['additionalPrice'] as num?)?.toDouble() ?? 0,
      status: DetergentStatusX.fromValue(data['status']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Value equality by id — matches [LaundryItemModel], and lets the
  /// PART 09.3 selection widget compare/select detergents safely
  /// (e.g. `selected == detergent` in a RadioListTile) without relying
  /// on default identity equality.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DetergentModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}