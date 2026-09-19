import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/file_service.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import 'service_photo_field.dart';

/// PART 17 — the "Add service" / "Edit service" form.
///
/// One dialog handles both cases: [existing] null means "Add service"
/// (a brand-new [ServiceModel] with a blank Firestore-assigned id is
/// created); non-null means "Edit service" (name, description, price,
/// estimated time, and active/inactive are all editable).
///
/// ── SERVICE PHOTO ───────────────────────────────────────────────
/// An optional photo, uploaded by the admin from their device via
/// [ServicePhotoField] (between Service Name and Description). The
/// image bytes go to Supabase Storage through [FileService]; only the
/// resulting public URL is saved on the service document as
/// [ServiceModel.imageUrl]. Editing shows the currently saved photo,
/// which can be replaced or removed. Nothing is uploaded, replaced,
/// or deleted until the admin taps Save — Cancel discards any picked
/// photo.
///
/// ── GLASS REDESIGN ──────────────────────────────────────────────
/// A frosted glass card (`BackdropFilter` blur + translucent white
/// `Container`) instead of a stock `AlertDialog`. The card uses a
/// *tight* width (`SizedBox(width: cardWidth)`) rather than a loose
/// `ConstrainedBox(maxWidth: ...)`, because a loose max-width
/// combined with `BackdropFilter`/`ClipRRect` can make Flutter Web
/// collapse a `TextButton`'s internal tap-target sizing pass into an
/// unbounded one ("BoxConstraints forces an infinite width").
///
/// ── BUTTON ROW FIX ──────────────────────────────────────────────
/// The app's global `TextButtonTheme` gives every `TextButton` a
/// full-width `minimumSize` — correct for standalone form buttons,
/// wrong here. The Cancel `TextButton` below carries its own explicit,
/// compact `style:` that overrides the theme locally, so it sits
/// inline with "Save" instead of stretching into a full-width pill.
///
/// ── "WHY IS IT DARK" FIX ─────────────────────────────────────────
/// `showDialog()`'s default `barrierColor` is `Colors.black54`
/// (54% black) painted behind the dialog. `BackdropFilter` blurs
/// *everything* behind this card, including that dark scrim — so a
/// glass fill that's only ~55% opaque white lets the darkened,
/// blurred scrim show through and reads as grey instead of white.
/// Fixed two ways, both needed:
///   1. Raised the glass fill opacity here from 0.55 → 0.88 (and the
///      border from 0.6 → 0.8) so the card reads as white regardless
///      of what's blurred behind it.
///   2. The `showDialog(...)` call site (wherever this dialog is
///      opened, e.g. `manage_services_screen.dart`) should also pass
///      a lighter `barrierColor` — see the snippet at the bottom of
///      this file's accompanying message.
class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({
    super.key,
    this.existing,
    this.repository,
    this.fileService,
  });

  /// Null for "Add service"; the service being edited otherwise.
  final ServiceModel? existing;

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [ServiceRepository].
  final ServiceRepository? repository;

  /// Injectable for widget tests; defaults to a real Supabase-backed
  /// [FileService].
  final FileService? fileService;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  late final ServiceRepository _repository =
      widget.repository ?? ServiceRepository();
  late final FileService _fileService = widget.fileService ?? FileService();
  final _formKey = GlobalKey<FormState>();

  /// BUG FIX — a failed save (e.g. the Supabase image upload throwing)
  /// used to just silently re-enable the form with no visible sign
  /// anything went wrong: [_errorMessage]'s [_GlassErrorBanner] renders
  /// at the very top of this long form, but an admin who has scrolled
  /// down to Price/Estimated Time (a likely place to be looking right
  /// before tapping Save) would never see it — the dialog would look
  /// exactly like nothing happened, indistinguishable from a hang.
  /// [_scrollController] lets [_submit] scroll back to the top the
  /// moment an error is set, so the banner is always the first thing
  /// visible.
  final _scrollController = ScrollController();

  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description ?? '',
  );
  late final _priceController = TextEditingController(
    text: widget.existing != null
        ? widget.existing!.pricePerKg.toStringAsFixed(2)
        : '',
  );
  late final _estimatedTimeController = TextEditingController(
    text: widget.existing?.estimatedTime ?? '',
  );

  late ServiceStatus _status = widget.existing?.status ?? ServiceStatus.active;

  /// Defaults to kilogram for "Add service" — matches
  /// `ServiceModel.unit`'s own default.
  late ServiceUnit _unit = widget.existing?.unit ?? ServiceUnit.kilogram;

  // ── Service photo state ────────────────────────────────────────
  // [_existingImageUrl] is the saved photo being shown (Edit only);
  // [_pickedImageFile]/[_pickedImageBytes] are a photo picked this
  // session and not yet uploaded — they take priority for preview.
  // [_removePhoto] records an explicit Remove of a *saved* photo,
  // which is different from "nothing changed": _submit needs to know
  // whether to clear the stored imageUrl or leave it alone.
  late String? _existingImageUrl = widget.existing?.imageUrl;
  XFile? _pickedImageFile;
  Uint8List? _pickedImageBytes;
  bool _isPickingImage = false;
  bool _removePhoto = false;

  /// Id for a *new* service, generated once (lazily, on first save) and
  /// reused if saving fails and the admin retries — so the retry
  /// overwrites the same Storage object instead of orphaning a new one.
  late final String _newServiceId = _repository.newServiceId();

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _estimatedTimeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Scrolls the form back to the top so a freshly-set
  /// [_errorMessage]'s banner is guaranteed to be visible, regardless
  /// of how far down the admin had scrolled when they tapped Save.
  /// Runs after the current frame so it scrolls against the *new*
  /// (taller, error-banner-included) content height, not the old one.
  void _scrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String? _requiredField(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validatePrice(String? value) {
    final trimmed = value?.trim() ?? '';
    final unitNoun = _unit.isPiece ? 'piece' : 'kg';
    if (trimmed.isEmpty) return 'Price per $unitNoun is required.';
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number.';
    if (parsed <= 0) return 'Price must be greater than zero.';
    return null;
  }

  /// Opens the device's file/photo picker. Validates (JPG/PNG, not
  /// empty, under 5 MB) right away so a bad file is rejected now, with
  /// a clear message, rather than after the admin taps Save.
  Future<void> _pickImage() async {
    if (_isSaving || _isPickingImage) return;

    XFile? picked;
    try {
      picked = await _fileService.pickFromGallery();
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not open your photos. Please try again.');
      }
      return;
    }
    if (picked == null) return; // admin cancelled the picker

    setState(() {
      _isPickingImage = true;
      _errorMessage = null;
    });
    try {
      await _fileService.validateImage(picked);
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImageFile = picked;
        _pickedImageBytes = bytes;
        _removePhoto = false;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not load that photo. Please try another.');
      }
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  /// Clears whichever photo is showing (picked or saved). If the
  /// service already had a saved photo, that's flagged for deletion on
  /// Save; a picked-but-unsaved photo is simply dropped.
  void _removeImage() {
    if (_isSaving) return;
    setState(() {
      _removePhoto = (widget.existing?.imageUrl ?? '').trim().isNotEmpty;
      _pickedImageFile = null;
      _pickedImageBytes = null;
      _existingImageUrl = null;
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim();
    final pricePerKg = double.parse(_priceController.text.trim());
    final estimatedTime = _estimatedTimeController.text.trim();

    try {
      final serviceId = _isEditing ? widget.existing!.id : _newServiceId;

      // A newly picked photo is uploaded first — its public URL has to
      // exist before the document is written. Uploading overwrites the
      // same Storage path (upsert), so replacing needs no separate
      // delete step. `null` here means "no new photo": Edit keeps
      // whatever imageUrl is already saved (or clears it, see below).
      String? uploadedImageUrl;
      if (_pickedImageFile != null) {
        try {
          uploadedImageUrl = await _fileService.uploadServiceImage(
            serviceId: serviceId,
            file: _pickedImageFile!,
          );
        } on AppException {
          rethrow; // already user-facing (bad file, Storage error)
        } catch (_) {
          throw const AppException('Could not upload the photo. Please try again.');
        }
      }

      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          name: name,
          description: description,
          pricePerKg: pricePerKg,
          estimatedTime: estimatedTime,
          status: _status,
          unit: _unit,
          imageUrl: uploadedImageUrl,
          clearImageUrl: _removePhoto,
        );
        await _repository.updateService(updated);

        // Removing a saved photo deletes its Storage object only
        // *after* the document stops pointing at it, so a failed save
        // never leaves the service referencing a deleted image.
        // Non-fatal: the document is already correct either way.
        if (_removePhoto) {
          try {
            await _fileService.removeServiceImage(serviceId);
          } catch (_) {}
        }
      } else {
        await _repository.createService(
          ServiceModel(
            id: serviceId,
            name: name,
            description: description,
            pricePerKg: pricePerKg,
            estimatedTime: estimatedTime,
            status: _status,
            unit: _unit,
            imageUrl: uploadedImageUrl,
          ),
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on AppException catch (e) {
      setState(() => _errorMessage = e.message);
      _scrollToTop();
    } on FirebaseException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Unable to save this service.');
      _scrollToTop();
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
      _scrollToTop();
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tight width instead of a loose ConstrainedBox(maxWidth: ...) —
    // see the class doc comment for why this matters here.
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth < 480 + 40 ? screenWidth - 40 : 480.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: cardWidth,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              width: cardWidth,
              decoration: BoxDecoration(
                // Raised from 0.55 → 0.88: BackdropFilter blurs the
                // dark showDialog() scrim behind this card too, so a
                // fill that's only ~55% opaque let that darkened blur
                // bleed through and read as grey instead of white.
                color: Colors.white.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xff2E75B6).withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isEditing
                                  ? Icons.edit_outlined
                                  : Icons.local_laundry_service_outlined,
                              size: 18,
                              color: const Color(0xff2E75B6),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _isEditing ? 'Edit Service' : 'Add Service',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black87,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Flexible(
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_errorMessage != null) ...[
                                _GlassErrorBanner(message: _errorMessage!),
                                const SizedBox(height: 12),
                              ],
                              AppTextField(
                                label: 'Service Name',
                                controller: _nameController,
                                enabled: !_isSaving,
                                validator: (v) => _requiredField(v, 'Service name'),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              ServicePhotoField(
                                pendingImageBytes: _pickedImageBytes,
                                existingImageUrl: _existingImageUrl,
                                isBusy: _isPickingImage,
                                enabled: !_isSaving,
                                onPick: _pickImage,
                                onRemove: _removeImage,
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                label: 'Description',
                                controller: _descriptionController,
                                enabled: !_isSaving,
                                maxLines: 3,
                                validator: (v) => _requiredField(v, 'Description'),
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Priced By',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: Colors.black54,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<ServiceUnit>(
                                  segments: const [
                                    ButtonSegment(
                                      value: ServiceUnit.kilogram,
                                      label: Text('Per Kg'),
                                      icon: Icon(Icons.scale_outlined),
                                    ),
                                    ButtonSegment(
                                      value: ServiceUnit.piece,
                                      label: Text('Per Piece'),
                                      icon: Icon(Icons.checkroom_outlined),
                                    ),
                                  ],
                                  selected: {_unit},
                                  onSelectionChanged: _isSaving
                                      ? null
                                      : (selection) {
                                          setState(() => _unit = selection.first);
                                          _formKey.currentState?.validate();
                                        },
                                ),
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                label: ServiceUnitFormat.priceFieldLabel(_unit),
                                controller: _priceController,
                                enabled: !_isSaving,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                validator: _validatePrice,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 12),
                              AppTextField(
                                label: 'Estimated Time',
                                controller: _estimatedTimeController,
                                enabled: !_isSaving,
                                hint: 'e.g. 24 hours',
                                validator: (v) => _requiredField(v, 'Estimated time'),
                                textInputAction: TextInputAction.done,
                              ),
                              const SizedBox(height: 12),
                              Material(
                                type: MaterialType.transparency,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    activeThumbColor: const Color(0xff2E75B6),
                                    value: _status == ServiceStatus.active,
                                    onChanged: _isSaving
                                        ? null
                                        : (value) => setState(
                                              () => _status = value
                                                  ? ServiceStatus.active
                                                  : ServiceStatus.inactive,
                                            ),
                                    title: const Text(
                                      'Active',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _status == ServiceStatus.active
                                          ? 'Visible to customers when placing an order.'
                                          : 'Hidden from customers, but past orders keep working.',
                                      style: const TextStyle(color: Colors.black54),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Button row: Material(transparency) so ink
                      // splashes paint over the glass correctly, and
                      // SizedBox(width: infinity) so the Row always
                      // has a concrete width to lay out against
                      // (prevents the "infinite width" crash).
                      // Cancel carries its own local style so it
                      // doesn't inherit the app's global full-width
                      // TextButtonTheme.
                      Material(
                        type: MaterialType.transparency,
                        child: SizedBox(
                          width: double.infinity,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed:
                                    _isSaving ? null : () => Navigator.pop(context, false),
                                style: TextButton.styleFrom(
                                  minimumSize: const Size(64, 44),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  foregroundColor: Colors.black54,
                                  backgroundColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                ),
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 120,
                                height: 44,
                                child: AppButton(
                                  label: 'Save',
                                  isLoading: _isSaving,
                                  onPressed: _submit,
                                ),
                              ),
                            ],
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
      ),
    );
  }
}

/// Glass-styled error banner, matching the frosted look of the rest
/// of the dialog rather than a flat error-container [Container].
class _GlassErrorBanner extends StatelessWidget {
  const _GlassErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xffFF4D67).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffFF4D67).withValues(alpha: 0.3)),
      ),
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