/// PART 19A — reusable, UI-independent Admin report calculations.
///
/// This file has zero Flutter/widget/Firebase dependencies — it's
/// plain Dart, same reasoning as [PriceCalculator] (PART 11.1) — so
/// [ReportsScreen]/[SalesReportScreen]/[OrderReportScreen] never
/// compute a total, an average, or a status count themselves. They
/// only ever call into this file and render whatever comes back.
/// PART 19B's `PdfService` builds on the same [SalesReportData]/
/// [OrderReportData] this produces, so a PDF/printed report can never
/// show numbers that disagree with what's on screen.
library;

import '../models/order_model.dart';

/// The four date-range choices this part's spec calls for. [custom]
/// needs an explicit start/end supplied to [ReportService.resolveRange]
/// — every other value derives its range purely from "now".
enum ReportRangePreset { today, thisWeek, thisMonth, custom }

extension ReportRangePresetX on ReportRangePreset {
  String get label {
    switch (this) {
      case ReportRangePreset.today:
        return 'Today';
      case ReportRangePreset.thisWeek:
        return 'This Week';
      case ReportRangePreset.thisMonth:
        return 'This Month';
      case ReportRangePreset.custom:
        return 'Custom Range';
    }
  }
}

/// A resolved, concrete `[start, endExclusive)` window plus the
/// [preset] it came from — e.g. "This Week" resolved against today's
/// actual date. [endExclusive] is always the instant *after* the last
/// millisecond the report should include (start of the next day for
/// [ReportRangePreset.today], the Monday after for
/// [ReportRangePreset.thisWeek], etc.), so [contains] never needs a
/// fiddly `<=` on a raw `DateTime` with a non-midnight time-of-day.
class ReportDateRange {
  final DateTime start;
  final DateTime endExclusive;
  final ReportRangePreset preset;

  const ReportDateRange({
    required this.start,
    required this.endExclusive,
    required this.preset,
  });

  /// The actual last calendar day included in this range (inclusive),
  /// purely for display — e.g. "Sep 6, 2026 – Sep 12, 2026".
  DateTime get lastInclusiveDay => endExclusive.subtract(const Duration(days: 1));

  bool contains(DateTime dateTime) =>
      !dateTime.isBefore(start) && dateTime.isBefore(endExclusive);

  @override
  String toString() => 'ReportDateRange(${preset.label}: $start – $endExclusive)';
}

/// PART 19A's Sales Report numbers: "Total Revenue / Completed Orders
/// / Average Order Value", for whatever [range] was requested (or
/// every order ever placed, when [range] is null — the Reports
/// Dashboard's all-time summary cards).
class SalesReportData {
  final double totalRevenue;
  final int completedOrders;
  final double averageOrderValue;

  /// Every order that fell inside [range], regardless of status —
  /// shown as context alongside the completed-only revenue figures
  /// above (e.g. "42 orders in range, 30 completed").
  final int totalOrdersInRange;

  /// Null when this report covers all-time (no date filter applied).
  final ReportDateRange? range;

  const SalesReportData({
    required this.totalRevenue,
    required this.completedOrders,
    required this.averageOrderValue,
    required this.totalOrdersInRange,
    required this.range,
  });
}

/// PART 19A's Order Report numbers: total orders plus a breakdown by
/// every [OrderStatus] (Pending / Received / Washing / Drying /
/// Ready / Completed / Cancelled), for whatever [range] was requested
/// (or all-time, when [range] is null).
class OrderReportData {
  final int totalOrders;
  final Map<OrderStatus, int> statusCounts;
  final ReportDateRange? range;

  const OrderReportData({
    required this.totalOrders,
    required this.statusCounts,
    required this.range,
  });

  int countFor(OrderStatus status) => statusCounts[status] ?? 0;
}

class ReportService {
  ReportService._();

