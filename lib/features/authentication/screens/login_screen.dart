import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../data/repositories/auth_repository.dart';
import '../widgets/login_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final AuthRepository _authRepository = AuthRepository(
    userRepository: AuthState.sharedUserRepository,
  );

  bool _isLoading = false;
  String? _errorMessage;
  bool _didCheckArguments = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didCheckArguments) return;
    _didCheckArguments = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['deactivated'] == true) {
      _errorMessage = 'This account has been deactivated. Please contact support.';
    }
  }

  Future<void> _handleLogin(String email, String password) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Auth-only sign-in: verifies credentials against Firebase Auth and
      // returns as soon as that resolves, WITHOUT also waiting on the
      // Firestore profile lookup.
      final user = await _authRepository.signInAuthOnly(
        email: email,
        password: password,
      );

      if (!mounted) return;

      // Tell AuthState synchronously so RoleGuard doesn't briefly see
      // stale "unauthenticated" state and bounce back to /login.
      // Deliberately not awaited: markSignedIn drives its own profile
      // fetch through to `authenticated` internally (see its doc
      // comment), so the dashboard route can be pushed immediately —
      // RoleGuard shows its own spinner and updates the moment that
      // fetch resolves, without this screen needing to block on it.
      unawaited(AuthState.instance.markSignedIn(user));

      Navigator.pushReplacementNamed(
        context,
        AppRoutes.userDashboard,
        arguments: const {'fromLogin': true},
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message ?? 'Login failed.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Log In')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: LoginForm(
          isLoading: _isLoading,
          errorMessage: _errorMessage,
          onSubmit: _handleLogin,
          onForgotPassword: () =>
              Navigator.pushNamed(context, AppRoutes.forgotPassword),
          onCreateAccount: () =>
              Navigator.pushNamed(context, AppRoutes.register),
        ),
      ),
    );
  }
}