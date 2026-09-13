import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/user_model.dart';

/// Raw Firestore access for the `users` collection.
/// No business rules here — just reads/writes.
class UserDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      FirebaseService.firestore.collection('users');

  Future<void> createUserDocument(String uid, UserModel user) {
    return _usersRef.doc(uid).set(user.toMapForCreate()).timeout(
          _timeout,
          onTimeout: () => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'deadline-exceeded',
            message:
                'Timed out writing the user profile — check your network connection.',
          ),
        );
  }

  Future<UserModel?> getUserById(String uid) async {
    final doc = await _usersRef.doc(uid).get().timeout(
          _timeout,
          onTimeout: () => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'deadline-exceeded',
            message:
                'Timed out reading the user profile — check your network connection.',
          ),
        );
    if (!doc.exists) return null;
    return UserModel.fromFirestore(doc);
  }

  /// Part 07 — partial update for profile edits (name/phone/address/
  /// profileImageUrl). Uses `update`, not `set`, so it can never
  /// accidentally wipe fields (like role or createdAt) it wasn't given.
  Future<void> updateUserFields(String uid, Map<String, dynamic> fields) {
    return _usersRef.doc(uid).update(fields).timeout(
          _timeout,
          onTimeout: () => throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'deadline-exceeded',
            message:
                'Timed out saving your profile — check your network connection.',
          ),
        );
  }

  /// PART 15 — real-time stream of every user document, newest first,
  /// for the Admin Dashboard's Total Users stat and its recent-users
  /// list. Same reasoning as [OrderDatasource.streamAllOrders]:
  /// unrestricted here because only an Admin-guarded screen ever
  /// calls it. PART 17's admin user management reuses this stream
  /// rather than duplicating it.
  Stream<List<UserModel>> streamAllUsers() {
    return _usersRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => UserModel.fromFirestore(doc)).toList());
  }
}