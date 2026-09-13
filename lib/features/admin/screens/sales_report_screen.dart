import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing_service.dart';
import '../../../services/report_service.dart';
import '../widgets/report_actions_row.dart';
import '../widgets/report_date_filter_bar.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Sales Report')),
      body: SafeArea(
        child: StreamBuilder<List<OrderModel>>(
          key: ValueKey('sales-report-orders-$_retryToken'),
          stream: _repository.streamAllOrders(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading sales data...');
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: 'Unable to load sales data. Please try again.',
                onRetry: () => setState(() => _retryToken++),
              );
            }

            final orders = snapshot.data ?? const <OrderModel>[];
            final filterBar = ReportDateFilterBar(
              selected: _preset,
              onPresetSelected: (preset) => setState(() => _preset = preset),
              customStart: _customStart,
              customEnd: _customEnd,
              onPickStart: () => _pickCustomDate(isStart: true),
              onPickEnd: () => _pickCustomDate(isStart: false),
            );

            // Custom Range needs both dates before there's anything
            // to compute — show the filter alone with a prompt rather
            // than a report for an undefined range.
            if (_preset == ReportRangePreset.custom &&
                (_customStart == null || _customEnd == null)) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  filterBar,
                  const SizedBox(height: 24),
                  const EmptyState(
                    title: 'Select a date range',
                    message: 'Choose a start and end date to generate the sales report.',
                    icon: Icons.date_range_outlined,
                  ),
                ],
              );
            }

            if (_preset == ReportRangePreset.custom && _customEnd!.isBefore(_customStart!)) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  filterBar,
                  const SizedBox(height: 24),
                  const EmptyState(
                    title: 'Invalid date range',
                    message: 'The end date cannot be before the start date.',
                    icon: Icons.error_outline,
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
            final completedOrders = ReportService.completedOrdersInRange(orders, range);

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                filterBar,
                const SizedBox(height: 16),
                Text(
                  ReportService.formatRange(range),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                ReportActionsRow(
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
                const SizedBox(height: 12),
                _SalesSummaryCard(report: report),
                const SizedBox(height: 8),
                Text(
                  '${report.totalOrdersInRange} order(s) placed in this range '
                  '(${report.completedOrders} completed).',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SalesSummaryCard extends StatelessWidget {
  const _SalesSummaryCard({required this.report});

  final SalesReportData report;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SalesRow(
            label: 'Total Revenue',
            value: PriceCalculator.formatCurrency(report.totalRevenue),
            icon: Icons.payments_outlined,
            emphasize: true,
          ),
          const Divider(height: 28),
          _SalesRow(
            label: 'Completed Orders',
            value: '${report.completedOrders}',
            icon: Icons.task_alt_outlined,
          ),
          const SizedBox(height: 16),
          _SalesRow(
            label: 'Average Order Value',
            value: PriceCalculator.formatCurrency(report.averageOrderValue),
            icon: Icons.trending_up_outlined,
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
    this.emphasize = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, color: colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: textTheme.bodyMedium),
        ),
        Text(
          value,
          style: (emphasize ? textTheme.headlineSmall : textTheme.titleMedium)
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}