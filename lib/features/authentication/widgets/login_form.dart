import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

/// Pure presentational form for the login screen: owns its own
/// controllers, validation, and field layout, but has no knowledge of
/// Firebase, navigation, or AuthState. The parent screen supplies
/// [onSubmit] and controls [isLoading]/[errorMessage].
class LoginForm extends StatefulWidget {
  const LoginForm({
    super.key,
    required this.isLoading,
    required this.onSubmit,
    required this.onForgotPassword,
    required this.onCreateAccount,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  /// Called with the trimmed email/password once local validation passes.
  final Future<void> Function(String email, String password) onSubmit;

  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePassword(String? value) {
    if ((value ?? '').isEmpty) return 'Password is required.';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSubmit(
      _emailController.text.trim(),
      _passwordController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = widget.isLoading;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.local_laundry_service_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome back',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          AppTextField(
            label: 'Email',
            controller: _emailController,
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            enabled: !isLoading,
            validator: _validateEmail,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Password',
            controller: _passwordController,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            enabled: !isLoading,
            validator: _validatePassword,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isLoading ? null : widget.onForgotPassword,
              child: const Text('Forgot password?'),
            ),
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: isLoading ? 'Logging in...' : 'Log In',
            isLoading: isLoading,
            onPressed: isLoading ? null : _submit,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Create an account',
            variant: AppButtonVariant.text,
            onPressed: isLoading ? null : widget.onCreateAccount,
          ),
        ],
      ),
    );
  }
}