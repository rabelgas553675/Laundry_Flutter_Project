import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_service.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';
import '../widgets/promo_photo_field.dart';

/// PART 18B — "Edit promotions" (code, discount type/value, minimum
/// order, valid dates, description) and "Deactivate promotions" (via
/// the Active switch).
///
/// Same shape and validation rules as [AddPromoScreen], seeded from
/// an [existing] promo — the one difference is the uniqueness check
/// excludes [existing]'s own id, so saving a promo without changing
/// its code never falsely reports a collision with itself.
class EditPromoScreen extends StatefulWidget {
  const EditPromoScreen({super.key, required this.existing, this.repository});

  final PromoModel existing;

  /// Injectable for widget tests; defaults to a real
  /// Supabase-backed [PromoRepository].
  final PromoRepository? repository;

  @override
  State<EditPromoScreen> createState() => _EditPromoScreenState();
}

class _EditPromoScreenState extends State<EditPromoScreen> {
  late final PromoRepository _repository = widget.repository ?? PromoRepository();
  final _fileService = FileService();
  final _formKey = GlobalKey<FormState>();

  late final _codeController = TextEditingController(text: widget.existing.code);
  late final _discountValueController =
      TextEditingController(text: _trimZeros(widget.existing.discountValue));
  late final _minimumOrderController =
      TextEditingController(text: _trimZeros(widget.existing.minimumOrder));
  late final _descriptionController = TextEditingController(text: widget.existing.description);

  late PromoDiscountType _discountType = widget.existing.discountType;
  late PromoStatus _status = widget.existing.status;
  late DateTime? _startDate = widget.existing.startDate;
  late DateTime? _endDate = widget.existing.endDate;

  // PART 19 — mirrors AddPromoScreen's photo state. [_removePhoto]
  // tracks an explicit "Remove Selected Photo" action distinctly from
  // "nothing changed", so _submit knows whether to clear
  // widget.existing.imageUrl versus leaving it untouched.
  late String? _existingImageUrl = widget.existing.imageUrl;
  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  bool _isPickingImage = false;
  bool _removePhoto = false;

  bool _isSaving = false;
  String? _errorMessage;

  static String _trimZeros(double value) {
    return value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toString();
  }

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
    final hasAnyPhoto = _pickedImageBytes != null || (_existingImageUrl ?? '').trim().isNotEmpty;
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
                if (hasAnyPhoto)
                  PromoPhotoSheetOption(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove Selected Photo',
                    color: colorScheme.error,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      setState(() {
                        _pickedImageFile = null;
                        _pickedImageBytes = null;
                        _existingImageUrl = null;
                        _removePhoto = true;
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
        _removePhoto = false;
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
      // "Promo code must be unique" — excluding this promo's own id,
      // so leaving the code unchanged never reports a false collision.
      final taken = await _repository.isCodeTaken(code, excludeId: widget.existing.id);
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

      // PART 19 — a newly picked photo replaces the old Storage
      // object at the same path (uploadPromoImage uses upsert), so no
      // separate delete-then-upload step is needed for a replacement.
      // An explicit "Remove Selected Photo" with nothing re-picked
      // deletes the stored photo outright.
      String? imageUrl = widget.existing.imageUrl;
      if (_pickedImageFile != null) {
        try {
          imageUrl = await _fileService.uploadPromoImage(
            promoId: widget.existing.id,
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
      } else if (_removePhoto) {
        try {
          await _fileService.removePromoImage(widget.existing.id);
        } catch (_) {
          // Non-fatal — proceed with clearing imageUrl on the promo
          // document either way, same as removeProfileImage callers
          // elsewhere in the app.
        }
        imageUrl = null;
      }

      final updated = widget.existing.copyWith(
        code: code,
        discountType: _discountType,
        discountValue: discountValue,
        minimumOrder: minimumOrder,
        startDate: _startDate,
        endDate: _endDate,
        status: _status,
        description: _descriptionController.text.trim(),
        imageUrl: imageUrl,
      );

      await _repository.updatePromo(updated);

      if (!mounted) return;
      Navigator.pop(context, true);
    } on sb.PostgrestException catch (e) {
      setState(() => _errorMessage = e.message.isNotEmpty ? e.message : 'Unable to save this promotion.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Promotion')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 12),
              ],
              Text('Offer Photo', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              PromoPhotoField(
                onTap: _isSaving ? () {} : _showPhotoOptions,
                pendingImageBytes: _pickedImageBytes,
                existingImageUrl: _existingImageUrl,
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
              Text('Discount Type', style: Theme.of(context).textTheme.titleSmall),
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
                    : (selection) => setState(() => _discountType = selection.first),
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: _discountType == PromoDiscountType.percentage
                    ? 'Discount Value (%)'
                    : 'Discount Value (₱)',
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
              Text('Valid Period', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => _pickDate(isStart: true),
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(
                        'Start: ${_formatDate(_startDate)}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : () => _pickDate(isStart: false),
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        'End: ${_formatDate(_endDate)}',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                label: 'Description (optional)',
                controller: _descriptionController,
                enabled: !_isSaving,
                maxLines: 3,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _status == PromoStatus.active,
                onChanged: _isSaving
                    ? null
                    : (value) =>
                        setState(() => _status = value ? PromoStatus.active : PromoStatus.inactive),
                title: const Text('Active'),
                subtitle: Text(
                  _status == PromoStatus.active
                      ? 'Usable by customers once its valid period begins.'
                      : 'Hidden and unusable by customers until reactivated.',
                ),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Save Changes',
                icon: Icons.check_circle_outline,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(color: colors.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}