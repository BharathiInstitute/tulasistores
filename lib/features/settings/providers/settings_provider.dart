/// Settings providers for app preferences
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/data_retention_service.dart';

/// App settings state
class AppSettings {
  final bool isDarkMode;
  final Locale locale;
  final String languageCode;
  final int retentionDays;
  final bool autoCleanupEnabled;

  const AppSettings({
    this.isDarkMode = false,
    this.locale = const Locale('en'),
    this.languageCode = 'en',
    this.retentionDays = 90,
    this.autoCleanupEnabled = true,
  });

  RetentionPeriod get retentionPeriod =>
      RetentionPeriod.fromDays(retentionDays);

  AppSettings copyWith({
    bool? isDarkMode,
    Locale? locale,
    String? languageCode,
    int? retentionDays,
    bool? autoCleanupEnabled,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      locale: locale ?? this.locale,
      languageCode: languageCode ?? this.languageCode,
      retentionDays: retentionDays ?? this.retentionDays,
      autoCleanupEnabled: autoCleanupEnabled ?? this.autoCleanupEnabled,
    );
  }
}

/// Main settings provider - rebuilds on user change
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((
  ref,
) {
  // Settings reload is triggered by ref.invalidate() from auth provider
  // after login/logout — NOT by watching authNotifierProvider
  // (watching auth causes a provider rebuild cycle that resets auth state).
  return SettingsNotifier();
});

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings()) {
    // Load local cache SYNCHRONOUSLY first to avoid flash of wrong theme
    _loadLocalSync();
    // Then sync from cloud in background
    _loadFromCloud();
  }

  /// Synchronous load from SharedPreferences — instant, no flash
  void _loadLocalSync() {
    try {
      final isDark =
          OfflineStorageService.getSetting<bool>(
            SettingsKeys.isDarkMode,
            defaultValue: false,
          ) ??
          false;

      final langCode =
          OfflineStorageService.getSetting<String>(
            SettingsKeys.language,
            defaultValue: 'en',
          ) ??
          'en';

      final retDays =
          OfflineStorageService.getSetting<int>(
            SettingsKeys.retentionDays,
            defaultValue: 90,
          ) ??
          90;

      final autoCleanup =
          OfflineStorageService.getSetting<bool>(
            SettingsKeys.autoCleanupEnabled,
            defaultValue: true,
          ) ??
          true;

      state = AppSettings(
        isDarkMode: isDark,
        locale: Locale(langCode),
        languageCode: langCode,
        retentionDays: retDays,
        autoCleanupEnabled: autoCleanup,
      );
      debugPrint('✅ Settings loaded instantly from local cache');
    } catch (e) {
      debugPrint('Error loading settings from local cache: $e');
    }
  }

  /// Async cloud fetch — updates if cloud has newer data
  Future<void> _loadFromCloud() async {
    try {
      final cloudData = await OfflineStorageService.loadAllSettingsFromCloud();

      if (cloudData.isNotEmpty) {
        final cloudDark = cloudData[SettingsKeys.isDarkMode] as bool?;
        final cloudLang = cloudData[SettingsKeys.language] as String?;
        final cloudRetention = cloudData[SettingsKeys.retentionDays] as int?;
        final cloudAutoCleanup =
            cloudData[SettingsKeys.autoCleanupEnabled] as bool?;

        if (cloudDark != null || cloudLang != null || cloudRetention != null) {
          final langCode = cloudLang ?? state.languageCode;
          final newState = AppSettings(
            isDarkMode: cloudDark ?? state.isDarkMode,
            locale: Locale(langCode),
            languageCode: langCode,
            retentionDays: cloudRetention ?? state.retentionDays,
            autoCleanupEnabled: cloudAutoCleanup ?? state.autoCleanupEnabled,
          );
          // Only update if different
          if (newState.isDarkMode != state.isDarkMode ||
              newState.languageCode != state.languageCode ||
              newState.retentionDays != state.retentionDays ||
              newState.autoCleanupEnabled != state.autoCleanupEnabled) {
            state = newState;
            debugPrint('✅ Settings updated from cloud');
          }
        }
      }
    } catch (e) {
      debugPrint('Cloud settings load failed: $e');
    }
  }

  /// Reload settings (called on user switch)
  Future<void> reloadSettings() async {
    _loadLocalSync();
    await _loadFromCloud();
  }

  void toggleDarkMode() {
    state = state.copyWith(isDarkMode: !state.isDarkMode);
    OfflineStorageService.saveSetting(
      SettingsKeys.isDarkMode,
      state.isDarkMode,
    );
  }

  void setDarkMode(bool isDark) {
    state = state.copyWith(isDarkMode: isDark);
    OfflineStorageService.saveSetting(SettingsKeys.isDarkMode, isDark);
  }

  void setLanguage(String languageCode) {
    state = state.copyWith(
      languageCode: languageCode,
      locale: Locale(languageCode),
    );
    OfflineStorageService.saveSetting(SettingsKeys.language, languageCode);
  }

  void setRetentionPeriod(RetentionPeriod period) {
    state = state.copyWith(retentionDays: period.days);
    OfflineStorageService.saveSetting(SettingsKeys.retentionDays, period.days);
  }

  void setRetentionDays(int days) {
    state = state.copyWith(retentionDays: days);
    OfflineStorageService.saveSetting(SettingsKeys.retentionDays, days);
  }

  void setAutoCleanup(bool enabled) {
    state = state.copyWith(autoCleanupEnabled: enabled);
    OfflineStorageService.saveSetting(SettingsKeys.autoCleanupEnabled, enabled);
  }
}

