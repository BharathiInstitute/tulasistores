/// Tests for thermal printer services — EscPosBuilder, WiFi, USB
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';

void main() {
  // ───────────────────────────────────────────────
  // EscPosBuilder — ESC/POS command helpers
  // ───────────────────────────────────────────────
  group('EscPosBuilder ESC/POS commands', () {
    test('init returns ESC @ reset sequence', () {
      expect(EscPosBuilder.init(), equals([0x1B, 0x40]));
    });

    test('center returns ESC a 1', () {
      expect(EscPosBuilder.center(), equals([0x1B, 0x61, 0x01]));
    });

    test('left returns ESC a 0', () {
      expect(EscPosBuilder.left(), equals([0x1B, 0x61, 0x00]));
    });

    test('bold on returns ESC E 1', () {
      expect(EscPosBuilder.bold(true), equals([0x1B, 0x45, 0x01]));
    });

    test('bold off returns ESC E 0', () {
      expect(EscPosBuilder.bold(false), equals([0x1B, 0x45, 0x00]));
    });

    test('doubleHeight on returns ESC ! 0x10', () {
      expect(EscPosBuilder.doubleHeight(true), equals([0x1B, 0x21, 0x10]));
    });

    test('doubleHeight off returns ESC ! 0x00', () {
      expect(EscPosBuilder.doubleHeight(false), equals([0x1B, 0x21, 0x00]));
    });

    test('feed returns ESC d n', () {
      expect(EscPosBuilder.feed(3), equals([0x1B, 0x64, 3]));
      expect(EscPosBuilder.feed(0), equals([0x1B, 0x64, 0]));
      expect(EscPosBuilder.feed(5), equals([0x1B, 0x64, 5]));
    });

    test('cut returns GS V 0', () {
      expect(EscPosBuilder.cut(), equals([0x1D, 0x56, 0x00]));
    });

    test('text returns code units', () {
      expect(EscPosBuilder.text('A'), equals([65]));
      expect(EscPosBuilder.text('Hi'), equals([72, 105]));
      expect(EscPosBuilder.text('\n'), equals([10]));
    });
  });

  // ───────────────────────────────────────────────
  // EscPosBuilder — fontSize
  // ───────────────────────────────────────────────
  group('EscPosBuilder fontSize', () {
    test('small font returns ESC ! 0x01', () {
      expect(
        EscPosBuilder.fontSize(PrinterFontSizeMode.small),
        equals([0x1B, 0x21, 0x01]),
      );
    });

    test('normal font returns ESC ! 0x00', () {
      expect(
        EscPosBuilder.fontSize(PrinterFontSizeMode.normal),
        equals([0x1B, 0x21, 0x00]),
      );
    });

    test('large font returns ESC ! 0x10', () {
      expect(
        EscPosBuilder.fontSize(PrinterFontSizeMode.large),
        equals([0x1B, 0x21, 0x10]),
      );
    });
  });

  // ───────────────────────────────────────────────
  // EscPosBuilder — formatLine
  // ───────────────────────────────────────────────
  group('EscPosBuilder.formatLine', () {
    test('pads 3-column line to specified width', () {
      final line = EscPosBuilder.formatLine('Item', 'x2', '100', 32);
      // 4 + 2 + 3 = 9 chars content, 32 - 9 = 23 spaces distributed
      expect(line.trimRight().length, lessThanOrEqualTo(32));
      expect(line, contains('Item'));
      expect(line, contains('x2'));
      expect(line, contains('100'));
      expect(line, endsWith('\n'));
    });

    test('handles overflow gracefully', () {
      final line = EscPosBuilder.formatLine(
        'Very Long Product Name',
        'x999',
        '99999',
        20,
      );
      // Content > width: falls back to space-separated
      expect(line, contains('Very Long Product Name'));
      expect(line, contains('x999'));
      expect(line, contains('99999'));
    });

    test('handles empty columns', () {
      final line = EscPosBuilder.formatLine('TOTAL', '', 'Rs500', 32);
      expect(line, contains('TOTAL'));
      expect(line, contains('Rs500'));
    });

    test('handles exact width content', () {
      // A + B + C = 10 chars, width = 10
      final line = EscPosBuilder.formatLine('ABCD', 'EF', 'GHIJ', 10);
      expect(line, endsWith('\n'));
    });
  });

  // ───────────────────────────────────────────────
  // PrinterFontSizeMode
  // ───────────────────────────────────────────────
  group('PrinterFontSizeMode', () {
    test('fromValue returns correct modes', () {
      expect(PrinterFontSizeMode.fromValue(0), PrinterFontSizeMode.small);
      expect(PrinterFontSizeMode.fromValue(1), PrinterFontSizeMode.normal);
      expect(PrinterFontSizeMode.fromValue(2), PrinterFontSizeMode.large);
    });

    test('fromValue defaults to normal for unknown values', () {
      expect(PrinterFontSizeMode.fromValue(-1), PrinterFontSizeMode.normal);
      expect(PrinterFontSizeMode.fromValue(99), PrinterFontSizeMode.normal);
    });
  });

  // ───────────────────────────────────────────────
  // PrinterPaperSize
  // ───────────────────────────────────────────────
  group('PrinterPaperSize', () {
    test('58mm has 32 charsPerLine', () {
      expect(PrinterPaperSize.mm58.charsPerLine, equals(32));
    });

    test('80mm has 48 charsPerLine', () {
      expect(PrinterPaperSize.mm80.charsPerLine, equals(48));
    });

    test('fromIndex returns correct paper size', () {
      expect(PrinterPaperSize.fromIndex(0), PrinterPaperSize.mm58);
      expect(PrinterPaperSize.fromIndex(1), PrinterPaperSize.mm80);
    });

    test('fromIndex defaults to valid size for invalid index', () {
      // Out of range indices are clamped by Dart enum indexing
      final result = PrinterPaperSize.fromIndex(-1);
      expect(result, isA<PrinterPaperSize>());
    });

    test('displayName returns readable name', () {
      expect(PrinterPaperSize.mm58.displayName, equals('58mm'));
      expect(PrinterPaperSize.mm80.displayName, equals('80mm'));
    });
  });
}
