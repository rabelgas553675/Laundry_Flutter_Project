import 'package:cloud_firestore/cloud_firestore.dart';

/// Whether a laundry item is currently selectable by customers.
/// Mirrors [ServiceStatus] in `service_model.dart` — admins will be
/// able to toggle this later without deleting the document, so past
/// orders can still resolve an itemId.
enum LaundryItemStatus { active, inactive }

extension LaundryItemStatusX on LaundryItemStatus {
  String get value => name; // 'active' or 'inactive'

  static LaundryItemStatus fromValue(String? value) {
    switch (value) {
      case 'inactive':
        return LaundryItemStatus.inactive;
      case 'active':
      default:
        return LaundryItemStatus.active;
    }
  }
}

/// Mirrors the Firestore document at `laundryItems/{itemId}`.
///
/// Represents a category of laundry a customer can include in an
/// order (Clothes, Bedsheets, Blankets, Towels, ...). Unlike
/// [ServiceModel] and [DetergentModel], laundry items carry no price
/// of their own in this part — they exist so the order form (PART 10)
/// can let a customer flag *what* is being washed. If per-item pricing
/// is ever needed, `pricePerKg`/`additionalPrice` can be added later
/// without breaking this shape.
class LaundryItemModel {
  final String id;
  final String name;
  final String description;

  /// Name of a Material icon (e.g. 'checkroom', 'bed', 'dry_cleaning')
  /// so selection widgets (PART 09.3) can render a consistent icon
  /// without hard-coding icon choices in the UI layer.
  final String icon;

  final LaundryItemStatus status;
  final DateTime? createdAt;

  const LaundryItemModel({
    required this.id,
    required this.name,
    this.description = '',
    this.icon = 'checkroom',
    this.status = LaundryItemStatus.active,
    this.createdAt,
  });

  /// Used when seeding/creating a new laundry item document.
  /// createdAt is left to Firestore's server timestamp, same pattern
  /// as ServiceModel/UserModel.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'description': description,
      'icon': icon,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Reserved for future admin editing of laundry items, kept in the
  /// same shape as [ServiceModel.toEditableMap] for consistency.
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'description': description,
      'icon': icon,
      'status': status.value,
    };
  }

  LaundryItemModel copyWith({
    String? name,
    String? description,
    String? icon,
    LaundryItemStatus? status,
  }) {
    return LaundryItemModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory LaundryItemModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return LaundryItemModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      icon: data['icon'] ?? 'checkroom',
      status: LaundryItemStatusX.fromValue(data['status']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }

  /// Value equality so a `Set<LaundryItemModel>` (used by the multi-select
  /// widget in PART 09.3) correctly dedupes by Firestore document id.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LaundryItemModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}