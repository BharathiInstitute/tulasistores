/// Tests for Settings Provider — AppSettings, PrinterState, enums, StateNotifiers
///
/// Tests pure data class logic, copyWith, enum conversions, and state transitions.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';

void main() {
  // ── AppSettings ──

  group('AppSettings', () {
    test('defaults are correct', () {
      const settings = AppSettings();
      expect(settings.isDarkMode, isFalse);
      expect(settings.locale, const Locale('en'));
      expect(settings.languageCode, 'en');
      expect(settings.retentionDays, 90);
      expect(settings.autoCleanupEnabled, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const original = AppSettings(isDarkMode: true, languageCode: 'hi');
      final copy = original.copyWith(retentionDays: 365);
      expect(copy.isDarkMode, isTrue);
      expect(copy.languageCode, 'hi');
      expect(copy.retentionDays, 365);
    });

    test('copyWith overrides specified fields', () {
      const settings = AppSettings();
      final copy = settings.copyWith(isDarkMode: true, languageCode: 'te');
      expect(copy.isDarkMode, isTrue);
      expect(copy.languageCode, 'te');
    });

    test('retentionPeriod derives from retentionDays', () {
      const s30 = AppSettings(retentionDays: 30);
      expect(s30.retentionPeriod.days, 30);

      const s90 = AppSettings();
      expect(s90.retentionPeriod.days, 90);

      const s365 = AppSettings(retentionDays: 365);
      expect(s365.retentionPeriod.days, 365);
    });
  });

  // ── AppLanguage enum ──

  group('AppLanguage', () {
    test('has 3 languages', () {
      expect(AppLanguage.values.length, 3);
    });

    test('english has code en', () {
      expect(AppLanguage.english.code, 'en');
      expect(AppLanguage.english.displayName, 'English');
    });

    test('hindi has code hi', () {
      expect(AppLanguage.hindi.code, 'hi');
    });

    test('telugu has code te', () {
      expect(AppLanguage.telugu.code, 'te');
    });

    test('fromCode returns matching language', () {
      expect(AppLanguage.fromCode('en'), AppLanguage.english);
      expect(AppLanguage.fromCode('hi'), AppLanguage.hindi);
      expect(AppLanguage.fromCode('te'), AppLanguage.telugu);
    });

    test('fromCode defaults to english for unknown code', () {
      expect(AppLanguage.fromCode('fr'), AppLanguage.english);
      expect(AppLanguage.fromCode(''), AppLanguage.english);
    });
  });

  // ── PrinterFontSize enum ──

  group('PrinterFontSize', () {
    test('has 3 sizes', () {
      expect(PrinterFontSize.values.length, 3);
    });

    test('small has value 0', () {
      expect(PrinterFontSize.small.value, 0);
      expect(PrinterFontSize.small.label, 'Small');
    });

    test('normal has value 1', () {
      expect(PrinterFontSize.normal.value, 1);
      expect(PrinterFontSize.normal.label, 'Normal');
    });

    test('large has value 2', () {
      expect(PrinterFontSize.large.value, 2);
      expect(PrinterFontSize.large.label, 'Large');
    });

    test('fromValue returns matching size', () {
      expect(PrinterFontSize.fromValue(0), PrinterFontSize.small);
      expect(PrinterFontSize.fromValue(1), PrinterFontSize.normal);
      expect(PrinterFontSize.fromValue(2), PrinterFontSize.large);
    });

    test('fromValue defaults to normal for unknown value', () {
      expect(PrinterFontSize.fromValue(99), PrinterFontSize.normal);
      expect(PrinterFontSize.fromValue(-1), PrinterFontSize.normal);
    });
  });

  // ── PrinterTypeOption enum ──

  group('PrinterTypeOption', () {
    test('has 7 types', () {
      expect(PrinterTypeOption.values.length, 7);
    });

    test('system is not thermal', () {
      expect(PrinterTypeOption.system.isThermal, isFalse);
    });

    test('bluetooth is thermal', () {
      expect(PrinterTypeOption.bluetooth.isThermal, isTrue);
    });

    test('usb is thermal', () {
      expect(PrinterTypeOption.usb.isThermal, isTrue);
    });

    test('wifi is thermal', () {
      expect(PrinterTypeOption.wifi.isThermal, isTrue);
    });

    test('fromString returns matching type', () {
      expect(PrinterTypeOption.fromString('system'), PrinterTypeOption.system);
      expect(
        PrinterTypeOption.fromString('bluetooth'),
        PrinterTypeOption.bluetooth,
      );
      expect(PrinterTypeOption.fromString('usb'), PrinterTypeOption.usb);
      expect(PrinterTypeOption.fromString('wifi'), PrinterTypeOption.wifi);
      expect(PrinterTypeOption.fromString('sunmi'), PrinterTypeOption.sunmi);
      expect(
        PrinterTypeOption.fromString('webBluetooth'),
        PrinterTypeOption.webBluetooth,
      );
      expect(
        PrinterTypeOption.fromString('webSerial'),
        PrinterTypeOption.webSerial,
      );
    });

    test('fromString defaults to system for unknown', () {
      expect(PrinterTypeOption.fromString('unknown'), PrinterTypeOption.system);
      expect(PrinterTypeOption.fromString(''), PrinterTypeOption.system);
    });

    test('all have labels', () {
      for (final type in PrinterTypeOption.values) {
        expect(type.label, isNotEmpty);
      }
    });

    test('all have descriptions', () {
      for (final type in PrinterTypeOption.values) {
        expect(type.description, isNotEmpty);
      }
    });
  });

  // ── PrinterState ──

  group('PrinterState', () {
    test('defaults are correct', () {
      const state = PrinterState();
      expect(state.isConnected, isFalse);
      expect(state.printerName, isNull);
      expect(state.printerAddress, isNull);
      expect(state.paperSizeIndex, 1); // 80mm default
      expect(state.fontSizeIndex, 1); // Normal default
      expect(state.customWidth, 0); // Auto
      expect(state.isScanning, isFalse);
      expect(state.error, isNull);
      expect(state.printerType, PrinterTypeOption.system);
      expect(state.autoPrint, isFalse);
      expect(state.receiptFooter, '');
    });

    test('paperSizeLabel for 58mm', () {
      const state = PrinterState(paperSizeIndex: 0);
      expect(state.paperSizeLabel, '58mm');
    });

    test('paperSizeLabel for 80mm', () {
      const state = PrinterState();
      expect(state.paperSizeLabel, '80mm');
    });

    test('fontSize returns correct enum', () {
      expect(
        const PrinterState(fontSizeIndex: 0).fontSize,
        PrinterFontSize.small,
      );
      expect(const PrinterState().fontSize, PrinterFontSize.normal);
      expect(
        const PrinterState(fontSizeIndex: 2).fontSize,
        PrinterFontSize.large,
      );
    });

    test('effectiveWidth with auto (58mm)', () {
      const state = PrinterState(paperSizeIndex: 0);
      expect(state.effectiveWidth, 32);
    });

    test('effectiveWidth with auto (80mm)', () {
      const state = PrinterState();
      expect(state.effectiveWidth, 48);
    });

    test('effectiveWidth with custom width', () {
      const state = PrinterState(customWidth: 40);
      expect(state.effectiveWidth, 40);
    });

    test('widthLabel with auto', () {
      const state = PrinterState();
      expect(state.widthLabel, 'Auto (48 chars)');
    });

    test('widthLabel with custom', () {
      const state = PrinterState(customWidth: 36);
      expect(state.widthLabel, '36 chars');
    });

    test('copyWith preserves unchanged fields', () {
      const original = PrinterState(
        isConnected: true,
        printerName: 'My Printer',
        paperSizeIndex: 0,
      );
      final copy = original.copyWith(autoPrint: true);
      expect(copy.isConnected, isTrue);
      expect(copy.printerName, 'My Printer');
      expect(copy.paperSizeIndex, 0);
      expect(copy.autoPrint, isTrue);
    });

    test('copyWith clears error when not specified', () {
      final withError = const PrinterState().copyWith(error: 'some error');
      expect(withError.error, 'some error');

      final cleared = withError.copyWith();
      expect(cleared.error, isNull);
    });
  });

  // ── ThemeModeNotifier ──

  group('ThemeModeNotifier', () {
    late ThemeModeNotifier notifier;

    setUp(() {
      notifier = ThemeModeNotifier();
    });

    test('initial mode is system', () {
      expect(notifier.state, ThemeMode.system);
    });

    test('setThemeMode changes mode', () {
      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);
    });

    test('toggleDarkMode from system goes to dark', () {
      notifier.toggleDarkMode();
      expect(notifier.state, ThemeMode.dark);
    });

    test('toggleDarkMode from dark goes to light', () {
      notifier.setThemeMode(ThemeMode.dark);
      notifier.toggleDarkMode();
      expect(notifier.state, ThemeMode.light);
    });

    test('toggleDarkMode from light goes to dark', () {
      notifier.setThemeMode(ThemeMode.light);
      notifier.toggleDarkMode();
      expect(notifier.state, ThemeMode.dark);
    });

    test('isDarkMode returns correct value', () {
      expect(notifier.isDarkMode, isFalse); // system
      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.isDarkMode, isTrue);
      notifier.setThemeMode(ThemeMode.light);
      expect(notifier.isDarkMode, isFalse);
    });
  });

  // ── LanguageNotifier ──

  group('LanguageNotifier', () {
    late LanguageNotifier notifier;

    setUp(() {
      notifier = LanguageNotifier();
    });

    test('initial language is english', () {
      expect(notifier.state, AppLanguage.english);
    });

    test('setLanguage changes language', () {
      notifier.setLanguage(AppLanguage.hindi);
      expect(notifier.state, AppLanguage.hindi);
    });

    test('can set all languages', () {
      for (final lang in AppLanguage.values) {
        notifier.setLanguage(lang);
        expect(notifier.state, lang);
      }
    });
  });
}
