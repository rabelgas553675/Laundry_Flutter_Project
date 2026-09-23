import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/order_model.dart';

/// PART 19D — Order Report's secondary analytics component: a bar
/// chart of [OrderReportData.statusCounts], one bar per
/// [OrderStatus], sitting alongside the existing status-count list
/// (see [OrderReportScreen]) rather than replacing it.
///
/// Purely presentational — [statusCounts] should be exactly
/// [OrderReportData.statusCounts] (or [OrderReportData.countFor] for
/// each status), computed by [ReportService.buildOrderReport] from
/// real Firestore order data. This widget never touches Firestore
/// itself, and never decides what counts as a given status.
///
/// Bar colors match [StatusBadge]'s own status → color mapping (kept
/// as a small local copy, same pattern this file's screen already
/// uses for its private glass-shell pieces) so a status reads the
/// same color here as it does on every order card/badge elsewhere in
/// the Admin section.
class StatusBreakdownChart extends StatelessWidget {
  const StatusBreakdownChart({super.key, required this.statusCounts});

  final Map<OrderStatus, int> statusCounts;

  static Color _colorFor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return const Color(0xFFF59E0B);
      case OrderStatus.received:
        return const Color(0xFF6366F1);
      case OrderStatus.washing:
        return const Color(0xFF0EA5E9);
      case OrderStatus.drying:
        return const Color(0xFF14B8A6);
      case OrderStatus.ready:
        return const Color(0xFF8B5CF6);
      case OrderStatus.completed:
        return const Color(0xFF16A34A);
      case OrderStatus.cancelled:
        return const Color(0xFFDC2626);
    }
  }

  /// Short, fixed-width labels for the X-axis — the full status name
  /// (e.g. "Cancelled") is used everywhere else (the [StatusBadge]
  /// rows below this chart already spell it out in full), but would
  /// overlap badly across 7 bars at this chart's width.
  static String _shortLabelFor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.received:
        return 'Received';
      case OrderStatus.washing:
        return 'Washing';
      case OrderStatus.drying:
        return 'Drying';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  @override
  Widget build(BuildContext context) {
    final statuses = OrderStatus.values;
    final counts = [for (final status in statuses) statusCounts[status] ?? 0];
    final highestCount = counts.fold<int>(0, (max, v) => v > max ? v : max);
    final maxY = highestCount <= 0 ? 4.0 : (highestCount * 1.3).ceilToDouble();
    final yInterval = (maxY / 4).clamp(1.0, double.infinity);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.bar_chart_rounded, size: 18, color: Color(0xff2196F3)),
            const SizedBox(width: 8),
            Text(
              'Orders by Status',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: BarChart(
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yInterval,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.black.withValues(alpha: 0.06),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                show: true,
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: yInterval,
                    getTitlesWidget: (value, meta) {
                      if (value != value.roundToDouble()) return const SizedBox.shrink();
                      return Text(
                        value.round().toString(),
                        style: const TextStyle(fontSize: 10, color: Colors.black54),
                      );
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (value, meta) {
                      final index = value.round();
                      if (index < 0 || index >= statuses.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Transform.rotate(
                          angle: -0.5,
                          child: Text(
                            _shortLabelFor(statuses[index]),
                            style: const TextStyle(fontSize: 9, color: Colors.black54),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => Colors.black.withValues(alpha: 0.78),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final status = statuses[group.x];
                    final count = counts[group.x];
                    final label = count == 1 ? '1 order' : '$count orders';
                    return BarTooltipItem(
                      '${_shortLabelFor(status)}\n$label',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (var i = 0; i < statuses.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: counts[i].toDouble(),
                        color: _colorFor(statuses[i]),
                        width: 18,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }
}