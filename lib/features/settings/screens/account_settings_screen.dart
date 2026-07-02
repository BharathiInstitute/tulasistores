/// Account Settings Screen - Profile, Password, Subscription
/// Mirrors Web Account Tab
library;

import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/design/app_colors.dart';
import 'package:retaillite/core/services/image_service.dart';
import 'package:retaillite/core/services/privacy_consent_service.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/router/app_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountSettingsScreen extends ConsumerStatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  ConsumerState<AccountSettingsScreen> createState() =>
      _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends ConsumerState<AccountSettingsScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isUploadingImage = false;
  UserSubscription _subscription = UserSubscription();
  UserLimits _limits = UserLimits();

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _emailController.text = user?.email ?? '';
    _phoneController.text = user?.phone ?? '';
    _loadSubscription();
  }

  Future<void> _loadSubscription() async {
    final sub = await UserMetricsService.getUserSubscription();
    final limits = await UserMetricsService.getUserLimits();
    if (mounted) {
      setState(() {
        _subscription = sub;
        _limits = limits;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    debugPrint('🖼️ _pickProfileImage called');
    setState(() => _isUploadingImage = true);
    try {
      final downloadUrl = await ImageService.pickAndUploadProfileImage();
      debugPrint('🖼️ downloadUrl: $downloadUrl');
      if (downloadUrl != null && mounted) {
        final success = await ref
            .read(authNotifierProvider.notifier)
            .updateProfileImage(downloadUrl);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Profile picture updated'
                  : 'Failed to update profile picture',
            ),
            backgroundColor: success ? AppColors.primary : AppColors.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('🖼️ Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pick image: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Widget _buildProfileImage(String? imagePath) {
    if (_isUploadingImage) {
      return const CircleAvatar(radius: 50, child: CircularProgressIndicator());
    }

    final hasImage = imagePath != null && imagePath.isNotEmpty;

    if (!hasImage) {
      return const CircleAvatar(
        radius: 50,
        child: Icon(Icons.person, size: 50),
      );
    }

    // Check if it's a URL or local file
    if (imagePath.startsWith('http')) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: NetworkImage(imagePath),
        onBackgroundImageError: (_, _) {},
      );
    }

    // Local file (non-web only)
    if (!kIsWeb && File(imagePath).existsSync()) {
      return CircleAvatar(
        radius: 50,
        backgroundImage: FileImage(File(imagePath)),
      );
    }

    return const CircleAvatar(radius: 50, child: Icon(Icons.person, size: 50));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final profileImagePath = user?.profileImagePath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Settings'),
        actions: [
          TextButton(onPressed: _saveSettings, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Section
          _buildSectionHeader(theme, 'Profile'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Profile Picture
                  Center(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(50),
                      onTap: _isUploadingImage ? null : _pickProfileImage,
                      child: Stack(
                        children: [
                          _buildProfileImage(profileImagePath),
                          if (!_isUploadingImage)
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: theme.cardColor,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to change profile picture',
                    style: TextStyle(
                      color: theme.colorScheme.outline,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Email (read-only)
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    readOnly: true,
                    enabled: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // ── Linked Accounts Section ──
          _buildSectionHeader(theme, 'Linked Accounts'),
          _buildLinkedAccountsCard(theme),
          const SizedBox(height: 24),

          // ── Subscription Section (link to dedicated tab) ──
          _buildSectionHeader(theme, 'Subscription'),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Icon(
                  Icons.workspace_premium,
                  color: AppColors.primary,
                ),
              ),
              title: Text(
                '${_subscription.plan.name[0].toUpperCase()}${_subscription.plan.name.substring(1)} Plan',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                _limits.billsThisMonth < _limits.billsLimit
                    ? '${_limits.billsThisMonth} / ${_limits.billsLimit == 999999 ? "∞" : _limits.billsLimit} bills used this month'
                    : '⚠️ Bill limit reached — upgrade to continue',
                style: TextStyle(
                  color: _limits.billsThisMonth >= _limits.billsLimit
                      ? AppColors.error
                      : null,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/settings/subscription'),
            ),
          ),
          const SizedBox(height: 24),

          // ── Privacy & Data ──
          _buildSectionHeader(theme, 'Privacy & Data'),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_rounded),
                  title: const Text('Download My Data'),
                  subtitle: const Text('Export all your data as JSON'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _exportPersonalData,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacy Policy'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl('https://retaillite.com/privacy'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  trailing: const Icon(Icons.open_in_new, size: 18),
                  onTap: () => _openUrl('https://retaillite.com/terms'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Danger Zone: Delete Account ──
          _buildSectionHeader(theme, 'Danger Zone'),
          Card(
            color: AppColors.error.withAlpha(15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: AppColors.error.withAlpha(60)),
            ),
            child: ListTile(
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
          const SizedBox(height: 24),
        ],
      ),
    );
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

  Widget _buildLinkedAccountsCard(ThemeData theme) {
    final providers = ref.watch(linkedProvidersProvider);
    final hasGoogle = providers.contains('google.com');
    final hasPassword = providers.contains('password');

    return Card(
      child: Column(
        children: [
          // Google provider
          ListTile(
            leading: CircleAvatar(
              backgroundColor: hasGoogle
                  ? Colors.green.withAlpha(30)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.g_mobiledata,
                color: hasGoogle ? Colors.green : theme.colorScheme.outline,
                size: 28,
              ),
            ),
            title: const Text('Google Sign-In'),
            subtitle: Text(hasGoogle ? 'Linked' : 'Not linked'),
            trailing: hasGoogle
                ? const Icon(Icons.check_circle, color: Colors.green)
                : TextButton(onPressed: _linkGoogle, child: const Text('Link')),
          ),
          const Divider(height: 1),
          // Email/Password provider
          ListTile(
            leading: CircleAvatar(
              backgroundColor: hasPassword
                  ? Colors.green.withAlpha(30)
                  : theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.email_outlined,
                color: hasPassword ? Colors.green : theme.colorScheme.outline,
              ),
            ),
            title: const Text('Email & Password'),
            subtitle: Text(hasPassword ? 'Linked' : 'Not linked'),
            trailing: hasPassword
                ? const Icon(Icons.check_circle, color: Colors.green)
                : TextButton(
                    onPressed: _showSetPasswordDialog,
                    child: const Text('Set Password'),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _linkGoogle() async {
    // Windows desktop doesn't support Google Sign-In linking
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Google linking is not available on Windows. '
              'Please use the web or mobile app.',
            ),
          ),
        );
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final success = await ref
        .read(authNotifierProvider.notifier)
        .linkGoogleToCurrentAccount();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Google account linked successfully!'
              : 'Failed to link Google account.',
        ),
        backgroundColor: success ? Colors.green : AppColors.error,
      ),
    );
    if (success) setState(() {}); // Refresh providers list
  }

  void _showSetPasswordDialog() {
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Set Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Set a password so you can also sign in with email & password.',
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: obscure,
                decoration: const InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: Icon(Icons.lock_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (passwordCtrl.text.length < 6) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Password must be at least 6 characters',
                            ),
                          ),
                        );
                        return;
                      }
                      if (passwordCtrl.text != confirmCtrl.text) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Passwords do not match'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      final success = await ref
                          .read(authNotifierProvider.notifier)
                          .linkEmailPasswordToCurrentAccount(passwordCtrl.text);
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              success
                                  ? 'Password set! You can now sign in with email & password.'
                                  : 'Failed to set password.',
                            ),
                            backgroundColor: success
                                ? Colors.green
                                : AppColors.error,
                          ),
                        );
                        if (success) setState(() {});
                      }
                    },
              child: saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Set Password'),
            ),
          ],
        ),
      ),
    );
  }

  /// Confirm and execute account deletion (Google Play + DPDP Act requirement)
  Future<void> _confirmDeleteAccount() async {
    // Step 1: First confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Delete Account?'),
          ],
        ),
        content: const Text(
          'This will permanently delete:\n\n'
          '• Your shop profile\n'
          '• All products, bills & invoices\n'
          '• All customer records & transactions\n'
          '• All reports & expenses\n'
          '• All settings & preferences\n\n'
          'This action is IRREVERSIBLE and cannot be undone.',
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

    if (confirmed != true || !mounted) return;

    // Step 2: Type confirmation
    final controller = TextEditingController();
    final typed = await showDialog<bool>(
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
    final typedText = controller.text;
    controller.dispose();

    if (typed != true || typedText != 'DELETE' || !mounted) {
      if (typed == true && typedText != 'DELETE' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please type DELETE exactly to confirm'),
          ),
        );
      }
      return;
    }

    // Step 3: Execute deletion
    if (!mounted) return;
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Deleting account and all data...')),
            ],
          ),
        ),
      ),
    );

    final success = await ref
        .read(authNotifierProvider.notifier)
        .deleteAccount();

    if (!mounted) return;
    Navigator.of(context).pop(); // dismiss loading dialog

    if (success) {
      // Navigate to login — account is gone
      context.go('/login');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to delete account. Please try again.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Export all personal data (DPDP right to data portability)
  Future<void> _exportPersonalData() async {
    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Preparing your data export...')),
            ],
          ),
        ),
      ),
    );

    try {
      final jsonData = await PrivacyConsentService.exportAllUserData();
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

      // Share as file
      await Share.share(jsonData, subject: 'RetailLite Data Export');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  /// Open external URL in browser
  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _saveSettings() {
    final authNotifier = ref.read(authNotifierProvider.notifier);
    authNotifier.updateShopInfo(phone: _phoneController.text);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Account settings saved'),
        backgroundColor: AppColors.primary,
      ),
    );
    Navigator.pop(context);
  }
}
