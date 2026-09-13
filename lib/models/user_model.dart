import 'package:cloud_firestore/cloud_firestore.dart';

/// The two roles supported by the app.
enum UserRole { admin, user }

extension UserRoleX on UserRole {
  String get value => name; // 'admin' or 'user'

  static UserRole fromValue(String? value) {
    switch (value) {
      case 'admin':
        return UserRole.admin;
      case 'user':
      default:
        return UserRole.user;
    }
  }
}

/// Mirrors the Firestore document at `users/{userId}`.
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String address;
  final UserRole role;
  final DateTime? createdAt;

  /// Added in Part 07. Never contains raw bytes — only the Firebase
  /// Storage download URL for `users/{uid}/profile/profile.jpg`.
  final String? profileImageUrl;

  /// Added in Part 17. Whether this account may sign in / place
  /// orders — an Admin toggles this via "Activate/deactivate
  /// accounts" instead of deleting the user document, so their order
  /// history stays intact and their `userId` still resolves on any
  /// past order. Defaults to `true`: every account created through
  /// PART 04/05 registration is active from the moment it exists.
  final bool isActive;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.role,
    this.createdAt,
    this.profileImageUrl,
    this.isActive = true,
  });

  /// Used only when writing a brand-new user document.
  /// createdAt is left to Firestore's server timestamp so client
  /// clock skew can never affect it.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'role': role.value,
      'profileImageUrl': null,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Used by ProfileScreen (Part 07) to persist edits. Deliberately
  /// excludes role/email/createdAt — those aren't editable from the
  /// profile screen (role changes go through Admin in Part 17; email
  /// changes require Firebase Auth re-verification, out of scope here).
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'profileImageUrl': profileImageUrl,
    };
  }

  /// Part 17 — persists an Admin's edit from Manage Users (name,
  /// phone, address, role, active/inactive). Deliberately excludes
  /// [email] and [createdAt], for the same reasons [toEditableMap]
  /// already excludes them from a self-service profile edit: email
  /// changes require Firebase Auth re-verification (out of scope
  /// here), and [createdAt] never changes once set. Unlike
  /// [toEditableMap], this one *does* include [role] and [isActive] —
  /// those two fields are Admin-only levers, never exposed on the
  /// customer-facing Profile screen.
  Map<String, dynamic> toAdminEditableMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'role': role.value,
      'isActive': isActive,
    };
  }

  /// [clearProfileImage] exists because `profileImageUrl: null` as an
  /// argument is indistinguishable from "not provided" in a normal
  /// copyWith — this makes "remove the photo" an explicit, unambiguous
  /// call site (see ProfileScreen._removePhoto).
  UserModel copyWith({
    String? name,
    String? phone,
    String? address,
    String? profileImageUrl,
    bool clearProfileImage = false,
    UserRole? role,
    bool? isActive,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      role: role ?? this.role,
      createdAt: createdAt,
      profileImageUrl:
          clearProfileImage ? null : (profileImageUrl ?? this.profileImageUrl),
      isActive: isActive ?? this.isActive,
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      role: UserRoleX.fromValue(data['role']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      profileImageUrl: data['profileImageUrl'] as String?,
      // Defaults to true for any document written before PART 17
      // introduced this field, so a pre-existing account is never
      // silently treated as deactivated just because the field is
      // missing.
      isActive: data['isActive'] as bool? ?? true,
    );
  }
}