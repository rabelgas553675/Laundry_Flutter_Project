import 'package:cloud_firestore/cloud_firestore.dart';

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

/// Mirrors the Firestore document at `services/{serviceId}`.
///
/// Per PART 08: prices/turnaround live here only — nothing in the UI
/// layer should ever hard-code a price.
class ServiceModel {
  final String id;
  final String name;
  final String description;
  final double pricePerKg;
  final String estimatedTime;
  final ServiceStatus status;
  final DateTime? createdAt;

  const ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePerKg,
    required this.estimatedTime,
    this.status = ServiceStatus.active,
    this.createdAt,
  });

  /// Used when seeding/creating a new service document. createdAt is
  /// left to Firestore's server timestamp, same pattern as UserModel.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'description': description,
      'pricePerKg': pricePerKg,
      'estimatedTime': estimatedTime,
      'status': status.value,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Part 17 — Admin edits (price, description, estimated time,
  /// active/inactive). Excludes createdAt, which never changes.
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'description': description,
      'pricePerKg': pricePerKg,
      'estimatedTime': estimatedTime,
      'status': status.value,
    };
  }

  ServiceModel copyWith({
    String? name,
    String? description,
    double? pricePerKg,
    String? estimatedTime,
    ServiceStatus? status,
  }) {
    return ServiceModel(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      pricePerKg: pricePerKg ?? this.pricePerKg,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  factory ServiceModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return ServiceModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      pricePerKg: (data['pricePerKg'] as num?)?.toDouble() ?? 0,
      estimatedTime: data['estimatedTime'] ?? '',
      status: ServiceStatusX.fromValue(data['status']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
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