import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_card.dart';
import '../../../models/service_item_model.dart';

/// PART 2 — one row of an itemized per-garment order (currently only
/// Dry Cleaning, see `ServiceType.isItemized`): a catalog
/// [ServiceItemModel] (e.g. "Suit" at ₱150) with a `[-] N [+]`
/// quantity stepper and its running total (`quantity × price`).
///
/// Reused in two places on `LaundryOrderScreen`:
/// - The "Select Items" step: interactive, [onChanged] wired up so
///   the customer can tap `+`/`-`.
/// - The item review step, once quantities are picked: the same card
///   with [onChanged] left `null`, which hides the stepper buttons
///   and shows just the chosen quantity as a read-only pill — a
///   lightweight variant instead of a second, near-identical widget.
class OrderItemCard extends StatelessWidget {
  const OrderItemCard({
    super.key,
    required this.item,
    required this.quantity,
    this.onChanged,
    this.minQuantity = 0,
    this.maxQuantity = 99,
  });

  final ServiceItemModel item;
  final int quantity;

  /// Called with the new quantity when `+`/`-` is tapped. `null`
  /// renders this card in its read-only variant (no stepper buttons).
  final ValueChanged<int>? onChanged;

  final int minQuantity;
  final int maxQuantity;

  bool get _isInteractive => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSelected = quantity > 0;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${PriceCalculator.formatCurrency(item.price)} / pc',
                  style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (quantity > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '$quantity × ${PriceCalculator.formatCurrency(item.price)} = '
                    '${PriceCalculator.formatCurrency(item.price * quantity)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_isInteractive)
            _QuantityStepper(
              quantity: quantity,
              onDecrement:
                  quantity > minQuantity ? () => onChanged!(quantity - 1) : null,
              onIncrement:
                  quantity < maxQuantity ? () => onChanged!(quantity + 1) : null,
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.10)
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '×$quantity',
                style: textTheme.titleSmall?.copyWith(
                  color: isSelected ? colors.primary : colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(icon: Icons.remove, onPressed: onDecrement),
        SizedBox(
          width: 28,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, color: colors.primary),
          ),
        ),
        _StepperButton(icon: Icons.add, onPressed: onIncrement),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onPressed,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? colors.primary.withValues(alpha: 0.12)
              : colors.surfaceContainerHighest,
        ),
        child: Icon(icon, size: 16, color: enabled ? colors.primary : colors.outline),
      ),
    );
  }
}