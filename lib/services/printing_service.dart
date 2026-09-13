/// PART 19B — the last link in the report/receipt pipeline:
///
///   Report Screen → ReportService → PdfService → PrintingService
///
/// This is the *only* file in the project that imports
/// `package:printing` — same reasoning [PdfService] is the only file
/// that imports `package:pdf`. Every screen that needs to print or
/// export a PDF calls in here with already-built bytes from
/// [PdfService]; nothing else in the app talks to the OS print
/// dialog or share sheet directly.
library;

import 'dart:typed_data';

import 'package:printing/printing.dart';

class PrintingService {
  PrintingService._();

  /// Opens the platform print dialog for an already-generated PDF.
  /// On most platforms that dialog also offers "Save as PDF" /
  /// "Export" as one of its destinations, so this alone covers a
  /// good chunk of "I just want the file" too — [exportPdf] below is
  /// for the direct "skip the dialog, give me the file" case.
  ///
  /// [documentName] is shown as the print job's/preview's title —
  /// not a file path.
  ///
  /// Note: `printing`'s [Printing.layoutPdf] technically re-invokes
  /// [onLayout] with whatever [PdfPageFormat] the chosen destination
  /// prefers, expecting a fresh document back. Every PDF
  /// [PdfService] builds already targets standard A4, so this always
  /// hands back the same pre-built [bytes] regardless of the
  /// requested format rather than re-generating the document.
  static Future<void> printPdf({
    required Uint8List bytes,
    required String documentName,
  }) async {
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: documentName,
    );
  }

  /// Opens the OS share sheet (mobile) or triggers a direct file
  /// save/download (web/desktop) for an already-generated PDF — the
  /// "export a PDF I can keep or send" action, distinct from
  /// [printPdf]'s "send this to a printer right now" action.
  static Future<void> exportPdf({
    required Uint8List bytes,
    required String fileName,
  }) async {
    await Printing.sharePdf(bytes: bytes, filename: fileName);
  }
}