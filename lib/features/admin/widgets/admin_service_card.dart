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
    required this.onDelete,
    this.isUpdating = false,
    this.isDeleting = false,
  });

  final ServiceModel service;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;

  /// Delete Service action — shows a trash icon next to Edit.
  /// [ManageServicesScreen] owns the confirmation dialog and the
  /// actual delete; this card only surfaces the tap.
  final VoidCallback onDelete;

  /// True while this specific service's activate/deactivate toggle is
  /// mid-flight, so only its own switch shows a spinner rather than
  /// the whole list looking busy.
  final bool isUpdating;

  /// True while this specific service is being deleted. Disables
  /// Edit/Delete/toggle on this card (same reasoning as [isUpdating])
  /// so the admin can't start a second action on a service that's
  /// already being removed.
  final bool isDeleting;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isActive = service.status == ServiceStatus.active;
    final isBusy = isUpdating || isDeleting;

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
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit service',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: isBusy ? null : onEdit,
                  ),
                  if (isDeleting)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      tooltip: 'Delete service',
                      icon: Icon(Icons.delete_outline, color: colors.error),
                      onPressed: isBusy ? null : onDelete,
                    ),
                ],
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
                  onChanged: isBusy ? null : (_) => onToggleStatus(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}