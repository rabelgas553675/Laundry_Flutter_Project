import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing_service.dart';
import '../../../services/report_service.dart';
import '../widgets/report_actions_row.dart';
import '../widgets/report_date_filter_bar.dart';

/// Fixed content height of the glass app bar (excludes the status-bar
/// inset, which SafeArea adds on top of this) — matches the same
/// constant used across the rest of the Admin section (dashboard,
/// notifications) so every glass app bar in the app sits at the same
/// height.
const double _kAppBarContentHeight = 64;

/// PART 19A — Sales Report: Total Revenue / Completed Orders /
/// Average Order Value for a chosen date range (Today / This Week /
/// This Month / Custom Range).
///
/// All the actual arithmetic lives in [ReportService.buildSalesReport]
/// — this screen only owns which [ReportRangePreset] (and, for
/// Custom Range, which two dates) is currently selected, and renders
/// whatever [ReportService] hands back. Same real-time order stream
/// as [ReportsScreen]/[AdminDashboard], so the figures update live as
/// orders are placed or an Admin changes a status elsewhere.
///
/// PART 19B adds [ReportActionsRow] — "Export PDF" / "Print" — which
/// hands the currently-displayed [SalesReportData] (and its matching
/// completed-order list) to [PdfService], then [PrintingService].
///
/// REDESIGN — now dressed in the same frosted-glass Admin theme as
/// [AdminDashboard]/[AdminNotificationsScreen]: a blurred, rounded app
/// bar over the blue-blob backdrop, and every card (filter bar,
/// actions row, summary) rendered as a [GlassContainer] instead of a
/// flat [AppCard], so this screen reads as part of the same section.
class SalesReportScreen extends StatefulWidget {
  const SalesReportScreen({super.key, this.repository});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [OrderRepository].
  final OrderRepository? repository;

  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  late final OrderRepository _repository = widget.repository ?? OrderRepository();

  ReportRangePreset _preset = ReportRangePreset.thisWeek;
  DateTime? _customStart;
  DateTime? _customEnd;

  int _retryToken = 0;

  /// True while PART 19B's PDF export/print is in flight — see
  /// [ReportActionsRow.isBusy].
  bool _isProcessingPdf = false;

  /// PART 19B — Sales Report PDF, built via [PdfService] from
  /// exactly the same [report]/[completedOrders] already on screen,
  /// then handed to [PrintingService] to export or print.
  Future<void> _handlePdfAction({
    required SalesReportData report,
    required List<OrderModel> completedOrders,
    required bool openPrintDialog,
  }) async {
    if (_isProcessingPdf) return;
    setState(() => _isProcessingPdf = true);
    try {
      final generatedAt = DateTime.now();
      final bytes = await PdfService.buildSalesReportPdf(
        report: report,
        completedOrders: completedOrders,
        generatedAt: generatedAt,
      );
      if (openPrintDialog) {
        await PrintingService.printPdf(bytes: bytes, documentName: 'Sales Report');
      } else {
        await PrintingService.exportPdf(
          bytes: bytes,
          fileName: PdfService.salesReportFileName(generatedAt),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to generate the PDF. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _isProcessingPdf = false);
    }
  }

  Future<void> _pickCustomDate({required bool isStart}) async {
    final now = DateTime.now();
    final initial = isStart ? (_customStart ?? now) : (_customEnd ?? _customStart ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _customStart = picked;
      } else {
        _customEnd = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _ReportAppBar(title: 'Sales Report', onBack: () => Navigator.maybePop(context)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ReportBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, appBarTotalHeight + 14, 16, 0),
                  child: StreamBuilder<List<OrderModel>>(
                    key: ValueKey('sales-report-orders-$_retryToken'),
                    stream: _repository.streamAllOrders(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const _GlassStatePanel(
                          child: LoadingWidget(message: 'Loading sales data...'),
                        );
                      }
                      if (snapshot.hasError) {
                        return _GlassStatePanel(
                          child: ErrorState(
                            message: 'Unable to load sales data. Please try again.',
                            onRetry: () => setState(() => _retryToken++),
                          ),
                        );
                      }

                      final orders = snapshot.data ?? const <OrderModel>[];
                      final filterBar = GlassContainer(
                        borderRadius: 20,
                        padding: const EdgeInsets.all(12),
                        child: ReportDateFilterBar(
                          selected: _preset,
                          onPresetSelected: (preset) => setState(() => _preset = preset),
                          customStart: _customStart,
                          customEnd: _customEnd,
                          onPickStart: () => _pickCustomDate(isStart: true),
                          onPickEnd: () => _pickCustomDate(isStart: false),
                        ),
                      );

                      // Custom Range needs both dates before there's
                      // anything to compute — show the filter alone
                      // with a prompt rather than a report for an
                      // undefined range.
                      if (_preset == ReportRangePreset.custom &&
                          (_customStart == null || _customEnd == null)) {
                        return ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            filterBar,
                            const SizedBox(height: 24),
                            const _GlassStatePanel(
                              child: EmptyState(
                                title: 'Select a date range',
                                message:
                                    'Choose a start and end date to generate the sales report.',
                                icon: Icons.date_range_outlined,
                              ),
                            ),
                          ],
                        );
                      }

                      if (_preset == ReportRangePreset.custom &&
                          _customEnd!.isBefore(_customStart!)) {
                        return ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            filterBar,
                            const SizedBox(height: 24),
                            const _GlassStatePanel(
                              child: EmptyState(
                                title: 'Invalid date range',
                                message: 'The end date cannot be before the start date.',
                                icon: Icons.error_outline,
                              ),
                            ),
                          ],
                        );
                      }

