import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/receipt_service.dart';
import 'package:retaillite/core/services/sunmi_printer_service.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';
import 'package:retaillite/core/services/web_bluetooth_printer_service.dart';
import 'package:retaillite/core/services/web_serial_printer_service.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';
import 'package:retaillite/models/bill_model.dart';
import 'package:retaillite/models/user_model.dart';

/// Centralized print helper — single source of truth for all receipt printing.
///
/// Used by both mobile (payment_modal) and web (pos_web_widgets) checkout flows.
class PrintHelper {
  PrintHelper._();

  /// Find a system printer by name using [Printing.listPrinters].
  /// Falls back to the default printer if [name] doesn't match.
  static Future<Printer?> _findPrinter(String name) async {
    try {
      final printers = await Printing.listPrinters();
      if (printers.isEmpty) return null;

      // Exact match first
      for (final p in printers) {
        if (p.name == name) return p;
      }
      // Case-insensitive match
      final lower = name.toLowerCase();
      for (final p in printers) {
        if (p.name.toLowerCase() == lower) return p;
      }
      // Default printer as last resort
      for (final p in printers) {
        if (p.isDefault) return p;
      }
      return printers.first;
    } catch (e) {
      debugPrint('PrintHelper: Failed to list printers: $e');
      return null;
    }
  }

  /// Try to print a PDF directly to a known printer (no dialog).
  /// Returns true if successful, false otherwise.
  static Future<bool> _tryDirectPdfPrint({
    required BillModel bill,
    required UserModel? user,
    required String? footer,
  }) async {
    try {
      // 1. Check saved system printer
      final savedName = PrinterStorage.getSystemPrinterName();
      final savedUrl = PrinterStorage.getSystemPrinterUrl();
      Printer? printer;

      if (savedName.isNotEmpty && savedUrl.isNotEmpty) {
        printer = Printer(url: savedUrl, name: savedName);
      } else {
        // 2. Look up USB printer name in system printers
        final usbName = UsbPrinterService.getSavedPrinterName();
        if (usbName.isNotEmpty) {
          printer = await _findPrinter(usbName);
          // Save for next time so lookup is instant
          if (printer != null) {
            await PrinterStorage.saveSystemPrinter(printer.name, printer.url);
          }
        } else {
          // 3. Try default printer
          final printers = await Printing.listPrinters();
          printer = printers.where((p) => p.isDefault).firstOrNull;
          printer ??= printers.firstOrNull;
        }
      }

      if (printer == null) return false;

      return await ReceiptService.directPrintReceipt(
        printer: printer,
        bill: bill,
        shopName: user?.shopName,
        shopAddress: user?.address,
        shopPhone: user?.phone,
        gstNumber: user?.gstNumber,
        receiptFooter: footer,
        shopLogoPath: user?.shopLogoPath,
      );
    } catch (e) {
      debugPrint('PrintHelper: directPdfPrint failed: $e');
      return false;
    }
  }