/// Language options
enum AppLanguage {
  english('en', 'English'),
  hindi('hi', 'हिंदी'),
  telugu('te', 'తెలుగు');

  final String code;
  final String displayName;

  const AppLanguage(this.code, this.displayName);

  static AppLanguage fromCode(String code) {
    return AppLanguage.values.firstWhere(
      (l) => l.code == code,
      orElse: () => AppLanguage.english,
    );
  }
}

/// Theme mode provider (legacy, use settingsProvider instead)
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system);

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void toggleDarkMode() {
    if (state == ThemeMode.dark) {
      state = ThemeMode.light;
    } else {
      state = ThemeMode.dark;
    }
  }

  bool get isDarkMode => state == ThemeMode.dark;
}

/// Language provider (legacy, use settingsProvider instead)
final languageProvider = StateNotifierProvider<LanguageNotifier, AppLanguage>(
  (ref) => LanguageNotifier(),
);

class LanguageNotifier extends StateNotifier<AppLanguage> {
  LanguageNotifier() : super(AppLanguage.english);

  void setLanguage(AppLanguage language) {
    state = language;
  }
}

/// Printer font size enum
enum PrinterFontSize {
  small(0, 'Small', 'Compact - fits more text'),
  normal(1, 'Normal', 'Default size'),
  large(2, 'Large', 'Easier to read');

  final int value;
  final String label;
  final String description;

  const PrinterFontSize(this.value, this.label, this.description);

  static PrinterFontSize fromValue(int value) {
    return PrinterFontSize.values.firstWhere(
      (f) => f.value == value,
      orElse: () => PrinterFontSize.normal,
    );
  }
}

/// Printer type enum
enum PrinterTypeOption {
  system('System Printer', 'PDF print — select a printer for direct print'),
  bluetooth('Bluetooth', 'Direct ESC/POS via Bluetooth'),
  usb('USB', 'Direct ESC/POS via USB cable'),
  wifi('WiFi', 'Direct ESC/POS via network'),
  sunmi('Sunmi Built-in', 'Built-in printer on Sunmi POS devices'),
  webBluetooth('Web Bluetooth', 'Print via Chrome Web Bluetooth API');

  final String label;
  final String description;
  const PrinterTypeOption(this.label, this.description);

  /// Whether this type uses direct ESC/POS thermal printing
  bool get isThermal => this != system;

  static PrinterTypeOption fromString(String value) {
    return PrinterTypeOption.values.firstWhere(
      (t) => t.name == value,
      orElse: () => PrinterTypeOption.system,
    );
  }
}

/// Receipt language
enum ReceiptLanguage {
  english('English'),
  hindi('हिन्दी');

  final String label;
  const ReceiptLanguage(this.label);

  static ReceiptLanguage fromString(String value) {
    return ReceiptLanguage.values.firstWhere(
      (l) => l.name == value,
      orElse: () => ReceiptLanguage.english,
    );
  }
}

/// Cut mode for thermal paper
enum CutMode {
  fullCut('Full Cut'),
  partialCut('Partial Cut');

  final String label;
  const CutMode(this.label);

