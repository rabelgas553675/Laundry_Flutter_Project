import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/services/file_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../models/user_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fileService = FileService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _addressController;

  UserModel? _user;
  bool _isUploadingImage = false;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _user = AuthState.instance.userModel;
    _nameController = TextEditingController(text: _user?.name ?? '');
    _emailController = TextEditingController(text: _user?.email ?? '');
    _phoneController = TextEditingController(text: _user?.phone ?? '');
    _addressController = TextEditingController(text: _user?.address ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String? _requiredField(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 7) return 'Enter a valid phone number.';
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showImageOptions() async {
    final user = _user;
    if (user == null) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUpload(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose From Gallery'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndUpload(ImageSource.gallery);
                },
              ),
              if (user.profileImageUrl != null)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                  title: Text(
                    'Remove Photo',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _removePhoto();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    final user = _user;
    if (user == null) return;

    final XFile? picked = source == ImageSource.camera
        ? await _fileService.pickFromCamera()
        : await _fileService.pickFromGallery();
    if (picked == null) return; // user cancelled the picker

    setState(() => _isUploadingImage = true);
    try {
      final url = await _fileService.uploadProfileImage(uid: user.uid, file: picked);
      final updated = user.copyWith(profileImageUrl: url);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      setState(() => _user = updated);
      _showMessage('Profile photo updated.');
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not upload the photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _removePhoto() async {
    final user = _user;
    if (user == null) return;

    setState(() => _isUploadingImage = true);
    try {
      await _fileService.removeProfileImage(user.uid);
      final updated = user.copyWith(clearProfileImage: true);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      setState(() => _user = updated);
      _showMessage('Profile photo removed.');
    } on AppException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not remove the photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<void> _handleSave() async {
    final user = _user;
    if (user == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final updated = user.copyWith(
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        address: _addressController.text.trim(),
      );
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      setState(() => _user = updated);
      _showMessage('Profile updated.');
    } catch (_) {
      setState(() => _errorMessage = 'Could not save your changes. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: user == null
          ? const LoadingWidget(message: 'Loading profile...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 52,
                            backgroundImage: user.profileImageUrl != null
                                ? NetworkImage(user.profileImageUrl!)
                                : null,
                            child: user.profileImageUrl == null
                                ? const Icon(Icons.person, size: 48)
                                : null,
                          ),
                          if (_isUploadingImage)
                            const Positioned.fill(
                              child: CircleAvatar(
                                radius: 52,
                                backgroundColor: Colors.black45,
                                child: CircularProgressIndicator(color: Colors.white),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Material(
                              color: Theme.of(context).colorScheme.primary,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _isUploadingImage ? null : _showImageOptions,
                                child: Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.edit,
                                    size: 18,
                                    color: Theme.of(context).colorScheme.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    AppTextField(
                      label: 'Full Name',
                      controller: _nameController,
                      prefixIcon: Icons.person_outline,
                      validator: (v) => _requiredField(v, 'Full name'),
                    ),
                    const SizedBox(height: 16),
                    // Read-only: changing email requires Firebase Auth
                    // re-verification, which is out of scope for this part.
                    AppTextField(
                      label: 'Email',
                      controller: _emailController,
                      prefixIcon: Icons.email_outlined,
                      enabled: false,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Phone',
                      controller: _phoneController,
                      prefixIcon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      label: 'Address',
                      controller: _addressController,
                      prefixIcon: Icons.home_outlined,
                      maxLines: 2,
                      validator: (v) => _requiredField(v, 'Address'),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    AppButton(
                      label: _isSaving ? 'Saving...' : 'Save Changes',
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _handleSave,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}