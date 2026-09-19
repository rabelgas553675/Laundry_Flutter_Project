// TARGET PATH IN YOUR PROJECT: lib/core/widgets/dropoff_info_card.dart
//
// Shop info shown for Drop-off orders (used by the New Laundry Order
// form and the Order Summary screen).
//
// FIX: "RIGHT OVERFLOWED BY ~23 PIXELS" — the shop name Text sat directly
// inside a Row, so it could not shrink and ran past the card edge. Every
// row below now puts its text inside Expanded so long text wraps.
//
// NOTE: this was rebuilt from screenshots. The defaults below match what
// the app currently shows. If your original file reads the shop name /
// address / hours from a config, model or constants file, keep that source
// and only copy the layout (Expanded around each Text).

import 'package:flutter/material.dart';

class DropoffInfoCard extends StatelessWidget {
  const DropoffInfoCard({
    super.key,
    this.shopName = 'Laundry Management System',
    this.address = 'Rizal Street, Digos City, Davao del Sur, Philippines',
    this.hours = const ['Mon–Sat: 8:00 AM – 7:00 PM', 'Sun: 9:00 AM – 5:00 PM'],
  });

  final String shopName;
  final String address;
  final List<String> hours;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Shop name ------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.storefront_outlined, size: 20, color: colors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  shopName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ---- Address --------------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(address, style: textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ---- Business hours ------------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.schedule_outlined,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in hours)
                      Text(line, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}