                      final range = ReportService.resolveRange(
                        _preset,
                        customStart: _customStart,
                        customEnd: _customEnd,
                      );
                      final report = ReportService.buildSalesReport(orders, range: range);
                      final completedOrders =
                          ReportService.completedOrdersInRange(orders, range);

                      return ListView(
                        padding: const EdgeInsets.only(bottom: 16),
                        children: [
                          filterBar,
                          const SizedBox(height: 16),
                          Text(
                            ReportService.formatRange(range),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 12),
                          GlassContainer(
                            borderRadius: 20,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: ReportActionsRow(
                              isBusy: _isProcessingPdf,
                              onExport: () => _handlePdfAction(
                                report: report,
                                completedOrders: completedOrders,
                                openPrintDialog: false,
                              ),
                              onPrint: () => _handlePdfAction(
                                report: report,
                                completedOrders: completedOrders,
                                openPrintDialog: true,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _SalesSummaryCard(report: report),
                          const SizedBox(height: 8),
                          Text(
                            '${report.totalOrdersInRange} order(s) placed in this range '
                            '(${report.completedOrders} completed).',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.black54,
                                ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesSummaryCard extends StatelessWidget {
  const _SalesSummaryCard({required this.report});

  final SalesReportData report;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SalesRow(
            label: 'Total Revenue',
            value: PriceCalculator.formatCurrency(report.totalRevenue),
            icon: Icons.payments_outlined,
            iconColor: const Color(0xff34C759),
            emphasize: true,
          ),
          Divider(height: 28, color: Colors.black.withValues(alpha: 0.08)),
          _SalesRow(
            label: 'Completed Orders',
            value: '${report.completedOrders}',
            icon: Icons.task_alt_outlined,
            iconColor: const Color(0xff2196F3),
          ),
          const SizedBox(height: 16),
          _SalesRow(
            label: 'Average Order Value',
            value: PriceCalculator.formatCurrency(report.averageOrderValue),
            icon: Icons.trending_up_outlined,
            iconColor: const Color(0xff8B5CF6),
          ),
        ],
      ),
    );
  }
}

class _SalesRow extends StatelessWidget {
  const _SalesRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(color: Colors.black87),
          ),
        ),
        Text(
          value,
          style: (emphasize ? textTheme.headlineSmall : textTheme.titleMedium)?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------
/// Shared glass shell pieces (background blobs, app bar, state
/// panel) — same look as [AdminDashboard]/[AdminNotificationsScreen],
/// duplicated here (private to this file) so this screen doesn't
/// depend on the admin dashboard file directly.
/// -----------------------------------------------------------------

class _ReportBackground extends StatelessWidget {
  const _ReportBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0D47A1), Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff0D47A1).withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff8EC5FC).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Minimal glass app bar: back button + title, same blur/border
/// treatment as the Admin section's other app bars.
class _ReportAppBar extends StatelessWidget {
  const _ReportAppBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kAppBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small circular glass button — same treatment used across the rest
/// of the Admin section's app bars.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// Wraps a loading/error/empty state widget in a glass panel so it
/// still reads as belonging to this screen's frosted-glass
/// background instead of floating as a bare opaque block.
class _GlassStatePanel extends StatelessWidget {
  const _GlassStatePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        borderRadius: 24,
        child: child,
      ),
    );
  }
}