  static CutMode fromString(String value) {
    return CutMode.values.firstWhere(
      (c) => c.name == value,
      orElse: () => CutMode.fullCut,
    );
  }
}

/// Printer state
class PrinterState {
  final bool isConnected;
  final String? printerName;
  final String? printerAddress;
  final int paperSizeIndex; // 0 = 58mm, 1 = 80mm
  final int fontSizeIndex; // 0 = Small, 1 = Normal, 2 = Large
  final int customWidth; // 0 = auto, 28-52 = custom chars per line
  final bool isScanning;
  final String? error;
  final PrinterTypeOption printerType;
  final bool autoPrint;
  final String receiptFooter;
  final bool openCashDrawer;
  final int printCopies; // 1-3
  final bool showQrOnReceipt;
  final bool showGstBreakdown;
  final ReceiptLanguage receiptLanguage;
  final bool showLogoOnThermal;
  final CutMode cutMode;
  final bool showCopyLabel;
  final bool showHsnOnReceipt;
  final int printDensity; // 0=Light, 1=Normal, 2=Dark

  const PrinterState({
    this.isConnected = false,
    this.printerName,
    this.printerAddress,
    this.paperSizeIndex = 1, // Default 80mm
    this.fontSizeIndex = 1, // Default Normal
    this.customWidth = 0, // Default auto
    this.isScanning = false,
    this.error,
    this.printerType = PrinterTypeOption.system,
    this.autoPrint = false,
    this.receiptFooter = '',
    this.openCashDrawer = false,
    this.printCopies = 1,
    this.showQrOnReceipt = false,
    this.showGstBreakdown = false,
    this.receiptLanguage = ReceiptLanguage.english,
    this.showLogoOnThermal = false,
    this.cutMode = CutMode.fullCut,
    this.showCopyLabel = false,
    this.showHsnOnReceipt = false,
    this.printDensity = 1,
  });

  String get paperSizeLabel => paperSizeIndex == 0 ? '58mm' : '80mm';

  PrinterFontSize get fontSize => PrinterFontSize.fromValue(fontSizeIndex);

  /// Get effective characters per line
  int get effectiveWidth {
    if (customWidth > 0) return customWidth;
    // Default widths based on paper size
    return paperSizeIndex == 0 ? 32 : 48;
  }

  String get widthLabel {
    if (customWidth > 0) return '$customWidth chars';
    return 'Auto ($effectiveWidth chars)';
  }

  PrinterState copyWith({
    bool? isConnected,
    String? printerName,
    String? printerAddress,
    int? paperSizeIndex,
    int? fontSizeIndex,
    int? customWidth,
    bool? isScanning,
    String? error,
    PrinterTypeOption? printerType,
    bool? autoPrint,
    String? receiptFooter,
    bool? openCashDrawer,
    int? printCopies,
    bool? showQrOnReceipt,
    bool? showGstBreakdown,
    ReceiptLanguage? receiptLanguage,
    bool? showLogoOnThermal,
    CutMode? cutMode,
    bool? showCopyLabel,
    bool? showHsnOnReceipt,
    int? printDensity,
  }) {
    return PrinterState(
      isConnected: isConnected ?? this.isConnected,
      printerName: printerName ?? this.printerName,
      printerAddress: printerAddress ?? this.printerAddress,
      paperSizeIndex: paperSizeIndex ?? this.paperSizeIndex,
      fontSizeIndex: fontSizeIndex ?? this.fontSizeIndex,
      customWidth: customWidth ?? this.customWidth,
      isScanning: isScanning ?? this.isScanning,
      error: error,
      printerType: printerType ?? this.printerType,
      autoPrint: autoPrint ?? this.autoPrint,
      receiptFooter: receiptFooter ?? this.receiptFooter,
      openCashDrawer: openCashDrawer ?? this.openCashDrawer,
      printCopies: printCopies ?? this.printCopies,
      showQrOnReceipt: showQrOnReceipt ?? this.showQrOnReceipt,
      showGstBreakdown: showGstBreakdown ?? this.showGstBreakdown,
      receiptLanguage: receiptLanguage ?? this.receiptLanguage,
      showLogoOnThermal: showLogoOnThermal ?? this.showLogoOnThermal,
      cutMode: cutMode ?? this.cutMode,
      showCopyLabel: showCopyLabel ?? this.showCopyLabel,
      showHsnOnReceipt: showHsnOnReceipt ?? this.showHsnOnReceipt,
      printDensity: printDensity ?? this.printDensity,
    );
  }
}

