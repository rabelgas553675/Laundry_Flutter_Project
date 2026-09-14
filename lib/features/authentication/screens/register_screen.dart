import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/widgets/auth_header.dart';
import '../../../data/repositories/auth_repository.dart';
import '../widgets/register_form.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late final AuthRepository _authRepository = AuthRepository(
    userRepository: AuthState.sharedUserRepository,
  );

  bool _isLoading = false;
  String? _errorMessage;

  static const double _maxFormWidth = 480;

  Future<void> _handleRegister({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Creates Auth user + Firestore profile (role = user). Firebase Auth
      // auto-signs-in the new account as a side effect of createUser — we
      // deliberately sign that back out below so registration lands the
      // user on Login rather than skipping straight past it.
      await _authRepository.register(
        name: name,
        email: email,
        phone: phone,
        address: address,
        password: password,
      );

      // Undo the automatic sign-in and reset AuthState to unauthenticated,
      // so the new account has to log in with its own credentials.
      await AuthState.instance.signOut();

      if (!mounted) return;

      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _errorMessage = e.message ?? 'Registration failed.');
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
              AuthHeader(
                title: 'Create account',
                subtitle: 'Set up your profile to start booking pickups.',
                onBack: () => Navigator.pop(context),
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
                        RegisterForm(
                          isLoading: _isLoading,
                          errorMessage: null, // Driven by _ErrorBanner above
                          onSubmit: _handleRegister,
                          onLoginInstead: () => Navigator.pop(context),
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