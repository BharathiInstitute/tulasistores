import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';
import 'package:retaillite/features/settings/providers/theme_settings_provider.dart';
import 'package:retaillite/models/theme_settings_model.dart';
import 'package:retaillite/core/services/sync_settings_service.dart';
import 'package:retaillite/core/services/image_service.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/services/privacy_consent_service.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:retaillite/core/services/payment_link_service.dart';
import 'package:retaillite/core/services/thermal_printer_service.dart';
import 'package:retaillite/core/services/qz_tray_service.dart';
import 'package:retaillite/main.dart' show appVersion, appBuildNumber;
import 'package:url_launcher/url_launcher.dart';
import 'package:retaillite/router/app_router.dart';
import 'package:retaillite/shared/widgets/shop_logo_widget.dart';

/// Settings tab enum
enum SettingsTab { general, account, hardware, billing }

class SettingsWebScreen extends ConsumerStatefulWidget {
  final String initialTab;

  const SettingsWebScreen({super.key, this.initialTab = 'general'});

  @override
  ConsumerState<SettingsWebScreen> createState() => _SettingsWebScreenState();
}

class _SettingsWebScreenState extends ConsumerState<SettingsWebScreen> {
  // Text controllers for editable fields
  late TextEditingController _shopNameController;
  late TextEditingController _ownerNameController;
  late TextEditingController _contactNumberController;
  late TextEditingController _shopAddressController;
  late TextEditingController _emailController;
  late TextEditingController _termsController;
  late TextEditingController _gstController;
  late TextEditingController _upiController;

  String _selectedCurrency = 'INR';
  String _selectedTimezone = 'Asia/Kolkata';

  UserSubscription _subscription = UserSubscription();
  UserLimits _limits = UserLimits();

  // Printer state
  List<String> _availablePrinters = [];
  bool _isLoadingPrinters = false;

