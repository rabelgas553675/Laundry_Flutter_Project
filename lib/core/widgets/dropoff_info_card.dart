import 'package:flutter/material.dart';

import '../../app/constants.dart';
import 'app_card.dart';

/// Read-only info card shown when the customer picks Drop-off in the
/// PART 10.2 order form. The shop has exactly one physical location,
/// so this reads from [AppConstants] rather than Firestore — no
/// database/Firebase functionality is added in PART 10.
class DropoffInfoCard extends StatelessWidget {
  const DropoffInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.storefront_outlined, color: colors.primary),
              const SizedBox(width: 8),
              Text(AppConstants.shopName, style: textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(AppConstants.shopAddress, style: textTheme.bodyMedium),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule_outlined, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(AppConstants.shopBusinessHours, style: textTheme.bodyMedium),
              ),
            ],
          ),
        ],
      ),
    );
  }
}