import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/features/user/screens/laundry_order_screen.dart'
    show DeliveryMethod;
import 'package:laundry_flutter/models/order_model.dart';
import 'package:laundry_flutter/services/report_service.dart';

/// PART 19C — Sales Report analytics: SUM(discount)/SUM(pickupFee)/
/// SUM(detergentFee) on [SalesReportData], and the Revenue Trend
/// line graph's per-day series from [ReportService.buildDailyRevenueSeries].
OrderModel _order({
  required OrderStatus status,
  required DateTime createdAt,
  double total = 0,
  double discount = 0,
  double pickupFee = 0,
  double detergentFee = 0,
}) {
  return OrderModel(
    orderNumber: 'ORD-TEST',
    userId: 'user1',
    serviceId: 'service1',
    serviceName: 'Wash & Fold',
    weight: 1,
    detergentId: 'detergent1',
    method: DeliveryMethod.dropoff,
    subtotal: total,
    detergentFee: detergentFee,
    pickupFee: pickupFee,
    discount: discount,
    total: total,
    status: status,
    createdAt: createdAt,
  );
}

void main() {
  group('ReportService.buildSalesReport — fee/discount totals', () {
    test('sums discount/pickupFee/detergentFee across completed orders only', () {
      final range = ReportService.resolveRange(
        ReportRangePreset.today,
        now: DateTime(2026, 9, 23),
      );

      final orders = [
        _order(
          status: OrderStatus.completed,
          createdAt: DateTime(2026, 9, 23, 9),
          total: 500,
          discount: 50,
          pickupFee: 30,
          detergentFee: 20,
        ),
        _order(
          status: OrderStatus.completed,
          createdAt: DateTime(2026, 9, 23, 14),
          total: 300,
          discount: 0,
          pickupFee: 30,
          detergentFee: 10,
        ),
        // Not completed — must be excluded from every total below.
        _order(
          status: OrderStatus.pending,
          createdAt: DateTime(2026, 9, 23, 15),
          total: 1000,
          discount: 500,
          pickupFee: 500,
          detergentFee: 500,
        ),
      ];

      final report = ReportService.buildSalesReport(orders, range: range);

      expect(report.totalRevenue, 800);
      expect(report.completedOrders, 2);
      expect(report.totalDiscounts, 50);
      expect(report.totalPickupFees, 60);
      expect(report.totalDetergentFees, 30);
    });

    test('every total is zero, never divides by zero, when there are no completed orders', () {
      final range = ReportService.resolveRange(
        ReportRangePreset.today,
        now: DateTime(2026, 9, 23),
      );
      final report = ReportService.buildSalesReport(const [], range: range);

      expect(report.totalRevenue, 0);
      expect(report.completedOrders, 0);
      expect(report.averageOrderValue, 0);
      expect(report.totalDiscounts, 0);
      expect(report.totalPickupFees, 0);
      expect(report.totalDetergentFees, 0);
    });
  });

  group('ReportService.buildDailyRevenueSeries', () {
    test('includes every day in the range, with ₱0 for days with no completed orders', () {
      // "This Week" style 7-day range: Mon Sep 21 – Sun Sep 27, 2026.
      final range = ReportDateRange(
        start: DateTime(2026, 9, 21),
        endExclusive: DateTime(2026, 9, 28),
        preset: ReportRangePreset.thisWeek,
      );

      final orders = [
        _order(status: OrderStatus.completed, createdAt: DateTime(2026, 9, 21, 10), total: 200),
        _order(status: OrderStatus.completed, createdAt: DateTime(2026, 9, 23, 8), total: 300),
        // Same day as the point above — should sum into one bucket.
        _order(status: OrderStatus.completed, createdAt: DateTime(2026, 9, 23, 18), total: 100),
        // Cancelled — must never contribute revenue.
        _order(status: OrderStatus.cancelled, createdAt: DateTime(2026, 9, 25, 9), total: 999),
      ];

      final series = ReportService.buildDailyRevenueSeries(orders, range);

      expect(series.length, 7);
      expect(series.map((p) => p.date), [
        DateTime(2026, 9, 21),
        DateTime(2026, 9, 22),
        DateTime(2026, 9, 23),
        DateTime(2026, 9, 24),
        DateTime(2026, 9, 25),
        DateTime(2026, 9, 26),
        DateTime(2026, 9, 27),
      ]);
      expect(series[0].revenue, 200); // Sep 21
      expect(series[1].revenue, 0); // Sep 22 — no completed orders
      expect(series[2].revenue, 400); // Sep 23 — two orders summed
      expect(series[4].revenue, 0); // Sep 25 — only a cancelled order
    });

    test('a single-day range still returns exactly one point', () {
      final range = ReportService.resolveRange(
        ReportRangePreset.today,
        now: DateTime(2026, 9, 23),
      );
      final series = ReportService.buildDailyRevenueSeries(const [], range);

      expect(series.length, 1);
      expect(series.single.date, DateTime(2026, 9, 23));
      expect(series.single.revenue, 0);
    });
  });

  group('ReportService.buildDailyOrderCountSeries', () {
    test('counts every order regardless of status, filling missing days with 0', () {
      final range = ReportDateRange(
        start: DateTime(2026, 9, 21),
        endExclusive: DateTime(2026, 9, 28),
        preset: ReportRangePreset.thisWeek,
      );

      final orders = [
        _order(status: OrderStatus.completed, createdAt: DateTime(2026, 9, 21, 10)),
        _order(status: OrderStatus.pending, createdAt: DateTime(2026, 9, 23, 8)),
        _order(status: OrderStatus.cancelled, createdAt: DateTime(2026, 9, 23, 18)),
      ];

      final series = ReportService.buildDailyOrderCountSeries(orders, range);

      expect(series.length, 7);
      expect(series[0].count, 1); // Sep 21
      expect(series[1].count, 0); // Sep 22
      expect(series[2].count, 2); // Sep 23 — pending + cancelled both count
      expect(series[3].count, 0); // Sep 24
    });

    test('a single-day range still returns exactly one point', () {
      final range = ReportService.resolveRange(
        ReportRangePreset.today,
        now: DateTime(2026, 9, 23),
      );
      final series = ReportService.buildDailyOrderCountSeries(const [], range);

      expect(series.length, 1);
      expect(series.single.date, DateTime(2026, 9, 23));
      expect(series.single.count, 0);
    });
  });

  group('ReportService.formatShortDate', () {
    test('renders month + day without a year', () {
      expect(ReportService.formatShortDate(DateTime(2026, 9, 23)), 'Sep 23');
    });
  });
}