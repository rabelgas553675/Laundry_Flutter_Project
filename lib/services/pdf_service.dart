/// PART 19B — turns [ReportService]'s already-computed report data
/// (and a single [OrderModel]) into PDF bytes, using `package:pdf`.
///
/// This is the *only* file in the project that imports
/// `package:pdf` — same reasoning [ReportService] is the only place
/// that computes report totals: every report/receipt screen calls in
/// here, and here alone decides how a total becomes a page of PDF.
/// [PrintingService] is the next (and last) link in the chain — it
/// only ever receives the finished [Uint8List] this file produces, it
/// never builds a document of its own.
///
///   Report Screen → ReportService → PdfService → PrintingService
///
/// Every method here is a pure function of its input data — no
/// Firestore, no `BuildContext`, no widget tree — so a screen never
/// needs to know *how* a PDF is laid out, only that calling one of
/// these methods gets it a finished document.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app/constants.dart';
import '../core/utils/price_calculator.dart';
import '../core/utils/service_unit.dart';
import '../features/user/widgets/order_list_tile.dart' show OrderStatusStyle;
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../models/user_model.dart';
import 'report_service.dart';

class PdfService {
  PdfService._();

  // ---------------------------------------------------------------
  // Shared formatting helpers
  // ---------------------------------------------------------------

  static String _currency(double amount) {
    return PriceCalculator.formatCurrency(amount).replaceFirst('₱', 'PHP ');
  }

  static String _twoDigits(int n) => n.toString().padLeft(2, '0');

  static String _formatDateTime(DateTime dateTime) {
    final hour12 = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final period = dateTime.hour >= 12 ? 'PM' : 'AM';
    final minute = _twoDigits(dateTime.minute);
    return '${ReportService.formatDate(dateTime)}, $hour12:$minute $period';
  }

  static String _fileTimestamp(DateTime dateTime) {
    return '${dateTime.year}${_twoDigits(dateTime.month)}${_twoDigits(dateTime.day)}'
        '_${_twoDigits(dateTime.hour)}${_twoDigits(dateTime.minute)}';
  }

  static String salesReportFileName(DateTime generatedAt) =>
      'sales_report_${_fileTimestamp(generatedAt)}.pdf';

  static String orderReportFileName(DateTime generatedAt) =>
      'order_report_${_fileTimestamp(generatedAt)}.pdf';

  static String receiptFileName(String orderNumber) {
    final safeNumber = orderNumber.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'receipt_$safeNumber.pdf';
  }

  // ---------------------------------------------------------------
  // Shared page chrome
  // ---------------------------------------------------------------

  /// Placeholder for "no value" cells/labels in a generated PDF.
  ///
  /// Deliberately a plain ASCII hyphen, not an em dash ('—' / U+2014):
  /// the `pdf` package's default Helvetica base font has no Unicode
  /// glyph table, so an em dash prints as a visible "missing glyph"
  /// box on every receipt/report that hits one of these placeholders
  /// — most commonly the Dry Cleaning receipt's "Weight" row, since
  /// an itemized order always has `weightKg == 0`. The in-app Flutter
  /// widgets that show the same em dash (order details/summary
  /// screens, admin cards) are unaffected and unchanged — Flutter's
  /// own text rendering uses a full Unicode-capable system font, only
  /// the separately-rendered PDF output does not.
  static const _placeholder = '-';

  static const _padding = pw.EdgeInsets.symmetric(horizontal: 32, vertical: 32);

  static pw.Widget _brandHeader({
    required String reportTitle,
    String? rangeLabel,
    required DateTime generatedAt,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          AppConstants.appName,
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          reportTitle,
          style: pw.TextStyle(fontSize: 15, color: PdfColors.blueGrey700),
        ),
        pw.SizedBox(height: 10),
        if (rangeLabel != null) pw.Text('Date range: $rangeLabel', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('Generated on: ${_formatDateTime(generatedAt)}', style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 12),
        pw.Divider(thickness: 1, color: PdfColors.grey400),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
    );
  }

