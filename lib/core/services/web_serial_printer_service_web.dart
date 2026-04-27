/// Web Serial printer service for Chrome-based USB printing.
///
/// Uses the Web Serial API (`navigator.serial`) to connect directly to
/// USB-connected thermal printers via their COM port.
///
/// **Requirements**:
/// - Chrome/Edge on Windows, macOS, or Linux (not Android/iOS)
/// - HTTPS or localhost
/// - Printer must be connected via USB
/// - User selects the COM port once per session
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';
import 'package:retaillite/models/bill_model.dart';
import 'package:web/web.dart' as web;

/// Service for printing via Chrome Web Serial API (USB thermal printers).
class WebSerialPrinterService {
  WebSerialPrinterService._();

  static JSObject? _port;
  static JSObject?
  _writer; // held for the full session; released only on disconnect
  static bool _connected = false;
  static String _connectedPortName = 'USB Printer';

  /// Whether Web Serial is supported in this browser.
  static bool get isSupported {
    if (!kIsWeb) return false;
    try {
      final nav = web.window.navigator as JSObject;
      final serial = nav['serial'];
      return serial != null && serial.isA<JSObject>();
    } catch (_) {
      return false;
    }
  }

  /// Whether a port is currently open and ready.
  static bool get isConnected => _connected && _port != null && _writer != null;

  /// Display name for the connected port (e.g. "USB Printer (0483:5740)")
  static String get connectedPortName => _connectedPortName;

  /// Show Chrome's port picker and open the selected serial port.
  /// Acquires a WritableStreamDefaultWriter immediately and holds it for
  /// the lifetime of the connection — no get/release per send.
  /// Whether [connect] can silently reconnect without the picker.
  /// True when Chrome has a previously-granted port that is still available.
  static Future<bool> get canAutoReconnect async {
    if (!isSupported) return false;
    try {
      final nav = web.window.navigator as JSObject;
      final serial = nav['serial']! as JSObject;
      final portsArray =
          await (serial.callMethod('getPorts'.toJS) as JSPromise<JSObject>)
              .toDart;
      final length =
          (portsArray['length'] as JSNumber?)?.toDartDouble.round() ?? 0;
      return length > 0;
    } catch (_) {
      return false;
    }
  }

  /// Show Chrome's port picker and open the selected serial port.
  /// If [silent] is true, only tries previously-granted ports — no picker.
  /// Acquires a WritableStreamDefaultWriter immediately and holds it for
  /// the lifetime of the connection — no get/release per send.
  /// Returns true if connected successfully.
  static Future<bool> connect({bool silent = false}) async {
    if (!isSupported) return false;

    // ── Clean up any previous connection BEFORE opening the new one ─────────
    if (_writer != null) {
      try {
        _writer!.callMethod('releaseLock'.toJS);
      } catch (_) {}
      _writer = null;
    }
    if (_port != null) {
      try {
        await (_port!.callMethod('close'.toJS) as JSPromise).toDart;
      } catch (_) {}
      _port = null;
    }
    _connected = false;
    // ────────────────────────────────────────────────────────────────────────

    try {
      final nav = web.window.navigator as JSObject;
      final serial = nav['serial']! as JSObject;

      // ── Try previously-granted ports first (no picker needed) ────────────
      // Only do this for silent reconnect (e.g. on page load).
      // When the user explicitly taps "Select Port" (silent=false), always
      // show the picker so they can choose any port — not just port 0.
      JSObject? port;
      if (silent) {
        try {
          final portsArray =
              await (serial.callMethod('getPorts'.toJS) as JSPromise<JSObject>)
                  .toDart;
          final length =
              (portsArray['length'] as JSNumber?)?.toDartDouble.round() ?? 0;
          if (length > 0) {
            port = portsArray['0'] as JSObject;
            debugPrint(
              'Web Serial: Auto-reconnecting to previously granted port',
            );
          }
        } catch (_) {}
        if (port == null) return false; // silent=true means no picker
      } else {
        // Explicit connect — always show the Chrome picker so the user can
        // choose any available COM port, not just the previously-granted one.
        port =
            await (serial.callMethod('requestPort'.toJS) as JSPromise<JSObject>)
                .toDart;
      }

      _port = port;

      // Try common baud rates for USB/BT-SPP thermal printers.
      // For Bluetooth virtual COM ports the OS ignores the baud rate, so any
      // value works.  For real USB-serial chips 9600 is the safest default.
      const baudRates = [9600, 115200, 19200, 38400];
      bool opened = false;
      for (final baud in baudRates) {
        try {
          final options = {'baudRate': baud}.jsify()!;
          await (port.callMethod('open'.toJS, options) as JSPromise).toDart;
          debugPrint('Web Serial: Port opened at $baud baud');
          opened = true;
          break;
        } catch (_) {
          // try next baud rate
        }
      }

      if (!opened) {
        _port = null;
        return false;
      }

      // Acquire the writer once and keep it for the lifetime of this connection.
      // This avoids "stream is locked" errors from repeated get/release cycles.
      try {
        final writable = port['writable'] as JSObject;
        _writer = writable.callMethod('getWriter'.toJS) as JSObject;
      } catch (e) {
        debugPrint('Web Serial: could not acquire writer: $e');
        try {
          await (port.callMethod('close'.toJS) as JSPromise).toDart;
        } catch (_) {}
        _port = null;
        return false;
      }

      _connected = true;

      // Try to get a human-readable port identifier
      try {
        final info =
            await (port.callMethod('getInfo'.toJS) as JSPromise<JSObject>)
                .toDart;
        final vendorId = info['usbVendorId'];
        final productId = info['usbProductId'];
        if (vendorId != null && productId != null) {
          final vid = (vendorId as JSNumber).toDartDouble
              .round()
              .toRadixString(16)
              .padLeft(4, '0')
              .toUpperCase();
          final pid = (productId as JSNumber).toDartDouble
              .round()
              .toRadixString(16)
              .padLeft(4, '0')
              .toUpperCase();
          _connectedPortName = 'USB Printer ($vid:$pid)';
        } else {
          _connectedPortName = 'USB Serial Port';
        }
      } catch (_) {
        _connectedPortName = 'USB Serial Port';
      }

      debugPrint('Web Serial: Connected — $_connectedPortName');
      return true;
    } catch (e) {
      debugPrint('Web Serial connect error: $e');
      _connected = false;
      _port = null;
      _writer = null;
      return false;
    }
  }

