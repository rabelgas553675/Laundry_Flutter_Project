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
  const ProfileScreen({super.key, this.embedded = false});

  /// When `true`, this screen is being shown as one tab of
  /// [UserDashboard]'s bottom-nav `IndexedStack`, which already
  /// provides its own gradient app bar above. In that case this
  /// screen must NOT draw its own `Scaffold`/`AppBar`, and its hero
  /// header must not reserve extra top space for a status bar / app
  /// bar that isn't there — doing both stacked a second "← Profile"
  /// header directly under the dashboard's own bar, with an
  /// oversized gap above the avatar. When `false` (the default),
  /// this screen is being pushed on its own via `Navigator.push` and
  /// needs its own full `Scaffold`/`AppBar` as before.
  final bool embedded;

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

  static const double _maxContentWidth = 480;

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

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colorScheme.error : colorScheme.inverseSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
                color: isError ? colorScheme.onError : colorScheme.onInverseSurface,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError ? colorScheme.onError : colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _showImageOptions() async {
    final user = _user;
    if (user == null) return;

    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Profile Photo',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 12),
                _SheetOption(
                  icon: Icons.photo_camera_rounded,
                  label: 'Take Photo',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUpload(ImageSource.camera);
                  },
                ),
                _SheetOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose From Gallery',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickAndUpload(ImageSource.gallery);
                  },
                ),
                if (user.profileImageUrl != null)
                  _SheetOption(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove Photo',
                    color: colorScheme.error,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _removePhoto();
                    },
                  ),
              ],
            ),
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
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not upload the photo. Please try again.', isError: true);
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
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not remove the photo. Please try again.', isError: true);
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

  Widget _buildBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _user;

    if (user == null) {
      return const LoadingWidget(message: 'Loading profile...');
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProfileHeader(
            name: user.name,
            email: user.email,
            imageUrl: user.profileImageUrl,
            isUploading: _isUploadingImage,
            onEditTap: _isUploadingImage ? null : _showImageOptions,
            // Embedded (dashboard tab): the dashboard's own gradient
            // bar already reserves the status-bar + app-bar space
            // above this widget, so this header only needs its own
            // internal padding, not another status-bar allowance on
            // top of that.
            reserveAppBarSpace: !widget.embedded,
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxContentWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
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
                      _SectionLabel(text: 'Personal Info'),
                      const SizedBox(height: 10),
                      _SectionCard(
                        colorScheme: colorScheme,
                        children: [
                          AppTextField(
                            label: 'Full Name',
                            controller: _nameController,
                            prefixIcon: Icons.person_outline_rounded,
                            validator: (v) => _requiredField(v, 'Full name'),
                          ),
                          const SizedBox(height: 18),
                          // Read-only: changing email requires Firebase Auth
                          // re-verification, which is out of scope for this part.
                          AppTextField(
                            label: 'Email',
                            controller: _emailController,
                            prefixIcon: Icons.email_outlined,
                            enabled: false,
                          ),
                          const SizedBox(height: 18),
                          AppTextField(
                            label: 'Phone',
                            controller: _phoneController,
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            validator: _validatePhone,
                          ),
                          const SizedBox(height: 18),
                          AppTextField(
                            label: 'Address',
                            controller: _addressController,
                            prefixIcon: Icons.home_outlined,
                            maxLines: 2,
                            validator: (v) => _requiredField(v, 'Address'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      AppButton(
                        label: _isSaving ? 'Saving...' : 'Save Changes',
                        isLoading: _isSaving,
                        onPressed: _isSaving ? null : _handleSave,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (widget.embedded) {
      // No Scaffold/AppBar here — the dashboard's own gradient bar is
      // the only header.
      return _buildBody();
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'Profile',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(),
    );
  }
}

/// Full-width gradient hero that anchors the screen and hosts the avatar,
/// giving the page a focal point instead of starting flat with form fields.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.isUploading,
    required this.onEditTap,
    required this.reserveAppBarSpace,
  });

  final String name;
  final String email;
  final String? imageUrl;
  final bool isUploading;
  final VoidCallback? onEditTap;

  /// `true` when this header sits directly under this screen's own
  /// transparent `AppBar` (standalone/push usage) and must reserve
  /// `statusBarHeight + kToolbarHeight` of top padding so the avatar
  /// clears it. `false` when embedded as a dashboard tab, where that
  /// space is already reserved by the dashboard's own app bar and
  /// adding it again here would push the avatar down twice.
  final bool reserveAppBarSpace;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = MediaQuery.of(context).padding.top;
    final topInset = reserveAppBarSpace ? topPadding + kToolbarHeight + 8 : 24.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, topInset, 24, 36),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.82),
            colorScheme.tertiary.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(36),
          bottomRight: Radius.circular(36),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          _ProfileAvatar(
            imageUrl: imageUrl,
            isUploading: isUploading,
            onEditTap: onEditTap,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase caption used to label a group of fields, like
/// "PERSONAL INFO" — gives the card context without adding visual weight.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Holds related fields with no background, border, or shadow — matches
/// the flat, transparent form styling used on the Login screen instead of
/// a boxed card.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.colorScheme, required this.children});

  final ColorScheme colorScheme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

/// A single row in the "edit photo" bottom sheet.
class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 16),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Avatar with a soft ring, drop shadow, and floating edit button —
/// gives the photo more visual weight than a plain CircleAvatar.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageUrl,
    required this.isUploading,
    required this.onEditTap,
  });

  final String? imageUrl;
  final bool isUploading;
  final VoidCallback? onEditTap;

  static const double _radius = 52;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: (_radius + 8) * 2,
      height: (_radius + 8) * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: _radius,
              backgroundColor: Colors.white.withValues(alpha: 0.25),
              backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
              child: imageUrl == null
                  ? Icon(
                      Icons.person_rounded,
                      size: _radius,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          if (isUploading)
            Positioned.fill(
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black45,
                ),
                child: const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onEditTap,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    Icons.edit_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A sleek, modern error message banner with subtle entry transition.
/// Matches the banner used on the Login/Register screens.
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