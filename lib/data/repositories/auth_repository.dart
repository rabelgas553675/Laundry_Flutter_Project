import 'package:firebase_auth/firebase_auth.dart';

import '../../models/user_model.dart';
import '../datasources/auth_datasource.dart';
import '../datasources/user_datasource.dart';
import 'user_repository.dart';

class AuthRepository {
  AuthRepository({
    AuthDatasource? authDatasource,
    UserRepository? userRepository,
  })  : _authDatasource = authDatasource ?? AuthDatasource(),
        _userRepository =
            userRepository ?? UserRepository(datasource: UserDatasource());

  final AuthDatasource _authDatasource;
  final UserRepository _userRepository;

  /// Registers the account, then creates the matching Firestore profile
  /// with role = user. Returns the profile.
  Future<UserModel> register({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    final credential = await _authDatasource.register(
      email: email,
      password: password,
    );

    return _userRepository.createUserProfile(
      uid: credential.user!.uid,
      name: name,
      email: email,
      phone: phone,
      address: address,
    );
  }

  /// Signs in, then fetches the matching Firestore profile.
  Future<UserModel> signIn({
    required String email,
    required String password,
  }) async {
    final credential = await _authDatasource.signIn(
      email: email,
      password: password,
    );

    final profile = await _userRepository.getUserById(credential.user!.uid);
    if (profile == null) {
      throw StateError('No profile found for this account.');
    }
    return profile;
  }

  /// Part 17 — "Add users". Creates a brand-new account (Firebase
  /// Auth credentials + Firestore profile) with an Admin-chosen
  /// [role], without disturbing the Admin's own signed-in session.
  ///
  /// Mirrors [register] almost exactly, except:
  /// - it calls [AuthDatasource.registerWithoutSigningIn] instead of
  ///   [AuthDatasource.register], so creating this account never
  ///   swaps out the Admin's current session for the new one, and
  /// - it calls [UserRepository.createUserProfileAsAdmin] instead of
  ///   [UserRepository.createUserProfile], so the new profile gets
  ///   whatever [role] the Admin picked rather than always
  ///   defaulting to [UserRole.user].
  Future<UserModel> createUserAsAdmin({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
    required UserRole role,
  }) async {
    final credential = await _authDatasource.registerWithoutSigningIn(
      email: email,
      password: password,
    );

    return _userRepository.createUserProfileAsAdmin(
      uid: credential.user!.uid,
      name: name,
      email: email,
      phone: phone,
      address: address,
      role: role,
    );
  }

  /// Firebase Auth sign-in only — deliberately does NOT wait for the
  /// Firestore profile. That second network round-trip is what was making
  /// the Login → Dashboard transition feel slow, and the role it returns
  /// isn't needed to show a screen, only to pick which one. Callers that
  /// want to navigate the instant credentials are verified (and let
  /// AuthState's own authStateChanges listener fetch the profile in the
  /// background, same as it already does on a cold app start) should use
  /// this instead of [signIn].
  Future<User> signInAuthOnly({
    required String email,
    required String password,
  }) async {
    final credential = await _authDatasource.signIn(
      email: email,
      password: password,
    );
    return credential.user!;
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _authDatasource.sendPasswordResetEmail(email);
  }

  Future<void> signOut() async {
    _userRepository.clearCache();
    return _authDatasource.signOut();
  }

  User? get currentUser => _authDatasource.currentUser;
}