final printerProvider = StateNotifierProvider<PrinterNotifier, PrinterState>(
  (ref) => PrinterNotifier(),
);

class PrinterNotifier extends StateNotifier<PrinterState> {
  PrinterNotifier() : super(const PrinterState()) {
    _loadSavedPrinter();
  }

  /// Load saved printer from storage
  void _loadSavedPrinter() {
    final savedPrinter = PrinterStorage.getSavedPrinter();
    final paperSize = PrinterStorage.getSavedPaperSize();
    final fontSize = PrinterStorage.getSavedFontSize();
    final customWidth = PrinterStorage.getSavedCustomWidth();
    final autoPrint = PrinterStorage.getAutoPrint();
    final receiptFooter = PrinterStorage.getReceiptFooter();
    final openCashDrawer = PrinterStorage.getOpenCashDrawer();
    final printCopies = PrinterStorage.getPrintCopies();
    final showQrOnReceipt = PrinterStorage.getShowQrOnReceipt();
    final showGstBreakdown = PrinterStorage.getShowGstBreakdown();
    final receiptLanguage = ReceiptLanguage.fromString(
      PrinterStorage.getReceiptLanguage(),
    );
    final showLogoOnThermal = PrinterStorage.getShowLogoOnThermal();
    final cutMode = CutMode.fromString(PrinterStorage.getCutMode());
    final showCopyLabel = PrinterStorage.getShowCopyLabel();
    final showHsnOnReceipt = PrinterStorage.getShowHsnOnReceipt();
    final printerType = PrinterTypeOption.fromString(
      PrinterStorage.getPrinterType(),
    );
    final printDensity = PrinterStorage.getPrintDensity();

    if (savedPrinter != null) {
      state = PrinterState(
        isConnected: true,
        printerName: savedPrinter['name'],
        printerAddress: savedPrinter['address'],
        paperSizeIndex: paperSize,
        fontSizeIndex: fontSize,
        customWidth: customWidth,
        autoPrint: autoPrint,
        receiptFooter: receiptFooter,
        openCashDrawer: openCashDrawer,
        printCopies: printCopies,
        showQrOnReceipt: showQrOnReceipt,
        showGstBreakdown: showGstBreakdown,
        receiptLanguage: receiptLanguage,
        showLogoOnThermal: showLogoOnThermal,
        cutMode: cutMode,
        printerType: printerType,
        showCopyLabel: showCopyLabel,
        showHsnOnReceipt: showHsnOnReceipt,
        printDensity: printDensity,
      );
    } else {
      state = PrinterState(
        paperSizeIndex: paperSize,
        fontSizeIndex: fontSize,
        customWidth: customWidth,
        autoPrint: autoPrint,
        receiptFooter: receiptFooter,
        openCashDrawer: openCashDrawer,
        printCopies: printCopies,
        showQrOnReceipt: showQrOnReceipt,
        showGstBreakdown: showGstBreakdown,
        receiptLanguage: receiptLanguage,
        showLogoOnThermal: showLogoOnThermal,
        cutMode: cutMode,
        printerType: printerType,
        showCopyLabel: showCopyLabel,
        showHsnOnReceipt: showHsnOnReceipt,
        printDensity: printDensity,
      );
    }
  }

  /// Set paper size
  Future<void> setPaperSize(int sizeIndex) async {
    await PrinterStorage.savePaperSize(sizeIndex);
    state = state.copyWith(paperSizeIndex: sizeIndex);
  }

  /// Set font size
  Future<void> setFontSize(int fontSizeIndex) async {
    await PrinterStorage.saveFontSize(fontSizeIndex);
    state = state.copyWith(fontSizeIndex: fontSizeIndex);
  }

  /// Set custom width (0 = auto)
  Future<void> setCustomWidth(int width) async {
    await PrinterStorage.saveCustomWidth(width);
    state = state.copyWith(customWidth: width);
  }

  /// Set print density (0=Light, 1=Normal, 2=Dark)
  Future<void> setPrintDensity(int density) async {
    await PrinterStorage.savePrintDensity(density);
    state = state.copyWith(printDensity: density);
  }

  /// Save and connect to printer
  Future<bool> connectPrinter(String name, String address) async {
    state = state.copyWith(isScanning: true);

    // Save to storage
    await PrinterStorage.savePrinter(name, address);

    state = state.copyWith(
      isConnected: true,
      printerName: name,
      printerAddress: address,
      isScanning: false,
    );

    return true;
  }

