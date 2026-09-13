import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';

/// PART 18B — "Create promotions."
///
/// Same shape and validation rules as [EditPromoScreen], starting
/// from blank fields instead of an existing promo. The uniqueness
/// check here has no id to exclude, since there's no promo document
/// yet — the very first save is what creates one.
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

      final promo = PromoModel(
        id: '',
        code: code,
        discountType: _discountType,
        discountValue: discountValue,
        minimumOrder: minimumOrder,
        startDate: _startDate!,
        endDate: _endDate!,
        status: _status,
        description: _descriptionController.text.trim(),
      );

      await _repository.createPromo(promo);

      if (!mounted) return;
      Navigator.pop(context, true);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Add Promotion')),
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
                hint: _discountType == PromoDiscountType.percentage ? 'e.g. 20' : 'e.g. 50',
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
                hint: 'e.g. 20% off orders over ₱300',
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
                      : 'Saved, but hidden and unusable by customers until activated.',
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