/// Stub implementation for non-web platforms.
///
/// All methods return false / no-op since Web Serial
/// is not available outside of a browser.
library;

import 'dart:typed_data';

import 'package:retaillite/models/bill_model.dart';

class WebSerialPrinterService {
  WebSerialPrinterService._();

  static bool get isSupported => false;
  static bool get isConnected => false;
  static String get connectedPortName => '';

  static Future<bool> connect() async => false;
  static Future<void> disconnect() async {}
  static Future<bool> sendBytes(List<int> bytes) async => false;

  static Future<bool> printReceipt({
    required BillModel bill,
    String? shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? upiId,
    double? taxRate,
    bool partialCut = false,
    bool isHindi = false,
    String? copyLabel,
    bool showHsnOnReceipt = false,
    Uint8List? logoBytes,
  }) async => false;

  static Future<bool> printTestPage() async => false;
}
