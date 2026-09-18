import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';
import '../widgets/promo_photo_field.dart';

/// Fixed content height of the glass app bar (excludes the status-bar
/// inset, which SafeArea adds on top of this) — matches the same
/// constant used across the rest of the Admin section (dashboard,
/// notifications, reports) so every glass app bar in the app sits at
/// the same height.
const double _kAppBarContentHeight = 64;

/// PART 18B — "Create promotions."
///
/// Same shape and validation rules as [EditPromoScreen], starting
/// from blank fields instead of an existing promo. The uniqueness
/// check here has no id to exclude, since there's no promo document
/// yet — the very first save is what creates one.
///
/// REDESIGN — now dressed in the same frosted-glass Admin theme as
/// [AdminDashboard]/[AdminNotificationsScreen]/the report screens: a
/// blurred, rounded app bar over the blue-blob backdrop, with the
/// whole form laid out inside one [GlassContainer] panel instead of a
/// flat white [Scaffold] body.
class AddPromoScreen extends StatefulWidget {
  const AddPromoScreen({super.key, this.repository});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [PromoRepository].
  final PromoRepository? repository;

  @override
  State<AddPromoScreen> createState() => _AddPromoScreenState();
}

class _AddPromoScreenState extends State<AddPromoScreen> {
  late final PromoRepository _repository = widget.repository ?? PromoRepository();
  final _fileService = FileService();
  final _formKey = GlobalKey<FormState>();

  final _codeController = TextEditingController();
  final _discountValueController = TextEditingController();
  final _minimumOrderController = TextEditingController();
  final _descriptionController = TextEditingController();

  PromoDiscountType _discountType = PromoDiscountType.percentage;
  PromoStatus _status = PromoStatus.active;

  // Defaults to a one-month window starting today, so an admin who
  // doesn't touch the date pickers still lands on a sensible, valid
  // period rather than two null dates.
  DateTime? _startDate = DateTime.now();
  DateTime? _endDate = DateTime.now().add(const Duration(days: 30));

  // PART 19 — the admin's selected offer photo, held locally (never
  // auto-generated/defaulted — see PromoModel.imageUrl) until the
  // promotion is actually created. [_pickedImageFile] is what
  // eventually gets uploaded; [_pickedImageBytes] is just its preview.
  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  bool _isPickingImage = false;

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    _discountValueController.dispose();
    _minimumOrderController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _requiredCode(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Promo code is required.';
    return null;
  }

  String? _validateDiscountValue(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Discount value is required.';
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number.';
    if (parsed <= 0) return 'Discount value must be greater than 0.';
    if (_discountType == PromoDiscountType.percentage && parsed > 100) {
      return 'A percentage discount cannot exceed 100%.';
    }
    return null;
  }

