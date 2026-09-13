import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/promo_model.dart';

/// PART 18B — a single row in [ManagePromosScreen]'s promo list.
///
/// Doubles as the "view promotion details" surface (code, discount,
/// minimum order, valid dates, description, and computed
/// [PromoDisplayStatus]) since a promo has few enough fields to show
/// fully here — there's no separate details screen. Also exposes Edit
/// and Activate/Deactivate actions.
///
/// Purely presentational — it never touches Firestore. All actual
/// writes go through [PromoRepository] from the screen that owns this
/// card, same split as [AdminServiceCard] (PART 17).
class AdminPromoCard extends StatelessWidget {
  const AdminPromoCard({
    super.key,
    required this.promo,
    required this.onEdit,
    required this.onToggleStatus,
    this.isUpdating = false,
  });

  final PromoModel promo;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;

  /// True while this specific promo's activate/deactivate toggle is
  /// mid-flight, so only its own switch shows a spinner rather than
  /// the whole list looking busy.
  final bool isUpdating;

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final isActive = promo.status == PromoStatus.active;
    final displayStatus = promo.displayStatus();

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
                        promo.code,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(status: displayStatus.label),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  promo.discountLabel,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (promo.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    promo.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  promo.minimumOrder > 0
                      ? 'Min. order: ${PriceCalculator.formatCurrency(promo.minimumOrder)}'
                      : 'No minimum order',
                  style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  'Valid: ${_formatDate(promo.startDate)} – ${_formatDate(promo.endDate)}',
                  style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            children: [
              IconButton(
                tooltip: 'Edit promotion',
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