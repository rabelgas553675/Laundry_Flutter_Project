import '../datasources/user_datasource.dart';
import '../../models/user_model.dart';

class UserRepository {
  UserRepository({UserDatasource? datasource})
      : _datasource = datasource ?? UserDatasource();

  final UserDatasource _datasource;

  /// Session cache — cleared on logout / different uid.
  UserModel? _cached;

  Future<UserModel> createUserProfile({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String address,
  }) async {
    final newUser = UserModel(
      uid: uid,
      name: name,
      email: email,
      phone: phone,
      address: address,
      role: UserRole.user, // forced for new registrations
    );

    await _datasource.createUserDocument(uid, newUser);
    _cached = newUser;
    return newUser;
  }

  Future<UserModel?> getUserById(String uid) async {
    if (_cached != null && _cached!.uid == uid) {
      return _cached;
    }

    final user = await _datasource.getUserById(uid);
    if (user != null) {
      _cached = user;
    }
    return user;
  }

  /// Part 07 — persists a profile edit (name/phone/address and/or
  /// profile image) and refreshes the cache so the next getUserById
  /// call doesn't return stale data.
  Future<UserModel> updateProfile(UserModel updated) async {
    await _datasource.updateUserFields(updated.uid, updated.toEditableMap());
    _cached = updated;
    return updated;
  }

  /// Part 17 — persists an Admin's edit from Manage Users (name,
  /// phone, address, role, active/inactive), via
  /// [UserModel.toAdminEditableMap].
  ///
  /// Only refreshes [_cached] when [updated] *is* the signed-in Admin
  /// editing their own account — [_cached] holds a single user (the
  /// one currently signed in), so overwriting it with some other
  /// customer's record here would make the next [getUserById] call
  /// (e.g. from [AuthState]) return the wrong profile entirely.
  Future<UserModel> updateUserByAdmin(UserModel updated) async {
    await _datasource.updateUserFields(updated.uid, updated.toAdminEditableMap());
    if (_cached != null && _cached!.uid == updated.uid) {
      _cached = updated;
    }
    return updated;
  }

  /// Part 17 — "Add users". Writes the Firestore profile half of a
  /// brand-new account with an Admin-chosen [role] and `isActive:
  /// true`; the caller ([AuthRepository.createUserAsAdmin]) is
  /// responsible for creating the matching Firebase Auth account
  /// *first* and passing in its [uid].
  ///
  /// Deliberately separate from [createUserProfile]: that method
  /// hard-codes `role: UserRole.user` by design (a customer
  /// registering themselves can never grant themselves admin), while
  /// this one exists specifically so an Admin can.
  Future<UserModel> createUserProfileAsAdmin({
    required String uid,
    required String name,
    required String email,
    required String phone,
    required String address,
    required UserRole role,
  }) async {
    final newUser = UserModel(
      uid: uid,
      name: name,
      email: email,
      phone: phone,
      address: address,
      role: role,
    );

    await _datasource.createUserDocument(uid, newUser);
    return newUser;
  }

  /// PART 15 — thin pass-through to [UserDatasource.streamAllUsers].
  /// No business rules to add on top, same as
  /// [OrderRepository.streamAllOrders]. Deliberately doesn't touch
  /// [_cached] — that field holds only the single signed-in user for
  /// [getUserById], and has nothing to do with this all-users stream
  /// for the Admin Dashboard.
  Stream<List<UserModel>> streamAllUsers() {
    return _datasource.streamAllUsers();
  }

  /// Call on logout so the next account does not see the previous profile.
  void clearCache() {
    _cached = null;
  }
}