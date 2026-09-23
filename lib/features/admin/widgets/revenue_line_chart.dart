import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../services/report_service.dart';

/// PART 19C — Sales Report's main analytics component: a line graph
/// of daily revenue (SUM of completed orders' `total`, grouped by
/// `createdAt`'s calendar day) across the currently selected date
/// range.
///
/// Purely presentational, same split every report widget in this
/// project follows (see [ReportDateFilterBar]): [SalesReportScreen]
/// is what calls [ReportService.buildDailyRevenueSeries] and hands
/// the resulting [points] here — this widget never touches Firestore
/// or [ReportService] itself, and never decides what counts as
/// "revenue". It only ever renders whatever list it's given.
///
/// [points] should be exactly what [ReportService.buildDailyRevenueSeries]
/// returns: one entry per calendar day in the selected range, in
/// order, with `revenue: 0` for a day with no completed orders — so
/// this widget draws every day in the range (never skipping a date),
/// and a flat ₱0 line for a range with no completed orders at all is
/// a normal, valid chart, not an "empty" state.
///
/// This widget is only ever "empty" (shows a placeholder instead of
/// a chart) when [points] itself has nothing in it — i.e. the caller
/// couldn't resolve a date range at all — which
/// [ReportService.buildDailyRevenueSeries] should never actually
/// produce for a valid range, but is guarded against here anyway so
/// a bad/empty range can never crash the chart.
class RevenueLineChart extends StatelessWidget {
  const RevenueLineChart({super.key, required this.points});

  final List<DailyRevenuePoint> points;

  static const Color _lineColor = Color(0xff2196F3);
  static const Color _fillColor = Color(0xff8B5CF6);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart_rounded, size: 18, color: Color(0xff2196F3)),
            const SizedBox(width: 8),
            Text(
              'Revenue Trend',
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

    final revenues = points.map((p) => p.revenue).toList();
    final highestRevenue = revenues.fold<double>(0, (max, v) => v > max ? v : max);
    // Never divide/space against a zero-height axis — an all-₱0
    // range (no completed orders yet) still needs *some* headroom
    // above the flat line so it renders as a visible line, not a
    // degenerate single pixel.
    final maxY = highestRevenue <= 0 ? 100.0 : highestRevenue * 1.2;

    // Thin out X-axis labels so they never overlap on a long range
    // (e.g. "This Month" ≈ 30 days) — always label the first and
    // last day, plus evenly spaced days in between.
    final labelEvery = (points.length / 5).ceil().clamp(1, points.length);

    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].revenue),
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
          horizontalInterval: maxY / 4,
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
              reservedSize: 52,
              interval: maxY / 4,
              getTitlesWidget: (value, meta) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _compactPeso(value),
                  style: const TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ),
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
                return LineTooltipItem(
                  '${ReportService.formatShortDate(point.date)}\n'
                  '${PriceCalculator.formatCurrency(point.revenue)}',
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

  /// "₱1.2k" / "₱500" — compact peso label for the Y-axis, where
  /// [PriceCalculator.formatCurrency]'s full `₱1,234.00` form would
  /// crowd the reserved axis width.
  static String _compactPeso(double value) {
    if (value.abs() >= 1000) {
      final thousands = value / 1000;
      final label = thousands == thousands.roundToDouble()
          ? thousands.toStringAsFixed(0)
          : thousands.toStringAsFixed(1);
      return '₱${label}k';
    }
    return '₱${value.round()}';
  }
}

/// Shown instead of the chart only when [RevenueLineChart.points]
/// itself is empty (no resolvable range) — never for a valid range
/// with ₱0 revenue, which still renders as a normal flat line.
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