import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../models/service_model.dart';

/// PART 2 — small "you're ordering: X" banner shown above the item
/// selection / weight steps, so the customer keeps seeing which
/// service they picked (and its price/unit) without scrolling back
/// up to "Select Service". Pure presentation — takes a [ServiceModel]
/// and renders it; it never fetches anything itself.
class OrderServiceHeader extends StatelessWidget {
  const OrderServiceHeader({super.key, required this.service});

  final ServiceModel service;

  IconData get _icon {
    switch (service.serviceType) {
      case ServiceType.dryCleaning:
        return Icons.dry_cleaning_outlined;
      case ServiceType.washAndIroning:
        return Icons.iron_outlined;
      case ServiceType.premiumWash:
        return Icons.auto_awesome_outlined;
      case ServiceType.quickWash:
        return Icons.flash_on_outlined;
      case ServiceType.standardWash:
        return Icons.local_laundry_service_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(_icon, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  service.pricingType == PricingType.perItem
                      ? 'Priced per garment · see items below'
                      : '${ServiceUnitFormat.formatPricePerUnit(service.unit, PriceCalculator.formatCurrency(service.price))} · ${service.estimatedTime}',
                  style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}