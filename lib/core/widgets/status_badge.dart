import 'package:flutter/material.dart';

class StatusBadge extends StatefulWidget {
  const StatusBadge({super.key, required this.status});

  final String status;

  @override
  State<StatusBadge> createState() => _StatusBadgeState();
}

class _StatusBadgeState extends State<StatusBadge> {
  Color _colorFor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'received':
        return const Color(0xFF6366F1);
      case 'washing':
        return const Color(0xFF0EA5E9);
      case 'drying':
        return const Color(0xFF14B8A6);
      case 'ready':
        return const Color(0xFF8B5CF6);
      case 'completed':
        return const Color(0xFF16A34A);
      case 'cancelled':
        return const Color(0xFFDC2626);
      // PART 18B — promo PromoDisplayStatus labels ('Active' also
      // covers PART 17's service active/inactive badges, which
      // previously fell through to the gray default).
      case 'active':
        return const Color(0xFF16A34A);
      case 'inactive':
        return const Color(0xFF64748B);
      case 'expired':
        return const Color(0xFFDC2626);
      case 'scheduled':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(widget.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(widget.status, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}