  /// Resolves [preset] into a concrete [ReportDateRange] against
  /// [now] (defaults to the real wall clock — injectable for tests).
  ///
  /// "This Week" runs Monday → Sunday (ISO-8601's definition of a
  /// week, matching `DateTime.weekday`'s own 1=Monday..7=Sunday
  /// numbering), not the calendar week the device's locale might use.
  ///
  /// [customStart]/[customEnd] are required (and validated) only for
  /// [ReportRangePreset.custom]; both are normalized to whole calendar
  /// days, and the resulting range is *inclusive* of [customEnd]'s
  /// entire day. Throws [ArgumentError] if [customEnd] is before
  /// [customStart].
  static ReportDateRange resolveRange(
    ReportRangePreset preset, {
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? now,
  }) {
    final today = _dateOnly(now ?? DateTime.now());

    switch (preset) {
      case ReportRangePreset.today:
        return ReportDateRange(
          start: today,
          endExclusive: today.add(const Duration(days: 1)),
          preset: preset,
        );

      case ReportRangePreset.thisWeek:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return ReportDateRange(
          start: monday,
          endExclusive: monday.add(const Duration(days: 7)),
          preset: preset,
        );

      case ReportRangePreset.thisMonth:
        final firstOfMonth = DateTime(today.year, today.month, 1);
        final firstOfNextMonth = DateTime(today.year, today.month + 1, 1);
        return ReportDateRange(
          start: firstOfMonth,
          endExclusive: firstOfNextMonth,
          preset: preset,
        );

      case ReportRangePreset.custom:
        if (customStart == null || customEnd == null) {
          throw ArgumentError(
            'customStart and customEnd are required for ReportRangePreset.custom.',
          );
        }
        final start = _dateOnly(customStart);
        final end = _dateOnly(customEnd);
        if (end.isBefore(start)) {
          throw ArgumentError('customEnd must not be before customStart.');
        }
        return ReportDateRange(
          start: start,
          endExclusive: end.add(const Duration(days: 1)),
          preset: preset,
        );
    }
  }

  static DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  /// Every order in [orders] that falls inside [range]'s window,
  /// keyed off [OrderModel.createdAt]. Returns [orders] unchanged when
  /// [range] is null (the all-time / unfiltered case). An order with
  /// no [OrderModel.createdAt] yet (the brief window before Firestore's
  /// server timestamp round-trips back down) is excluded from any
  /// date-filtered report, since there's no date to test it against.
  static List<OrderModel> ordersInRange(List<OrderModel> orders, ReportDateRange? range) {
    if (range == null) return orders;
    return orders.where((o) => o.createdAt != null && range.contains(o.createdAt!)).toList();
  }

  /// PART 19A's Sales Report. Revenue only counts
  /// [OrderStatus.completed] orders — matches PART 15's Admin
  /// Dashboard, which counts revenue the same way ("a pending/washing
  /// order's total isn't money the shop has actually earned yet, and
  /// a cancelled order never will be").
  static SalesReportData buildSalesReport(List<OrderModel> orders, {ReportDateRange? range}) {
    final inRange = ordersInRange(orders, range);
    final completed = inRange.where((o) => o.status == OrderStatus.completed).toList();
    final totalRevenue = completed.fold<double>(0, (sum, o) => sum + o.total);
    final completedCount = completed.length;
    final average = completedCount == 0 ? 0.0 : totalRevenue / completedCount;

    return SalesReportData(
      totalRevenue: totalRevenue,
      completedOrders: completedCount,
      averageOrderValue: average,
      totalOrdersInRange: inRange.length,
      range: range,
    );
  }

  /// Every [OrderStatus.completed] order within [range] (or all-time
  /// when [range] is null), newest first. Feeds PART 19B's Sales
  /// Report PDF/print per-order detail table — by deriving it from
  /// the exact same [ordersInRange] window [buildSalesReport] uses,
  /// that table can never list a different set of orders than what
  /// [SalesReportData.totalRevenue]/[SalesReportData.completedOrders]
  /// were actually computed from.
  static List<OrderModel> completedOrdersInRange(List<OrderModel> orders, ReportDateRange? range) {
    final completed = ordersInRange(orders, range)
        .where((o) => o.status == OrderStatus.completed)
        .toList();
    completed.sort((a, b) {
      final aDate = a.createdAt;
      final bDate = b.createdAt;
      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;
      return bDate.compareTo(aDate);
    });
    return completed;
  }

  /// PART 19A's Order Report — total orders plus a count per
  /// [OrderStatus], all within [range] (or all-time when [range] is
  /// null).
  static OrderReportData buildOrderReport(List<OrderModel> orders, {ReportDateRange? range}) {
    final inRange = ordersInRange(orders, range);
    final counts = <OrderStatus, int>{
      for (final status in OrderStatus.values)
        status: inRange.where((o) => o.status == status).length,
    };

    return OrderReportData(
      totalOrders: inRange.length,
      statusCounts: counts,
      range: range,
    );
  }

  /// "Sep 12, 2026" — shared date formatting for every report
  /// screen/widget and PART 19B's PDF export, so the same date never
  /// renders two different ways across the report system.
  static String formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// "Sep 6 – Sep 12, 2026" (same year) or "Dec 29, 2026 – Jan 4, 2027"
  /// (spanning years) — a compact label for [range], used in report
  /// headers and PART 19B's PDF export.
  static String formatRange(ReportDateRange range) {
    final start = range.start;
    final end = range.lastInclusiveDay;
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return formatDate(start);
    }
    if (start.year == end.year) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[start.month - 1]} ${start.day} – ${formatDate(end)}';
    }
    return '${formatDate(start)} – ${formatDate(end)}';
  }
}