  /// Check current connection status
  Future<void> checkConnection() async {
    // This would be called to verify Bluetooth connection
    // For now, we just update state based on saved printer
    final savedPrinter = PrinterStorage.getSavedPrinter();
    if (savedPrinter == null) {
      state = state.copyWith(isConnected: false);
    }
  }

  /// Disconnect and clear saved printer
  Future<void> disconnectPrinter() async {
    await PrinterStorage.clearSavedPrinter();
    state = PrinterState(
      paperSizeIndex: state.paperSizeIndex,
      fontSizeIndex: state.fontSizeIndex,
      customWidth: state.customWidth,
      autoPrint: state.autoPrint,
      receiptFooter: state.receiptFooter,
      openCashDrawer: state.openCashDrawer,
      printCopies: state.printCopies,
      showQrOnReceipt: state.showQrOnReceipt,
      showGstBreakdown: state.showGstBreakdown,
      receiptLanguage: state.receiptLanguage,
      showLogoOnThermal: state.showLogoOnThermal,
      cutMode: state.cutMode,
      printerType: state.printerType,
      printDensity: state.printDensity,
    );
  }

  /// Set printer type
  Future<void> setPrinterType(PrinterTypeOption type) async {
    await PrinterStorage.savePrinterType(type.name);
    state = state.copyWith(printerType: type);
  }

  /// Set auto-print
  Future<void> setAutoPrint(bool autoPrint) async {
    await PrinterStorage.saveAutoPrint(autoPrint);
    state = state.copyWith(autoPrint: autoPrint);
  }

  /// Set receipt footer text
  Future<void> setReceiptFooter(String footer) async {
    await PrinterStorage.saveReceiptFooter(footer);
    state = state.copyWith(receiptFooter: footer);
  }

  /// Set open cash drawer on payment
  Future<void> setOpenCashDrawer(bool open) async {
    await PrinterStorage.saveOpenCashDrawer(open);
    state = state.copyWith(openCashDrawer: open);
  }

  /// Set number of print copies (1-3)
  Future<void> setPrintCopies(int copies) async {
    final clamped = copies.clamp(1, 3);
    await PrinterStorage.savePrintCopies(clamped);
    state = state.copyWith(printCopies: clamped);
  }

  /// Set show QR on receipt
  Future<void> setShowQrOnReceipt(bool show) async {
    await PrinterStorage.saveShowQrOnReceipt(show);
    state = state.copyWith(showQrOnReceipt: show);
  }

  /// Set show GST breakdown on receipt
  Future<void> setShowGstBreakdown(bool show) async {
    await PrinterStorage.saveShowGstBreakdown(show);
    state = state.copyWith(showGstBreakdown: show);
  }

  /// Set receipt language
  Future<void> setReceiptLanguage(ReceiptLanguage lang) async {
    await PrinterStorage.saveReceiptLanguage(lang.name);
    state = state.copyWith(receiptLanguage: lang);
  }

  /// Set show logo on thermal receipt
  Future<void> setShowLogoOnThermal(bool show) async {
    await PrinterStorage.saveShowLogoOnThermal(show);
    state = state.copyWith(showLogoOnThermal: show);
  }

  /// Set cut mode
  Future<void> setCutMode(CutMode mode) async {
    await PrinterStorage.saveCutMode(mode.name);
    state = state.copyWith(cutMode: mode);
  }

  /// Set show copy label (Original/Duplicate)
  Future<void> setShowCopyLabel(bool show) async {
    await PrinterStorage.saveShowCopyLabel(show);
    state = state.copyWith(showCopyLabel: show);
  }

  /// Set show HSN/SAC on receipt
  Future<void> setShowHsnOnReceipt(bool show) async {
    await PrinterStorage.saveShowHsnOnReceipt(show);
    state = state.copyWith(showHsnOnReceipt: show);
  }

  /// Set error state
  void setError(String error) {
    state = state.copyWith(error: error, isScanning: false);
  }

  /// Update connection status (e.g., after checking if USB device is still present)
  void setConnectionStatus(bool connected) {
    state = state.copyWith(isConnected: connected);
  }

  /// Clear error
  void clearError() {
    state = state.copyWith();
  }
}

/// Settings loading state
final settingsLoadingProvider = StateProvider<bool>((ref) => false);
