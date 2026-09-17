import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/utils/service_unit.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/service_model.dart';

/// PART 17 — a single row in [ManageServicesScreen]'s service list:
/// name, description, price per kg, estimated time, and an
/// active/inactive [StatusBadge], plus Edit and Activate/Deactivate
/// actions.
///
/// Purely presentational — it never touches Firestore. All actual
/// writes go through [ServiceRepository] from the screen that owns
/// this card, same split as [AdminOrderCard] (PART 16).
class AdminServiceCard extends StatelessWidget {
  const AdminServiceCard({
    super.key,
    required this.service,
    required this.onEdit,
    required this.onToggleStatus,
    this.isUpdating = false,
  });

  final ServiceModel service;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;

  /// True while this specific service's activate/deactivate toggle is
  /// mid-flight, so only its own switch shows a spinner rather than
  /// the whole list looking busy.
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isActive = service.status == ServiceStatus.active;

    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        service.name,
                        style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status: isActive ? 'Active' : 'Inactive'),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  service.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  '${ServiceUnitFormat.formatPricePerUnit(service.unit, PriceCalculator.formatCurrency(service.pricePerKg))} · '
                  '${service.estimatedTime}',
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: 'Edit service',
                icon: const Icon(Icons.edit_outlined),
                onPressed: isUpdating ? null : onEdit,
              ),
              if (isUpdating)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Switch(
                  value: isActive,
                  onChanged: (_) => onToggleStatus(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}