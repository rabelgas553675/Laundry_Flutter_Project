import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/widgets/auth_header.dart';
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

  static const double _maxFormWidth = 480;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didCheckArguments) return;
    _didCheckArguments = true;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['deactivated'] == true) {
      _errorMessage =
          'This account has been deactivated. Please contact support.';
    }
  }

  Future<void> _handleLogin(String email, String password) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = await _authRepository.signInAuthOnly(
        email: email,
        password: password,
      );

      if (!mounted) return;

      unawaited(AuthState.instance.markSignedIn(user));

      if (!mounted) return;

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
        setState(
          () => _errorMessage = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AuthHeader(
                title: 'Welcome back',
                subtitle:
                    'Log in to pick up right where your last order left off.',
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _maxFormWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _errorMessage != null
                              ? _ErrorBanner(
                                  key: ValueKey(_errorMessage),
                                  message: _errorMessage!,
                                )
                              : const SizedBox.shrink(),
                        ),
                        LoginForm(
                          isLoading: _isLoading,
                          errorMessage: null, // Driven by _ErrorBanner above
                          onSubmit: _handleLogin,
                          onForgotPassword: () => Navigator.pushNamed(
                            context,
                            AppRoutes.forgotPassword,
                          ),
                          onCreateAccount: () => Navigator.pushNamed(
                            context,
                            AppRoutes.register,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sleek, modern error message banner with subtle entry transition.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}