import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../models/order_item_model.dart';

/// PART 3 — renders an itemized order's priced line items exactly
/// the way the spec's examples show them:
///
///   2 × Suit             ₱300
///   1 × Dress            ₱150
///   3 × Pants            ₱270
///
/// Shared between `OrderSummaryScreen` (pre-confirm review of an
/// [OrderDraft]) and `OrderDetailsScreen` (post-order view of a
/// persisted [OrderModel]), so a Dry Cleaning order's per-garment
/// breakdown is only ever formatted in one place. Both screens pass
/// in the same `List<OrderItemModel>` shape (`OrderDraft
/// .selectedItems` / `OrderModel.items`), so no adapter is needed on
/// either side.
///
/// Read-only — this widget never edits [items] itself. Editing a Dry
/// Cleaning line back on the order form is out of this part's scope.
class OrderItemsBreakdown extends StatelessWidget {
  const OrderItemsBreakdown({super.key, required this.items});

  final List<OrderItemModel> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    if (items.isEmpty) {
      return Text(
        'No items selected.',
        style: textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${item.quantity} × ${item.itemName}',
                    style: textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  PriceCalculator.formatCurrency(item.totalPrice),
                  textAlign: TextAlign.right,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.onSurface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}