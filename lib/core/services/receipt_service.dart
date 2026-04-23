/// Receipt PDF generator for thermal printers
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/core/services/escpos_builder.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/qz_tray_service.dart';
import 'package:retaillite/models/bill_model.dart';
import 'package:intl/intl.dart';

/// Service for generating and printing receipts
class ReceiptService {
  ReceiptService._();

  static final _dateFormat = DateFormat('dd/MM/yyyy');
  static final _timeFormat = DateFormat('hh:mm a');

  // 58mm paper: POS58 driver reports 48mm printable area to Chrome.
  // Keep PDF EXACTLY 48mm so Chrome prints at 100% with no scaling.
  // Use extra right margin because many POS58 drivers have slight right-shift,
  // which otherwise clips the last characters on the right edge.
  static const PdfPageFormat _roll58 = PdfPageFormat(
    48 * PdfPageFormat.mm,
    double.infinity,
    marginLeft: 2 * PdfPageFormat.mm,
    marginTop: 2 * PdfPageFormat.mm,
    marginRight: 5 * PdfPageFormat.mm,
    marginBottom: 2 * PdfPageFormat.mm,
  );

  // 80mm paper: driver typically reports ~72mm printable area.
  // PDF at 72mm → 100% scale. 4mm margins → 64mm content area.
  static const PdfPageFormat _roll80 = PdfPageFormat(
    72 * PdfPageFormat.mm,
    double.infinity,
    marginLeft: 4 * PdfPageFormat.mm,
    marginTop: 2 * PdfPageFormat.mm,
    marginRight: 4 * PdfPageFormat.mm,
    marginBottom: 2 * PdfPageFormat.mm,
  );

  /// Get PdfPageFormat from paper size index
  static PdfPageFormat _getPageFormat(int paperSizeIndex) {
    switch (paperSizeIndex) {
      case 0:
        return _roll58; // 58mm
      case 1:
      default:
        return _roll80; // 80mm
    }
  }

  /// Generate receipt PDF
  static Future<pw.Document> generateReceipt({
    required BillModel bill,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? shopLogoPath,
    String? upiId,
    double? taxRate,
    int? paperSizeIndex,
    String? copyLabel,
    bool showHsnOnReceipt = false,
    PdfPageFormat? customPageFormat,
  }) async {
    final pdf = pw.Document();
    final effectivePaperSize =
        paperSizeIndex ?? PrinterStorage.getSavedPaperSize();
    final baseFormat = _getPageFormat(effectivePaperSize);

    final PdfPageFormat pageFormat;
    if (customPageFormat != null) {
      pageFormat = customPageFormat;
    } else {
      pageFormat = baseFormat;
    }

    // Load logo image bytes (if available)
    pw.MemoryImage? logoImage;
    if (shopLogoPath != null && shopLogoPath.isNotEmpty) {
      logoImage = await _loadLogoImage(shopLogoPath);
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        orientation: pw.PageOrientation.portrait,
        build: (context) => _buildReceipt(
          bill: bill,
          shopName: shopName ?? AppConstants.defaultShopName,
          shopAddress: shopAddress,
          shopPhone: shopPhone,
          gstNumber: gstNumber,
          receiptFooter: receiptFooter ?? 'Thank you for shopping!',
          logoImage: logoImage,
          upiId: upiId,
          taxRate: taxRate,
          copyLabel: copyLabel,
          showHsnOnReceipt: showHsnOnReceipt,
        ),
      ),
    );