  // QZ Tray state (silent raw ESC/POS printing for Chrome)
  bool _qzAvailable = false;
  bool _qzEnabled = false;
  bool _qzLoading = false;
  List<String> _qzPrinters = [];
  String? _qzSelectedPrinter;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _loadSubscription();
    _loadAvailablePrinters();
    if (kIsWeb) {
      _refreshQzTray();
    }
    _shopNameController = TextEditingController(text: user?.shopName ?? '');
    _ownerNameController = TextEditingController(text: user?.ownerName ?? '');
    _contactNumberController = TextEditingController(text: user?.phone ?? '');
    _shopAddressController = TextEditingController(text: user?.address ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _gstController = TextEditingController(text: user?.gstNumber ?? '');
    _upiController = TextEditingController(text: user?.upiId ?? '');
    _selectedCurrency = user?.currency ?? 'INR';
    _selectedTimezone = user?.timezone ?? 'Asia/Kolkata';
    _termsController = TextEditingController(
      text:
          user?.settings.receiptFooter ??
          '1. Goods once sold will not be taken back.\n2. Subject to local jurisdiction.\n3. Warranty as per manufacturer terms.',
    );
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _ownerNameController.dispose();
    _contactNumberController.dispose();
    _shopAddressController.dispose();
    _emailController.dispose();
    _gstController.dispose();
    _upiController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailablePrinters() async {
    if (kIsWeb) return;
    setState(() => _isLoadingPrinters = true);
    try {
      if (!kIsWeb && Platform.isWindows) {
        final printers = await UsbPrinterService.getWindowsPrinters();
        if (mounted) setState(() => _availablePrinters = printers);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoadingPrinters = false);
  }

  // ─── QZ Tray (Chrome silent raw ESC/POS printing) ───
  Future<void> _refreshQzTray() async {
    if (!kIsWeb) return;
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

  Future<void> _handleTestPrint() async {
    final messenger = ScaffoldMessenger.of(context);

    if (!kIsWeb && Platform.isWindows) {
      final usbName = UsbPrinterService.getSavedPrinterName();
      if (usbName.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No printer selected')),
        );
        return;
      }
      final success = await UsbPrinterService.printTestPage(usbName);
      messenger.showSnackBar(
        SnackBar(
          content: Text(success ? 'Test print sent!' : 'Print failed'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'System printer: Use the print dialog when printing a receipt',
          ),
        ),
      );
    }
  }

  Future<void> _selectPrinter(String? printerName) async {
    if (printerName == null) return;
    if (printerName == 'None') {
      await ref.read(printerProvider.notifier).disconnectPrinter();
    } else {
      if (!kIsWeb && Platform.isWindows) {
        await UsbPrinterService.saveUsbPrinter(printerName);
        await ref
            .read(printerProvider.notifier)
            .connectPrinter('USB: $printerName', printerName);
        // Set printer type to USB so ESC/POS raw bytes are sent instead of PDF
        await ref
            .read(printerProvider.notifier)
            .setPrinterType(PrinterTypeOption.usb);
      }
    }
  }

  Future<void> _loadSubscription() async {
    try {
      final sub = await UserMetricsService.getUserSubscription();
      final limits = await UserMetricsService.getUserLimits();
      if (mounted) {
        setState(() {
          _subscription = sub;
          _limits = limits;
        });
      }
    } catch (_) {}
  }

  SettingsTab get _selectedTab {
    switch (widget.initialTab) {
      case 'account':
        return SettingsTab.account;
      case 'hardware':
        return SettingsTab.hardware;
      case 'billing':
        return SettingsTab.billing;
      default:
        return SettingsTab.general;
    }
  }

  void _navigateToTab(SettingsTab tab) {
    context.go('/settings/${tab.name}');
  }

  bool _isSyncing = false;
  bool _isSaving = false;
  bool _isUploadingLogo = false;
  bool _isUploadingProfileImage = false;

  bool get _isMobileView =>
      ResponsiveHelper.isMobile(context) || ResponsiveHelper.isTablet(context);

  Future<void> _pickShopLogo() async {
    setState(() => _isUploadingLogo = true);
    try {
      final downloadUrl = await ImageService.pickAndUploadLogo();
      if (downloadUrl != null && mounted) {
        final success = await ref
            .read(authNotifierProvider.notifier)
            .updateShopLogo(downloadUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success ? 'Shop logo updated!' : 'Failed to update logo',
              ),
              backgroundColor: success ? AppColors.primary : AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _pickProfileImage() async {
    setState(() => _isUploadingProfileImage = true);
    try {
      final downloadUrl = await ImageService.pickAndUploadProfileImage();
      if (downloadUrl != null && mounted) {
        final success = await ref
            .read(authNotifierProvider.notifier)
            .updateProfileImage(downloadUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? 'Profile picture updated!'
                    : 'Failed to update profile picture',
              ),
              backgroundColor: success ? AppColors.primary : AppColors.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isUploadingProfileImage = false);
    }
  }

  Future<void> _removeShopLogo() async {
    setState(() => _isUploadingLogo = true);
    try {
      await ImageService.deleteLogoFromStorage();
      final success = await ref
          .read(authNotifierProvider.notifier)
          .updateShopLogo('');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Logo removed' : 'Failed to remove logo'),
            backgroundColor: success ? AppColors.primary : AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingLogo = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final footer = _termsController.text.trim();
      final success = await ref
          .read(authNotifierProvider.notifier)
          .updateShopInfo(
            shopName: _shopNameController.text.trim(),
            ownerName: _ownerNameController.text.trim(),
            phone: _contactNumberController.text.trim(),
            address: _shopAddressController.text.trim(),
            email: _emailController.text.trim(),
            gstNumber: _gstController.text.trim(),
            upiId: _upiController.text.trim(),
            currency: _selectedCurrency,
            timezone: _selectedTimezone,
            receiptFooter: footer,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Settings saved successfully!'
                  : 'Failed to save settings',
            ),
            backgroundColor: success ? AppColors.primary : AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving settings: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showRedeemDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Promo Code'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.characters,
          maxLength: 16,
          decoration: const InputDecoration(hintText: 'e.g. DIWALI2026'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, controller.text.trim().toUpperCase()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'asia-south1');
      await fn.httpsCallable('redeemReferralCode').call({'code': result});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Referral code applied! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not apply code: $e')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    // Step 1: Warning dialog
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: AppColors.error,
          size: 48,
        ),
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete:\n\n'
          '• Your account and profile\n'
          '• All products, bills, and inventory\n'
          '• All settings and preferences\n'
          '• Khata (credit) records\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    // Step 2: Type DELETE confirmation
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Type DELETE to confirm'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Type DELETE here',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );
    final typedText = controller.text.trim();
    controller.dispose();
    if (confirmed != true || !mounted) return;
    if (typedText != 'DELETE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must type DELETE to confirm')),
      );
      return;
    }

    // Step 3: Execute deletion
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      ),
    );

    final success = await ref
        .read(authNotifierProvider.notifier)
        .deleteAccount();

    if (mounted) {
      Navigator.of(context).pop(); // dismiss spinner
      if (success) {
        context.go(AppRoutes.login);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to delete account. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Widget _buildLogoPreview(String? logoPath) {
    if (_isUploadingLogo) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (logoPath != null && logoPath.isNotEmpty) {
      // If it's a URL (Firebase Storage), use Image.network
      if (logoPath.startsWith('http')) {
        // Add cache-buster to force reload after upload
        final separator = logoPath.contains('?') ? '&' : '?';
        final cacheBustedUrl =
            '$logoPath${separator}t=${DateTime.now().millisecondsSinceEpoch}';
        return CachedNetworkImage(
          imageUrl: cacheBustedUrl,
          width: 64,
          height: 64,
          fit: BoxFit.cover,
          placeholder: (_, url) => const SizedBox(
            width: 64,
            height: 64,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (_, url, error) {
            debugPrint('Logo load error: $error');
            return const Icon(Icons.store, size: 28, color: Colors.grey);
          },
        );
      }
      // If it's a local file path (non-web)
      if (!kIsWeb) {
        final file = File(logoPath);
        if (file.existsSync()) {
          return Image.file(file, width: 64, height: 64, fit: BoxFit.cover);
        }
      }
    }
    return const Icon(Icons.store, size: 28, color: Colors.grey);
  }

  /// Build user profile avatar (separate from shop logo)
  Widget _buildUserProfileAvatar(String? imagePath, double radius) {
    if (_isUploadingProfileImage) {
      return CircleAvatar(
        radius: radius,
        child: SizedBox(
          width: radius,
          height: radius,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final hasImage = imagePath != null && imagePath.isNotEmpty;

    if (!hasImage) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).dividerColor,
        child: Icon(Icons.person, size: radius, color: Colors.grey),
      );
    }

    if (imagePath.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(imagePath),
        backgroundColor: Theme.of(context).dividerColor,
        onBackgroundImageError: (_, _) {},
      );
    }

    // Fallback
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).dividerColor,
      child: Icon(Icons.person, size: radius, color: Colors.grey),
    );
  }