  /// Part 3 (per-piece pricing) — the receipt's "Order Contents" row
  /// needs a per-unit rate (`'₱150/pc'` / `'₱80/kg'`) to match the
  /// spec's example (`"Dry Cleaning  3 pcs  ₱150/pc  ₱450"`), but
  /// [OrderReceiptData]/[OrderModel] deliberately never persist the
  /// service's price-per-unit directly (only the already-computed
  /// [OrderReceiptData.subtotal]). Since `subtotal` is always exactly
  /// `pricePerUnit * quantity` with no fees mixed in (see
  /// `PriceCalculator.calculate`), dividing back out is safe and
  /// avoids adding a redundant field that could drift from `subtotal`
  /// if it were ever stored separately.
  static String _rateLabel(OrderReceiptData receipt) {
    // PART 3/5 fix — the `pdf` package's default Helvetica base font
    // has no glyph for U+2014 (em dash), which prints as a visible
    // "missing glyph" box on every itemized (Dry Cleaning) receipt,
    // since those always have `weightKg == 0` and hit this branch.
    // A plain ASCII hyphen renders correctly under every base14 font
    // without pulling in a bundled Unicode font just for one
    // character. Every other placeholder in this file was changed
    // the same way, for the same reason — see `_placeholder` below.
    if (receipt.weightKg <= 0) return _placeholder;
    final rate = receipt.subtotal / receipt.weightKg;
    return ServiceUnitFormat.formatPricePerUnit(receipt.serviceUnit, _currency(rate));
  }

  /// PART 5 fix — the receipt's "Quantity"/"Weight" cell, unit-aware
  /// the same way [_rateLabel] is. An itemized (Dry Cleaning) receipt
  /// always has `weightKg == 0` (it isn't priced by weight at all —
  /// see [OrderReceiptData.isItemized]'s doc comment), so running it
  /// through `formatQuantity` would print every Dry Cleaning receipt
  /// as `"0 pcs"`. Show the garment-type count instead, matching the
  /// exact same fix already applied to `order_list_tile.dart`,
  /// `admin_order_card.dart`, and `active_order_card.dart`.
  static String _quantityLabel(OrderReceiptData receipt) {
    if (receipt.isItemized) return '${receipt.items.length} item type(s)';
    return ServiceUnitFormat.formatQuantity(receipt.serviceUnit, receipt.weightKg);
  }

  /// PART 5 fix — the receipt's "Items" cell. [OrderReceiptData
  /// .itemNames] alone (`'Suit, Dress, Formal Pants'`) drops the
  /// per-garment quantity, so a Dry Cleaning receipt could never
  /// actually show `"2 × Suit"` the way the on-screen Order Summary/
  /// Order Details breakdown does (`OrderItemsBreakdown`). Builds the
  /// same `"{quantity} × {name}"` format from the full [OrderItemModel]
  /// list instead. A Wash & Ironing receipt's unpriced category tags
  /// (`quantity == 1` for every tag) keep reading as plain names —
  /// `"1 × T-Shirt"` would be redundant noise a customer never asked
  /// for, so only an itemized line shows its quantity prefix.
  static String _itemsLabel(OrderReceiptData receipt) {
    if (receipt.items.isEmpty) return _placeholder;
    return receipt.items
        .map((item) => receipt.isItemized ? '${item.quantity} × ${item.itemName}' : item.itemName)
        .join(', ');
  }

