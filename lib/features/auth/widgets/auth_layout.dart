/// Shared auth layout for consistent login/register screens
library;

import 'package:retaillite/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:retaillite/core/design/design_system.dart';

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
}
