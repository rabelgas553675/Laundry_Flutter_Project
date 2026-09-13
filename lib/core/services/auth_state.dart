import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../models/user_model.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

/// Single source of truth for auth + role.
class AuthState extends ChangeNotifier {
  AuthState._() {
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen(
      _onAuthChanged,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('AuthState: authStateChanges() stream error: $error');
        debugPrintStack(stackTrace: stackTrace);
        _fetchGeneration++;
        _firebaseUser = null;
        _userModel = null;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      },
    );

    _startupFallbackTimer = Timer(const Duration(seconds: 8), () {
      if (_status == AuthStatus.loading && _firebaseUser == null) {
        debugPrint(
          'AuthState: authStateChanges() produced no event within 8s — '
          'falling back to unauthenticated so the UI can recover.',
        );
        _fetchGeneration++;
        _status = AuthStatus.unauthenticated;
        notifyListeners();
      }
    });
  }

  static final AuthState instance = AuthState._();

  static void warmUp() => instance;

  /// Shared so Login/Register and the auth stream use the same profile cache.
  static final UserRepository sharedUserRepository = UserRepository();

  final UserRepository _userRepository = AuthState.sharedUserRepository;
  final AuthRepository _authRepository = AuthRepository(
    userRepository: AuthState.sharedUserRepository,
  );

  late final StreamSubscription<User?> _authSubscription;
  Timer? _startupFallbackTimer;

  AuthStatus _status = AuthStatus.loading;
  User? _firebaseUser;
  UserModel? _userModel;

  /// Bumped on every manual set / sign-out so in-flight stream fetches are ignored.
  int _fetchGeneration = 0;

  AuthStatus get status => _status;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isLoggedIn => _status == AuthStatus.authenticated;

  User? get firebaseUser => _firebaseUser;
  UserModel? get userModel => _userModel;
  UserRole? get role => _userModel?.role;

  void _cancelStartupFallback() {
    _startupFallbackTimer?.cancel();
    _startupFallbackTimer = null;
  }

  /// Call right after AuthRepository returns a profile.
  /// Wins over any concurrent authStateChanges fetch.
  void setFromLogin(UserModel profile) {
    _cancelStartupFallback();
    _fetchGeneration++;
    _firebaseUser = FirebaseAuth.instance.currentUser;
    _userModel = profile;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  void updateUserModel(UserModel updated) {
    _userModel = updated;
    notifyListeners();
  }

  /// Call right after a successful auth-only sign-in (credentials verified,
  /// profile not fetched yet). Synchronously marks us as "loading" with a
  /// known firebaseUser, so RoleGuard doesn't briefly read the pre-login
  /// `unauthenticated` state and bounce back to /login, then itself drives
  /// the profile fetch through to `authenticated`/`unauthenticated` and
  /// returns a Future that completes when that's done.
  ///
  /// ROOT CAUSE of the "stuck on the loading screen after login, fixed by
  /// a manual browser refresh" bug: this method used to only flip
  /// `_status` to `loading` and stop there, leaving the *rest* of the
  /// transition — the Firestore profile fetch and the final flip to
  /// `authenticated` — entirely dependent on `_onAuthChanged` being
  /// invoked later by the passive `authStateChanges()` stream, from a
  /// completely separate call site. That stream event is NOT part of
  /// this call's own async chain: on Flutter Web it can arrive late
  /// relative to the `signInWithEmailAndPassword` call that produced
  /// it, and in some cases is missed outright for an interactive
  /// sign-in with no app restart in between. When that happened,
  /// nothing else was ever going to move `_status` off `loading` —
  /// `markSignedIn` cancels the 8s cold-start fallback timer
  /// (correctly, since we already know who's signed in), so there was
  /// no other safety net, and RoleGuard/AuthGate spun forever. A full
  /// browser refresh only "fixed" it because it re-ran `main()` from
  /// scratch and used the already-reliable cold-start path instead.
  ///
  /// The fix: do the profile fetch here, directly, in the same async
  /// chain as the sign-in that triggered it. Callers still don't need
  /// to await this (see LoginScreen) to get "navigate immediately"
  /// behaviour — RoleGuard's listener picks up the `authenticated`
  /// transition the moment this resolves. The `authStateChanges()`
  /// listener below is untouched and still covers every other case
  /// (cold start, sign-out from another tab, token invalidation); the
  /// `_fetchGeneration` counter keeps the two from racing each other.
  Future<void> markSignedIn(User user) async {
    _cancelStartupFallback();
    if (_userModel != null && _userModel!.uid == user.uid) return;

    final generation = ++_fetchGeneration;
    _firebaseUser = user;
    _status = AuthStatus.loading;
    notifyListeners();

    UserModel? profile;
    try {
      profile = await _userRepository.getUserById(user.uid);
    } catch (e) {
      if (generation != _fetchGeneration) return;
      debugPrint('AuthState: failed to load profile after login for ${user.uid}: $e');
      _firebaseUser = null;
      _userModel = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    if (generation != _fetchGeneration) return;

    if (profile == null) {
      debugPrint('AuthState: no profile found for ${user.uid} after login.');
      _firebaseUser = null;
      _userModel = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _userModel = profile;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> _onAuthChanged(User? user) async {
    _cancelStartupFallback();

    if (user == null) {
      _fetchGeneration++;
      _firebaseUser = null;
      _userModel = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    _firebaseUser = user;

    if (_userModel != null && _userModel!.uid == user.uid) {
      if (_status != AuthStatus.authenticated) {
        _status = AuthStatus.authenticated;
        notifyListeners();
      }
      return;
    }

    final generation = ++_fetchGeneration;

    if (_status != AuthStatus.authenticated) {
      _status = AuthStatus.loading;
      notifyListeners();
    }

    UserModel? profile;
    try {
      profile = await _userRepository.getUserById(user.uid);
    } catch (e) {
      if (generation != _fetchGeneration) return;
      debugPrint('AuthState: failed to load profile for ${user.uid}: $e');
      _userModel = null;
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }

    if (generation != _fetchGeneration) return;

    _userModel = profile;
    _status = AuthStatus.authenticated;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    await _onAuthChanged(FirebaseAuth.instance.currentUser);
  }

  Future<void> signOut() async {
    _cancelStartupFallback();
    _fetchGeneration++;
    await _authRepository.signOut();
    _firebaseUser = null;
    _userModel = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  @override
  void dispose() {
    _cancelStartupFallback();
    _authSubscription.cancel();
    super.dispose();
  }
}