  String? _validateMinimumOrder(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null; // blank == no minimum (0)
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < 0) return 'Minimum order cannot be negative.';
    return null;
  }

  Future<void> _showPhotoOptions() async {
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
                  'Offer Photo',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                PromoPhotoSheetOption(
                  icon: Icons.photo_camera_rounded,
                  label: 'Take Photo',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.camera);
                  },
                ),
                PromoPhotoSheetOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose From Gallery',
                  color: colorScheme.primary,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pickImage(ImageSource.gallery);
                  },
                ),
                if (_pickedImageBytes != null)
                  PromoPhotoSheetOption(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove Selected Photo',
                    color: colorScheme.error,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() {
                        _pickedImageFile = null;
                        _pickedImageBytes = null;
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final XFile? picked = source == ImageSource.camera
        ? await _fileService.pickFromCamera()
        : await _fileService.pickFromGallery();
    if (picked == null) return; // user cancelled the picker

    setState(() => _isPickingImage = true);
    try {
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImageFile = picked;
        _pickedImageBytes = bytes;
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load that photo. Please try another.');
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_startDate ?? now) : (_endDate ?? _startDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    if (_startDate == null || _endDate == null) {
      setState(() => _errorMessage = 'Please select a start date and an end date.');
      return;
    }
    // "End date must not be before start date."
    if (_endDate!.isBefore(_startDate!)) {
      setState(() => _errorMessage = 'End date must not be before start date.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final code = _codeController.text.trim().toUpperCase();

    try {
      // "Promo code must be unique."
      final taken = await _repository.isCodeTaken(code);
      if (taken) {
        setState(() {
          _errorMessage = 'This promo code is already in use. Please choose a different one.';
          _isSaving = false;
        });
        return;
      }

      final discountValue = double.parse(_discountValueController.text.trim());
      final minimumOrderText = _minimumOrderController.text.trim();
      final minimumOrder = minimumOrderText.isEmpty ? 0.0 : double.parse(minimumOrderText);

      // PART 19 — the promo's id is generated up front so a selected
      // photo can be uploaded to a path keyed by it *before* the
      // promo document itself is written, so this very first write
      // already carries the right imageUrl.
      final promoId = _repository.newPromoId();

      String? imageUrl;
      if (_pickedImageFile != null) {
        try {
          imageUrl = await _fileService.uploadPromoImage(
            promoId: promoId,
            file: _pickedImageFile!,
          );
        } on AppException catch (e) {
          setState(() {
            _errorMessage = e.message;
            _isSaving = false;
          });
          return;
        } catch (_) {
          setState(() {
            _errorMessage = 'Could not upload the photo. Please try again.';
            _isSaving = false;
          });
          return;
        }
      }

      final promo = PromoModel(
        id: promoId,
        code: code,
        discountType: _discountType,
        discountValue: discountValue,
        minimumOrder: minimumOrder,
        startDate: _startDate!,
        endDate: _endDate!,
        status: _status,
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
      );

      await _repository.createPromo(promo);

      if (!mounted) return;
      // Return the created promo itself (not just `true`) so the
      // caller can splice it straight into its in-memory list instead
      // of re-fetching the whole catalog just to show one new row.
      Navigator.pop(context, promo);
    } on FirebaseException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Unable to save this promotion.');
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _ReportAppBar(title: 'Add Promotion', onBack: () => Navigator.maybePop(context)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ReportBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, appBarTotalHeight + 14, 16, 16),
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        if (_errorMessage != null) ...[
                          _ErrorBanner(message: _errorMessage!),
                          const SizedBox(height: 12),
                        ],
                        GlassContainer(
                          borderRadius: 24,
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Offer Photo',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              PromoPhotoField(
                                onTap: _isSaving ? () {} : _showPhotoOptions,
                                pendingImageBytes: _pickedImageBytes,
                                isBusy: _isPickingImage,
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: 'Promo Code',
                                hint: 'e.g. WELCOME20',
                                controller: _codeController,
                                enabled: !_isSaving,
                                validator: _requiredCode,
                                textInputAction: TextInputAction.next,
                                prefixIcon: Icons.sell_outlined,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Discount Type',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              SegmentedButton<PromoDiscountType>(
                                segments: const [
                                  ButtonSegment(
                                    value: PromoDiscountType.percentage,
                                    label: Text('Percentage'),
                                    icon: Icon(Icons.percent),
                                  ),
                                  ButtonSegment(
                                    value: PromoDiscountType.fixedAmount,
                                    label: Text('Fixed Amount'),
                                    icon: Icon(Icons.attach_money),
                                  ),
                                ],
                                selected: {_discountType},
                                onSelectionChanged: _isSaving
                                    ? null
                                    : (selection) =>
                                        setState(() => _discountType = selection.first),
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: _discountType == PromoDiscountType.percentage
                                    ? 'Discount Value (%)'
                                    : 'Discount Value (₱)',
                                hint: _discountType == PromoDiscountType.percentage
                                    ? 'e.g. 20'
                                    : 'e.g. 50',
                                controller: _discountValueController,
                                enabled: !_isSaving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: _validateDiscountValue,
                                textInputAction: TextInputAction.next,
                                prefixIcon: Icons.discount_outlined,
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                label: 'Minimum Order (₱)',
                                hint: 'Leave as 0 for no minimum',
                                controller: _minimumOrderController,
                                enabled: !_isSaving,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: _validateMinimumOrder,
                                textInputAction: TextInputAction.next,
                                prefixIcon: Icons.payments_outlined,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Valid Period',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black87,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _GlassDateButton(
                                      icon: Icons.calendar_today_outlined,
                                      label: 'Start: ${_formatDate(_startDate)}',
                                      onTap: _isSaving ? null : () => _pickDate(isStart: true),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _GlassDateButton(
                                      icon: Icons.event_outlined,
                                      label: 'End: ${_formatDate(_endDate)}',
                                      onTap: _isSaving ? null : () => _pickDate(isStart: false),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              AppTextField(
                                label: 'Description (optional)',
                                hint: 'e.g. 20% off orders over ₱300',
                                controller: _descriptionController,
                                enabled: !_isSaving,
                                maxLines: 3,
                                textInputAction: TextInputAction.done,
                              ),
                              const SizedBox(height: 12),
                              // Wrapped in its own transparent Material —
                              // SwitchListTile paints its background/ripple
                              // on the nearest Material ancestor, and the
                              // glass panel's own colored Container would
                              // otherwise sit between it and that ancestor,
                              // hiding those effects (Flutter's "ListTile
                              // background color or ink splashes may be
                              // invisible" warning).
                              Material(
                                type: MaterialType.transparency,
                                child: SwitchListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _status == PromoStatus.active,
                                  onChanged: _isSaving
                                      ? null
                                      : (value) => setState(() => _status =
                                          value ? PromoStatus.active : PromoStatus.inactive),
                                  title: const Text('Active'),
                                  subtitle: Text(
                                    _status == PromoStatus.active
                                        ? 'Usable by customers once its valid period begins.'
                                        : 'Saved, but hidden and unusable by customers until activated.',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        AppButton(
                          label: 'Create Promotion',
                          icon: Icons.add_circle_outline,
                          isLoading: _isSaving,
                          onPressed: _isSaving ? null : _submit,
                        ),
                      ],
                    ),
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xffFF4D67), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}

/// Glass-styled replacement for the plain [OutlinedButton.icon] date
/// pickers, so the "Valid Period" row reads as frosted glass like
/// the rest of the panel instead of a bordered Material button.
class _GlassDateButton extends StatelessWidget {
  const _GlassDateButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.35),
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------
/// Shared glass shell pieces (background blobs, app bar) — same look
/// as [AdminDashboard]/[AdminNotificationsScreen]/the report screens,
/// duplicated here (private to this file) so this screen doesn't
/// depend on those files directly.
/// -----------------------------------------------------------------

class _ReportBackground extends StatelessWidget {
  const _ReportBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0D47A1), Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff0D47A1).withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff8EC5FC).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal glass app bar: back button + title, same blur/border
/// treatment as the Admin section's other app bars.
class _ReportAppBar extends StatelessWidget {
  const _ReportAppBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kAppBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular glass button — same treatment used across the rest
/// of the Admin section's app bars.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}