  /// Two columns on desktop, stacked on mobile
  Widget _responsiveColumns(
    List<Widget> leftChildren,
    List<Widget> rightChildren, {
    double spacing = 24,
  }) {
    if (_isMobileView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...leftChildren,
          SizedBox(height: spacing),
          ...rightChildren,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: leftChildren)),
        SizedBox(width: spacing),
        Expanded(child: Column(children: rightChildren)),
      ],
    );
  }

  /// Side-by-side fields on desktop, stacked on mobile
  Widget _responsiveFields(List<Widget> children, {double spacing = 16}) {
    if (_isMobileView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:
            children.expand((w) => [w, SizedBox(height: spacing)]).toList()
              ..removeLast(),
      );
    }
    return Row(
      children:
          children
              .expand((w) => [Expanded(child: w), SizedBox(width: spacing)])
              .toList()
            ..removeLast(),
    );
  }

  // Tab metadata
  static const _tabData = {
    SettingsTab.general: (
      icon: Icons.settings,
      label: 'General',
      title: 'General Settings',
      subtitle:
          'Manage your shop profile, business details, and customize your app branding.',
    ),
    SettingsTab.account: (
      icon: Icons.person,
      label: 'Account',
      title: 'Account Settings',
      subtitle: 'Manage your personal profile and security preferences.',
    ),
    SettingsTab.hardware: (
      icon: Icons.print,
      label: 'Hardware',
      title: 'System Settings',
      subtitle:
          'Configure your shop\'s hardware, cloud synchronization, and localized app preferences.',
    ),
    SettingsTab.billing: (
      icon: Icons.receipt_long,
      label: 'Billing',
      title: 'Invoice & Billing Settings',
      subtitle:
          'Customize your invoice appearance, tax rules, and digital payment integrations.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final tabInfo = _tabData[_selectedTab]!;
    final isMobile = ResponsiveHelper.isMobile(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    if (isMobile || isTablet) {
      return _buildMobileLayout(tabInfo);
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Top bar — mirrors the main app header
          _buildTopBar(),

          Expanded(
            child: Row(
              children: [
                // Side Navigation
                _buildSideNav(),

                // Main Content
                Expanded(
                  child: Column(
                    children: [
                      // Header with breadcrumb
                      _buildHeader(tabInfo),

                      // Tab Content
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(
                            ResponsiveHelper.isTablet(context) ? 20 : 24,
                          ),
                          child: _buildTabContent(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Top bar with app branding + back arrow — consistent with main shell look
  Widget _buildTopBar() {
    final user = ref.watch(currentUserProvider);
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // Back arrow
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => context.go(AppRoutes.billing),
            tooltip: 'Back to app',
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          // App icon / Store logo
          ShopLogoWidget(
            logoPath: user?.shopLogoPath,
            size: 30,
            borderRadius: 6,
            iconSize: 16,
          ),
          const SizedBox(width: 10),
          Text(
            user?.shopName ?? 'Settings',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '/ Settings',
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          const Spacer(),
          // Notification icon (for consistency)
          IconButton(
            icon: const Icon(Icons.notifications_outlined, size: 22),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No new notifications'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Mobile layout with AppBar and drawer navigation
  Widget _buildMobileLayout(
    ({IconData icon, String label, String title, String subtitle}) tabInfo,
  ) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(tabInfo.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.dashboard),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Tab selector chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SettingsTab.values.map((tab) {
                  final isSelected = tab == _selectedTab;
                  final data = _tabData[tab]!;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(data.label),
                      avatar: Icon(data.icon, size: 18),
                      selected: isSelected,
                      onSelected: (_) => _navigateToTab(tab),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideNav() {
    return Container(
      width: 200,
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section title
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
            child: Text(
              'Settings',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ...SettingsTab.values.map((tab) => _buildNavItem(tab)),
          const Spacer(),
          // Logout button
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextButton.icon(
              onPressed: () {
                ref.read(authNotifierProvider.notifier).signOut();
              },
              icon: const Icon(Icons.logout, size: 20),
              label: const Text('Log Out'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(SettingsTab tab) {
    final isSelected = _selectedTab == tab;
    final data = _tabData[tab]!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: isSelected ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => _navigateToTab(tab),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  data.icon,
                  size: 20,
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  data.label,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    ({IconData icon, String label, String title, String subtitle}) tabInfo,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumb
                Row(
                  children: [
                    Text(
                      'Home',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 13,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 13,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                    Text(
                      tabInfo.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Title
                Text(
                  tabInfo.title,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tabInfo.subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Save button
          ElevatedButton.icon(
            onPressed: _isSaving ? null : _saveSettings,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTab) {
      case SettingsTab.general:
        return _buildGeneralTab();
      case SettingsTab.account:
        return _buildAccountTab();
      case SettingsTab.hardware:
        return _buildHardwareTab();
      case SettingsTab.billing:
        return _buildBillingTab();
    }
  }

  // ============ GENERAL TAB ============
  Widget _buildGeneralTab() {
    final user = ref.watch(currentUserProvider);

    return _responsiveColumns(
      [
        // Shop Profile
        _SectionCard(
          icon: Icons.store,
          iconColor: AppColors.info,
          title: 'Shop Profile',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shop Logo
              _buildFieldLabel('Shop Logo'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.small,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildLogoPreview(user?.shopLogoPath),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _isUploadingLogo
                                  ? null
                                  : () => _pickShopLogo(),
                              icon: _isUploadingLogo
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.upload, size: 16),
                              label: Text(
                                _isUploadingLogo ? 'Uploading...' : 'Upload',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            OutlinedButton(
                              onPressed: _isUploadingLogo
                                  ? null
                                  : () => _removeShopLogo(),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          '500×500px. JPG, PNG or SVG',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildFieldLabel('Shop Name', required: true),
              _buildTextField(controller: _shopNameController),
              const SizedBox(height: 16),
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Owner Name'),
                    _buildTextField(controller: _ownerNameController),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Contact Number'),
                    _buildTextField(controller: _contactNumberController),
                  ],
                ),
              ]),
              const SizedBox(height: 16),
              _buildFieldLabel('Shop Address'),
              _buildTextField(controller: _shopAddressController, maxLines: 2),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Business Details
        _SectionCard(
          icon: Icons.business,
          iconColor: AppColors.warning,
          title: 'Business Details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('GST Number'),
              _buildTextField(
                controller: _gstController,
                hint: '22AAAAA0000A1Z5',
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter GSTIN to enable tax invoicing.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Currency'),
                    _buildDropdown(
                      _selectedCurrency,
                      ['INR', 'USD', 'EUR'],
                      onChanged: (v) => setState(() => _selectedCurrency = v!),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Timezone'),
                    _buildDropdown(
                      _selectedTimezone,
                      ['Asia/Kolkata', 'America/New_York', 'Europe/London'],
                      onChanged: (v) => setState(() => _selectedTimezone = v!),
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ],
      [
        // App Branding & Theme
        _SectionCard(
          icon: Icons.palette,
          iconColor: const Color(0xFFEC4899),
          title: 'App Branding & Theme',
          child: Builder(
            builder: (context) {
              final themeSettings = ref.watch(themeSettingsProvider);
              final themeNotifier = ref.read(themeSettingsProvider.notifier);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Brand Accent Color (connected to provider)
                  _buildFieldLabel('Brand Accent Color'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: ThemeSettingsModel.colorPresets.map((hex) {
                      final isSelected = hex == themeSettings.primaryColorHex;
                      final color = Color(
                        int.parse('FF${hex.replaceFirst('#', '')}', radix: 16),
                      );
                      return GestureDetector(
                        onTap: () => themeNotifier.setPrimaryColor(hex),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: Colors.white, width: 3)
                                : null,
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    ),
                                  ]
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Font Family
                  _buildFieldLabel('Font Family'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: ThemeSettingsModel.fontPresets.map((font) {
                      final isSelected = font == themeSettings.fontFamily;
                      return ChoiceChip(
                        label: Text(font),
                        selected: isSelected,
                        onSelected: (_) => themeNotifier.setFontFamily(font),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // Font Size
                  _buildFieldLabel('Font Size'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Aa', style: TextStyle(fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: themeSettings.fontSizeScale,
                          min: 0.85,
                          max: 1.15,
                          divisions: 2,
                          label: _getFontSizeLabel(themeSettings.fontSizeScale),
                          onChanged: (v) => themeNotifier.setFontSizeScale(v),
                        ),
                      ),
                      const Text('Aa', style: TextStyle(fontSize: 24)),
                    ],
                  ),
                  Text(
                    _getFontSizeLabel(themeSettings.fontSizeScale),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Theme Mode
                  const Divider(),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Use System Theme',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              'Match your device settings',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: themeSettings.useSystemTheme,
                        onChanged: (v) => themeNotifier.setUseSystemTheme(v),
                        activeThumbColor: AppColors.primary,
                      ),
                    ],
                  ),
                  if (!themeSettings.useSystemTheme) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dark Mode',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Enable dark appearance',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: themeSettings.useDarkMode,
                          onChanged: (v) => themeNotifier.setDarkMode(v),
                          activeThumbColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 24),

        // Quick Actions & Support
        _SectionCard(
          icon: Icons.flash_on,
          iconColor: const Color(0xFFF97316),
          title: 'Quick Actions & Support',
          child: Column(
            children: [
              _buildActionRow(
                'Backup Data',
                'Download a local copy of your shop data',
                Icons.download,
              ),
              const Divider(height: 24),
              _buildActionRow(
                'Reset Settings',
                'Restore default configuration',
                Icons.refresh,
              ),
              const Divider(height: 24),
              _buildClickableActionRow(
                'Help Center',
                'Chat with support & manage tickets',
                Icons.support_agent,
                () => context.push('/support'),
              ),
              const Divider(height: 24),
              _buildClickableActionRow(
                'About',
                'Version $appVersion+$appBuildNumber',
                Icons.info_outline,
                () => _showAboutDialog(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============ ACCOUNT TAB ============
  Widget _buildAccountTab() {
    final user = ref.watch(currentUserProvider);
    final profileImagePath = user?.profileImagePath;

    final leftChildren = <Widget>[
      // User Profile
      _SectionCard(
        icon: Icons.person,
        iconColor: AppColors.info,
        title: 'User Profile',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: _isUploadingProfileImage ? null : _pickProfileImage,
                  child: Stack(
                    children: [
                      _buildUserProfileAvatar(profileImagePath, 40),
                      if (!_isUploadingProfileImage)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context).cardColor,
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.ownerName ?? 'User',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Owner',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            _responsiveFields([
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Full Name'),
                  _buildTextField(controller: _ownerNameController),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFieldLabel('Email Address'),
                  _buildTextField(controller: _emailController, enabled: false),
                ],
              ),
            ]),
          ],
        ),
      ),

      const SizedBox(height: 20),

      // Verification Status
      _SectionCard(
        icon: Icons.verified_user,
        iconColor: AppColors.success,
        title: 'Verification Status',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Firebase UID
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.fingerprint,
                    size: 16,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'UID: ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      user?.id ?? '—',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Phone verification row
            _buildVerificationRow(
              icon: Icons.phone_android,
              label: 'Phone Number',
              value: user?.phone ?? '—',
              isVerified: user?.phoneVerified ?? false,
              verifiedAt: user?.phoneVerifiedAt,
            ),
            const Divider(height: 24),

            // Email verification row
            _buildVerificationRow(
              icon: Icons.email_outlined,
              label: 'Email Address',
              value: user?.email ?? '—',
              isVerified: user?.emailVerified ?? false,
            ),
          ],
        ),
      ),
    ];

    // Subscription
    leftChildren.add(const SizedBox(height: 20));
    leftChildren.add(
      _SectionCard(
        icon: Icons.workspace_premium,
        iconColor: AppColors.primary,
        title: 'Subscription',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Icon(Icons.workspace_premium, color: AppColors.primary),
          ),
          title: Text(
            '${_subscription.plan.name[0].toUpperCase()}${_subscription.plan.name.substring(1)} Plan',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _limits.billsThisMonth < _limits.billsLimit
                ? '${_limits.billsThisMonth} / ${_limits.billsLimit == 999999 ? "\u221e" : _limits.billsLimit} bills used this month'
                : '\u26a0\ufe0f Bill limit reached — upgrade to continue',
            style: TextStyle(
              color: _limits.billsThisMonth >= _limits.billsLimit
                  ? AppColors.error
                  : null,
            ),
          ),
          trailing: _subscription.plan == SubscriptionPlan.free
              ? FilledButton(
                  onPressed: () => context.push(AppRoutes.subscription),
                  child: const Text('Upgrade'),
                )
              : TextButton(
                  onPressed: () => context.push(AppRoutes.subscription),
                  child: const Text('Manage'),
                ),
        ),
      ),
    );

    // Promo Code
    leftChildren.add(const SizedBox(height: 20));
    leftChildren.add(
      _SectionCard(
        icon: Icons.redeem,
        iconColor: AppColors.accent,
        title: 'Promo Code',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Have a promo code? Redeem it to get free days added to your subscription!',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showRedeemDialog,
                icon: const Icon(Icons.redeem, size: 18),
                label: const Text('Redeem Promo Code'),
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Privacy & Data Export
    leftChildren.add(const SizedBox(height: 20));
    leftChildren.add(
      _SectionCard(
        icon: Icons.shield_outlined,
        iconColor: AppColors.info,
        title: 'Privacy & Data',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download),
              title: const Text('Export My Data'),
              subtitle: const Text('Download all your data as JSON'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final data = await PrivacyConsentService.exportAllUserData();
                  if (mounted) {
                    await Clipboard.setData(ClipboardData(text: data));
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Data copied to clipboard')),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text('Export failed: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );

    // Danger Zone: Delete Account
    leftChildren.add(const SizedBox(height: 20));
    leftChildren.add(
      _SectionCard(
        icon: Icons.warning_amber_rounded,
        iconColor: AppColors.error,
        title: 'Danger Zone',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.delete_forever, color: AppColors.error),
          title: const Text(
            'Delete Account',
            style: TextStyle(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: const Text(
            'Permanently delete your account and all data. This cannot be undone.',
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.error),
          onTap: _confirmDeleteAccount,
        ),
      ),
    );

    final rightChildren = <Widget>[];

    if (_isMobileView) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...leftChildren,
          const SizedBox(height: 24),
          ...rightChildren,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: leftChildren)),
        const SizedBox(width: 24),
        SizedBox(width: 320, child: Column(children: rightChildren)),
      ],
    );
  }

  Widget _buildQzTraySectionCard() {
    final theme = Theme.of(context);
    return _SectionCard(
      icon: Icons.cloud_download_outlined,
      iconColor: AppColors.success,
      title: 'Silent Print (Chrome)',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: (_qzAvailable ? AppColors.success : Colors.grey)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _qzAvailable ? Icons.check_circle : Icons.cancel,
                  size: 12,
                  color: _qzAvailable ? AppColors.success : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  _qzAvailable ? 'Ready' : 'Not set up',
                  style: TextStyle(
                    color: _qzAvailable ? AppColors.success : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _qzAvailable
                ? 'Prints receipts directly to the thermal printer — no Chrome '
                      'print dialog, correct 58mm width, correct orientation.'
                : 'Fixes wrong-size / upside-down receipts from Chrome. '
                      'Download and run the setup file below — it installs '
                      'everything automatically (free, one-time per PC).',
            style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 16),
          if (!_qzAvailable) ...[
            FilledButton.icon(
              icon: const Icon(Icons.download, size: 18),
              label: const Text('Download Print Setup (.bat)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
              ),
              onPressed: () {
                // Direct Firebase Storage URL — always available, no web build required
                const url =
                    'https://firebasestorage.googleapis.com/v0/b/'
                    'login-radha.firebasestorage.app/o/'
                    'downloads%2Fqz-tray-setup.bat?alt=media';
                // ignore: deprecated_member_use
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
            ),
            const SizedBox(height: 14),
            _buildQzStep(
              '1',
              'Click the button above — your browser downloads '
                  'qz-tray-setup.bat',
            ),
            _buildQzStep('2', 'Double-click the downloaded file to run it'),
            _buildQzStep(
              '3',
              'The script installs QZ Tray (if needed) and trusts its '
                  'certificate — fully automatic',
            ),
            _buildQzStep(
              '4',
              'Come back and click the ↻ refresh button above — the badge '
                  'turns green',
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.security_outlined, size: 14),
              label: const Text(
                'Manual certificate trust (advanced — only if the script '
                'didn\'t work)',
              ),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.outline,
                textStyle: const TextStyle(fontSize: 11),
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
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
              title: const Text('Use silent print for receipts'),
              subtitle: const Text(
                'Falls back to Chrome print dialog if QZ Tray is unreachable.',
              ),
              value: _qzEnabled,
              onChanged: _toggleQzEnabled,
            ),
            if (_qzEnabled) ...[
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.print, size: 16),
                  label: const Text('Test print'),
                  onPressed: _qzSelectedPrinter == null ? null : _testQzPrint,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildQzStep(String number, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(right: 10, top: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ HARDWARE TAB ============
  Widget _buildHardwareTab() {
    final printerState = ref.watch(printerProvider);

    return _responsiveColumns(
      [
        // Printer Settings
        _SectionCard(
          icon: Icons.print,
          iconColor: AppColors.info,
          title: 'Printer Settings',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color:
                  (printerState.isConnected ? AppColors.success : Colors.grey)
                      .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: printerState.isConnected
                        ? AppColors.success
                        : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  printerState.isConnected ? 'Connected' : 'Not connected',
                  style: TextStyle(
                    color: printerState.isConnected
                        ? AppColors.success
                        : Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Select Printer'),
              _isLoadingPrinters
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _buildDropdown(printerState.printerName ?? 'None', [
                      'None',
                      ..._availablePrinters,
                      // Include current printer if not in list
                      if (printerState.printerName != null &&
                          printerState.printerName != 'None' &&
                          !_availablePrinters.contains(
                            printerState.printerName,
                          ))
                        printerState.printerName!,
                    ], onChanged: _selectPrinter),
              const SizedBox(height: 20),
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Paper Width'),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => ref
                              .read(printerProvider.notifier)
                              .setPaperSize(0),
                          child: _buildToggleChip(
                            '58mm',
                            printerState.paperSizeIndex == 0,
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => ref
                              .read(printerProvider.notifier)
                              .setPaperSize(1),
                          child: _buildToggleChip(
                            '80mm',
                            printerState.paperSizeIndex == 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Density'),
                    const SizedBox(height: 8),
                    Slider(
                      value: printerState.printDensity.toDouble(),
                      max: 2,
                      divisions: 2,
                      onChanged: (v) => ref
                          .read(printerProvider.notifier)
                          .setPrintDensity(v.round()),
                      activeColor: AppColors.primary,
                    ),
                    Text(
                      ['Light', 'Normal', 'Dark'][printerState.printDensity],
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ]),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  onPressed: _handleTestPrint,
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Test Print'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // QZ Tray - Silent Chrome printing (web only)
        if (kIsWeb) ...[_buildQzTraySectionCard(), const SizedBox(height: 24)],

        // Barcode Scanner
        _SectionCard(
          icon: Icons.qr_code_scanner,
          iconColor: AppColors.warning,
          title: 'Barcode Scanner',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Prefix'),
                    _buildTextField(value: 'None'),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Suffix'),
                    _buildTextField(value: 'Enter (Return)'),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              const Text(
                'TEST CONFIGURATION',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  hintText: 'Scan an item here to test...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Scan test reset - ready for new scan'),
                        duration: Duration(seconds: 2),
                      ),
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ],
          ),
        ),
      ],
      [
        // Cloud Synchronization
        _SectionCard(
          icon: Icons.cloud_sync,
          iconColor: AppColors.success,
          title: 'Cloud Synchronization',
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: AppColors.success,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sync Status',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                        Text(
                          'Up to date',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Last synced: Just now',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'PENDING',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                        ),
                      ),
                      Text(
                        '0',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Transactions',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSyncing
                      ? null
                      : () async {
                          setState(() => _isSyncing = true);
                          await SyncSettingsService.syncNow();
                          if (mounted) setState(() => _isSyncing = false);
                        },
                  icon: _isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: const Text('Sync Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              // Sync Interval Selector
              _isMobileView
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sync Interval',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Text(
                          'How often to auto-sync data',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: AppShadows.small,
                          ),
                          child: DropdownButtonFormField<SyncInterval>(
                            isExpanded: true,
                            initialValue: SyncSettingsService.getSyncInterval(),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: InputBorder.none,
                            ),
                            items: SyncInterval.values.map((interval) {
                              return DropdownMenuItem(
                                value: interval,
                                child: Text(interval.displayName),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value != null) {
                                SyncSettingsService.setSyncInterval(value);
                                setState(() {});
                              }
                            },
                          ),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sync Interval',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'How often to auto-sync data',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Flexible(
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 150),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: AppShadows.small,
                            ),
                            child: DropdownButtonFormField<SyncInterval>(
                              isExpanded: true,
                              initialValue:
                                  SyncSettingsService.getSyncInterval(),
                              decoration: const InputDecoration(
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: InputBorder.none,
                              ),
                              items: SyncInterval.values.map((interval) {
                                return DropdownMenuItem(
                                  value: interval,
                                  child: Text(interval.displayName),
                                );
                              }).toList(),
                              onChanged: (value) {
                                if (value != null) {
                                  SyncSettingsService.setSyncInterval(value);
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // App Preferences
        _SectionCard(
          icon: Icons.tune,
          iconColor: AppColors.upi,
          title: 'App Preferences',
          child: Builder(
            builder: (context) {
              final appSettings = ref.watch(settingsProvider);
              final appSettingsNotifier = ref.read(settingsProvider.notifier);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Language Selector
                  _buildFieldLabel('Language'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppShadows.small,
                    ),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: appSettings.languageCode,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: InputBorder.none,
                      ),
                      items: AppLanguage.values.map((lang) {
                        return DropdownMenuItem(
                          value: lang.code,
                          child: Text(lang.displayName),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          appSettingsNotifier.setLanguage(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Data Retention
                  _buildFieldLabel('Data Retention'),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppShadows.small,
                    ),
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: appSettings.retentionDays,
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: InputBorder.none,
                      ),
                      items: const [
                        DropdownMenuItem(value: 30, child: Text('30 days')),
                        DropdownMenuItem(value: 60, child: Text('60 days')),
                        DropdownMenuItem(value: 90, child: Text('90 days')),
                        DropdownMenuItem(value: 180, child: Text('180 days')),
                        DropdownMenuItem(value: 365, child: Text('1 year')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          appSettingsNotifier.setRetentionDays(value);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Existing toggles
                  _buildPreferenceToggle(
                    'Offline Mode',
                    'Continue billing even when the internet connection is lost. Data will sync automatically when back online.',
                    true,
                  ),
                  const SizedBox(height: 20),
                  _buildPreferenceToggle(
                    'Voice Input',
                    'Enable product search using voice commands. Supports English and Hindi (Hinglish).',
                    false,
                    badge: 'BETA',
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.info,
                          size: 20,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Need Help?',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                "If your hardware isn't connecting, try restarting the RetailLite app or re-pairing your Bluetooth device.",
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ============ BILLING TAB ============
  Widget _buildBillingTab() {
    final user = ref.watch(currentUserProvider);

    return _responsiveColumns(
      [
        // Invoice Header
        _SectionCard(
          icon: Icons.receipt,
          iconColor: AppColors.info,
          title: 'Invoice Header',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppShadows.small,
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt, size: 24, color: Colors.grey),
                        SizedBox(height: 4),
                        Text(
                          'Logo',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFieldLabel('Shop Name'),
                        _buildTextField(controller: _shopNameController),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildFieldLabel('Invoice Title'),
              _buildTextField(value: 'Tax Invoice'),
              const SizedBox(height: 16),
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Address Line 1'),
                    _buildTextField(controller: _shopAddressController),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('Contact Number'),
                    _buildTextField(controller: _contactNumberController),
                  ],
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Tax Settings
        _SectionCard(
          icon: Icons.percent,
          iconColor: AppColors.warning,
          title: 'Tax Settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Enable GST Billing',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Automatically calculate CGST/SGST based on rates.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: user?.settings.gstEnabled ?? true,
                      onChanged: (v) async {
                        final uid = ref.read(currentUserProvider)?.id;
                        if (uid == null) return;
                        try {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(uid)
                              .update({'settings.gstEnabled': v});
                          final notifier = ref.read(
                            authNotifierProvider.notifier,
                          );
                          final current = ref.read(currentUserProvider);
                          if (current != null) {
                            notifier.updateLocalUserSettings(
                              current.settings.copyWith(gstEnabled: v),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Failed to update GST setting'),
                              ),
                            );
                          }
                        }
                      },
                      activeThumbColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _responsiveFields([
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldLabel('GSTIN'),
                    _buildTextField(
                      controller: _gstController,
                      hint: '22AAAAA0000A1Z5',
                    ),
                  ],
                ),
              ]),
            ],
          ),
        ),
      ],
      [
        _SectionCard(
          icon: Icons.description,
          iconColor: AppColors.error,
          title: 'Terms & Conditions',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Footer Text'),
              const SizedBox(height: 8),
              TextField(
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Enter terms and conditions...',
                  filled: true,
                ),
                controller: _termsController,
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'This text will appear at the bottom of every printed invoice.',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Digital Payment Setup
        _SectionCard(
          icon: Icons.payment,
          iconColor: AppColors.success,
          title: 'Digital Payment Setup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'UPI QR Code',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  if (_upiController.text.trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ACTIVE',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _buildFieldLabel('UPI ID'),
              TextField(
                controller: _upiController,
                decoration: const InputDecoration(
                  hintText: 'yourname@upi',
                  filled: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              if (_upiController.text.trim().isNotEmpty)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: AppShadows.small,
                    ),
                    child: QrImageView(
                      data: PaymentLinkService.generateUpiQrData(
                        upiId: _upiController.text.trim(),
                        payeeName: _shopNameController.text.trim(),
                      ),
                      size: 180,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Enter your UPI ID and click Save. The QR code will be shown on invoices.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============ HELPER WIDGETS ============

  /// Get font size label from scale value
  String _getFontSizeLabel(double scale) {
    if (scale <= 0.90) return 'Small';
    if (scale <= 1.05) return 'Compact';
    return 'Large';
  }

  Widget _buildFieldLabel(String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (required) const Text(' *', style: TextStyle(color: Colors.red)),
        ],
      ),
    );
  }

  Widget _buildTextField({
    String? value,
    TextEditingController? controller,
    String? hint,
    bool obscure = false,
    int maxLines = 1,
    bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? (value ?? '') : null,
      obscureText: obscure,
      maxLines: maxLines,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String value,
    List<String> items, {
    ValueChanged<String?>? onChanged,
  }) {
    // Ensure value is in items list to prevent assertion error
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.small,
      ),
      child: DropdownButton<String>(
        value: safeValue,
        isExpanded: true,
        underline: const SizedBox(),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionRow(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: Icon(icon, color: AppColors.textSecondary),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildClickableActionRow(
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, color: AppColors.textSecondary),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About ${AppConstants.appName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              AppConstants.appName,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text('Version $appVersion+$appBuildNumber'),
            const SizedBox(height: 16),
            const Text('Simple POS for Small Retailers'),
            const SizedBox(height: 16),
            const Text(
              '© 2026 RetailLite',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isVerified,
    DateTime? verifiedAt,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isVerified
                ? AppColors.success.withAlpha(25)
                : AppColors.error.withAlpha(25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isVerified
                  ? AppColors.success.withAlpha(80)
                  : AppColors.error.withAlpha(80),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVerified ? Icons.check_circle : Icons.cancel,
                size: 14,
                color: isVerified ? AppColors.success : AppColors.error,
              ),
              const SizedBox(width: 4),
              Text(
                isVerified ? 'Verified' : 'Not Verified',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isVerified ? AppColors.success : AppColors.error,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildToggleChip(String label, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primary.withValues(alpha: 0.1)
            : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: isSelected ? Border.all(color: AppColors.primary) : null,
        boxShadow: isSelected ? null : AppShadows.small,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isSelected
              ? AppColors.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPreferenceToggle(
    String title,
    String description,
    bool value, {
    String? badge,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (badge != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.info,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: null, // Read-only display
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}

/// Section card widget
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.medium,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}
