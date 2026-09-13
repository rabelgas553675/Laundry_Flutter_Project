import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

/// Pure presentational form for the registration screen. Owns its own
/// controllers and field-level validation; the parent screen owns
/// Firebase calls, loading/error state, and navigation.
class RegisterForm extends StatefulWidget {
  const RegisterForm({
    super.key,
    required this.isLoading,
    required this.onSubmit,
    required this.onLoginInstead,
    this.errorMessage,
  });

  final bool isLoading;
  final String? errorMessage;

  /// Called with trimmed field values once local validation passes.
  final Future<void> Function({
    required String name,
    required String email,
    required String phone,
    required String address,
    required String password,
  }) onSubmit;

  final VoidCallback onLoginInstead;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _requiredField(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validateEmail(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Email is required.';
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(trimmed)) return 'Enter a valid email address.';
    return null;
  }

  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 7) return 'Enter a valid phone number.';
    return null;
  }

  String? _validatePassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if ((value ?? '').isEmpty) return 'Please confirm your password.';
    if (value != _passwordController.text) return 'Passwords do not match.';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.onSubmit(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      address: _addressController.text.trim(),
      password: _passwordController.text.trim(),
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
          AppTextField(
            label: 'Full Name',
            controller: _nameController,
            prefixIcon: Icons.person_outline,
            enabled: !isLoading,
            validator: (v) => _requiredField(v, 'Full name'),
          ),
          const SizedBox(height: 16),
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
            label: 'Phone',
            controller: _phoneController,
            prefixIcon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            enabled: !isLoading,
            validator: _validatePhone,
          ),
          const SizedBox(height: 16),
          AppTextField(
            label: 'Address',
            controller: _addressController,
            prefixIcon: Icons.home_outlined,
            enabled: !isLoading,
            validator: (v) => _requiredField(v, 'Address'),
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
          const SizedBox(height: 16),
          AppTextField(
            label: 'Confirm Password',
            controller: _confirmPasswordController,
            prefixIcon: Icons.lock_outline,
            isPassword: true,
            enabled: !isLoading,
            validator: _validateConfirmPassword,
          ),
          if (widget.errorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              widget.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          AppButton(
            label: isLoading ? 'Creating account...' : 'Create Account',
            isLoading: isLoading,
            onPressed: isLoading ? null : _submit,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Already have an account? Log in',
            variant: AppButtonVariant.text,
            onPressed: isLoading ? null : widget.onLoginInstead,
          ),
        ],
      ),
    );
  }
}