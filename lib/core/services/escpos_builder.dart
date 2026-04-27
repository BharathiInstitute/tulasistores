/// ESC/POS byte builder for thermal receipt printers (POSIFlow SR20 / 58mm).
///
/// Produces a raw byte stream that is sent to the printer via QZ Tray,
/// completely bypassing Chrome's print dialog and the Windows driver's
/// paper-size / orientation settings.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:retaillite/models/bill_model.dart';
import 'package:intl/intl.dart';

class EscPosBuilder {
  EscPosBuilder._();

  // ---- ESC/POS control codes ----
  static const int _esc = 0x1B;
  static const int _gs = 0x1D;
  static const int _lf = 0x0A;

  /// Line width in characters for 58mm paper (POSIFlow SR20).
  /// 80mm printers use 48.
  static const int _lineWidth58 = 32;
  static const int _lineWidth80 = 48;

  static final _dateFmt = DateFormat('dd/MM/yyyy');
  static final _timeFmt = DateFormat('hh:mm a');

  /// Build receipt bytes for a bill.
  ///
  /// [paperSizeIndex] — 0 = 58mm (32 cols), 1 = 80mm (48 cols).
  static Uint8List buildReceipt({
    required BillModel bill,
    required String shopName,
    String? shopAddress,
    String? shopPhone,
    String? gstNumber,
    String? receiptFooter,
    String? upiId,
    double? taxRate,
    int paperSizeIndex = 0,
    String? copyLabel,
    bool showHsnOnReceipt = false,
  }) {
    final cols = paperSizeIndex == 1 ? _lineWidth80 : _lineWidth58;
    final b = BytesBuilder();

    // --- Init printer ---
    b.add([_esc, 0x40]); // ESC @ — reset
    b.add([_esc, 0x74, 0x10]); // code page CP1252 (Western)

    // --- Shop name (centered, double size, bold) ---
    _align(b, 1);
    _bold(b, true);
    _size(b, w: 1, h: 1);
    b.add(_encode(shopName));
    b.add([_lf]);
    _size(b);
    _bold(b, false);

    if (shopAddress != null && shopAddress.isNotEmpty) {
      b.add(_encode(shopAddress));
      b.add([_lf]);
    }
    if (shopPhone != null && shopPhone.isNotEmpty) {
      b.add(_encode('Ph: $shopPhone'));
      b.add([_lf]);
    }
    if (gstNumber != null && gstNumber.isNotEmpty) {
      b.add(_encode('GSTIN: $gstNumber'));
      b.add([_lf]);
    }

    _align(b, 0);
    _hr(b, cols);

    // --- Bill header ---
    b.add(
      _encode(
        _twoCol(
          'Bill #${bill.billNumber}',
          _dateFmt.format(bill.createdAt),
          cols,
        ),
      ),
    );
    b.add([_lf]);

    if (copyLabel != null) {
      _align(b, 1);
      _bold(b, true);
      b.add(_encode('*** $copyLabel ***'));
      _bold(b, false);
      b.add([_lf]);
      _align(b, 0);
    }

    b.add(
      _encode(
        _twoCol(
          bill.paymentMethod.displayName,
          _timeFmt.format(bill.createdAt),
          cols,
        ),
      ),
    );
    b.add([_lf]);

    if (bill.customerName != null && bill.customerName!.isNotEmpty) {
      b.add(_encode('Customer: ${bill.customerName}'));
      b.add([_lf]);
    }

    _hr(b, cols);

    // --- Items header ---
    // Item (left, flex) | Qty (4) | Amt (right, 8)
    const qtyW = 4;
    const amtW = 8;
    final nameW = cols - qtyW - amtW;
    _bold(b, true);
    b.add(
      _encode(
        _pad('Item', nameW) + _padCenter('Qty', qtyW) + _padRight('Amt', amtW),
      ),
    );
    _bold(b, false);
    b.add([_lf]);
    _hr(b, cols, thin: true);

    // --- Items ---
    for (final item in bill.items) {
      final nameLines = _wrap(item.name, nameW);
      final firstLine = nameLines.first;
      b.add(
        _encode(
          _pad(firstLine, nameW) +
              _padCenter(item.quantity.toString(), qtyW) +
              _padRight('Rs.${item.total.toStringAsFixed(0)}', amtW),
        ),
      );
      b.add([_lf]);
      // Additional name wrap lines
      for (var i = 1; i < nameLines.length; i++) {
        b.add(_encode(_pad(nameLines[i], cols)));
        b.add([_lf]);
      }
      // Price-per-unit line
      b.add(_encode(_pad('  @ Rs.${item.price.toStringAsFixed(0)}', cols)));
      b.add([_lf]);
      if (showHsnOnReceipt &&
          item.hsnCode != null &&
          item.hsnCode!.isNotEmpty) {
        b.add(_encode(_pad('  HSN: ${item.hsnCode}', cols)));
        b.add([_lf]);
      }
    }

    _hr(b, cols);

    // --- Totals ---
    b.add(_encode(_twoCol('Items:', '${bill.items.length}', cols)));
    b.add([_lf]);

    _bold(b, true);
    _size(b, h: 1);
    b.add(
      _encode(
        _twoCol(
          'TOTAL:',
          'Rs.${bill.total.toStringAsFixed(0)}',
          cols ~/
              2, // halved because chars are double width? actually only height doubled
        ),
      ),
    );
    b.add([_lf]);
    _size(b);
    _bold(b, false);

    // --- GST breakdown ---
    if (taxRate != null && taxRate > 0 && gstNumber != null) {
      final gstHalf = bill.total * taxRate / (100 + taxRate) / 2;
      b.add(
        _encode(
          _twoCol(
            'CGST @${(taxRate / 2).toStringAsFixed(1)}%',
            'Rs.${gstHalf.toStringAsFixed(2)}',
            cols,
          ),
        ),
      );
      b.add([_lf]);
      b.add(
        _encode(
          _twoCol(
            'SGST @${(taxRate / 2).toStringAsFixed(1)}%',
            'Rs.${gstHalf.toStringAsFixed(2)}',
            cols,
          ),
        ),
      );
      b.add([_lf]);
    }

    // --- Cash change ---
    if (bill.paymentMethod == PaymentMethod.cash &&
        bill.receivedAmount != null) {
      b.add(
        _encode(
          _twoCol(
            'Received:',
            'Rs.${bill.receivedAmount!.toStringAsFixed(0)}',
            cols,
          ),
        ),
      );
      b.add([_lf]);
      if ((bill.changeAmount ?? 0) > 0) {
        b.add(
          _encode(
            _twoCol(
              'Change:',
              'Rs.${bill.changeAmount!.toStringAsFixed(0)}',
              cols,
            ),
          ),
        );
        b.add([_lf]);
      }
    }

    // --- Udhar / credit note ---
    if (bill.paymentMethod == PaymentMethod.udhar) {
      b.add([_lf]);
      _align(b, 1);
      _bold(b, true);
      b.add(_encode('*** UDHAR - Pending ***'));
      _bold(b, false);
      _align(b, 0);
      b.add([_lf]);
    }

    _hr(b, cols, thin: true);

    // --- UPI QR code ---
    if (upiId != null && upiId.isNotEmpty) {
      final upiUri =
          'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(shopName)}&am=${bill.total.toStringAsFixed(2)}&cu=INR';
      _align(b, 1);
      b.add(_encode('Scan to pay via UPI'));
      b.add([_lf]);
      _qrCode(b, upiUri);
      _align(b, 0);
    }

    // --- Footer ---
    final footer = receiptFooter ?? 'Thank you for shopping!';
    _align(b, 1);
    _bold(b, true);
    b.add(_encode(footer));
    _bold(b, false);
    b.add([_lf]);
    _align(b, 0);

    // --- Feed + cut ---
    b.add([_lf, _lf, _lf, _lf, _lf]); // feed paper past cutter
    b.add([_gs, 0x56, 0x01]); // GS V 1 — partial cut

    return b.toBytes();
  }

