/// Main app shell with responsive navigation
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/utils/color_utils.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/shared/widgets/logout_dialog.dart';
import 'package:retaillite/shared/widgets/offline_banner.dart';
import 'package:retaillite/features/auth/widgets/demo_mode_banner.dart';
import 'package:retaillite/features/notifications/widgets/notification_bell.dart';
import 'package:retaillite/shared/widgets/global_sync_indicator.dart';
import 'package:retaillite/features/shell/web_shell.dart';
import 'package:retaillite/l10n/app_localizations.dart';
import 'package:retaillite/models/user_model.dart';
import 'package:retaillite/router/app_router.dart';
import 'package:retaillite/shared/widgets/shop_logo_widget.dart';
import 'package:retaillite/shared/widgets/plan_badge.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/features/staff/services/auto_attendance_service.dart';

class AppShell extends ConsumerWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  int _getSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/billing')) return 0;
    if (location.startsWith('/khata')) return 1;
    if (location.startsWith('/products')) return 2;
    if (location.startsWith('/dashboard')) return 3;
    if (location.startsWith('/bills')) return 4;
    if (location.startsWith('/staff')) return 5;
    if (location.startsWith('/my-attendance')) return 6;
    if (location.startsWith('/vendors')) return 7;
    if (location.startsWith('/my-stores')) return 8;
    if (location.startsWith('/user-management')) return 9;
    if (location.startsWith('/settings')) return 10;
    return 0;
  }

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go(AppRoutes.billing);
        break;
      case 1:
        context.go(AppRoutes.khata);
        break;
      case 2:
        context.go(AppRoutes.products);
        break;
      case 3:
        context.go(AppRoutes.dashboard);
        break;
      case 4:
        context.go(AppRoutes.bills);
        break;
      case 5:
        context.go(AppRoutes.staff);
        break;
      case 6:
        context.go(AppRoutes.myAttendance);
        break;
      case 7:
        context.go(AppRoutes.vendors);
        break;
      case 8:
        context.go(AppRoutes.myStores);
        break;
      case 9:
        context.go(AppRoutes.userManagement);
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = _getSelectedIndex(context);
    final deviceType = ResponsiveHelper.getDeviceType(context);

    // Auto-initialize store on every shell rebuild (idempotent — no-op if already done)
    ref.watch(storeInitializerProvider);

    // Auto check-in for staff attendance (hybrid mode)
    ref.listen(storeInitializerProvider, (_, next) {
      if (next.hasValue) {
        AutoAttendanceService.autoCheckIn();
      }
    });

    // Use WebShell for Desktop/Web view (desktop + desktopLarge)
    if (deviceType == DeviceType.desktop ||
        deviceType == DeviceType.desktopLarge) {
      return WebShell(
        selectedIndex: selectedIndex,
        onItemTapped: (index) => _onItemTapped(context, index),
        child: child,
      );
    }

    final user = ref.watch(currentUserProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: deviceType == DeviceType.mobile
          ? AppBar(
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  ShopLogoWidget(
                    logoPath: user?.shopLogoPath,
                    size: 28,
                    borderRadius: 6,
                    iconSize: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      user?.shopName ?? AppConstants.defaultShopName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              actions: [
                const PlanBadge(),
                const SizedBox(width: 4),
                const GlobalSyncIndicator(),
                const NotificationBell(),
                IconButton(
                  icon: _buildProfileAvatar(user?.profileImagePath, 16),
                  onPressed: () => _showProfileSheet(context, ref),
                ),
              ],
              elevation: 0.5,
              backgroundColor: Theme.of(context).cardColor,
              surfaceTintColor: Colors.transparent,
            )
          : null,
      body: Column(
        children: [
          // Demo mode banner
          const DemoModeBanner(),
          const OfflineBanner(),
          Expanded(
            child: Row(
              children: [
                // Side navigation for tablet (Desktop uses WebShell now)
                if (deviceType == DeviceType.tablet)
                  _buildSideNavigation(
                    context,
                    selectedIndex,
                    deviceType,
                    user,
                  ),

                // Main content
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
      // Bottom navigation for mobile
      bottomNavigationBar: deviceType == DeviceType.mobile
          ? _buildBottomNavigation(context, selectedIndex)
          : null,
    );
  }

  /// Build profile avatar that handles both URL and local file
  Widget _buildProfileAvatar(String? logoPath, double radius) {
    final hasImage = logoPath != null && logoPath.isNotEmpty;

    if (!hasImage) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        child: Icon(Icons.person, size: radius, color: AppColors.primary),
      );
    }

    if (logoPath.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(logoPath),
        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
        onBackgroundImageError: (e, _) {
          debugPrint('⚠️ Shell avatar image error: $e');
        },
      );
    }

    // Fallback to icon
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primary.withValues(alpha: 0.1),
      child: Icon(Icons.person, size: radius, color: AppColors.primary),
    );
  }

  void _showProfileSheet(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // User info with edit button
              Stack(
                children: [
                  _buildProfileAvatar(user?.profileImagePath, 28),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        context.go('/settings/account');
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.edit,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Shop name (prominent)
              if (user?.shopName != null && user!.shopName.isNotEmpty) ...[
                Text(
                  user.shopName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
              ],
              // Owner name
              Text(
                user?.ownerName ?? 'User',
                style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if (user?.email != null) ...[
                const SizedBox(height: 2),
                Text(
                  user!.email!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ],

              const SizedBox(height: 8),
              const PlanBadge(),
              const SizedBox(height: 16),
              const Divider(height: 1),

              // Settings
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.settings_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                title: const Text('Settings'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go('/settings/general');
                },
              ),

              // Contact / Support
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.help_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 22,
                ),
                title: const Text('Help & Support'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/support');
                },
              ),

              const Divider(height: 1),

              // Logout
              ListTile(
                dense: true,
                leading: const Icon(Icons.logout, color: Colors.red, size: 22),
                title: const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showLogoutDialog(context, ref);
                },
              ),

              const SizedBox(height: 16),
              Text(
                'Powered by ${AppConstants.appName}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigation(BuildContext context, int selectedIndex) {
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            color: OpacityColors.black10,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: BottomNavigationBar(
          currentIndex: selectedIndex,
          onTap: (index) => _onItemTapped(context, index),
          type: BottomNavigationBarType.fixed,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.point_of_sale_outlined),
              activeIcon: Icon(Icons.point_of_sale),
              label: 'POS',
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.people_outline),
              activeIcon: const Icon(Icons.people),
              label: l10n.khata,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.inventory_2_outlined),
              activeIcon: const Icon(Icons.inventory_2),
              label: l10n.products,
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard_outlined),
              activeIcon: const Icon(Icons.dashboard),
              label: l10n.dashboard,
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.receipt_outlined),
              activeIcon: Icon(Icons.receipt),
              label: 'Bills',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideNavigation(
    BuildContext context,
    int selectedIndex,
    DeviceType deviceType,
    UserModel? user,
  ) {
    final isExpanded = deviceType == DeviceType.desktop;
    final l10n = context.l10n;

    return Container(
      width: AppSizes.sidebarWidth(context),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            color: OpacityColors.black05,
            blurRadius: 8,
            offset: Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Logo/Header
          Container(
            height: 64,
            padding: EdgeInsets.symmetric(
              horizontal: isExpanded ? 16 : 8,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                ShopLogoWidget(logoPath: user?.shopLogoPath),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      user?.shopName ?? l10n.appName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),

          // Navigation items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(
                  icon: Icons.point_of_sale,
                  label: 'POS',
                  isSelected: selectedIndex == 0,
                  isExpanded: isExpanded,
                  onTap: () => _onItemTapped(context, 0),
                ),
                _NavItem(
                  icon: Icons.people,
                  label: l10n.khata,
                  isSelected: selectedIndex == 1,
                  isExpanded: isExpanded,
                  onTap: () => _onItemTapped(context, 1),
                ),
                _NavItem(
                  icon: Icons.inventory_2,
                  label: l10n.products,
                  isSelected: selectedIndex == 2,
                  isExpanded: isExpanded,
                  onTap: () => _onItemTapped(context, 2),
                ),
                _NavItem(
                  icon: Icons.dashboard,
                  label: l10n.dashboard,
                  isSelected: selectedIndex == 3,
                  isExpanded: isExpanded,
                  onTap: () => _onItemTapped(context, 3),
                ),
                _NavItem(
                  icon: Icons.receipt,
                  label: 'Bills',
                  isSelected: selectedIndex == 4,
                  isExpanded: isExpanded,
                  onTap: () => _onItemTapped(context, 4),
                ),
              ],
            ),
          ),

          // Sync indicator
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: GlobalSyncIndicator(),
          ),

          // Support & Settings at bottom
          const Divider(height: 1),
          _NavItem(
            icon: Icons.support_agent,
            label: 'Support',
            isSelected: false,
            isExpanded: isExpanded,
            onTap: () => context.push('/support'),
          ),
          _NavItem(
            icon: Icons.settings,
            label: l10n.settings,
            isSelected: false,
            isExpanded: isExpanded,
            onTap: () => context.go('/settings/general'),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Powered by ${AppConstants.appName}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                  letterSpacing: 0.3,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 2,
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isExpanded ? 8 : 4,
        vertical: 2,
      ),
      child: Material(
        color: isSelected ? OpacityColors.primary10 : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: isExpanded ? 12 : 0),
            child: Row(
              mainAxisAlignment: isExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? AppColors.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
