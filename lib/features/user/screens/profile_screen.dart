import 'dart:ui';

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
  /// provides its own app bar above. In that case this screen must
  /// NOT draw its own `Scaffold`/`AppBar`, and its "Profile" title
  /// must not reserve extra top space for a status bar / app bar
  /// that isn't there. When `false` (the default), this screen is
  /// being pushed on its own via `Navigator.push` and needs its own
  /// full `Scaffold`/status-bar handling.
  final bool embedded;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _fileService = FileService();

  UserModel? _user;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _user = AuthState.instance.userModel;
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

  // ---------------------------------------------------------------------
  // Photo handling (unchanged behavior from before, only entry point moved)
  // ---------------------------------------------------------------------

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

  // ---------------------------------------------------------------------
  // Row edit sheets — each "General" row opens a focused bottom sheet
  // instead of one long form, matching the reference design.
  // ---------------------------------------------------------------------

  Future<void> _saveUser(UserModel updated) async {
    await AuthState.sharedUserRepository.updateProfile(updated);
    AuthState.instance.updateUserModel(updated);
    if (!mounted) return;
    setState(() => _user = updated);
  }

  void _showEmailInfoSheet() {
    final user = _user;
    if (user == null) return;
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Email',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your email is tied to sign-in and can\'t be changed here.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Text(
                    user.email,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditProfileSheet() async {
    final user = _user;
    if (user == null) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phone);
    bool isSaving = false;

    String? requiredField(String? value, String label) {
      if ((value ?? '').trim().isEmpty) return '$label is required.';
      return null;
    }

    String? validatePhone(String? value) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isEmpty) return 'Phone number is required.';
      final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
      if (digitsOnly.length < 7) return 'Enter a valid phone number.';
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SafeArea(
                top: false,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Profile Setting',
                        style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        label: 'Full Name',
                        controller: nameController,
                        prefixIcon: Icons.person_outline_rounded,
                        validator: (v) => requiredField(v, 'Full name'),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        label: 'Phone',
                        controller: phoneController,
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        validator: validatePhone,
                      ),
                      const SizedBox(height: 22),
                      AppButton(
                        label: isSaving ? 'Saving...' : 'Save Changes',
                        isLoading: isSaving,
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                setSheetState(() => isSaving = true);
                                try {
                                  final updated = user.copyWith(
                                    name: nameController.text.trim(),
                                    phone: phoneController.text.trim(),
                                  );
                                  await _saveUser(updated);
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  _showMessage('Profile updated.');
                                } catch (_) {
                                  _showMessage(
                                    'Could not save your changes. Please try again.',
                                    isError: true,
                                  );
                                } finally {
                                  setSheetState(() => isSaving = false);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    phoneController.dispose();
  }

  Future<void> _showEditAddressSheet() async {
    final user = _user;
    if (user == null) return;

    final formKey = GlobalKey<FormState>();
    final addressController = TextEditingController(text: user.address);
    bool isSaving = false;

    final colorScheme = Theme.of(context).colorScheme;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 4,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
              ),
              child: SafeArea(
                top: false,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'Address',
                        style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 18),
                      AppTextField(
                        label: 'Address',
                        controller: addressController,
                        prefixIcon: Icons.home_outlined,
                        maxLines: 2,
                        validator: (v) => (v ?? '').trim().isEmpty ? 'Address is required.' : null,
                      ),
                      const SizedBox(height: 22),
                      AppButton(
                        label: isSaving ? 'Saving...' : 'Save Changes',
                        isLoading: isSaving,
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!(formKey.currentState?.validate() ?? false)) return;
                                setSheetState(() => isSaving = true);
                                try {
                                  final updated = user.copyWith(
                                    address: addressController.text.trim(),
                                  );
                                  await _saveUser(updated);
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  _showMessage('Address updated.');
                                } catch (_) {
                                  _showMessage(
                                    'Could not save your changes. Please try again.',
                                    isError: true,
                                  );
                                } finally {
                                  setSheetState(() => isSaving = false);
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    addressController.dispose();
  }

  // ---------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------

  /// Corner radius used consistently across every panel/card/button on
  /// this screen (header, list card, row highlight, edit button ring).
  static const double _kRadius = 28.0;

  /// Cool near-white frost tint for the glass panels, matching the
  /// reference design (a fixed color, not derived from the theme).
  static const Color _kGlassTint = Color(0xFFF7F9FC);

  Widget _buildBody() {
    final colorScheme = Theme.of(context).colorScheme;
    final user = _user;

    if (user == null) {
      return const LoadingWidget(message: 'Loading profile...');
    }

    final topPadding = widget.embedded ? 0.0 : MediaQuery.of(context).padding.top;

    // Outer corner radius for the whole panel (the edges you circled) —
    // slightly larger than the inner glass panels' radius so the rounding
    // nests visually instead of competing with it.
    const outerRadius = _kRadius + 4;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(outerRadius),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.18),
              blurRadius: 32,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(outerRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ---- Backdrop: a soft, cool blue-grey diagonal gradient matching
              // the reference glass design (steel blue at the top-left, fading
              // to near-white toward the bottom-right). Fixed palette — not
              // derived from the app's theme colors — to match the reference. ----
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF93ACCE),
                      Color(0xFFC7D2E3),
                      Color(0xFFF2F4F8),
                      Colors.white,
                    ],
                    stops: [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              ),
              SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: widget.embedded ? 20 : topPadding + 16),
                    if (!widget.embedded) ...[
                      Text(
                        'Profile',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    // ---- Header glass panel: avatar, name, location. ----
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _GlassPanel(
                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                          borderRadius: BorderRadius.circular(_kRadius),
                          tintColor: _kGlassTint,
                          child: Column(
                            children: [
                              _ProfileAvatar(
                                imageUrl: user.profileImageUrl,
                                isUploading: _isUploadingImage,
                                onEditTap: _isUploadingImage ? null : _showImageOptions,
                                radius: _kRadius + 34,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                user.name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      user.address.isEmpty ? 'No address set' : user.address,
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // ---- General list glass panel. ----
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _GlassPanel(
                          margin: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                          borderRadius: BorderRadius.circular(_kRadius),
                          tintColor: _kGlassTint,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'General',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              _ProfileListRow(
                                icon: Icons.mail_outline_rounded,
                                label: 'Email',
                                onTap: _showEmailInfoSheet,
                                radius: _kRadius - 8,
                              ),
                              _ProfileListRow(
                                icon: Icons.person_outline_rounded,
                                label: 'Profile Setting',
                                onTap: _showEditProfileSheet,
                                radius: _kRadius - 8,
                              ),
                              _ProfileListRow(
                                icon: Icons.location_on_outlined,
                                label: 'Address',
                                onTap: _showEditAddressSheet,
                                radius: _kRadius - 8,
                                isLast: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      // No Scaffold here — the dashboard tab already provides the frame.
      return _buildBody();
    }

    return Scaffold(
      body: _buildBody(),
    );
  }
}

/// A frosted-glass panel: blurs whatever sits behind it (the themed
/// gradient backdrop) and overlays a translucent, theme-neutral tint so
/// content stays readable while the color beneath still shows through.
/// Used for every major section on this screen so the rounding, blur,
/// border, and shadow stay visually consistent.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.borderRadius,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.tintColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  /// Overrides the neutral `colorScheme.surface` tint with a fixed color —
  /// used here to match the reference design's cool near-white frost.
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseTint = tintColor ?? colorScheme.surface;

    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: baseTint.withValues(alpha: 0.72),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Large centered avatar with a floating edit button, matching the
/// reference design's hero photo treatment.
class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imageUrl,
    required this.isUploading,
    required this.onEditTap,
    this.radius = 62,
  });

  final String? imageUrl;
  final bool isUploading;
  final VoidCallback? onEditTap;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final resolvedRadius = radius;

    return Center(
      child: SizedBox(
        width: (resolvedRadius + 8) * 2,
        height: (resolvedRadius + 8) * 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: resolvedRadius,
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                backgroundImage: imageUrl != null ? NetworkImage(imageUrl!) : null,
                child: imageUrl == null
                    ? Icon(
                        Icons.person_rounded,
                        size: resolvedRadius,
                        color: colorScheme.primary,
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
      ),
    );
  }
}

/// One row in the "General" list — icon, label, chevron. Tappable.
class _ProfileListRow extends StatelessWidget {
  const _ProfileListRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.radius = 20,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double radius;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Icon(icon, size: 22, color: colorScheme.onSurface),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
      ],
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