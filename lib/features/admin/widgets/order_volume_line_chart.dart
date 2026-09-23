import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../services/report_service.dart';

/// PART 19D — Order Report's main analytics component: a line graph
/// of daily order volume (COUNT of every order, any status, grouped
/// by `createdAt`'s calendar day) across the currently selected date
/// range.
///
/// Purely presentational, same split as [RevenueLineChart]/
/// [ReportDateFilterBar]: [OrderReportScreen] is what calls
/// [ReportService.buildDailyOrderCountSeries] and hands the
/// resulting [points] here — this widget never touches Firestore or
/// [ReportService] itself.
///
/// [points] should be exactly what
/// [ReportService.buildDailyOrderCountSeries] returns: one entry per
/// calendar day in the selected range, in order, with `count: 0` for
/// a day with no orders — so this widget draws every day in the
/// range, and a flat zero line for a range with no orders at all is
/// a normal, valid chart, not an "empty" state.
///
/// This widget only shows a placeholder instead of a chart when
/// [points] itself is empty (no resolvable range) — guarded against
/// so a bad/empty range can never crash the chart.
class OrderVolumeLineChart extends StatelessWidget {
  const OrderVolumeLineChart({super.key, required this.points});

  final List<DailyOrderCountPoint> points;

  static const Color _lineColor = Color(0xff16A34A);
  static const Color _fillColor = Color(0xff14B8A6);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart_rounded, size: 18, color: _lineColor),
            const SizedBox(width: 8),
            Text(
              'Orders Trend',
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
          child: points.isEmpty ? const _ChartEmptyState() : _buildChart(context),
        ),
      ],
    );
  }

  Widget _buildChart(BuildContext context) {
    // A single-day range (e.g. "Today") still needs a non-zero X
    // span, or fl_chart has nothing to lay the point out against.
    final maxX = points.length > 1 ? (points.length - 1).toDouble() : 1.0;

    final counts = points.map((p) => p.count).toList();
    final highestCount = counts.fold<int>(0, (max, v) => v > max ? v : max);
    // Never divide/space against a zero-height axis — a range with
    // no orders at all still needs *some* headroom above the flat
    // line so it renders as a visible line, not a degenerate single
    // pixel. Whole-number headroom keeps the Y-axis labels as tidy
    // integers (order counts are never fractional).
    final maxY = highestCount <= 0 ? 4.0 : (highestCount * 1.3).ceilToDouble();
    final yInterval = (maxY / 4).clamp(1.0, double.infinity);

    // Thin out X-axis labels so they never overlap on a long range
    // (e.g. "This Month" ≈ 30 days) — always label the first and
    // last day, plus evenly spaced days in between.
    final labelEvery = (points.length / 5).ceil().clamp(1, points.length);

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].count.toDouble()),
    ];

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: maxY,
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
              reservedSize: 32,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                // Order counts are always whole numbers — skip a
                // non-integer gridline label rather than show "2.5
                // orders".
                if (value != value.roundToDouble()) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    value.round().toString(),
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= points.length) return const SizedBox.shrink();
                final isEdge = index == 0 || index == points.length - 1;
                if (!isEdge && index % labelEvery != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    ReportService.formatShortDate(points[index].date),
                    style: const TextStyle(fontSize: 10, color: Colors.black54),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black.withValues(alpha: 0.78),
            tooltipBorderRadius: BorderRadius.circular(10),
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final index = spot.x.round().clamp(0, points.length - 1);
                final point = points[index];
                final label = point.count == 1 ? '1 order' : '${point.count} orders';
                return LineTooltipItem(
                  '${ReportService.formatShortDate(point.date)}\n$label',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                );
              }).toList();
            },
          ),
          handleBuiltInTouches: true,
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: _lineColor,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: points.length <= 31,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3,
                color: _lineColor,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _fillColor.withValues(alpha: 0.22),
                  _fillColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }
}

/// Shown instead of the chart only when
/// [OrderVolumeLineChart.points] itself is empty (no resolvable
/// range) — never for a valid range with zero orders, which still
/// renders as a normal flat line.
class _ChartEmptyState extends StatelessWidget {
  const _ChartEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.show_chart_rounded, size: 40, color: Colors.black.withValues(alpha: 0.25)),
          const SizedBox(height: 8),
          Text(
            'No data to chart for this range.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}