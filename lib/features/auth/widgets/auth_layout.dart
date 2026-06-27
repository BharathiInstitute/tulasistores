/// Shared auth layout for consistent login/register screens
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/core/utils/website_url.dart';
import 'package:flutter/material.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:url_launcher/url_launcher.dart';

/// Modern auth layout with split-screen design
/// Left: Branding panel with gradient
/// Right: Form content
class AuthLayout extends StatelessWidget {
  final Widget child;
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool isAdminMode;
  final VoidCallback? onBack;

  const AuthLayout({
    super.key,
    required this.child,
    required this.title,
    this.subtitle,
    this.icon = Icons.store,
    this.isAdminMode = false,
    this.onBack,
  });

  /// Force light-mode input decoration regardless of global theme.
  /// Auth screens always use hardcoded light AppColors, so inputs must match.
  static InputDecorationTheme get _lightInputTheme => InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surface, // white
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    prefixIconColor: AppColors.textSecondary,
    suffixIconColor: AppColors.textSecondary,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: BorderSide(color: AppColors.primary, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      borderSide: const BorderSide(color: AppColors.error),
    ),
    hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
    labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
  );

  /// Build a fully light ThemeData overlay for auth form areas.
  /// Covers inputs, buttons, text, icons — everything inside the form.
  static ThemeData _lightAuthTheme(BuildContext context) {
    final base = Theme.of(context);
    return base.copyWith(
      brightness: Brightness.light,
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.light,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        outline: AppColors.border,
      ),
      inputDecorationTheme: _lightInputTheme,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primary),
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );
  }

  // Gradient colors based on mode
  List<Color> get _gradientColors => isAdminMode
      ? const [
          Color(0xFF7C3AED), // Violet 600
          Color(0xFF6D28D9), // Violet 700
          Color(0xFF5B21B6), // Violet 800
        ]
      : [
          AppColors.primaryDark,
          const Color(0xFF047857), // Emerald 700
          const Color(0xFF065F46), // Emerald 800
        ];

  @override
  Widget build(BuildContext context) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    if (isMobile) {
      return _buildMobileLayout(context);
    }

    return _buildDesktopLayout(context, isTablet);
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            if (onBack != null)
              Padding(
                padding: const EdgeInsets.all(AppSizes.sm),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: onBack,
                    ),
                  ],
                ),
              ),
            // App branding - clean, no gradient
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.xl,
                vertical: AppSizes.lg,
              ),
              child: Column(
                children: [
                  // App name - main focus
                  Text(
                    AppConstants.appName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: AppSizes.sm),
                  // Screen title as subtitle
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: AppSizes.xs),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            // Form content — forced light theme for all widgets
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSizes.xl),
                child: Theme(data: _lightAuthTheme(context), child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, bool isTablet) {
    return Scaffold(
      body: Row(
        children: [
          // Left branding panel hidden
          if (false)
            Expanded(
              flex: isTablet ? 40 : 45,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _gradientColors,
                  ),
                ),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.all(isTablet ? 32 : 48),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                constraints.maxHeight - (isTablet ? 64 : 96),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // App name
                              const Text(
                                AppConstants.appName,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: AppSizes.xl),
                              // Main content group
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Main heading
                                  Text(
                                    isAdminMode
                                        ? 'Admin Portal'
                                        : 'Welcome Back!',
                                    style: TextStyle(
                                      fontSize: isTablet ? 34 : 40,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.md),
                                  Text(
                                    isAdminMode
                                        ? 'Manage users, subscriptions, and analytics'
                                        : 'भारत का सबसे आसान बिलिंग ऐप\nSimplest billing app for Indian businesses',
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Colors.white.withValues(
                                        alpha: 0.9,
                                      ),
                                      height: 1.6,
                                    ),
                                  ),
                                  const SizedBox(height: AppSizes.xl),
                                  // Feature highlights
                                  _buildFeatureItem(
                                    Icons.bolt,
                                    isAdminMode
                                        ? 'Real-time Analytics'
                                        : 'Lightning Fast Billing',
                                  ),
                                  const SizedBox(height: AppSizes.md),
                                  _buildFeatureItem(
                                    Icons.cloud_sync,
                                    isAdminMode
                                        ? 'User Management'
                                        : 'Cloud Sync & Backup',
                                  ),
                                  const SizedBox(height: AppSizes.md),
                                  _buildFeatureItem(
                                    isAdminMode
                                        ? Icons.security
                                        : Icons.receipt_long,
                                    isAdminMode
                                        ? 'Secure Access'
                                        : 'GST Ready Invoices',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              // Visit Website link (web only)
                              if (kIsWeb && !isAdminMode)
                                TextButton.icon(
                                  onPressed: () {
                                    launchUrl(
                                      Uri.parse(websiteUrl),
                                      webOnlyWindowName: '_self',
                                    );
                                  },
                                  icon: const Icon(
                                    Icons.language,
                                    size: AppSizes.iconSm,
                                    color: Colors.white70,
                                  ),
                                  label: const Text(
                                    '← Visit Website',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          // Right form panel
          Expanded(
            flex: isTablet ? 60 : 55,
            child: Container(
              color: AppColors.background,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isTablet ? 28 : 48),
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Back button
                          if (onBack != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSizes.xl,
                              ),
                              child: TextButton.icon(
                                onPressed: onBack,
                                icon: const Icon(
                                  Icons.arrow_back,
                                  size: AppSizes.iconSm,
                                ),
                                label: const Text('Back'),
                              ),
                            ),
                          // Title
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: isAdminMode
                                  ? const Color(0xFF7C3AED)
                                  : AppColors.primary,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSizes.sm),
                            Text(
                              subtitle!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSizes.xl + AppSizes.md),
                          // Form content — forced light theme for all widgets
                          Theme(data: _lightAuthTheme(context), child: child),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSizes.sm),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          child: Icon(icon, size: AppSizes.iconSm, color: Colors.white),
        ),
        const SizedBox(width: AppSizes.cardPadding),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.95),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
