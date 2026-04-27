/// Hardware Settings Screen - Printer, Barcode, Sync, Preferences
/// Functional printer settings for Bluetooth thermal and system printers
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:retaillite/core/design/app_colors.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/qz_tray_service.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';
import 'package:retaillite/core/services/sunmi_printer_service.dart';
import 'package:retaillite/core/services/web_bluetooth_printer_service.dart';
import 'package:retaillite/core/services/web_serial_printer_service.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';
import 'package:retaillite/core/services/sync_settings_service.dart';
import 'package:retaillite/l10n/app_localizations.dart';
import 'package:retaillite/main.dart' show appVersion, appBuildNumber;

class HardwareSettingsScreen extends ConsumerStatefulWidget {
  const HardwareSettingsScreen({super.key});

  @override
  ConsumerState<HardwareSettingsScreen> createState() =>
      _HardwareSettingsScreenState();
}

class _HardwareSettingsScreenState
    extends ConsumerState<HardwareSettingsScreen> {
  bool _offlineMode = true;
  bool _voiceInput = false;
  bool _isScanning = false;
  List<PrinterDevice> _scannedDevices = [];

  // WiFi printer state
  final _wifiIpController = TextEditingController();
  final _wifiPortController = TextEditingController();
  bool _isWifiConnecting = false;

  // USB printer state (Windows)
  List<String> _windowsPrinters = [];
  bool _isLoadingUsbPrinters = false;

  // System printer state (direct print)
  List<Printer> _systemPrinters = [];
  bool _isLoadingSystemPrinters = false;

  // Web Bluetooth state (web only)
  bool _webBtConnecting = false;
  String? _webBtConnectedName;

  // QZ Tray state (web only) — raw ESC/POS printing that bypasses Chrome dialog
  bool _qzAvailable = false;
  bool _qzEnabled = false;
  bool _qzLoading = false;
  List<String> _qzPrinters = [];
  String? _qzSelectedPrinter;

  final _barcodePrefixController = TextEditingController();
  final _barcodeSuffixController = TextEditingController();
  final _receiptFooterController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _barcodePrefixController.text = PrinterStorage.getBarcodePrefix();
    _barcodeSuffixController.text = PrinterStorage.getBarcodeSuffix();
    _wifiIpController.text = WifiPrinterService.getSavedIp();
    _wifiPortController.text = WifiPrinterService.getSavedPort().toString();

    // Load receipt footer from state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final printerState = ref.read(printerProvider);
      _receiptFooterController.text = printerState.receiptFooter;

      // Load USB printers on Windows
      if (UsbPrinterService.isAvailable) {
        unawaited(_loadWindowsPrinters());
      }

      // Load system printers for direct print
      unawaited(_loadSystemPrinters());

      // Load QZ Tray state (web only)
      if (kIsWeb) {
        unawaited(_refreshQzTray());
      }
    });
  }

  @override
  void dispose() {
    _barcodePrefixController.dispose();
    _barcodeSuffixController.dispose();
    _receiptFooterController.dispose();
    _wifiIpController.dispose();
    _wifiPortController.dispose();
    super.dispose();
  }

  Future<void> _scanBluetoothPrinters() async {
    setState(() {
      _isScanning = true;
      _scannedDevices = [];
    });

    try {
      final permissionOk =
          await ThermalPrinterService.ensureBluetoothPermissions();
      if (!permissionOk) {
        if (mounted) {
          setState(() => _isScanning = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Bluetooth permission denied. Allow Nearby devices and Location to scan printers.',
              ),
            ),
          );
        }
        return;
      }

      final devices = await ThermalPrinterService.getPairedDevices();
      if (mounted) {
        setState(() {
          _scannedDevices = devices;
          _isScanning = false;
        });
        if (devices.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No paired Bluetooth printers found. Pair printer in phone Bluetooth settings, then scan again.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Scan failed: $e')));
      }
    }
  }

  Future<void> _connectToPrinter(PrinterDevice device) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Connecting to ${device.name}...')));

    final permissionOk =
        await ThermalPrinterService.ensureBluetoothPermissions();
    if (!permissionOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bluetooth permission denied. Enable permissions in Android app settings.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    final success = await ThermalPrinterService.connect(device);
    if (success) {
      await ThermalPrinterService.savePrinter(device);
      await ref
          .read(printerProvider.notifier)
          .setPrinterType(PrinterTypeOption.bluetooth);
      await ref
          .read(printerProvider.notifier)
          .connectPrinter(device.name, device.address);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connected to ${device.name}'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to connect'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _disconnectPrinter() async {
    await ThermalPrinterService.disconnect();
    await ref.read(printerProvider.notifier).disconnectPrinter();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Printer disconnected')));
    }
  }

  Future<void> _testPrint() async {
    final printerState = ref.read(printerProvider);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    switch (printerState.printerType) {
      case PrinterTypeOption.bluetooth:
        final connected = await ThermalPrinterService.isConnected;
        if (!connected) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('No Bluetooth printer connected')),
          );
          return;
        }
        final success = await ThermalPrinterService.printTestPage();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(success ? 'Test print sent!' : 'Print failed'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.wifi:
        if (!WifiPrinterService.isConnected) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('No WiFi printer connected')),
          );
          return;
        }
        final success = await WifiPrinterService.printTestPage();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(success ? 'Test print sent!' : 'Print failed'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.usb:
        final usbName = UsbPrinterService.getSavedPrinterName();
        if (usbName.isEmpty) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('No USB printer selected')),
          );
          return;
        }
        final success = await UsbPrinterService.printTestPage(usbName);
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(success ? 'Test print sent!' : 'Print failed'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.sunmi:
        final sunmiAvailable = await SunmiPrinterService.isAvailable;
        if (!sunmiAvailable) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Sunmi printer not available')),
          );
          return;
        }
        final sunmiSuccess = await SunmiPrinterService.printTestPage();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(sunmiSuccess ? 'Test print sent!' : 'Print failed'),
            backgroundColor: sunmiSuccess ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.webBluetooth:
        if (!WebBluetoothPrinterService.isSupported) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Web Bluetooth not supported in this browser'),
            ),
          );
          return;
        }
        final wbSuccess = await WebBluetoothPrinterService.printTestPage();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(wbSuccess ? 'Test print sent!' : 'Print failed'),
            backgroundColor: wbSuccess ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.webSerial:
        if (!WebSerialPrinterService.isConnected) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('No USB port connected')),
          );
          return;
        }
        final wsSuccess = await WebSerialPrinterService.printTestPage();
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text(wsSuccess ? 'Test print sent!' : 'Print failed'),
            backgroundColor: wsSuccess ? AppColors.success : AppColors.error,
          ),
        );
        break;

      case PrinterTypeOption.system:
        final sysName = PrinterStorage.getSystemPrinterName();
        final sysUrl = PrinterStorage.getSystemPrinterUrl();
        if (sysName.isNotEmpty && sysUrl.isNotEmpty) {
          final printer = Printer(url: sysUrl, name: sysName);
          final testPdf = pw.Document();
          testPdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.roll80,
              build: (ctx) => pw.Column(
                children: [
                  pw.Text(
                    'Test Print',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('Direct print is working!'),
                  pw.Text('Printer: $sysName'),
                ],
              ),
            ),
          );
          final ok = await Printing.directPrintPdf(
            printer: printer,
            onLayout: (_) => testPdf.save(),
          );
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(
                ok ? 'Test print sent to $sysName!' : 'Print failed',
              ),
              backgroundColor: ok ? AppColors.success : AppColors.error,
            ),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text(
                'No printer selected — select one above for direct print',
              ),
            ),
          );
        }
        break;
    }
  }

  // ─── WiFi Printer Methods ───

  Future<void> _connectWifiPrinter() async {
    final ip = _wifiIpController.text.trim();
    final port = int.tryParse(_wifiPortController.text.trim()) ?? 9100;

    if (ip.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a printer IP address')),
      );
      return;
    }

    setState(() => _isWifiConnecting = true);

    final success = await WifiPrinterService.connect(ip, port);

    if (success) {
      await WifiPrinterService.saveWifiPrinter(ip, port);
      unawaited(
        ref
            .read(printerProvider.notifier)
            .connectPrinter('WiFi Printer', '$ip:$port'),
      );
    }

    if (mounted) {
      setState(() => _isWifiConnecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Connected to $ip:$port'
                : 'Failed to connect to $ip:$port',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _disconnectWifiPrinter() async {
    await WifiPrinterService.disconnect();
    await ref.read(printerProvider.notifier).disconnectPrinter();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WiFi printer disconnected')),
      );
    }
  }

  // ─── USB Printer Methods (Windows) ───

  Future<void> _loadWindowsPrinters() async {
    setState(() => _isLoadingUsbPrinters = true);
    final printers = await UsbPrinterService.getWindowsPrinters();
    if (mounted) {
      setState(() {
        _windowsPrinters = printers;
        _isLoadingUsbPrinters = false;
      });
    }
  }

  Future<void> _selectUsbPrinter(String name) async {
    await UsbPrinterService.saveUsbPrinter(name);
    await ref.read(printerProvider.notifier).connectPrinter('USB: $name', name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected USB printer: $name'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  // ─── System Printer Methods (Direct Print) ───

  Future<void> _loadSystemPrinters() async {
    setState(() => _isLoadingSystemPrinters = true);
    try {
      final printers = await Printing.listPrinters();
      if (mounted) {
        setState(() {
          _systemPrinters = printers;
          _isLoadingSystemPrinters = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSystemPrinters = false);
      }
    }
  }

  Future<void> _selectSystemPrinter(Printer printer) async {
    await PrinterStorage.saveSystemPrinter(printer.name, printer.url);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Direct print set to: ${printer.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _clearSystemPrinter() async {
    await PrinterStorage.clearSystemPrinter();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Direct print disabled — will use print dialog'),
        ),
      );
    }
  }

  // ─── QZ Tray (web-only raw ESC/POS print — bypasses Chrome dialog) ───

  Future<void> _refreshQzTray() async {
    setState(() => _qzLoading = true);
    final avail = await QzTrayService.isAvailable();
    final enabled = await QzTrayService.isEnabled();
    final selected = await QzTrayService.getSelectedPrinter();
    final printers = avail ? await QzTrayService.listPrinters() : <String>[];
    if (!mounted) return;
    setState(() {
      _qzAvailable = avail;
      _qzEnabled = enabled;
      _qzSelectedPrinter = selected;
      _qzPrinters = printers;
      _qzLoading = false;
    });
  }

  Future<void> _toggleQzEnabled(bool v) async {
    await QzTrayService.setEnabled(v);
    if (mounted) setState(() => _qzEnabled = v);
  }

  Future<void> _selectQzPrinter(String? name) async {
    if (name == null) return;
    await QzTrayService.setSelectedPrinter(name);
    if (mounted) setState(() => _qzSelectedPrinter = name);
  }

  Future<void> _testQzPrint() async {
    final name = _qzSelectedPrinter;
    if (name == null) return;
    final bytes = <int>[
      0x1B, 0x40, // init
      0x1B, 0x61, 0x01, // center
      ...'Tulasi Stores\n'.codeUnits,
      ...'QZ Tray test print\n'.codeUnits,
      ...'Width + orientation OK\n\n\n'.codeUnits,
      0x1D, 0x56, 0x01, // partial cut
    ];
    final ok = await QzTrayService.printRaw(
      printerName: name,
      data: Uint8List.fromList(bytes),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Test sent to $name' : 'Test print failed'),
        backgroundColor: ok ? AppColors.success : AppColors.error,
      ),
    );
  }

  Widget _buildSetupStep(ThemeData theme, String number, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8, top: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQzTrayCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _qzAvailable ? Icons.check_circle : Icons.cancel,
                  color: _qzAvailable ? AppColors.success : AppColors.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Silent Print (QZ Tray)',
                  style: theme.textTheme.titleSmall,
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Re-check',
                  icon: _qzLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  onPressed: _qzLoading ? null : _refreshQzTray,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _qzAvailable
                  ? 'Bypasses Chrome print dialog — prints receipts directly '
                        'to the thermal printer with correct size and '
                        'orientation. No per-browser setup needed.'
                  : 'Not detected on this PC. Download and run the setup '
                        'script below — it installs QZ Tray and trusts the '
                        'certificate automatically (free, one-time).',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),
            if (!_qzAvailable) ...[
              // Download the one-click setup .bat (served from the web build)
              FilledButton.icon(
                icon: const Icon(Icons.download, size: 16),
                label: const Text('Download Print Setup (one-click .bat)'),
                onPressed: () {
                  // Direct Firebase Storage URL — always available, no web build required
                  const url =
                      'https://firebasestorage.googleapis.com/v0/b/'
                      'login-radha.firebasestorage.app/o/'
                      'downloads%2Fqz-tray-setup.bat?alt=media';
                  // ignore: deprecated_member_use
                  launchUrl(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
              const SizedBox(height: 10),
              // Numbered steps guide
              _buildSetupStep(
                theme,
                '1',
                'Click the button above — your browser downloads qz-tray-setup.bat',
              ),
              _buildSetupStep(
                theme,
                '2',
                'Double-click the downloaded file to run it',
              ),
              _buildSetupStep(
                theme,
                '3',
                'The script installs QZ Tray (if needed) and trusts its certificate automatically',
              ),
              _buildSetupStep(
                theme,
                '4',
                'Come back here and click the ↻ refresh button above',
              ),
              const SizedBox(height: 6),
              // Manual fallback for advanced users
              TextButton.icon(
                icon: const Icon(Icons.security_outlined, size: 14),
                label: const Text(
                  'Manual cert trust (if script doesn\'t work)',
                ),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.outline,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                onPressed: () {
                  // ignore: deprecated_member_use
                  launchUrl(
                    Uri.parse('https://localhost:8182'),
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
            ],
            if (_qzAvailable) ...[
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Use QZ Tray for receipt printing'),
                subtitle: const Text(
                  'Silent, correctly-sized print. Falls back to print dialog '
                  'if QZ Tray is unreachable.',
                ),
                value: _qzEnabled,
                onChanged: _toggleQzEnabled,
              ),
              if (_qzEnabled) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Thermal printer',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  initialValue: _qzPrinters.contains(_qzSelectedPrinter)
                      ? _qzSelectedPrinter
                      : null,
                  items: _qzPrinters
                      .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                      .toList(),
                  onChanged: _selectQzPrinter,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Test print'),
                  onPressed: _qzSelectedPrinter == null ? null : _testQzPrint,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final printerState = ref.watch(printerProvider);
    final syncInterval = SyncSettingsService.getSyncInterval();

    return Scaffold(
      appBar: AppBar(title: const Text('Hardware Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Printer Section
          _buildSectionHeader(theme, l10n.printer),
          _buildPrinterTypeCard(theme, printerState),
          const SizedBox(height: 16),
          if (kIsWeb) ...[_buildQzTrayCard(theme), const SizedBox(height: 16)],
          if (printerState.printerType == PrinterTypeOption.system)
            _buildSystemPrinterSection(theme),
          if (printerState.printerType == PrinterTypeOption.bluetooth)
            _buildBluetoothSection(theme, printerState),
          if (printerState.printerType == PrinterTypeOption.wifi)
            _buildWifiSection(theme),
          if (printerState.printerType == PrinterTypeOption.usb)
            _buildUsbSection(theme),
          if (printerState.printerType == PrinterTypeOption.webBluetooth)
            _buildWebBluetoothSection(theme),
          _buildPaperSettingsCard(theme, printerState),
          const SizedBox(height: 16),
          _buildReceiptSettingsCard(theme, printerState),
          const SizedBox(height: 24),

          // Barcode Scanner Section
          _buildSectionHeader(theme, 'Barcode Scanner'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _barcodePrefixController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode Prefix',
                      hintText: 'Optional prefix',
                    ),
                    onChanged: (v) => PrinterStorage.saveBarcodePrefix(v),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _barcodeSuffixController,
                    decoration: const InputDecoration(
                      labelText: 'Barcode Suffix',
                      hintText: 'Optional suffix',
                    ),
                    onChanged: (v) => PrinterStorage.saveBarcodeSuffix(v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add prefix/suffix to barcode input for scanner compatibility',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Sync Section
          _buildSectionHeader(theme, l10n.sync),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync),
                  title: Text(l10n.syncInterval),
                  trailing: DropdownButton<SyncInterval>(
                    value: syncInterval,
                    underline: const SizedBox(),
                    onChanged: (v) {
                      if (v != null) {
                        SyncSettingsService.setSyncInterval(v);
                        setState(() {});
                      }
                    },
                    items: SyncInterval.values.map((interval) {
                      return DropdownMenuItem(
                        value: interval,
                        child: Text(interval.displayName),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_delete),
                  title: Text(l10n.dataRetention),
                  trailing: DropdownButton<int>(
                    value: settings.retentionDays,
                    underline: const SizedBox(),
                    onChanged: (v) {
                      if (v != null) {
                        ref.read(settingsProvider.notifier).setRetentionDays(v);
                      }
                    },
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 days')),
                      DropdownMenuItem(value: 60, child: Text('60 days')),
                      DropdownMenuItem(value: 90, child: Text('90 days')),
                      DropdownMenuItem(value: 180, child: Text('180 days')),
                      DropdownMenuItem(value: 365, child: Text('1 year')),
                      DropdownMenuItem(value: -1, child: Text('Keep forever')),
                    ],
                  ),
                ),
                if (settings.retentionDays == -1)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 8,
                      left: 16,
                      right: 16,
                      bottom: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'High storage usage — data will never be auto-deleted',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App Preferences Section
          _buildSectionHeader(theme, 'App Preferences'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.wifi_off),
                  title: const Text('Offline Mode'),
                  subtitle: const Text('Continue billing when offline'),
                  value: _offlineMode,
                  onChanged: (v) => setState(() => _offlineMode = v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.mic),
                  title: const Text('Voice Input'),
                  subtitle: Row(
                    children: [
                      const Text('Voice search for products'),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'BETA',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  value: _voiceInput,
                  onChanged: (v) => setState(() => _voiceInput = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // App Version
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Text(
                'v$appVersion+$appBuildNumber',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Printer Type Card ───
  Widget _buildPrinterTypeCard(ThemeData theme, PrinterState printerState) {
    final showBluetooth = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
    const showWifi = !kIsWeb;
    final showUsb = !kIsWeb && Platform.isWindows;
    final showSunmi = !kIsWeb && Platform.isAndroid;
    const showWebBluetooth = kIsWeb;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Printer Type', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(
              'Choose how to connect your printer for direct ESC/POS printing.',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 12),

            _buildPrinterTypeOption(
              theme,
              PrinterTypeOption.system,
              printerState.printerType,
              Icons.computer,
            ),
            if (showBluetooth) ...[
              const SizedBox(height: 8),
              _buildPrinterTypeOption(
                theme,
                PrinterTypeOption.bluetooth,
                printerState.printerType,
                Icons.bluetooth,
              ),
            ],
            if (showWifi) ...[
              const SizedBox(height: 8),
              _buildPrinterTypeOption(
                theme,
                PrinterTypeOption.wifi,
                printerState.printerType,
                Icons.wifi,
              ),
            ],
            if (showUsb) ...[
              const SizedBox(height: 8),
              _buildPrinterTypeOption(
                theme,
                PrinterTypeOption.usb,
                printerState.printerType,
                Icons.usb,
              ),
            ],
            if (showSunmi) ...[
              const SizedBox(height: 8),
              _buildPrinterTypeOption(
                theme,
                PrinterTypeOption.sunmi,
                printerState.printerType,
                Icons.point_of_sale,
              ),
            ],
            if (showWebBluetooth) ...[
              const SizedBox(height: 8),
              _buildPrinterTypeOption(
                theme,
                PrinterTypeOption.webBluetooth,
                printerState.printerType,
                Icons.bluetooth_connected,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterTypeOption(
    ThemeData theme,
    PrinterTypeOption option,
    PrinterTypeOption selected,
    IconData icon,
  ) {
    final isSelected = option == selected;
    return InkWell(
      onTap: () {
        ref.read(printerProvider.notifier).setPrinterType(option);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.iconTheme.color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                  ),
                  Text(
                    option.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }

  // ─── Bluetooth Section ───
  // ─── Web Bluetooth Section (Chrome on Android/Desktop) ───
  Widget _buildWebBluetoothSection(ThemeData theme) {
    final isConnected = WebBluetoothPrinterService.isConnected;
    final isSupported = WebBluetoothPrinterService.isSupported;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Setup instructions
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chrome Bluetooth setup',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '1) Make sure printer is powered on & discoverable\n'
                        '2) Tap "Select Printer" — Chrome will show a device picker\n'
                        '3) Choose your thermal printer from the list\n'
                        '4) Use "Test Print" to verify\n\n'
                        'Note: Requires Chrome on Android/Desktop over HTTPS.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (!isSupported)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: AppColors.error),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Web Bluetooth is not supported in this browser. '
                            'Use Chrome on Android or Chrome on desktop.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (isSupported) ...[
                  // Connection status row
                  Row(
                    children: [
                      Icon(
                        Icons.bluetooth_connected,
                        color: isConnected ? AppColors.success : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _webBtConnectedName ??
                                  (isConnected
                                      ? 'Printer connected'
                                      : 'No printer selected'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              isConnected ? 'Ready to print' : 'Tap Select Printer',
                              style: TextStyle(
                                fontSize: 12,
                                color: isConnected
                                    ? AppColors.success
                                    : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? AppColors.success : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _webBtConnecting
                              ? null
                              : () async {
                                  setState(() => _webBtConnecting = true);
                                  try {
                                    final ok =
                                        await WebBluetoothPrinterService
                                            .connect();
                                    if (ok) {
                                      await ref
                                          .read(printerProvider.notifier)
                                          .setPrinterType(
                                            PrinterTypeOption.webBluetooth,
                                          );
                                      if (mounted) {
                                        setState(
                                          () => _webBtConnectedName =
                                              'Bluetooth Printer',
                                        );
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Printer connected!',
                                            ),
                                            backgroundColor: AppColors.success,
                                          ),
                                        );
                                      }
                                    } else {
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Could not connect. Make sure the printer is on and in range.',
                                            ),
                                            backgroundColor: AppColors.error,
                                          ),
                                        );
                                      }
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _webBtConnecting = false);
                                    }
                                  }
                                },
                          icon: _webBtConnecting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.bluetooth_searching),
                          label: Text(
                            _webBtConnecting
                                ? 'Connecting…'
                                : 'Select Printer',
                          ),
                        ),
                      ),
                      if (isConnected) ...[
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            WebBluetoothPrinterService.disconnect();
                            setState(() => _webBtConnectedName = null);
                          },
                          icon: const Icon(Icons.link_off),
                          label: const Text('Disconnect'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Android Bluetooth Section ───
  Widget _buildBluetoothSection(ThemeData theme, PrinterState printerState) {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Android Bluetooth setup',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '1) Pair printer in phone Bluetooth settings\n2) Tap Scan Printers\n3) Tap link icon to connect\n4) Use Test Print',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: openAppSettings,
                        icon: const Icon(Icons.settings),
                        label: const Text('Open App Settings'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Connection status
                Row(
                  children: [
                    Icon(
                      Icons.bluetooth,
                      color: printerState.isConnected
                          ? AppColors.success
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            printerState.printerName ?? 'No Printer',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            printerState.isConnected
                                ? 'Connected'
                                : 'Not connected',
                            style: TextStyle(
                              fontSize: 12,
                              color: printerState.isConnected
                                  ? AppColors.success
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: printerState.isConnected
                            ? AppColors.success
                            : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Scan / Disconnect buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isScanning ? null : _scanBluetoothPrinters,
                        icon: _isScanning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.search),
                        label: Text(
                          _isScanning ? 'Scanning...' : 'Scan Printers',
                        ),
                      ),
                    ),
                    if (printerState.isConnected) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _disconnectPrinter,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),

                // Scanned devices list
                if (_scannedDevices.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Found Devices:', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ..._scannedDevices.map(
                    (device) => ListTile(
                      leading: const Icon(Icons.print),
                      title: Text(device.name),
                      subtitle: Text(
                        device.address,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.link, color: AppColors.success),
                        onPressed: () => _connectToPrinter(device),
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── WiFi Printer Section ───
  Widget _buildWifiSection(ThemeData theme) {
    final isConnected = WifiPrinterService.isConnected;

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status
                Row(
                  children: [
                    Icon(
                      Icons.wifi,
                      color: isConnected ? AppColors.success : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isConnected
                                ? 'Connected: ${WifiPrinterService.connectedAddress}'
                                : 'WiFi Thermal Printer',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            isConnected
                                ? 'Connected'
                                : 'Enter printer IP and port (default: 9100)',
                            style: TextStyle(
                              fontSize: 12,
                              color: isConnected
                                  ? AppColors.success
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? AppColors.success : Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // IP + Port input
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _wifiIpController,
                        decoration: const InputDecoration(
                          labelText: 'IP Address',
                          hintText: '192.168.1.100',
                          isDense: true,
                          prefixIcon: Icon(Icons.router, size: 20),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _wifiPortController,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          hintText: '9100',
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Connect / Disconnect
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isWifiConnecting
                            ? null
                            : _connectWifiPrinter,
                        icon: _isWifiConnecting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.link),
                        label: Text(
                          _isWifiConnecting ? 'Connecting...' : 'Connect',
                        ),
                      ),
                    ),
                    if (isConnected) ...[
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _disconnectWifiPrinter,
                        icon: const Icon(Icons.link_off),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── System Printer Section (Direct Print) ───
  Widget _buildSystemPrinterSection(ThemeData theme) {
    final savedName = PrinterStorage.getSystemPrinterName();

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.print,
                      color: savedName.isNotEmpty
                          ? AppColors.success
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            savedName.isNotEmpty
                                ? savedName
                                : 'No printer selected',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            savedName.isNotEmpty
                                ? 'Direct print enabled (no dialog)'
                                : 'Select a printer to print directly',
                            style: TextStyle(
                              fontSize: 12,
                              color: savedName.isNotEmpty
                                  ? AppColors.success
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (savedName.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: _clearSystemPrinter,
                        tooltip: 'Use print dialog instead',
                      ),
                    IconButton(
                      icon: _isLoadingSystemPrinters
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isLoadingSystemPrinters
                          ? null
                          : _loadSystemPrinters,
                      tooltip: 'Refresh printer list',
                    ),
                  ],
                ),

                if (_systemPrinters.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Select printer for direct print:',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ..._systemPrinters.map(
                    (printer) => ListTile(
                      leading: Icon(
                        printer.isDefault ? Icons.star : Icons.print,
                        color: printer.name == savedName
                            ? AppColors.success
                            : null,
                      ),
                      title: Text(printer.name),
                      subtitle: printer.isDefault
                          ? const Text(
                              'Default',
                              style: TextStyle(fontSize: 11),
                            )
                          : null,
                      trailing: printer.name == savedName
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            )
                          : TextButton(
                              onPressed: () => _selectSystemPrinter(printer),
                              child: const Text('Select'),
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ] else if (!_isLoadingSystemPrinters) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No printers found. Click refresh to scan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── USB Printer Section (Windows) ───
  Widget _buildUsbSection(ThemeData theme) {
    final savedName = UsbPrinterService.getSavedPrinterName();

    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.usb,
                      color: savedName.isNotEmpty
                          ? AppColors.success
                          : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            savedName.isNotEmpty
                                ? 'USB: $savedName'
                                : 'USB Thermal Printer',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            savedName.isNotEmpty
                                ? 'Selected'
                                : 'Select a printer from the list below',
                            style: TextStyle(
                              fontSize: 12,
                              color: savedName.isNotEmpty
                                  ? AppColors.success
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isLoadingUsbPrinters
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      onPressed: _isLoadingUsbPrinters
                          ? null
                          : _loadWindowsPrinters,
                      tooltip: 'Refresh printer list',
                    ),
                  ],
                ),

                if (_windowsPrinters.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    'Available Printers:',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  ..._windowsPrinters.map(
                    (name) => ListTile(
                      leading: Icon(
                        Icons.print,
                        color: name == savedName ? AppColors.success : null,
                      ),
                      title: Text(name),
                      trailing: name == savedName
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.success,
                            )
                          : TextButton(
                              onPressed: () => _selectUsbPrinter(name),
                              child: const Text('Select'),
                            ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ] else if (!_isLoadingUsbPrinters) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      'No printers found. Click refresh to scan.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Paper Settings Card ───
  Widget _buildPaperSettingsCard(ThemeData theme, PrinterState printerState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paper & Font', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),

            // Paper size
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.straighten, size: 20),
                const SizedBox(width: 12),
                const Text('Paper Size'),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('58mm')),
                    ButtonSegment(value: 1, label: Text('80mm')),
                  ],
                  selected: {printerState.paperSizeIndex},
                  onSelectionChanged: (set) {
                    ref.read(printerProvider.notifier).setPaperSize(set.first);
                  },
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Font size
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.text_fields, size: 20),
                const SizedBox(width: 12),
                const Text('Font Size'),
                const Spacer(),
                SegmentedButton<int>(
                  segments: PrinterFontSize.values
                      .map(
                        (f) =>
                            ButtonSegment(value: f.value, label: Text(f.label)),
                      )
                      .toList(),
                  selected: {printerState.fontSizeIndex},
                  onSelectionChanged: (set) {
                    ref.read(printerProvider.notifier).setFontSize(set.first);
                  },
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Custom width
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.width_normal, size: 20),
                const SizedBox(width: 12),
                Text('Width: ${printerState.widthLabel}'),
              ],
            ),
            Slider(
              value: printerState.customWidth.toDouble(),
              max: 52,
              divisions: 52,
              label: printerState.customWidth == 0
                  ? 'Auto'
                  : '${printerState.customWidth}',
              onChanged: (v) {
                ref.read(printerProvider.notifier).setCustomWidth(v.toInt());
              },
            ),
            const SizedBox(height: 4),

            // Print copies
            Row(
              children: [
                const SizedBox(width: 4),
                const Icon(Icons.copy_all, size: 20),
                const SizedBox(width: 12),
                const Text('Copies'),
                const Spacer(),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2, label: Text('2')),
                    ButtonSegment(value: 3, label: Text('3')),
                  ],
                  selected: {printerState.printCopies},
                  onSelectionChanged: (set) {
                    ref
                        .read(printerProvider.notifier)
                        .setPrintCopies(set.first);
                  },
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Test Print button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testPrint,
                icon: const Icon(Icons.print),
                label: const Text('Test Print'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Receipt Settings Card ───
  Widget _buildReceiptSettingsCard(ThemeData theme, PrinterState printerState) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Receipt Settings', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),

            // Auto-print toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.autorenew),
              title: const Text('Auto-Print'),
              subtitle: const Text(
                'Print receipt automatically after bill completion',
              ),
              value: printerState.autoPrint,
              onChanged: (v) {
                ref.read(printerProvider.notifier).setAutoPrint(v);
              },
            ),
            const Divider(),

            // Open cash drawer on payment
            if (printerState.printerType.isThermal) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.point_of_sale),
                title: const Text('Open Cash Drawer'),
                subtitle: const Text(
                  'Automatically open cash drawer after payment',
                ),
                value: printerState.openCashDrawer,
                onChanged: (v) {
                  ref.read(printerProvider.notifier).setOpenCashDrawer(v);
                },
              ),
              const Divider(),
            ],

            // UPI QR on receipt
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.qr_code),
              title: const Text('UPI QR on Receipt'),
              subtitle: const Text('Print UPI payment QR code on receipt'),
              value: printerState.showQrOnReceipt,
              onChanged: (v) {
                ref.read(printerProvider.notifier).setShowQrOnReceipt(v);
              },
            ),

            // GST breakdown on receipt
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.receipt_long),
              title: const Text('GST Breakdown'),
              subtitle: const Text('Show CGST/SGST split on receipt'),
              value: printerState.showGstBreakdown,
              onChanged: (v) {
                ref.read(printerProvider.notifier).setShowGstBreakdown(v);
              },
            ),

            // Receipt language
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.language),
              title: const Text('Receipt Language'),
              trailing: SegmentedButton<ReceiptLanguage>(
                segments: ReceiptLanguage.values
                    .map((l) => ButtonSegment(value: l, label: Text(l.label)))
                    .toList(),
                selected: {printerState.receiptLanguage},
                onSelectionChanged: (s) {
                  ref
                      .read(printerProvider.notifier)
                      .setReceiptLanguage(s.first);
                },
              ),
            ),

            // Logo on thermal receipt
            if (printerState.printerType.isThermal)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.image),
                title: const Text('Logo on Receipt'),
                subtitle: const Text('Print shop logo on thermal receipts'),
                value: printerState.showLogoOnThermal,
                onChanged: (v) {
                  ref.read(printerProvider.notifier).setShowLogoOnThermal(v);
                },
              ),

            // Copy label (Original/Duplicate)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.copy),
              title: const Text('Original/Duplicate Label'),
              subtitle: const Text(
                'Mark copies as ORIGINAL or DUPLICATE when printing multiple',
              ),
              value: printerState.showCopyLabel,
              onChanged: (v) {
                ref.read(printerProvider.notifier).setShowCopyLabel(v);
              },
            ),

            // HSN/SAC code on receipt
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.tag),
              title: const Text('HSN/SAC Code on Receipt'),
              subtitle: const Text(
                'Show HSN/SAC code below each item on receipts',
              ),
              value: printerState.showHsnOnReceipt,
              onChanged: (v) {
                ref.read(printerProvider.notifier).setShowHsnOnReceipt(v);
              },
            ),

            // Cut mode
            if (printerState.printerType.isThermal)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.content_cut),
                title: const Text('Paper Cut'),
                trailing: SegmentedButton<CutMode>(
                  segments: CutMode.values
                      .map((c) => ButtonSegment(value: c, label: Text(c.label)))
                      .toList(),
                  selected: {printerState.cutMode},
                  onSelectionChanged: (s) {
                    ref.read(printerProvider.notifier).setCutMode(s.first);
                  },
                ),
              ),
            const Divider(),

            // Receipt footer
            TextField(
              controller: _receiptFooterController,
              decoration: const InputDecoration(
                labelText: 'Receipt Footer',
                hintText: 'e.g. Thank you for shopping!',
                helperText: 'Custom text at the bottom of receipts',
              ),
              onChanged: (v) {
                ref.read(printerProvider.notifier).setReceiptFooter(v);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
