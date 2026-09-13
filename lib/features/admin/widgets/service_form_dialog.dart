import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';

/// PART 17 — the "Add service" / "Edit service" form.
///
/// One dialog handles both cases: [existing] null means "Add service"
/// (a brand-new [ServiceModel] with a blank Firestore-assigned id is
/// created); non-null means "Edit service" (name, description, price,
/// estimated time, and active/inactive are all editable — matching
/// this part's spec: "Change price / Change description / Change
/// estimated time / Activate/deactivate service").
///
/// Talks directly to [ServiceRepository] itself (rather than handing
/// form values back to the caller) so [ManageServicesScreen] only
/// needs to know "did something change" (the `true` this pops with on
/// success), not how to persist it — same shape as the
/// `showDialog<bool>` confirmation in PART 16's Admin Order Details.
class ServiceFormDialog extends StatefulWidget {
  const ServiceFormDialog({super.key, this.existing, this.repository});

  /// Null for "Add service"; the service being edited otherwise.
  final ServiceModel? existing;

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [ServiceRepository].
  final ServiceRepository? repository;

  @override
  State<ServiceFormDialog> createState() => _ServiceFormDialogState();
}

class _ServiceFormDialogState extends State<ServiceFormDialog> {
  late final ServiceRepository _repository = widget.repository ?? ServiceRepository();
  final _formKey = GlobalKey<FormState>();

  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late final _descriptionController =
      TextEditingController(text: widget.existing?.description ?? '');
  late final _priceController = TextEditingController(
    text: widget.existing != null ? widget.existing!.pricePerKg.toStringAsFixed(2) : '',
  );
  late final _estimatedTimeController =
      TextEditingController(text: widget.existing?.estimatedTime ?? '');

  late ServiceStatus _status = widget.existing?.status ?? ServiceStatus.active;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _estimatedTimeController.dispose();
    super.dispose();
  }

  String? _requiredField(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validatePrice(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Price per kg is required.';
    final parsed = double.tryParse(trimmed);
    if (parsed == null) return 'Enter a valid number.';
    if (parsed <= 0) return 'Price must be greater than zero.';
    return null;
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
      if (_isEditing) {
        final updated = widget.existing!.copyWith(
          name: name,
          description: description,
          pricePerKg: pricePerKg,
          estimatedTime: estimatedTime,
          status: _status,
        );
        await _repository.updateService(updated);
      } else {
        await _repository.createService(ServiceModel(
          id: '',
          name: name,
          description: description,
          pricePerKg: pricePerKg,
          estimatedTime: estimatedTime,
          status: _status,
        ));
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseException catch (e) {
      setState(() => _errorMessage = e.message ?? 'Unable to save this service.');
    } catch (_) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Service' : 'Add Service'),
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
                label: 'Service Name',
                controller: _nameController,
                enabled: !_isSaving,
                validator: (v) => _requiredField(v, 'Service name'),
                textInputAction: TextInputAction.next,
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
              AppTextField(
                label: 'Price per kg (₱)',
                controller: _priceController,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _status == ServiceStatus.active,
                onChanged: _isSaving
                    ? null
                    : (value) => setState(
                          () => _status = value ? ServiceStatus.active : ServiceStatus.inactive,
                        ),
                title: const Text('Active'),
                subtitle: Text(
                  _status == ServiceStatus.active
                      ? 'Visible to customers when placing an order.'
                      : 'Hidden from customers, but past orders keep working.',
                ),
              ),
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