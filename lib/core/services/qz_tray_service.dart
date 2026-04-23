/// QZ Tray client — sends raw ESC/POS bytes to local printers via WebSocket.
///
/// QZ Tray (https://qz.io) is a free LGPL service that runs on the POS
/// computer and exposes printers over a local WebSocket. Flutter web
/// connects, lists printers, and sends raw byte streams — completely
/// bypassing Chrome's print dialog and the Windows driver's paper-size
/// and orientation settings.
///
/// End-user setup (one time per POS PC):
///   1. Download QZ Tray from https://qz.io/download/
///   2. Run installer → Finish
///   3. QZ Tray auto-starts as tray icon on every boot
///
/// No per-user configuration, no certificate, no Chrome tweaks needed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;

class QzTrayService {
  QzTrayService._();

  /// Insecure local port. QZ Tray also exposes wss://localhost:8181/8182
  /// Since the app is served over HTTPS (login-radha.web.app), Chrome blocks
  /// ws:// as mixed-content. We must use wss://localhost:8182 instead.
  /// QZ Tray uses a self-signed cert for wss — users trust it once by visiting
  /// https://localhost:8182 and clicking "Proceed anyway".
  /// Insecure ws://8181 is kept as last-resort fallback (works on http:// hosts).
  static const _secureUrl = 'wss://localhost:8182';
  static const _insecureUrl = 'ws://localhost:8181';

  /// Connect timeout.
  static const _connectTimeout = Duration(seconds: 2);
  static const _callTimeout = Duration(seconds: 10);

  static const _prefsKeyPrinterName = 'qz_tray_printer_name';
  static const _prefsKeyEnabled = 'qz_tray_enabled';

  /// Returns true if QZ Tray is reachable on this machine.
  ///
  /// Web-only; always returns false on non-web platforms (native platforms
  /// have direct printing).
  static Future<bool> isAvailable() async {
    if (!kIsWeb) return false;
    try {
      final channel = await _connect();
      unawaited(channel.sink.close(ws_status.normalClosure));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// User has opted in to QZ Tray printing (persisted in prefs).
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);
  }

  /// Saved printer name (user selects once from QZ Tray's list).
  static Future<String?> getSelectedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKeyPrinterName);
  }

  static Future<void> setSelectedPrinter(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyPrinterName, name);
  }

  /// List all printers known to QZ Tray. Returns empty list on failure.
  static Future<List<String>> listPrinters() async {
    try {
      final result = await _call('printers.find', {});
      if (result is List) {
        return result.map((e) => e.toString()).toList();
      }
      return const [];
    } catch (e) {
      debugPrint('QZ Tray listPrinters failed: $e');
      return const [];
    }
  }

  /// Send raw bytes (ESC/POS) to the named printer.
  ///
  /// Returns true on success.
  static Future<bool> printRaw({
    required String printerName,
    required Uint8List data,
  }) async {
    try {
      final b64 = base64Encode(data);
      final req = {
        'printer': {'name': printerName},
        'options': {'language': 'ESCP'},
        'data': [
          {'type': 'raw', 'format': 'base64', 'data': b64},
        ],
      };
      await _call('print', req);
      return true;
    } catch (e) {
      debugPrint('QZ Tray printRaw failed: $e');
      return false;
    }
  }

  // ---- internal ----

  static Future<WebSocketChannel> _connect() async {
    // HTTPS pages require wss://, not ws:// (Chrome mixed-content block).
    // Try wss://8182 first (QZ Tray self-signed cert — user trusts once).
    // Fall back to ws://8181 for http:// dev/local hosts.
    try {
      final ch = WebSocketChannel.connect(Uri.parse(_secureUrl));
      await ch.ready.timeout(_connectTimeout);
      return ch;
    } catch (_) {
      final ch = WebSocketChannel.connect(Uri.parse(_insecureUrl));
      await ch.ready.timeout(_connectTimeout);
      return ch;
    }
  }

  /// Send a single request to QZ Tray and await its response.
  ///
  /// QZ Tray's WebSocket API (unsigned mode) accepts JSON of the form:
  ///   `{ "call": "method", "params": {...}, "uid": "random" }`
  /// and responds with:
  ///   `{ "uid": "same", "result": ..., "error": ... }`
  static Future<dynamic> _call(String method, dynamic params) async {
    final channel = await _connect();
    final uid = _randomUid();
    final completer = Completer<dynamic>();

    // QZ Tray sends a handshake/version line first. Wait for that or our
    // response; differentiate by uid.
    late StreamSubscription<dynamic> sub;
    sub = channel.stream.listen(
      (raw) {
        try {
          final str = raw is String ? raw : utf8.decode(raw as List<int>);
          final msg = jsonDecode(str);
          if (msg is Map && msg['uid'] == uid) {
            if (msg['error'] != null && msg['error'].toString().isNotEmpty) {
              completer.completeError(
                StateError('QZ Tray error: ${msg['error']}'),
              );
            } else {
              completer.complete(msg['result']);
            }
            sub.cancel();
            channel.sink.close(ws_status.normalClosure);
          }
        } catch (_) {
          // ignore non-matching frames
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(
            StateError('QZ Tray closed before responding'),
          );
        }
      },
    );

    final payload = jsonEncode({'call': method, 'params': params, 'uid': uid});
    channel.sink.add(payload);

    return completer.future.timeout(_callTimeout);
  }

  static String _randomUid() {
    final rng = Random();
    return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}