  static pw.Widget _summaryRow(String label, String value, {bool emphasize = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: emphasize ? 13 : 11,
              fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // Sales Report PDF
  // ---------------------------------------------------------------

  static Future<Uint8List> buildSalesReportPdf({
    required SalesReportData report,
    required List<OrderModel> completedOrders,
    DateTime? generatedAt,
  }) async {
    final doc = pw.Document();
    final now = generatedAt ?? DateTime.now();
    final rangeLabel = report.range != null ? ReportService.formatRange(report.range!) : 'All time';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _padding,
        build: (context) => [
          _brandHeader(reportTitle: 'Sales Report', rangeLabel: rangeLabel, generatedAt: now),
          _sectionTitle('Summary'),
          _summaryRow('Total Revenue', _currency(report.totalRevenue), emphasize: true),
          _summaryRow('Completed Orders', '${report.completedOrders}'),
          _summaryRow('Average Order Value', _currency(report.averageOrderValue)),
          _summaryRow('Total Orders in Range', '${report.totalOrdersInRange}'),
          pw.SizedBox(height: 18),
          _sectionTitle('Completed Orders (${completedOrders.length})'),
          if (completedOrders.isEmpty)
            pw.Text(
              'No completed orders in this range.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            )
          else
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: const {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerRight,
              },
              headers: const ['Order #', 'Date', 'Service', 'Total'],
              data: [
                for (final order in completedOrders)
                  [
                    order.orderNumber,
                    order.createdAt != null ? ReportService.formatDate(order.createdAt!) : _placeholder,
                    order.serviceName,
                    _currency(order.total),
                  ],
              ],
            ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          _summaryRow('TOTAL REVENUE', _currency(report.totalRevenue), emphasize: true),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------
  // Order Report PDF
  // ---------------------------------------------------------------

  static Future<Uint8List> buildOrderReportPdf({
    required OrderReportData report,
    DateTime? generatedAt,
  }) async {
    final doc = pw.Document();
    final now = generatedAt ?? DateTime.now();
    final rangeLabel = report.range != null ? ReportService.formatRange(report.range!) : 'All time';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _padding,
        build: (context) => [
          _brandHeader(reportTitle: 'Order Report', rangeLabel: rangeLabel, generatedAt: now),
          _sectionTitle('Summary'),
          _summaryRow('Total Orders', '${report.totalOrders}', emphasize: true),
          pw.SizedBox(height: 18),
          _sectionTitle('Orders by Status'),
          pw.TableHelper.fromTextArray(
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: const {0: pw.Alignment.centerLeft, 1: pw.Alignment.centerRight},
            headers: const ['Status', 'Count'],
            data: [
              for (final status in OrderStatus.values)
                [OrderStatusStyle.of(status).label, '${report.countFor(status)}'],
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Divider(thickness: 1, color: PdfColors.grey400),
          _summaryRow('TOTAL ORDERS', '${report.totalOrders}', emphasize: true),
        ],
      ),
    );

    return doc.save();
  }

  // ---------------------------------------------------------------
  // Order Receipt PDF
  // ---------------------------------------------------------------

  static Future<Uint8List> buildOrderReceiptPdf(OrderReceiptData receipt) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: _padding,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      AppConstants.appName,
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(AppConstants.shopAddress, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('RECEIPT', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                    pw.Text(receipt.orderNumber, style: const pw.TextStyle(fontSize: 11)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(child: _receiptCustomerBlock(receipt)),
                pw.Expanded(child: _receiptOrderMetaBlock(receipt)),
              ],
            ),
            pw.SizedBox(height: 16),
            _sectionTitle('Order Contents'),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignments: const {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
              },
              // Part 3 — the quantity column's header and value both
              // come from `receipt.serviceUnit` (the unit this order
              // was actually placed under — see
              // `OrderReceiptData.fromOrder`), never a hard-coded
              // "Weight"/"kg". A piece-based receipt reads
              // "Quantity" / "3 pcs" / "₱150/pc"; a kg-based one
              // keeps reading "Weight" / "3 kg" / "₱80/kg". Never
              // "3.0 kg" for a piece order.
              headers: [
                'Service',
                receipt.serviceUnit.quantityFieldLabel,
                'Rate',
                'Detergent',
                'Items',
              ],
              data: [
                [
                  receipt.serviceName,
                  _quantityLabel(receipt),
                  _rateLabel(receipt),
                  receipt.detergentName.isNotEmpty ? receipt.detergentName : _placeholder,
                  _itemsLabel(receipt),
                ],
              ],
            ),
            pw.SizedBox(height: 20),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 240,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _summaryRow('Subtotal', _currency(receipt.subtotal)),
                    _summaryRow('Detergent Fee', _currency(receipt.detergentFee)),
                    if (receipt.isPickup) _summaryRow('Pickup Fee', _currency(receipt.pickupFee)),
                    if (receipt.discount > 0) _summaryRow('Discount', '-${_currency(receipt.discount)}'),
                    pw.Divider(thickness: 1, color: PdfColors.grey400),
                    _summaryRow('TOTAL', _currency(receipt.total), emphasize: true),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Divider(thickness: 1, color: PdfColors.grey400),
            pw.SizedBox(height: 8),
            _summaryRow('Payment Status', receipt.paymentStatus),
            _summaryRow('Order Status', receipt.orderStatusLabel),
            pw.SizedBox(height: 24),
            pw.Center(
              child: pw.Text(
                'Thank you for choosing ${AppConstants.appName}!',
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _receiptCustomerBlock(OrderReceiptData receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Customer', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(receipt.customerName, style: const pw.TextStyle(fontSize: 10)),
        if (receipt.customerPhone.isNotEmpty)
          pw.Text(receipt.customerPhone, style: const pw.TextStyle(fontSize: 10)),
        if (receipt.customerEmail.isNotEmpty)
          pw.Text(receipt.customerEmail, style: const pw.TextStyle(fontSize: 10)),
        if (receipt.isPickup && (receipt.deliveryAddress?.isNotEmpty ?? false))
          pw.Text('Pickup at: ${receipt.deliveryAddress}', style: const pw.TextStyle(fontSize: 10)),
      ],
    );
  }

  static pw.Widget _receiptOrderMetaBlock(OrderReceiptData receipt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Order Info', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(
          'Order Date: ${receipt.orderDate != null ? _formatDateTime(receipt.orderDate!) : _placeholder}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.Text(
          'Delivery Method: ${receipt.isPickup ? 'Pickup' : 'Drop-off'}',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    );
  }
}

/// Everything [PdfService.buildOrderReceiptPdf] needs to render one
/// order's receipt — a denormalized, PDF-ready snapshot built from a
/// persisted [OrderModel] (+ its [UserModel] customer, when already
/// loaded), so [PdfService] itself never has to know about
/// Firestore, streams, or repositories.
class OrderReceiptData {
  final String orderId;
  final String orderNumber;
  final DateTime? orderDate;

  final String customerName;
  final String customerPhone;
  final String customerEmail;

  final String serviceName;
  final double weightKg;

  /// Part 3 — the unit [weightKg] was actually priced under when
  /// this order was placed (`OrderModel.serviceUnit`), never the
  /// service's *current* configuration. This is what lets a
  /// historical Dry Cleaning receipt keep reading `"3 pcs"` even if
  /// an admin later reconfigures that service to be kg-based (or
  /// vice versa).
  final ServiceUnit serviceUnit;

  /// PART 3/5 fix — bare display names only (`'Suit'`, `'Dress'`),
  /// kept for source-compat with anything still reading this field,
  /// but no longer used to render the receipt's "Items" cell (see
  /// [items]/[_itemsLabel] below) since it has no quantity — a Dry
  /// Cleaning receipt built from just [itemNames] can't show
  /// `"2 × Suit"`, only `"Suit"`.
  final List<String> itemNames;

  /// PART 5 fix — the full priced line list (`OrderModel.items`),
  /// carrying each garment's `quantity`/`unitPrice` for an itemized
  /// (Dry Cleaning) order, or the plain unpriced category tags for a
  /// weight-based (Wash & Ironing) one. Lets the receipt render
  /// `"2 × Suit"` instead of just `"Suit"`, and lets [isItemized]
  /// mirror `OrderModel.isItemized` exactly instead of guessing from
  /// [weightKg].
  final List<OrderItemModel> items;

  final String detergentName;

  final double subtotal;
  final double detergentFee;
  final double pickupFee;
  final double discount;
  final double total;

  final String paymentStatus;
  final String orderStatusLabel;

  final bool isPickup;
  final String? deliveryAddress;

  /// PART 5 fix — mirrors `OrderModel.isItemized` exactly (a Dry
  /// Cleaning order's [items] carry a real `unitPrice`; a Wash &
  /// Ironing order's category tags are always `unitPrice == 0`), so
  /// the receipt branches on the same rule every other screen does
  /// rather than re-deriving it from [weightKg].
  bool get isItemized => items.any((item) => item.unitPrice > 0);

  const OrderReceiptData({
    required this.orderId,
    required this.orderNumber,
    required this.orderDate,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.serviceName,
    required this.weightKg,
    required this.serviceUnit,
    required this.itemNames,
    required this.items,
    required this.detergentName,
    required this.subtotal,
    required this.detergentFee,
    required this.pickupFee,
    required this.discount,
    required this.total,
    required this.paymentStatus,
    required this.orderStatusLabel,
    required this.isPickup,
    this.deliveryAddress,
  });

  factory OrderReceiptData.fromOrder(OrderModel order, {UserModel? customer}) {
    final String paymentStatus;
    switch (order.status) {
      case OrderStatus.completed:
        paymentStatus = 'Paid';
        break;
      case OrderStatus.cancelled:
        paymentStatus = 'N/A (Order Cancelled)';
        break;
      default:
        paymentStatus = 'Pending (Due on Completion)';
    }

    final phone = order.isPickup && (order.pickupPhone?.isNotEmpty ?? false)
        ? order.pickupPhone!
        : (customer?.phone ?? '');

    return OrderReceiptData(
      orderId: order.id ?? '',
      orderNumber: order.orderNumber,
      orderDate: order.createdAt,
      customerName: customer?.name.isNotEmpty == true ? customer!.name : 'Unknown customer',
      customerPhone: phone,
      customerEmail: customer?.email ?? '',
      serviceName: order.serviceName,
      weightKg: order.weight,
      serviceUnit: order.serviceUnit,
      itemNames: order.items.map((item) => item.itemName).toList(),
      items: order.items,
      detergentName: order.detergentName,
      subtotal: order.subtotal,
      detergentFee: order.detergentFee,
      pickupFee: order.pickupFee,
      discount: order.discount,
      total: order.total,
      paymentStatus: paymentStatus,
      orderStatusLabel: OrderStatusStyle.of(order.status).label,
      isPickup: order.isPickup,
      deliveryAddress: order.isPickup ? order.address : null,
    );
  }
}