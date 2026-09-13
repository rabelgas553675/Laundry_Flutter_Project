import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';

/// PART 18A — the user-side Offers & Promotion system.
///
/// Two jobs, both on one screen:
/// 1. Browse promotions that are currently active AND within their
///    start/end date window (never expired, never scheduled, never
///    admin-deactivated — see [PromoRepository.getVisiblePromos]).
/// 2. Redeem a promo code: type a code (and, optionally, an order
///    subtotal) and see whether it's valid, why not if it isn't, and
///    — when it is valid and a subtotal was given — exactly how much
///    it discounts and what the new total comes out to.
///
/// This screen never creates/saves an order itself — PART 12 already
/// owns that. It's a preview/lookup tool. Wiring a redeemed code into
/// the live PART 11 Order Summary discount total is a follow-up, not
/// part of this screen.
class OffersScreen extends StatefulWidget {
  const OffersScreen({super.key});

  @override
  State<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends State<OffersScreen> {
  final PromoRepository _promoRepository = PromoRepository();

  late Future<List<PromoModel>> _promosFuture;

  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _subtotalController = TextEditingController();

  bool _isChecking = false;
  PromoValidationResult? _result;

  @override
  void initState() {
    super.initState();
    _promosFuture = _promoRepository.getVisiblePromos();
  }

  @override
  void dispose() {
    _codeController.dispose();
    _subtotalController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _promosFuture = _promoRepository.getVisiblePromos(forceRefresh: true);
    });
    await _promosFuture;
  }

  /// PART 18A — "Enter promo codes" / "Apply valid promo codes" /
  /// "See the discounted order total", plus the four validation rules
  /// (expired, invalid, minimum order, inactive).
  Future<void> _applyCode() async {
    if (_isChecking) return;

    final rawSubtotal = _subtotalController.text.trim();
    double? subtotal;
    if (rawSubtotal.isNotEmpty) {
      final parsed = double.tryParse(rawSubtotal);
      if (parsed == null || parsed < 0) {
        setState(() {
          _result = const PromoValidationResult(
            status: PromoValidationStatus.emptyCode,
            promo: null,
            discountAmount: 0,
            newTotal: null,
            message: 'Please enter a valid order subtotal amount.',
          );
        });
        return;
      }
      subtotal = parsed;
    }

    setState(() {
      _isChecking = true;
      _result = null;
    });

    final result = await _promoRepository.validateCode(
      code: _codeController.text,
      orderSubtotal: subtotal,
    );

    if (!mounted) return;
    setState(() {
      _isChecking = false;
      _result = result;
    });
  }

  /// Tapping "Use this code" on a promo card fills the redeem field
  /// above and scrolls straight to applying it, so a user browsing
  /// the list doesn't have to type the code out by hand.
  void _useCode(String code) {
    _codeController.text = code;
    _applyCode();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offers & Promo Codes')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _RedeemCodeCard(
                codeController: _codeController,
                subtotalController: _subtotalController,
                isChecking: _isChecking,
                result: _result,
                onApply: _applyCode,
              ),
              const SizedBox(height: 20),
              Text('Active Promotions', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              FutureBuilder<List<PromoModel>>(
                future: _promosFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: LoadingWidget(message: 'Loading promotions...'),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: ErrorState(
                        message: 'We couldn\'t load current promotions. Please try again.',
                        onRetry: _refresh,
                      ),
                    );
                  }
                  final promos = snapshot.data ?? const <PromoModel>[];
                  if (promos.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(
                        icon: Icons.local_offer_outlined,
                        title: 'No active promotions right now',
                        message: 'Check back soon — new offers show up here automatically.',
                      ),
                    );
                  }
                  return Column(
                    children: promos
                        .map((promo) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _PromoCard(
                                promo: promo,
                                onUseCode: () => _useCode(promo.code),
                              ),
                            ))
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "redeem a code" area at the top of the screen: code field,
/// optional order-subtotal field, Apply button, and the result of the
/// last validation check (success or one of the four failure reasons).
class _RedeemCodeCard extends StatelessWidget {
  const _RedeemCodeCard({
    required this.codeController,
    required this.subtotalController,
    required this.isChecking,
    required this.result,
    required this.onApply,
  });

  final TextEditingController codeController;
  final TextEditingController subtotalController;
  final bool isChecking;
  final PromoValidationResult? result;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.confirmation_number_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('Redeem a Promo Code', style: textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Promo Code',
            hint: 'e.g. WELCOME20',
            controller: codeController,
            textInputAction: TextInputAction.next,
            prefixIcon: Icons.sell_outlined,
          ),
          const SizedBox(height: 12),
          AppTextField(
            label: 'Order Subtotal (optional)',
            hint: 'e.g. 350 — to preview your discounted total',
            controller: subtotalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            prefixIcon: Icons.payments_outlined,
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Apply Code',
            icon: Icons.check_circle_outline,
            isLoading: isChecking,
            onPressed: isChecking ? null : onApply,
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            _ResultBanner(result: result!),
          ],
        ],
      ),
    );
  }
}

/// Shows the outcome of the last `validateCode` call — green with a
/// discount breakdown when valid and a subtotal was given, green with
/// just the terms when valid but no subtotal was given, red with a
/// specific reason otherwise.
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});

  final PromoValidationResult result;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isValid = result.isValid;

    final Color bg = isValid ? colors.primaryContainer : colors.errorContainer;
    final Color fg = isValid ? colors.onPrimaryContainer : colors.onErrorContainer;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(isValid ? Icons.check_circle : Icons.error_outline, color: fg, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.message,
                  style: textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (isValid && result.newTotal != null) ...[
            const Divider(height: 20),
            _AmountRow(
              label: 'Order Subtotal',
              value: PriceCalculator.formatCurrency(result.newTotal! + result.discountAmount),
              color: fg,
            ),
            _AmountRow(
              label: 'Discount (${result.promo?.discountLabel ?? ''})',
              value: '-${PriceCalculator.formatCurrency(result.discountAmount)}',
              color: fg,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Discounted Total',
              value: PriceCalculator.formatCurrency(result.newTotal!),
              color: fg,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// One browsable promotion in the "Active Promotions" list — code,
/// what it's worth, its minimum order (if any), how long it's valid
/// for, and a shortcut to load it straight into the redeem field
/// above.
class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo, required this.onUseCode});

  final PromoModel promo;
  final VoidCallback onUseCode;

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_offer, size: 18, color: colors.primary),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            promo.code,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (promo.description.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(promo.description, style: textTheme.bodyMedium),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.secondaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  promo.discountLabel,
                  style: textTheme.labelLarge?.copyWith(color: colors.onSecondaryContainer),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (promo.minimumOrder > 0)
            Text(
              'Minimum order: ${PriceCalculator.formatCurrency(promo.minimumOrder)}',
              style: textTheme.bodySmall,
            ),
          Text(
            'Valid until ${_formatDate(promo.endDate)}',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: promo.code));
                onUseCode();
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
              label: const Text('Use this code'),
            ),
          ),
        ],
      ),
    );
  }
}