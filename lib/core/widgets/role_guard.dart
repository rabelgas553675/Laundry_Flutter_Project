import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../models/user_model.dart';
import '../services/auth_state.dart';

/// Wraps screens that require specific roles.
class RoleGuard extends StatefulWidget {
  const RoleGuard({
    super.key,
    required this.allowedRoles,
    required this.child,
    this.fallbackRoute = AppRoutes.userDashboard,
  });

  final Set<UserRole> allowedRoles;
  final Widget child;
  final String fallbackRoute;

  @override
  State<RoleGuard> createState() => _RoleGuardState();
}

class _RoleGuardState extends State<RoleGuard> {
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

  void _redirect(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
    });
  }

  /// Part 17 — an Admin can deactivate an account from Manage Users
  /// at any moment, including while that account is sitting on an
  /// already-open, RoleGuard-protected screen. Since every such
  /// screen listens to [AuthState] (see [_onAuthChanged] above), the
  /// very next auth-state notification after that Firestore write
  /// lands here — this signs the account out and bounces it to
  /// Login, rather than [_redirect]'s plain [widget.fallbackRoute]:
  /// a deactivated account has no dashboard it's allowed to land on
  /// (unlike a merely wrong-role user, who still has *their own*
  /// dashboard to fall back to), and staying signed in would just
  /// mean RoleGuard has to catch this same check again on every
  /// rebuild. `deactivated: true` lets [LoginScreen] show a clear
  /// message instead of silently landing back on the login form.
  void _handleDeactivated() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AuthState.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (route) => false,
        arguments: const {'deactivated': true},
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthState.instance;

    // Cold start only: no profile yet. AuthState guarantees this
    // resolves within ~8s even if authStateChanges() never fires or
    // errors (see auth_state.dart's startup fallback timer), so this
    // is a genuinely bounded loading state now, not an indefinite one.
    if (auth.isLoading && auth.userModel == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!auth.isLoggedIn && auth.userModel == null) {
      _redirect(AppRoutes.login);
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Part 17 — checked before the role check below: a deactivated
    // Admin account, for example, still has a "known, allowed" role
    // and would otherwise sail straight past the role check.
    if (auth.userModel?.isActive == false) {
      _handleDeactivated();
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final role = auth.role;
    if (role == null || !widget.allowedRoles.contains(role)) {
      _redirect(widget.fallbackRoute);
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Role known, account active → show screen immediately (no spinner).
    return widget.child;
  }
}