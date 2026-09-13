import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../models/user_model.dart';

/// PART 17 — a single row in [ManageUsersScreen]'s user list.
///
/// Displays exactly what this part's spec calls for: Name, Email,
/// Phone, Address, Role, Status, Registration Date — plus Edit and
/// Activate/Deactivate actions.
///
/// Purely presentational — it never touches Firestore. All writes go
/// through [UserRepository]/[AuthRepository] from the screen that
/// owns this card, same split as [AdminOrderCard]/[AdminServiceCard].
class AdminUserCard extends StatelessWidget {
  const AdminUserCard({
    super.key,
    required this.user,
    required this.isSelf,
    required this.onEdit,
    required this.onToggleActive,
    this.isUpdating = false,
  });

  final UserModel user;

  /// True when [user] is the currently signed-in Admin — disables the
  /// activate/deactivate switch so an Admin can't lock themselves out
  /// from this list (the edit dialog carries the same guard, and
  /// explains why, for the case where they open it anyway).
  final bool isSelf;

  final VoidCallback onEdit;
  final VoidCallback onToggleActive;

  /// True while this specific user's activate/deactivate toggle is
  /// mid-flight, so only its own switch shows a spinner.
  final bool isUpdating;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                backgroundImage:
                    user.profileImageUrl != null ? NetworkImage(user.profileImageUrl!) : null,
                child: user.profileImageUrl == null
                    ? Text(user.name.isNotEmpty ? user.name[0].toUpperCase() : '?')
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.name.isEmpty ? '—' : user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Text('(you)', style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  StatusBadge(status: user.role == UserRole.admin ? 'Admin' : 'User'),
                  const SizedBox(height: 6),
                  StatusBadge(status: user.isActive ? 'Active' : 'Inactive'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _InfoRow(icon: Icons.phone_outlined, label: user.phone.isEmpty ? '—' : user.phone),
          _InfoRow(icon: Icons.home_outlined, label: user.address.isEmpty ? '—' : user.address),
          _InfoRow(icon: Icons.event_outlined, label: _formatShortDate(user.createdAt)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              const SizedBox(width: 8),
              if (isUpdating)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: isSelf ? null : onToggleActive,
                  icon: Icon(
                    user.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                    size: 18,
                  ),
                  label: Text(user.isActive ? 'Deactivate' : 'Activate'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Sep 12, 2026" — matches the format already used for "Recent
/// Users" on the Admin Dashboard (PART 15), kept local to this file
/// for the same reason that copy is.
String _formatShortDate(DateTime? date) {
  if (date == null) return '—';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}