  /// Close the serial port and release all resources.
  static Future<void> disconnect() async {
    try {
      _writer?.callMethod('releaseLock'.toJS);
    } catch (_) {}
    _writer = null;
    try {
      if (_port != null) {
        await (_port!.callMethod('close'.toJS) as JSPromise).toDart;
      }
    } catch (e) {
      debugPrint('Web Serial disconnect error: $e');
    } finally {
      _port = null;
      _connected = false;
    }
  }

  /// Write raw ESC/POS bytes to the open serial port.
  ///
  /// Uses the persistent writer acquired during [connect].  All bytes are
  /// sent in a single write() call — the browser's WritableStream handles
  /// backpressure and the OS serial driver buffers the data for transmission.
  ///
  /// On write failure the entire connection is torn down so the next call
  /// will show the Chrome port picker and start fresh.
  static Future<bool> sendBytes(List<int> bytes) async {
    // If not connected, try silent reconnect first, then show picker.
    if (!isConnected) {
      final silentOk = await connect(silent: true);
      if (!silentOk && !await connect()) return false;
    }

    final data = Uint8List.fromList(bytes);

    // First attempt with the persistent writer
    if (await _tryWrite(data)) return true;

    // Write failed — the writer may be in an error state.
    // Try acquiring a fresh writer from the same open port before tearing down.
    debugPrint('Web Serial: first write failed, retrying with fresh writer…');
    try {
      _writer?.callMethod('releaseLock'.toJS);
    } catch (_) {}
    _writer = null;

    if (_port != null) {
      try {
        final writable = _port!['writable'] as JSObject;
        _writer = writable.callMethod('getWriter'.toJS) as JSObject;
        if (await _tryWrite(data)) return true;
      } catch (_) {}
    }

    // Still failing — full teardown, next call shows the Chrome picker
    debugPrint(
      'Web Serial: unrecoverable write error, tearing down connection',
    );
    try {
      _writer?.callMethod('releaseLock'.toJS);
    } catch (_) {}
    _writer = null;
    _connected = false;
    try {
      if (_port != null) {
        await (_port!.callMethod('close'.toJS) as JSPromise).toDart;
      }
    } catch (_) {}
    _port = null;
    return false;
  }

  /// Single write attempt. Returns true on success, false on any exception.
  static Future<bool> _tryWrite(Uint8List data) async {
    if (_writer == null) return false;
    try {
      await (_writer!.callMethod('write'.toJS, data.toJS) as JSPromise).toDart;
      return true;
    } catch (e) {
      debugPrint('Web Serial write attempt failed: $e');
      return false;
    }
  }

  /// Print a receipt via Web Serial using the shared ESC/POS builder.
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
  }) async {
    final bytes = EscPosBuilder.buildReceipt(
      bill: bill,
      shopName: shopName,
      shopAddress: shopAddress,
      shopPhone: shopPhone,
      gstNumber: gstNumber,
      receiptFooter: receiptFooter,
      upiId: upiId,
      taxRate: taxRate,
      partialCut: partialCut,
      isHindi: isHindi,
      copyLabel: copyLabel,
      showHsnOnReceipt: showHsnOnReceipt,
      logoBytes: logoBytes,
    );
    return sendBytes(bytes);
  }

  /// Print a test page.
  static Future<bool> printTestPage() async {
    return sendBytes(EscPosBuilder.buildTestPage());
  }
}
