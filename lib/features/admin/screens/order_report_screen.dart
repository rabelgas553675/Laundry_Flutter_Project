import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/repositories/order_repository.dart';
import '../../../models/order_model.dart';
import '../../../services/pdf_service.dart';
import '../../../services/printing_service.dart';
import '../../../services/report_service.dart';
import '../widgets/report_actions_row.dart';
import '../widgets/report_date_filter_bar.dart';

/// PART 19A — Order Report: Total Orders plus a breakdown by every
/// [OrderStatus] (Pending / Received / Washing / Drying / Ready /
/// Completed / Cancelled), for a chosen date range (Today / This
/// Week / This Month / Custom Range).
///
/// Same shape as [SalesReportScreen]: all counting is done by
/// [ReportService.buildOrderReport], this screen only owns the
/// currently-selected [ReportRangePreset]/custom dates and renders
/// the result. PART 19B adds the same [ReportActionsRow] "Export
/// PDF" / "Print" pair, backed by [PdfService] + [PrintingService].
class OrderReportScreen extends StatefulWidget {
  const OrderReportScreen({super.key, this.repository});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [OrderRepository].
  final OrderRepository? repository;

  @override
  State<OrderReportScreen> createState() => _OrderReportScreenState();
}

class _OrderReportScreenState extends State<OrderReportScreen> {
  late final OrderRepository _repository = widget.repository ?? OrderRepository();

  ReportRangePreset _preset = ReportRangePreset.thisWeek;
  DateTime? _customStart;
  DateTime? _customEnd;

  int _retryToken = 0;

  /// True while PART 19B's PDF export/print is in flight — see
  /// [ReportActionsRow.isBusy].
  bool _isProcessingPdf = false;

  /// PART 19B — Order Report PDF, built via [PdfService] from
  /// exactly the same [report] already on screen, then handed to
  /// [PrintingService] to export or print.
  Future<void> _handlePdfAction({required OrderReportData report, required bool openPrintDialog}) async {
    if (_isProcessingPdf) return;
    setState(() => _isProcessingPdf = true);
    try {
      final generatedAt = DateTime.now();
      final bytes = await PdfService.buildOrderReportPdf(report: report, generatedAt: generatedAt);
      if (openPrintDialog) {
        await PrintingService.printPdf(bytes: bytes, documentName: 'Order Report');
      } else {
        await PrintingService.exportPdf(
          bytes: bytes,
          fileName: PdfService.orderReportFileName(generatedAt),
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
      appBar: AppBar(title: const Text('Order Report')),
      body: SafeArea(
        child: StreamBuilder<List<OrderModel>>(
          key: ValueKey('order-report-orders-$_retryToken'),
          stream: _repository.streamAllOrders(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading order data...');
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: 'Unable to load order data. Please try again.',
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

            if (_preset == ReportRangePreset.custom &&
                (_customStart == null || _customEnd == null)) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  filterBar,
                  const SizedBox(height: 24),
                  const EmptyState(
                    title: 'Select a date range',
                    message: 'Choose a start and end date to generate the order report.',
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
            final report = ReportService.buildOrderReport(orders, range: range);

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
                  onExport: () => _handlePdfAction(report: report, openPrintDialog: false),
                  onPrint: () => _handlePdfAction(report: report, openPrintDialog: true),
                ),
                const SizedBox(height: 12),
                _TotalOrdersCard(total: report.totalOrders),
                const SizedBox(height: 16),
                Text('By Status', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (report.totalOrders == 0)
                  const EmptyState(
                    title: 'No orders in this range',
                    icon: Icons.inbox_outlined,
                  )
                else
                  AppCard(
                    child: Column(
                      children: [
                        for (final status in OrderStatus.values) ...[
                          _StatusCountRow(status: status, count: report.countFor(status)),
                          if (status != OrderStatus.values.last) const Divider(height: 20),
                        ],
                      ],
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

class _TotalOrdersCard extends StatelessWidget {
  const _TotalOrdersCard({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: [
          Icon(Icons.receipt_long_outlined, color: colors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Total Orders', style: textTheme.bodyMedium),
          ),
          Text(
            '$total',
            style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _StatusCountRow extends StatelessWidget {
  const _StatusCountRow({required this.status, required this.count});

  final OrderStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        StatusBadge(status: status.value),
        const Spacer(),
        Text(
          '$count',
          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}