  /// Print a receipt using the configured printer type.
  ///
  /// [isAutoPrint] — when true, skips system printer (shows dialog) and
  /// suppresses the fallback from a disconnected thermal printer to system.
  ///
  /// [onRetry] — callback for the "Retry" snackbar action. If null, no retry
  /// button is shown on failure.
  static Future<void> printReceipt({
    required BillModel bill,
    required PrinterState printerState,
    required UserModel? user,
    required ScaffoldMessengerState scaffoldMessenger,
    bool isAutoPrint = false,
    VoidCallback? onRetry,
  }) async {
    try {
      final footer = printerState.receiptFooter.isNotEmpty
          ? printerState.receiptFooter
          : null;

      bool? directSuccess;

      switch (printerState.printerType) {
        case PrinterTypeOption.bluetooth:
          if (ThermalPrinterService.isAvailable) {
            // Show a brief status snackbar so the user knows something is
            // happening during the BT (re)connect + warm-up phase.
            final printerName = printerState.printerName;
            if (!isAutoPrint) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text(
                    printerName != null && printerName.isNotEmpty
                        ? 'Connecting to $printerName…'
                        : 'Connecting to printer…',
                  ),
                  duration: const Duration(seconds: 12),
                ),
              );
            }
            directSuccess = await ThermalPrinterService.printReceipt(
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
            // Dismiss the connecting snackbar immediately after the print call
            if (!isAutoPrint) scaffoldMessenger.hideCurrentSnackBar();
          }
          break;

        case PrinterTypeOption.wifi:
          if (WifiPrinterService.isConnected) {
            directSuccess = await WifiPrinterService.printReceipt(
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
          }
          break;

        case PrinterTypeOption.usb:
          final usbName = UsbPrinterService.getSavedPrinterName();
          if (usbName.isNotEmpty) {
            // ESC/POS text commands — native printer language, reliable on
            // all thermal printers including Posiflow SR20.
            debugPrint('PrintHelper: USB — sending ESC/POS text receipt...');
            directSuccess = await UsbPrinterService.printReceipt(
              printerName: usbName,
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
            debugPrint('PrintHelper: USB — result: $directSuccess');
          }
          break;

        case PrinterTypeOption.sunmi:
          if (await SunmiPrinterService.isAvailable) {
            directSuccess = await SunmiPrinterService.printReceipt(
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
          }
          break;

        case PrinterTypeOption.webBluetooth:
          if (WebBluetoothPrinterService.isSupported) {
            if (!WebBluetoothPrinterService.hasDevice) {
              // No device selected yet — user hasn't gone through the picker
              if (!isAutoPrint) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Bluetooth printer not connected. '
                      'Go to Settings → Hardware and tap "Select Printer" first.',
                    ),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
              return;
            }
            // sendBytes() handles silent GATT reconnect if connection dropped
            directSuccess = await WebBluetoothPrinterService.printReceipt(
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
          }
          break;

        case PrinterTypeOption.webSerial:
          if (WebSerialPrinterService.isSupported) {
            directSuccess = await WebSerialPrinterService.printReceipt(
              bill: bill,
              shopName: user?.shopName,
              shopAddress: user?.address,
              shopPhone: user?.phone,
              gstNumber: user?.gstNumber,
              receiptFooter: footer,
            );
          } else {
            // Web Serial not supported (not Chrome on desktop)
            if (!isAutoPrint) {
              scaffoldMessenger.showSnackBar(
                const SnackBar(
                  content: Text(
                    'USB printing requires Chrome on Windows. '
                    'Use Settings → Hardware to connect.',
                  ),
                ),
              );
            }
            return;
          }
          break;

        case PrinterTypeOption.system:
          if (isAutoPrint) return; // Never auto-print via system dialog

          if (!kIsWeb && Platform.isWindows) {
            // On Windows, never open a dialog.
            // 1. Try ESC/POS raw bytes (best for thermal printers like POS58).
            final usbName = UsbPrinterService.getSavedPrinterName();
            if (usbName.isNotEmpty) {
              final escOk = await UsbPrinterService.printReceipt(
                printerName: usbName,
                bill: bill,
                shopName: user?.shopName,
                shopAddress: user?.address,
                shopPhone: user?.phone,
                gstNumber: user?.gstNumber,
                receiptFooter: footer,
              );
              if (escOk) return;
            }
            // 2. Fall back to silent PDF (no dialog) using default printer.
            final pdfOk = await _tryDirectPdfPrint(
              bill: bill,
              user: user,
              footer: footer,
            );
            if (pdfOk) return;
            // 3. Both failed — show error (no dialog).
            if (!isAutoPrint) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: const Text(
                    'Print failed. Select your printer in Settings → Hardware.',
                  ),
                  action: onRetry != null
                      ? SnackBarAction(label: 'Retry', onPressed: onRetry)
                      : null,
                ),
              );
            }
            return;
          }

          // Non-Windows / web: show the system print dialog.
          await ReceiptService.printReceipt(
            bill: bill,
            shopName: user?.shopName,
            shopAddress: user?.address,
            shopPhone: user?.phone,
            gstNumber: user?.gstNumber,
            receiptFooter: footer,
            shopLogoPath: user?.shopLogoPath,
          );
          return;
      }

      if (directSuccess == true) return; // Thermal print worked

      if (directSuccess == false || directSuccess == null) {
        if (!isAutoPrint) {
          final String msg;
          if (directSuccess == null) {
            msg =
                'Print failed: No printer selected. Go to Settings → Hardware.';
          } else if (printerState.printerType ==
              PrinterTypeOption.webBluetooth) {
            msg =
                'Bluetooth print failed. Try disconnecting and reconnecting in Settings → Hardware.';
          } else if (printerState.printerType == PrinterTypeOption.webSerial) {
            msg =
                'USB print failed. Reconnect the COM port in Settings → Hardware.';
          } else {
            msg =
                'Print failed. Reconnect your printer in Settings → Hardware.';
          }
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(msg),
              action: onRetry != null
                  ? SnackBarAction(label: 'Retry', onPressed: onRetry)
                  : null,
            ),
          );
        }
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }
}
