import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../app/routes.dart';
import '../../../core/services/auth_state.dart';
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
        setState(() => _errorMessage = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Account')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: RegisterForm(
          isLoading: _isLoading,
          errorMessage: _errorMessage,
          onSubmit: _handleRegister,
          onLoginInstead: () => Navigator.pop(context),
        ),
      ),
    );
  }
}