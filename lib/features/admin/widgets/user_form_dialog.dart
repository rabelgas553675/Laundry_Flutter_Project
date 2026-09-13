import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_state.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../data/repositories/user_repository.dart';
import '../../../models/user_model.dart';

/// PART 17 — the "Add users" / "Edit users" form.
///
/// Two distinct modes behind one dialog, same shape as
/// [ServiceFormDialog]:
/// - [existing] null → "Add users": collects name/email/phone/
///   address/password/role and creates a brand-new account via
///   [AuthRepository.createUserAsAdmin] (Firebase Auth + Firestore
///   profile together, without touching the signed-in Admin's own
///   session).
/// - [existing] non-null → "Edit users": name/phone/address/role/
///   active status, via [UserRepository.updateUserByAdmin]. Email and
///   password are intentionally NOT editable here — email changes
///   need Firebase Auth re-verification and password resets already
///   have their own flow (PART 04's "Forgot password"), both out of
///   scope for this admin form.
///
/// Guards against an Admin locking themselves out by demoting or
/// deactivating their own account from this screen — [_isEditingSelf]
/// disables the role dropdown and the active switch in that one case,
/// with an explanatory note, while every other field stays editable.
class UserFormDialog extends StatefulWidget {
  const UserFormDialog({super.key, this.existing, this.userRepository, this.authRepository});

  /// Null for "Add users"; the account being edited otherwise.
  final UserModel? existing;

  final UserRepository? userRepository;
  final AuthRepository? authRepository;

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog> {
  late final UserRepository _userRepository = widget.userRepository ?? UserRepository();
  late final AuthRepository _authRepository = widget.authRepository ?? AuthRepository();

  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _emailController = TextEditingController(text: widget.existing?.email ?? '');
  late final _phoneController = TextEditingController(text: widget.existing?.phone ?? '');
  late final _addressController = TextEditingController(text: widget.existing?.address ?? '');
  final _passwordController = TextEditingController();

  late UserRole _role = widget.existing?.role ?? UserRole.user;
  late bool _isActive = widget.existing?.isActive ?? true;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  bool get _isEditingSelf =>
      _isEditing && widget.existing!.uid == AuthState.instance.userModel?.uid;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _passwordController.dispose();
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
    if (_isEditing) return null; // password not collected when editing
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required.';
    if (v.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final address = _addressController.text.trim();

    try {
      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          name: name,
          phone: phone,
          address: address,
          role: _role,
          isActive: _isActive,
        );
        await _userRepository.updateUserByAdmin(updated);
      } else {
        await _authRepository.createUserAsAdmin(
          name: name,
          email: email,
          phone: phone,
          address: address,
          password: _passwordController.text,
          role: _role,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Unable to create this account.');
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit User' : 'Add User'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMessage != null) ...[
                Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              AppTextField(
                label: 'Full Name',
                controller: _nameController,
                enabled: !_isSaving,
                validator: (v) => _requiredField(v, 'Full name'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Email',
                controller: _emailController,
                // Email can't be changed once the Firebase Auth account
                // exists — see class doc comment above.
                enabled: !_isSaving && !_isEditing,
                keyboardType: TextInputType.emailAddress,
                validator: _validateEmail,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Phone',
                controller: _phoneController,
                enabled: !_isSaving,
                keyboardType: TextInputType.phone,
                validator: _validatePhone,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              AppTextField(
                label: 'Address',
                controller: _addressController,
                enabled: !_isSaving,
                maxLines: 2,
                validator: (v) => _requiredField(v, 'Address'),
                textInputAction: _isEditing ? TextInputAction.done : TextInputAction.next,
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 12),
                AppTextField(
                  label: 'Password',
                  controller: _passwordController,
                  enabled: !_isSaving,
                  isPassword: true,
                  validator: _validatePassword,
                  textInputAction: TextInputAction.done,
                ),
              ],
              const SizedBox(height: 16),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: UserRole.user, child: Text('User')),
                  DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
                ],
                onChanged: (_isSaving || _isEditingSelf)
                    ? null
                    : (value) => setState(() => _role = value ?? _role),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _isActive,
                  onChanged: (_isSaving || _isEditingSelf)
                      ? null
                      : (value) => setState(() => _isActive = value),
                  title: const Text('Active'),
                  subtitle: Text(
                    _isActive
                        ? 'This account can sign in and place orders.'
                        : 'This account is deactivated and cannot sign in.',
                  ),
                ),
              ],
              if (_isEditingSelf) ...[
                const SizedBox(height: 4),
                Text(
                  'You cannot change your own role or active status.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        SizedBox(
          width: 120,
          child: AppButton(
            label: 'Save',
            isLoading: _isSaving,
            onPressed: _submit,
          ),
        ),
      ],
    );
  }
}