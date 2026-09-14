import 'package:flutter/material.dart';

import '../core/services/auth_state.dart';
import '../features/welcome/screens/welcome_screen.dart';
import '../models/user_model.dart';
import 'routes.dart';

/// The app's initial screen (`AppRoutes.home`, `/`).
///
/// Watches [AuthState] and decides, on cold start, where a returning
/// user actually belongs — replacing the Part 01/02
/// `NavTestHomeScreen` placeholder, which always showed a manual
/// "pick a screen" menu regardless of session state.
///
/// - Still resolving the session (`AuthStatus.loading`, no cached
///   profile yet) → a bare loading spinner.
/// - No session (`AuthStatus.unauthenticated`) → [WelcomeScreen],
///   shown directly rather than navigated to, since this *is* the
///   root of the navigation stack. Explicit sign-outs elsewhere in
///   the app go straight to `AppRoutes.login` instead — this landing
///   screen is only for a visitor's very first impression.
/// - A session exists → hands off to the already-guarded named
///   dashboard route for that role ([AppRoutes.adminDashboard] /
///   [AppRoutes.userDashboard]) via [Navigator.pushReplacementNamed],
///   so [RoleGuard]'s deactivated-account and wrong-role handling on
///   that route keeps applying exactly as it does everywhere else in
///   the app — this widget itself makes no role decisions beyond
///   "which named route to hand off to".
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// Guards against scheduling more than one `pushReplacementNamed`
  /// per authenticated session — [AuthState] can notify listeners
  /// several times in a row while it settles (e.g. `markSignedIn`
  /// then the real profile fetch), and this widget stays mounted
  /// only until the first frame after the first notification fires.
  bool _redirected = false;

  @override
  void initState() {
    super.initState();
    AuthState.instance.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    AuthState.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  void _redirectToDashboard(UserRole role) {
    if (_redirected) return;
    _redirected = true;
    final route = role == UserRole.admin ? AppRoutes.adminDashboard : AppRoutes.userDashboard;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthState.instance;

    // Cold start: no cached profile yet, still resolving the
    // Firebase session (Firebase.initializeApp already awaited in
    // main.dart, but authStateChanges()'s first event is still async).
    if (auth.isLoading && auth.userModel == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isLoggedIn) {
      // Not signed in (or just signed out from elsewhere) — reset so
      // a future sign-in from this same still-mounted instance can
      // redirect again.
      _redirected = false;
      return const WelcomeScreen();
    }

    final role = auth.role;
    if (role != null) {
      _redirectToDashboard(role);
    }
    // Either redirecting (role known) or still waiting on the
    // profile fetch that will supply it — either way, a spinner is
    // the correct thing to show for this one frame.
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}