  // ---- Formatting helpers ----

  static void _align(BytesBuilder b, int mode) {
    // 0=left, 1=center, 2=right
    b.add([_esc, 0x61, mode]);
  }

  static void _bold(BytesBuilder b, bool on) {
    b.add([_esc, 0x45, on ? 1 : 0]);
  }

  /// Set character size. w/h are multipliers 0..7 (0 = 1x).
  static void _size(BytesBuilder b, {int w = 0, int h = 0}) {
    final n = ((w & 0x07) << 4) | (h & 0x07);
    b.add([_gs, 0x21, n]);
  }

  static void _hr(BytesBuilder b, int cols, {bool thin = false}) {
    final ch = thin ? '-' : '=';
    b.add(_encode(ch * cols));
    b.add([_lf]);
  }

  static void _qrCode(BytesBuilder b, String data) {
    final bytes = utf8.encode(data);
    // Model 2
    b.add([_gs, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    // Size (module px): 1..16 — use 6 for 58mm
    b.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, 0x06]);
    // Error correction L
    b.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);
    // Store data
    final pL = (bytes.length + 3) & 0xFF;
    final pH = ((bytes.length + 3) >> 8) & 0xFF;
    b.add([_gs, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30]);
    b.add(bytes);
    // Print
    b.add([_gs, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
  }

  // ---- Text helpers ----

  /// Encode a string to CP1252 bytes, stripping unsupported chars.
  static List<int> _encode(String s) {
    final out = <int>[];
    for (final rune in s.runes) {
      if (rune < 128) {
        out.add(rune);
      } else if (rune < 256) {
        out.add(rune);
      } else {
        // fallback for unsupported glyphs (e.g. emoji, Devanagari)
        out.add(0x3F); // '?'
      }
    }
    return out;
  }

  static String _pad(String s, int w) {
    if (s.length >= w) return s.substring(0, w);
    return s + ' ' * (w - s.length);
  }

  static String _padRight(String s, int w) {
    if (s.length >= w) return s.substring(0, w);
    return ' ' * (w - s.length) + s;
  }

  static String _padCenter(String s, int w) {
    if (s.length >= w) return s.substring(0, w);
    final total = w - s.length;
    final left = total ~/ 2;
    final right = total - left;
    return ' ' * left + s + ' ' * right;
  }

  static String _twoCol(String left, String right, int cols) {
    final maxLeft = cols - right.length - 1;
    final l = left.length > maxLeft ? left.substring(0, maxLeft) : left;
    final gap = cols - l.length - right.length;
    return l + ' ' * (gap < 1 ? 1 : gap) + right;
  }

  static List<String> _wrap(String s, int w) {
    if (s.length <= w) return [s];
    final out = <String>[];
    var i = 0;
    while (i < s.length) {
      final end = (i + w) > s.length ? s.length : (i + w);
      out.add(s.substring(i, end));
      i = end;
    }
    return out;
  }
}
