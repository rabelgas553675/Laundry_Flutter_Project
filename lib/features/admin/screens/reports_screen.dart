import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../../../services/report_service.dart';
import '../widgets/dashboard_stat_card.dart';
import 'order_report_screen.dart';
import 'sales_report_screen.dart';

/// PART 19A — Admin Reports dashboard: the landing screen for the
/// whole reporting system.
///
/// Shows all-time summary cards (Total Revenue, Completed Orders,
/// Average Order Value, Total Orders — computed via [ReportService]
/// with no date filter) and links into the two detailed, filterable
/// reports: [SalesReportScreen] and [OrderReportScreen].
///
/// Like [AdminDashboard] (PART 15), this streams every order in real
/// time via [OrderRepository.streamAllOrders] rather than a one-shot
/// fetch, so the summary cards stay accurate the moment an order's
/// status changes anywhere else in the app — no pull-to-refresh
/// needed.
///
/// Reachable only through the `reports` route, which [RoleGuard]
/// (PART 05) restricts to [UserRole.admin] — this screen does no role
/// checking of its own.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.repository, this.embedded = false});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [OrderRepository].
  final OrderRepository? repository;

  /// When `true`, shown as one tab of [AdminDashboard]'s bottom-nav
  /// `IndexedStack` — no own `Scaffold`/`AppBar` is drawn in that case.
  final bool embedded;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final OrderRepository _repository = widget.repository ?? OrderRepository();

  /// Bumped by [ErrorState]'s "Retry" button to force the
  /// StreamBuilder to resubscribe — same pattern [AdminDashboard]
  /// uses for the same reason (a bad index/permissions error won't
  /// clear itself without a fresh subscription attempt).
  int _retryToken = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded ? null : AppBar(title: const Text('Reports')),
      body: SafeArea(
        top: !widget.embedded,
        child: StreamBuilder<List<OrderModel>>(
          key: ValueKey('report-orders-$_retryToken'),
          stream: _repository.streamAllOrders(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading reports...');
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: 'Unable to load report data. Please try again.',
                onRetry: () => setState(() => _retryToken++),
              );
            }

            final orders = snapshot.data ?? const <OrderModel>[];
            // All-time (range: null) — this dashboard is the overview;
            // the date-filtered breakdowns live on the two detail
            // screens it links to.
            final sales = ReportService.buildSalesReport(orders, range: null);
            final orderReport = ReportService.buildOrderReport(orders, range: null);

            return _ReportsContent(sales: sales, orderReport: orderReport, repository: _repository);
          },
        ),
      ),
    );
  }
}

class _ReportsContent extends StatelessWidget {
  const _ReportsContent({
    required this.sales,
    required this.orderReport,
    required this.repository,
  });

  final SalesReportData sales;
  final OrderReportData orderReport;
  final OrderRepository repository;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width > 900 ? 32.0 : 16.0;
    final crossAxisCount = width > 600 ? 4 : 2;

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      children: [
        Text('All-Time Summary', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Across every order ever placed.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // FIX: aspect-ratio sizing (childAspectRatio) derives cell
          // height from the grid's *width*. At this screen's actual
          // width that math produced cells shorter than the stat
          // card's real content (icon + value + label), so the label
          // text got clipped/overlapped instead of laid out cleanly —
          // the red-striped overflow markers in the screenshot. A
          // fixed `mainAxisExtent` instead gives every cell a
          // constant, content-driven height regardless of screen
          // width, so nothing gets clipped at any breakpoint.
          //
          // 132 still overflowed by 6px — the debug RenderFlex trace
          // showed DashboardStatCard's inner Column getting
          // `h=100.0` (132 minus its own top+bottom padding) while
          // actually needing 106. 144 covers that plus a small
          // buffer against minor text-scale/locale differences.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            mainAxisExtent: 144,
          ),
          children: [
            DashboardStatCard(
              label: 'Total Revenue',
              value: PriceCalculator.formatCurrency(sales.totalRevenue),
              icon: Icons.payments_outlined,
              iconColor: Colors.green,
            ),
            DashboardStatCard(
              label: 'Completed Orders',
              value: '${sales.completedOrders}',
              icon: Icons.task_alt_outlined,
              iconColor: Colors.teal,
            ),
            DashboardStatCard(
              label: 'Average Order Value',
              value: PriceCalculator.formatCurrency(sales.averageOrderValue),
              icon: Icons.trending_up_outlined,
              iconColor: Colors.indigo,
            ),
            DashboardStatCard(
              label: 'Total Orders',
              value: '${orderReport.totalOrders}',
              icon: Icons.receipt_long_outlined,
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text('Detailed Reports', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        _ReportNavCard(
          title: 'Sales Report',
          subtitle: 'Revenue, completed orders, and average order value by date range.',
          icon: Icons.bar_chart_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SalesReportScreen(repository: repository)),
          ),
        ),
        const SizedBox(height: 10),
        _ReportNavCard(
          title: 'Order Report',
          subtitle: 'Order counts by status, filterable by date range.',
          icon: Icons.assignment_outlined,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OrderReportScreen(repository: repository)),
          ),
        ),
      ],
    );
  }
}

/// One tappable row in the "Detailed Reports" section — kept private
/// to this file since it's only ever used here, unlike the reusable
/// widgets in `features/admin/widgets/`.
class _ReportNavCard extends StatelessWidget {
  const _ReportNavCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}