    return pdf;
  }

  /// Print receipt directly
  static Future<bool> printReceipt({
    required BillModel bill,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? shopLogoPath,
    String? upiId,
    double? taxRate,
    int? paperSizeIndex,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) async {
    final effectivePaperSize =
        paperSizeIndex ?? PrinterStorage.getSavedPaperSize();

    if (kIsWeb) {
      // --- Prefer QZ Tray (silent raw ESC/POS print, bypasses Chrome dialog
      // and Windows driver's paper-size/orientation settings). ---
      if (await QzTrayService.isEnabled()) {
        final printerName = await QzTrayService.getSelectedPrinter();
        if (printerName != null && printerName.isNotEmpty) {
          final bytes = EscPosBuilder.buildReceipt(
            bill: bill,
            shopName: shopName ?? AppConstants.defaultShopName,
            shopAddress: shopAddress,
            shopPhone: shopPhone,
            gstNumber: gstNumber,
            receiptFooter: receiptFooter,
            upiId: upiId,
            taxRate: taxRate,
            paperSizeIndex: effectivePaperSize,
            copyLabel: copyLabel,
            showHsnOnReceipt: showHsnOnReceipt,
          );
          final ok = await QzTrayService.printRaw(
            printerName: printerName,
            data: bytes,
          );
          if (ok) return true;
          debugPrint('⚠️ QZ Tray print failed — falling back to PDF dialog');
        }
      }

      // --- Fallback: PDF through Chrome print dialog ---
      // PDF page = exactly 48mm (POS58's printable width) so Chrome prints
      // at 100% with no scale changes.
      // Asymmetric margins (2mm left, 5mm right) keep content away from the
      // right edge where some POS58 drivers physically clip.
      final webFormat = _getPageFormat(effectivePaperSize);

      final pdf = await generateReceipt(
        bill: bill,
        shopName: shopName,
        shopAddress: shopAddress,
        shopPhone: shopPhone,
        gstNumber: gstNumber,
        receiptFooter: receiptFooter,
        shopLogoPath: shopLogoPath,
        upiId: upiId,
        taxRate: taxRate,
        paperSizeIndex: effectivePaperSize,
        copyLabel: copyLabel,
        showHsnOnReceipt: showHsnOnReceipt,
        customPageFormat: webFormat,
      );

      return await Printing.layoutPdf(
        dynamicLayout: false,
        onLayout: (_) => pdf.save(),
        name: 'Bill_${bill.billNumber}',
        format: webFormat,
      );
    }

    // Non-web: use single-page roll format
    final pdf = await generateReceipt(
      bill: bill,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      gstNumber: gstNumber,
      receiptFooter: receiptFooter,
      shopLogoPath: shopLogoPath,
      upiId: upiId,
      taxRate: taxRate,
      paperSizeIndex: effectivePaperSize,
      copyLabel: copyLabel,
      showHsnOnReceipt: showHsnOnReceipt,
    );

    return await Printing.layoutPdf(
      onLayout: (f) => pdf.save(),
      name: 'Bill_${bill.billNumber}',
      format: _getPageFormat(effectivePaperSize),
    );
  }

  /// Print receipt directly to a named printer (no dialog)
  static Future<bool> directPrintReceipt({
    required Printer printer,
    required BillModel bill,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? shopLogoPath,
    String? upiId,
    double? taxRate,
    int? paperSizeIndex,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) async {
    final effectivePaperSize =
        paperSizeIndex ?? PrinterStorage.getSavedPaperSize();
    // Use a concrete page format with finite height for Windows — roll formats
    // use infinite height which Windows print DC cannot handle.
    // The same format is used for both PDF generation and directPrintPdf so the
    // page dimensions match exactly and Windows doesn't rotate to landscape.
    final baseFormat = _getPageFormat(effectivePaperSize);
    final directFormat = PdfPageFormat(
      baseFormat.width,
      300 * PdfPageFormat.mm, // finite height for Windows compatibility
      marginLeft: baseFormat.marginLeft,
      marginTop: baseFormat.marginTop,
      marginRight: baseFormat.marginRight,
      marginBottom: baseFormat.marginBottom,
    );

    final pdf = await generateReceipt(
      bill: bill,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      gstNumber: gstNumber,
      receiptFooter: receiptFooter,
      shopLogoPath: shopLogoPath,
      upiId: upiId,
      taxRate: taxRate,
      paperSizeIndex: effectivePaperSize,
      copyLabel: copyLabel,
      showHsnOnReceipt: showHsnOnReceipt,
      customPageFormat: directFormat,
    );

    return await Printing.directPrintPdf(
      printer: printer,
      onLayout: (format) => pdf.save(),
      name: 'Bill_${bill.billNumber}',
      format: directFormat,
      dynamicLayout: false,
    );
  }

  /// Share receipt as PDF
  static Future<void> shareReceipt({
    required BillModel bill,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? shopLogoPath,
    String? upiId,
    double? taxRate,
    int? paperSizeIndex,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) async {
    final pdf = await generateReceipt(
      bill: bill,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      gstNumber: gstNumber,
      receiptFooter: receiptFooter,
      shopLogoPath: shopLogoPath,
      upiId: upiId,
      taxRate: taxRate,
      paperSizeIndex: paperSizeIndex,
      copyLabel: copyLabel,
      showHsnOnReceipt: showHsnOnReceipt,
    );

    await Printing.sharePdf(
      bytes: await pdf.save(),
      filename: 'Bill_${bill.billNumber}_${bill.date}.pdf',
    );
  }

  /// Load logo image bytes from URL or local file
  static Future<pw.MemoryImage?> _loadLogoImage(String path) async {
    try {
      Uint8List? bytes;
      if (path.startsWith('http')) {
        final response = await http.get(Uri.parse(path));
        if (response.statusCode == 200) {
          bytes = response.bodyBytes;
        }
      } else if (!kIsWeb) {
        final file = File(path);
        if (file.existsSync()) {
          bytes = await file.readAsBytes();
        }
      }
      if (bytes != null && bytes.isNotEmpty) {
        return pw.MemoryImage(bytes);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load logo for receipt: $e');
    }
    return null;
  }

  /// Build receipt as a list of widgets (for MultiPage pagination on web).
  static List<pw.Widget> _buildReceiptWidgets({
    required BillModel bill,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    required String receiptFooter,
    pw.MemoryImage? logoImage,
    String? upiId,
    double? taxRate,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) {
    final createdAt = bill.createdAt;

    return [
      // Shop logo (if available)
      if (logoImage != null) ...[
        pw.Center(child: pw.Image(logoImage, width: 50, height: 50)),
        pw.SizedBox(height: 4),
      ],
      // Shop header (centered)
      pw.Text(
        shopName,
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
      if (shopAddress != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          shopAddress,
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
      ],
      if (shopPhone != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          'Ph: $shopPhone',
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
      ],
      if (gstNumber != null) ...[
        pw.SizedBox(height: 2),
        pw.Text(
          'GSTIN: $gstNumber',
          style: const pw.TextStyle(fontSize: 8),
          textAlign: pw.TextAlign.center,
        ),
      ],

      pw.SizedBox(height: 6),
      pw.Divider(thickness: 0.5),

      // Bill info
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Bill #${bill.billNumber}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            _dateFormat.format(createdAt),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),

      // Copy label (ORIGINAL / DUPLICATE)
      if (copyLabel != null) ...[
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            '*** $copyLabel ***',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],

      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            bill.paymentMethod.displayName,
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            _timeFormat.format(createdAt),
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),

      if (bill.customerName != null) ...[
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text('Customer: ', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
              bill.customerName!,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ],
        ),
      ],

      pw.SizedBox(height: 6),
      pw.Divider(thickness: 0.5),

      // Items header
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          pw.Expanded(
            flex: 4,
            child: pw.Text(
              'Item',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              'Qty',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              'Amt',
              style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.right,
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Divider(thickness: 0.3),

      // Items list
      ...bill.items.map(
        (item) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                flex: 4,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(item.name, style: const pw.TextStyle(fontSize: 9)),
                    pw.Text(
                      '@ Rs.${item.price.toStringAsFixed(0)}',
                      style: const pw.TextStyle(
                        fontSize: 7,
                        color: PdfColors.grey700,
                      ),
                    ),
                    if (showHsnOnReceipt &&
                        item.hsnCode != null &&
                        item.hsnCode!.isNotEmpty)
                      pw.Text(
                        'HSN: ${item.hsnCode}',
                        style: const pw.TextStyle(
                          fontSize: 7,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  item.quantity.toString(),
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Rs.${item.total.toStringAsFixed(0)}',
                  style: const pw.TextStyle(fontSize: 9),
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ],
          ),
        ),
      ),

      pw.SizedBox(height: 4),
      pw.Divider(thickness: 0.5),

      // Total section
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Items:', style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            '${bill.items.length}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'TOTAL:',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Rs.${bill.total.toStringAsFixed(0)}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),

      // GST breakdown (inclusive — tax already in total)
      if (taxRate != null && taxRate > 0 && gstNumber != null) ...[
        pw.SizedBox(height: 3),
        _gstRow(
          'CGST @${(taxRate / 2).toStringAsFixed(1)}%',
          bill.total * taxRate / (100 + taxRate) / 2,
        ),
        _gstRow(
          'SGST @${(taxRate / 2).toStringAsFixed(1)}%',
          bill.total * taxRate / (100 + taxRate) / 2,
        ),
      ],

      // Cash payment details
      if (bill.paymentMethod == PaymentMethod.cash &&
          bill.receivedAmount != null) ...[
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Received:', style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
              'Rs.${bill.receivedAmount!.toStringAsFixed(0)}',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ],
        ),
        if ((bill.changeAmount ?? 0) > 0)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Change:', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                'Rs.${bill.changeAmount!.toStringAsFixed(0)}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
      ],

      // Udhar note
      if (bill.paymentMethod == PaymentMethod.udhar) ...[
        pw.SizedBox(height: 6),
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
          child: pw.Text(
            '*** UDHAR - Pending ***',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],

      pw.SizedBox(height: 8),
      pw.Divider(thickness: 0.3),

      // UPI QR code
      if (upiId != null && upiId.isNotEmpty) ...[
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Scan to pay via UPI',
            style: const pw.TextStyle(fontSize: 8),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data:
                'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${bill.total.toStringAsFixed(2)}&cu=INR',
            width: 44,
            height: 44,
          ),
        ),
        pw.SizedBox(height: 4),
      ],

      // Footer
      pw.SizedBox(height: 4),
      pw.Text(
        receiptFooter,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Powered by ${AppConstants.appName}',
        style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
        textAlign: pw.TextAlign.center,
      ),
      pw.SizedBox(height: 12), // Space for tear
    ];
  }

  /// Build receipt as a single Column widget (for single-page layouts).
  static pw.Widget _buildReceipt({
    required BillModel bill,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    required String receiptFooter,
    pw.MemoryImage? logoImage,
    String? upiId,
    double? taxRate,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: _buildReceiptWidgets(
        bill: bill,
        shopName: shopName,
        shopAddress: shopAddress,
        shopPhone: shopPhone,
        gstNumber: gstNumber,
        receiptFooter: receiptFooter,
        logoImage: logoImage,
        upiId: upiId,
        taxRate: taxRate,
        copyLabel: copyLabel,
        showHsnOnReceipt: showHsnOnReceipt,
      ),
    );
  }

  static pw.Widget _gstRow(String label, double amount) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        pw.Text(
          'Rs.${amount.toStringAsFixed(2)}',
          style: const pw.TextStyle(fontSize: 8),
        ),
      ],
    );
  }
}
