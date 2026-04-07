/// Login screen — Google Sign-In (primary) + Email/Password (secondary)
/// with smart sign-in method detection (Option C)
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:retaillite/core/utils/website_url.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/auth/widgets/auth_layout.dart';
import 'package:retaillite/features/auth/widgets/auth_social_section.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  late bool _showEmailForm;
  bool _isCheckingEmail = false;

  // Windows desktop needs special handling for Google Sign-In
  bool get _isWindowsDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    // On Windows, auto-expand email form since it's the primary login method
    // Google button is still shown but opens browser
    _showEmailForm = _isWindowsDesktop;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    ref.read(authNotifierProvider.notifier).clearError();

    try {
      final success = await ref
          .read(authNotifierProvider.notifier)
          .signInWithGoogle();
      // If linking is needed, show password dialog
      if (!success && mounted) {
        final authState = ref.read(authNotifierProvider);
        if (authState.pendingAccountLink) {
          _showLinkPasswordDialog(authState.pendingLinkEmail ?? '');
        }
      }
      // Router redirect handles navigation automatically
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  /// Show dialog to enter password for account linking
  void _showLinkPasswordDialog(String email) {
    final linkPasswordController = TextEditingController();
    bool obscure = true;
    bool linking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Link Your Account'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'An account with $email already exists. '
                'Enter your password to link Google sign-in to this account.',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: linkPasswordController,
                obscureText: obscure,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Password',
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
                onSubmitted: linking
                    ? null
                    : (_) async {
                        setDialogState(() => linking = true);
                        final success = await ref
                            .read(authNotifierProvider.notifier)
                            .completeLinkWithPassword(
                              linkPasswordController.text,
                            );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                        }
                        if (!success && mounted) {
                          final error = ref.read(authErrorProvider);
                          if (error != null) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text(error)));
                          }
                        }
                      },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: linking
                  ? null
                  : () {
                      ref
                          .read(authNotifierProvider.notifier)
                          .cancelPendingLink();
                      Navigator.pop(ctx);
                    },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: linking
                  ? null
                  : () async {
                      setDialogState(() => linking = true);
                      final success = await ref
                          .read(authNotifierProvider.notifier)
                          .completeLinkWithPassword(
                            linkPasswordController.text,
                          );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (!success && mounted) {
                        final error = ref.read(authErrorProvider);
                        if (error != null) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text(error)));
                        }
                      }
                    },
              child: linking
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Link & Sign In'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _isCheckingEmail = true;
    });
    ref.read(authNotifierProvider.notifier).clearError();

    try {
      final email = _emailController.text.trim();

      if (mounted) setState(() => _isCheckingEmail = false);

      // Attempt sign-in directly — don't enumerate auth methods
      // to avoid revealing whether an email is registered.
      final success = await ref
          .read(authNotifierProvider.notifier)
          .signIn(email: email, password: _passwordController.text);

      // Router redirect handles navigation automatically
      if (!success && mounted) {
        // Error already set in auth provider
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authErrorProvider);

    return AuthLayout(
      title: 'Welcome',
      subtitle: 'Sign in to manage your shop',
      icon: Icons.storefront,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Error message
          if (error != null) ...[
            _buildErrorBox(error),
            const SizedBox(height: AppSizes.md),
          ],

          // ── Google + OR + Email Toggle (shared widget) ──
          AuthSocialSection(
            isGoogleLoading: _isGoogleLoading,
            isOtherLoading: _isLoading,
            showEmailForm: _showEmailForm,
            emailButtonLabel: 'Sign in with Email',
            onGooglePressed: _handleGoogleLogin,
            onEmailToggle: () => setState(() => _showEmailForm = true),
          ),

          // ── Email/Password Form ──
          if (_showEmailForm)
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Email field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      hintText: 'Enter your email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Email is required';
                      }
                      if (!RegExp(
                        r'^[^@]+@[^@]+\.[^@]+',
                      ).hasMatch(value.trim())) {
                        return 'Enter a valid email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleEmailLogin(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSizes.sm),

                  // Forgot Password link
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => context.push('/forgot-password'),
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSizes.md),

                  // Login button
                  SizedBox(
                    height: AppSizes.buttonHeight(context),
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _handleEmailLogin,
                      icon: _isLoading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login, size: 22),
                      label: Text(
                        _isCheckingEmail
                            ? 'Checking...'
                            : _isLoading
                            ? 'Signing in...'
                            : 'Sign In',
                        style: AppTypography.button,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSizes.lg),

          // Register link
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Don't have an account? ",
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              TextButton(
                onPressed: _isLoading ? null : () => context.push('/register'),
                child: const Text(
                  'Register',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ],
          ),

          // Try Demo Store
          const SizedBox(height: AppSizes.sm),
          TextButton.icon(
            onPressed: _isLoading || _isGoogleLoading
                ? null
                : () {
                    ref.read(authNotifierProvider.notifier).startDemoMode();
                  },
            icon: const Icon(
              Icons.science_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            label: const Text(
              'Try Demo Store',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),

          // Visit Website link (web only)
          if (kIsWeb) ...[
            const SizedBox(height: AppSizes.sm),
            const Divider(color: AppColors.border),
            const SizedBox(height: AppSizes.sm),
            TextButton.icon(
              onPressed: () {
                launchUrl(Uri.parse(websiteUrl), webOnlyWindowName: '_self');
              },
              icon: Icon(
                Icons.language,
                size: AppSizes.iconSm,
                color: AppColors.primary,
              ),
              label: Text(
                'Visit Website',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          // Super Admin link (subtle)
          const SizedBox(height: AppSizes.xs),
          GestureDetector(
            onTap: () => context.go('/super-admin/login'),
            child: Text(
              'Super Admin',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBox(String error) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: AppColors.error,
            size: AppSizes.iconMd,
          ),
          const SizedBox(width: AppSizes.cardPadding),
          Expanded(
            child: Text(
              error,
              style: const TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
