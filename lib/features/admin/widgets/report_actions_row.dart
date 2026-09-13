import 'package:flutter/material.dart';

/// PART 19B — "Export PDF" / "Print" action pair shown at the top of
/// a generated report, shared by [SalesReportScreen] and
/// [OrderReportScreen] (and reused for [AdminOrderDetailsScreen]'s
/// receipt actions) so all three offer this in exactly the same
/// place with exactly the same styling.
///
/// This widget has no idea what a PDF or a printer is — it only ever
/// calls [onExport]/[onPrint], which each screen wires to
/// `PdfService` + `PrintingService`. Keeping it this dumb is what
/// lets it be reused across very differently-shaped reports without
/// knowing anything about any of them.
class ReportActionsRow extends StatelessWidget {
  const ReportActionsRow({
    super.key,
    required this.onExport,
    required this.onPrint,
    this.isBusy = false,
  });

  final VoidCallback? onExport;
  final VoidCallback? onPrint;

  /// True while a PDF is being generated/handed off — disables both
  /// buttons so a slow render can't be triggered twice in a row.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isBusy ? null : onExport,
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('Export PDF'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isBusy ? null : onPrint,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print'),
          ),
        ),
        if (isBusy) ...[
          const SizedBox(width: 10),
          const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
      ],
    );
  }
}