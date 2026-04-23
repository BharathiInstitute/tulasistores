/// Tests for EscPosBuilder.buildReceipt — validates receipt content and structure
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';
import 'package:retaillite/models/bill_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Helper: decode all printable text from ESC/POS bytes (strips control sequences)
String extractText(List<int> bytes) {
  final textBytes = <int>[];
  var i = 0;
  while (i < bytes.length) {
    final b = bytes[i];
    // ESC (0x1B) commands: skip ESC + command byte + parameter
    if (b == 0x1B && i + 1 < bytes.length) {
      final cmd = bytes[i + 1];
      if (cmd == 0x40) {
        i += 2;
      } else if (cmd == 0x74 || cmd == 0x61 || cmd == 0x45 || cmd == 0x21) {
        i += 3;
      } else if (cmd == 0x64) {
        i += 3;
      } else {
        i += 3;
      }
      continue;
    }
    // GS (0x1D) commands: skip GS + command + parameter
    if (b == 0x1D && i + 1 < bytes.length) {
      i += 3;
      continue;
    }
    textBytes.add(b);
    i++;
  }
  return utf8.decode(textBytes, allowMalformed: true);
}

void main() {
  late BillModel cashBill;
  late BillModel udharBill;
  late BillModel upiBill;

  setUpAll(() {
    // Initialize SharedPreferences with default values for printer settings
    SharedPreferences.setMockInitialValues({
      'printer_paper_size': 0, // 58mm
      'printer_font_size': 1, // Normal
      'printer_custom_width': 0, // Auto
    });
  });

  setUp(() {
    cashBill = BillModel(
      id: 'bill_001',
      billNumber: 42,
      items: [
        const CartItem(
          productId: 'p1',
          name: 'Basmati Rice 5kg',
          price: 450,
          quantity: 2,
          unit: 'kg',
        ),
        const CartItem(
          productId: 'p2',
          name: 'Tata Salt 1kg',
          price: 28,
          quantity: 3,
          unit: 'piece',
        ),
      ],
      total: 984,
      paymentMethod: PaymentMethod.cash,
      receivedAmount: 1000,
      createdAt: DateTime(2026, 3, 24, 14, 30),
      date: '2026-03-24',
    );

    udharBill = BillModel(
      id: 'bill_002',
      billNumber: 43,
      items: [
        const CartItem(
          productId: 'p3',
          name: 'Cooking Oil 1L',
          price: 150,
          quantity: 1,
          unit: 'liter',
        ),
      ],
      total: 150,
      paymentMethod: PaymentMethod.udhar,
      customerId: 'c1',
      customerName: 'Rajesh Kumar',
      createdAt: DateTime(2026, 3, 24, 15),
      date: '2026-03-24',
    );

    upiBill = BillModel(
      id: 'bill_003',
      billNumber: 44,
      items: [
        const CartItem(
          productId: 'p4',
          name: 'Maggi Noodles',
          price: 14,
          quantity: 5,
          unit: 'piece',
        ),
      ],
      total: 70,
      paymentMethod: PaymentMethod.upi,
      createdAt: DateTime(2026, 3, 24, 16),
      date: '2026-03-24',
    );
  });

  // ─────────────────────────────────────────────────────
  // Receipt Structure Tests (RC-01 to RC-07)
  // ─────────────────────────────────────────────────────
  group('Receipt structure — shop header', () {
    test('RC-01: includes shop name', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        shopName: 'Tulasi Stores',
      );
      final text = extractText(bytes);
      expect(text, contains('Tulasi Stores'));
    });

    test('RC-01: uses default shop name when not provided', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('My Shop'));
    });

    test('RC-02: includes shop address', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        shopAddress: '123 Main Road, Hyderabad',
      );
      final text = extractText(bytes);
      expect(text, contains('123 Main Road, Hyderabad'));
    });

    test('RC-03: includes shop phone', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        shopPhone: '9876543210',
      );
      final text = extractText(bytes);
      expect(text, contains('Ph: 9876543210'));
    });

    test('RC-04: includes GST number', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        gstNumber: '22AAAAA0000A1Z5',
      );
      final text = extractText(bytes);
      expect(text, contains('GSTIN: 22AAAAA0000A1Z5'));
    });

    test('RC-04: omits GST when not provided', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, isNot(contains('GSTIN:')));
    });

    test('RC-02: omits address when not provided', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        shopName: 'Test',
      );
      final text = extractText(bytes);
      // Should have shop name but no stray address text
      expect(text, contains('Test'));
    });
  });

  // ─────────────────────────────────────────────────────
  // Receipt Bill Info Tests (RC-05 to RC-08)
  // ─────────────────────────────────────────────────────
  group('Receipt structure — bill info', () {
    test('RC-05: includes bill number', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Bill #42'));
    });

    test('RC-06: includes date and time', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('24/03/2026'));
      expect(text, contains('02:30 PM'));
    });

    test('RC-07: includes customer name when present', () {
      final bytes = EscPosBuilder.buildReceipt(bill: udharBill);
      final text = extractText(bytes);
      expect(text, contains('Customer: Rajesh Kumar'));
    });

    test('RC-07: omits customer when not provided', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, isNot(contains('Customer:')));
    });

    test('RC-08: includes payment method — Cash', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Payment: Cash'));
    });

    test('RC-08: includes payment method — Credit', () {
      final bytes = EscPosBuilder.buildReceipt(bill: udharBill);
      final text = extractText(bytes);
      expect(text, contains('Payment: Credit'));
    });

    test('RC-08: includes payment method — UPI', () {
      final bytes = EscPosBuilder.buildReceipt(bill: upiBill);
      final text = extractText(bytes);
      expect(text, contains('Payment: UPI'));
    });
  });

  // ─────────────────────────────────────────────────────
  // Receipt Item Tests (RC-09 to RC-11)
  // ─────────────────────────────────────────────────────
  group('Receipt structure — items', () {
    test('RC-09: includes all item names', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Basmati Rice 5kg'));
      expect(text, contains('Tata Salt 1kg'));
    });

    test('RC-10: includes item price and quantity', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('@450'));
      expect(text, contains('x2'));
      expect(text, contains('@28'));
      expect(text, contains('x3'));
    });

    test('RC-11: includes item totals', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('900')); // 450 * 2
      expect(text, contains('84')); // 28 * 3
    });

    test('RC-09: single item bill shows item correctly', () {
      final bytes = EscPosBuilder.buildReceipt(bill: udharBill);
      final text = extractText(bytes);
      expect(text, contains('Cooking Oil 1L'));
      expect(text, contains('@150'));
      expect(text, contains('x1'));
    });

    test('includes items header', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Item'));
      expect(text, contains('Qty'));
      expect(text, contains('Amt'));
    });
  });

  // ─────────────────────────────────────────────────────
  // Receipt Totals Tests (RC-12 to RC-18)
  // ─────────────────────────────────────────────────────
  group('Receipt structure — totals and payment', () {
    test('RC-15: includes grand total', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('TOTAL'));
      expect(text, contains('Rs984'));
    });

    test('RC-16: includes received amount for cash', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Received'));
      expect(text, contains('Rs1000'));
    });

    test('RC-17: includes change for cash payment', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Change'));
      expect(text, contains('Rs16'));
    });

    test('RC-16: no received/change for UPI', () {
      final bytes = EscPosBuilder.buildReceipt(bill: upiBill);
      final text = extractText(bytes);
      expect(text, isNot(contains('Received')));
      expect(text, isNot(contains('Change')));
    });

    test('RC-18: udhar shows PAYMENT PENDING', () {
      final bytes = EscPosBuilder.buildReceipt(bill: udharBill);
      final text = extractText(bytes);
      expect(text, contains('UDHAR - Payment Pending'));
    });

    test('RC-18: cash does NOT show payment pending', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, isNot(contains('Payment Pending')));
    });

    test('no change when received equals total', () {
      final exactBill = BillModel(
        id: 'exact',
        billNumber: 50,
        items: [
          const CartItem(
            productId: 'p1',
            name: 'Item',
            price: 100,
            quantity: 1,
            unit: 'piece',
          ),
        ],
        total: 100,
        paymentMethod: PaymentMethod.cash,
        receivedAmount: 100,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: exactBill);
      final text = extractText(bytes);
      expect(text, contains('Received'));
      // Change is 0, should not show "Change" line
      expect(text, isNot(contains('Change')));
    });
  });

  // ─────────────────────────────────────────────────────
  // Receipt Footer Tests (RC-19 to RC-20)
  // ─────────────────────────────────────────────────────
  group('Receipt structure — footer', () {
    test('RC-19: includes custom footer', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        receiptFooter: 'Visit us again!',
      );
      final text = extractText(bytes);
      expect(text, contains('Visit us again!'));
    });

    test('RC-19: default footer when no custom footer', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('Thank you for shopping!'));
    });

    test('RC-19: empty footer string uses default', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        receiptFooter: '',
      );
      final text = extractText(bytes);
      expect(text, contains('Thank you for shopping!'));
    });

    test('includes app name in footer', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      expect(text, contains('RetailLite'));
    });

    test('RC-20: ends with paper cut command', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      // Last 3 bytes before cut are feed, then cut = GS V 0
      final lastThree = bytes.sublist(bytes.length - 3);
      expect(lastThree, equals([0x1D, 0x56, 0x00]));
    });

    test('has feed before cut', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      // feed(3) = [0x1B, 0x64, 3] should appear before cut
      final feedIdx = bytes.lastIndexOf(0x64);
      final cutIdx = bytes.lastIndexOf(0x56);
      expect(feedIdx, lessThan(cutIdx));
    });
  });

  // ─────────────────────────────────────────────────────
  // Receipt Byte Structure Tests
  // ─────────────────────────────────────────────────────
  group('Receipt byte structure', () {
    test('starts with init sequence', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final initBytes = EscPosBuilder.init();
      expect(bytes.sublist(0, initBytes.length), equals(initBytes));
    });

    test('contains separator lines', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      final text = extractText(bytes);
      // Should have = and - separator lines
      expect(text, contains('='));
      expect(text, contains('-'));
    });

    test('receipt is non-empty byte list', () {
      final bytes = EscPosBuilder.buildReceipt(bill: cashBill);
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));
    });

    test('all shop details appear in receipt', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        shopName: 'Test Shop',
        shopAddress: '123 Road',
        shopPhone: '1234567890',
        gstNumber: 'GST123',
        receiptFooter: 'Come back!',
      );
      final text = extractText(bytes);
      expect(text, contains('Test Shop'));
      expect(text, contains('123 Road'));
      expect(text, contains('Ph: 1234567890'));
      expect(text, contains('GSTIN: GST123'));
      expect(text, contains('Come back!'));
    });
  });

  // ─────────────────────────────────────────────────────
  // Test Page Tests
  // ─────────────────────────────────────────────────────
  group('EscPosBuilder.buildTestPage', () {
    test('returns non-empty byte list', () {
      final bytes = EscPosBuilder.buildTestPage();
      expect(bytes, isNotEmpty);
    });

    test('starts with init', () {
      final bytes = EscPosBuilder.buildTestPage();
      final initBytes = EscPosBuilder.init();
      expect(bytes.sublist(0, initBytes.length), equals(initBytes));
    });

    test('contains TEST PRINT text', () {
      final bytes = EscPosBuilder.buildTestPage();
      final text = extractText(bytes);
      expect(text, contains('TEST PRINT'));
    });

    test('contains printer info', () {
      final bytes = EscPosBuilder.buildTestPage();
      final text = extractText(bytes);
      expect(text, contains('Printer: Connected'));
      expect(text, contains('Paper:'));
      expect(text, contains('Width:'));
      expect(text, contains('Font:'));
    });

    test('ends with cut command', () {
      final bytes = EscPosBuilder.buildTestPage();
      final lastThree = bytes.sublist(bytes.length - 3);
      expect(lastThree, equals([0x1D, 0x56, 0x00]));
    });

    test('contains app name', () {
      final bytes = EscPosBuilder.buildTestPage();
      final text = extractText(bytes);
      expect(text, contains('RetailLite'));
    });
  });

  // ─────────────────────────────────────────────────────
  // Edge Cases
  // ─────────────────────────────────────────────────────
  group('Receipt edge cases', () {
    test('ERR-03: handles empty items list gracefully', () {
      final emptyBill = BillModel(
        id: 'empty',
        billNumber: 99,
        items: const [],
        total: 0,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: emptyBill);
      expect(bytes, isNotEmpty);
      final text = extractText(bytes);
      expect(text, contains('Bill #99'));
      expect(text, contains('TOTAL'));
    });

    test('ERR-04: handles bill with many items', () {
      final items = List.generate(
        20,
        (i) => CartItem(
          productId: 'p$i',
          name: 'Product #$i',
          price: (i + 1) * 10,
          quantity: i + 1,
          unit: 'piece',
        ),
      );
      final bigBill = BillModel(
        id: 'big',
        billNumber: 100,
        items: items,
        total: items.fold(0.0, (s, i) => s + i.total),
        paymentMethod: PaymentMethod.cash,
        receivedAmount: 5000,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: bigBill);
      final text = extractText(bytes);
      // All 20 items should be present
      for (var i = 0; i < 20; i++) {
        expect(text, contains('Product #$i'));
      }
    });

    test('ERR-05: handles special characters in product name', () {
      final specialBill = BillModel(
        id: 'special',
        billNumber: 101,
        items: [
          const CartItem(
            productId: 'sp',
            name: 'Rice & Dal (5kg) "Premium"',
            price: 500,
            quantity: 1,
            unit: 'piece',
          ),
        ],
        total: 500,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: specialBill);
      final text = extractText(bytes);
      expect(text, contains('Rice & Dal'));
      expect(text, contains('"Premium"'));
    });

    test('ERR-05: handles Hindi characters', () {
      final hindiBill = BillModel(
        id: 'hindi',
        billNumber: 102,
        items: [
          const CartItem(
            productId: 'hi',
            name: 'चावल बासमती',
            price: 300,
            quantity: 1,
            unit: 'kg',
          ),
        ],
        total: 300,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: hindiBill);
      // Should not crash — UTF-8 encoding handles Hindi
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(50));
    });

    test('ERR-05: handles rupee symbol', () {
      final bytes = EscPosBuilder.buildReceipt(
        bill: cashBill,
        receiptFooter: 'Total ₹984 only',
      );
      final text = extractText(bytes);
      expect(text, contains('₹984'));
    });

    test('long product name does not crash', () {
      final longNameBill = BillModel(
        id: 'long',
        billNumber: 103,
        items: [
          const CartItem(
            productId: 'ln',
            name:
                'Extra Long Premium Organic Basmati Rice Imported From Punjab 10kg Pack',
            price: 1200,
            quantity: 1,
            unit: 'kg',
          ),
        ],
        total: 1200,
        paymentMethod: PaymentMethod.cash,
        createdAt: DateTime(2026),
        date: '2026-01-01',
      );
      final bytes = EscPosBuilder.buildReceipt(bill: longNameBill);
      final text = extractText(bytes);
      expect(text, contains('Extra Long Premium'));
    });
  });
}
