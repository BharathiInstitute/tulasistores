import 'package:flutter/material.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/notifications/providers/notification_provider.dart';
import 'package:retaillite/features/notifications/widgets/notification_bell.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/core/utils/permission_guard.dart';
import 'package:retaillite/shared/widgets/global_sync_indicator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/utils/website_url.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/auth/widgets/demo_mode_banner.dart';
import 'package:retaillite/router/app_router.dart';
import 'package:retaillite/shared/widgets/shop_logo_widget.dart';
import 'package:retaillite/shared/widgets/offline_banner.dart';
import 'package:retaillite/shared/widgets/plan_badge.dart';
import 'package:url_launcher/url_launcher.dart';

/// User-toggled sidebar collapse state. null = auto (follow screen width)
final sidebarCollapsedProvider = StateProvider<bool?>((ref) => null);

class WebShell extends ConsumerWidget {
  final Widget child;
  final int selectedIndex;
  final Function(int) onItemTapped;

  const WebShell({
    super.key,
    required this.child,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Current location for breadcrumbs/title
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          // Demo mode banner at the very top if active
          const DemoModeBanner(),
          const OfflineBanner(),

          Expanded(
            child: Row(
              children: [
                // Sidebar
                _WebSidebar(
                  selectedIndex: selectedIndex,
                  onItemTapped: onItemTapped,
                  currentPath: location,
                ),

                // Main Content Area
                Expanded(
                  child: Column(
                    children: [
                      // Header (hide for screens that have their own header)
                      if (!location.startsWith(AppRoutes.billing) &&
                          !location.startsWith(AppRoutes.khata) &&
                          !location.startsWith(AppRoutes.products) &&
                          !location.startsWith(AppRoutes.bills) &&
                          !location.startsWith(AppRoutes.dashboard))
                        _WebHeader(currentPath: location),

                      // Content
                      Expanded(child: child),
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
}

class _WebSidebar extends ConsumerWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;
  final String currentPath;

  const _WebSidebar({
    required this.selectedIndex,
    required this.onItemTapped,
    required this.currentPath,
  });

  /// Build profile avatar that handles both URL and local file
  Widget _buildProfileAvatar(String? logoPath, double radius, bool isSelected) {
    final hasImage = logoPath != null && logoPath.isNotEmpty;

    if (!hasImage) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: isSelected ? AppColors.primary : Colors.grey,
        child: Icon(Icons.person, size: radius, color: Colors.white),
      );
    }

    if (logoPath.startsWith('http')) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(logoPath),
        backgroundColor: isSelected ? AppColors.primary : Colors.grey,
        onBackgroundImageError: (e, _) {
          debugPrint('⚠️ Shell avatar image error: $e');
        },
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: isSelected ? AppColors.primary : Colors.grey,
      child: Icon(Icons.person, size: radius, color: Colors.white),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final activeStore = ref.watch(activeStoreProvider).valueOrNull;
    // Use active store name if available, else fall back to user profile
    final shopName =
        activeStore?.shopName ?? user?.shopName ?? AppConstants.defaultShopName;
    // Identify if we are in settings (since it might be outside standard index)
    final isSettings = currentPath.startsWith(AppRoutes.settings);
    final userToggle = ref.watch(sidebarCollapsedProvider);
    final autoCollapsed = MediaQuery.of(context).size.width < 800;
    final isCollapsed = userToggle ?? autoCollapsed;
    final sidebarWidth = isCollapsed
        ? 72.0
        : (ResponsiveHelper.isDesktopLarge(context) ? 280.0 : 240.0);

    return Container(
      width: sidebarWidth,
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: Column(
        children: [
          // Logo Area
          Container(
            height: 70,
            padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 0 : 24),
            alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
            child: isCollapsed
                ? ShopLogoWidget(logoPath: user?.shopLogoPath)
                : Row(
                    children: [
                      ShopLogoWidget(logoPath: user?.shopLogoPath),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          shopName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
          ),

          const SizedBox(height: 8),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 8 : 16),
              children: [
                _SidebarItem(
                  icon: Icons.point_of_sale_outlined,
                  label: 'POS',
                  isSelected: selectedIndex == 0,
                  isCollapsed: isCollapsed,
                  onTap: () => onItemTapped(0),
                ),
                if (canView(ref, 'customers'))
                  _SidebarItem(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Khata Ledger',
                    isSelected: selectedIndex == 1,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(1),
                  ),
                if (canView(ref, 'inventory'))
                  _SidebarItem(
                    icon: Icons.inventory_2_outlined,
                    label: 'Inventory',
                    isSelected: selectedIndex == 2,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(2),
                  ),
                if (canView(ref, 'dashboard'))
                  _SidebarItem(
                    icon: Icons.dashboard_outlined,
                    label: 'Dashboard',
                    isSelected: selectedIndex == 3,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(3),
                  ),
                if (canView(ref, 'bills'))
                  _SidebarItem(
                    icon: Icons.receipt_outlined,
                    label: 'Bills',
                    isSelected: selectedIndex == 4,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(4),
                  ),
                if (canView(ref, 'staff'))
                  _SidebarItem(
                    icon: Icons.people_outlined,
                    label: 'Staff',
                    isSelected: selectedIndex == 5,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(5),
                  ),
                _SidebarItem(
                  icon: Icons.fingerprint,
                  label: 'My Attendance',
                  isSelected: selectedIndex == 6,
                  isCollapsed: isCollapsed,
                  onTap: () => onItemTapped(6),
                ),
                if (canView(ref, 'vendors'))
                  _SidebarItem(
                    icon: Icons.storefront_outlined,
                    label: 'Vendors',
                    isSelected: selectedIndex == 7,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(7),
                  ),

                // Collapse / Expand toggle (middle)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: InkWell(
                    onTap: () {
                      ref.read(sidebarCollapsedProvider.notifier).state =
                          !isCollapsed;
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Tooltip(
                      message: isCollapsed
                          ? 'Expand sidebar'
                          : 'Collapse sidebar',
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          isCollapsed
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),

                const Divider(height: 16),

                _SidebarItem(
                  icon: Icons.store_outlined,
                  label: 'My Stores',
                  isSelected: selectedIndex == 8,
                  isCollapsed: isCollapsed,
                  onTap: () => onItemTapped(8),
                ),
                if (canView(ref, 'userManagement'))
                  _SidebarItem(
                    icon: Icons.manage_accounts_outlined,
                    label: 'User Management',
                    isSelected: selectedIndex == 9,
                    isCollapsed: isCollapsed,
                    onTap: () => onItemTapped(9),
                  ),

                const Divider(height: 32),

                // Notification bell — real-time unread badge
                if (isCollapsed)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: NotificationBell(),
                  )
                else
                  Consumer(
                    builder: (context, ref, _) {
                      final unreadAsync = ref.watch(
                        unreadNotificationCountProvider,
                      );
                      final count = unreadAsync.valueOrNull ?? 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () =>
                                GoRouter.of(context).push('/notifications'),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    count > 0
                                        ? Icons.notifications_active
                                        : Icons.notifications_outlined,
                                    size: 20,
                                    color: count > 0
                                        ? Colors.amber
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Notifications',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  if (count > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        count > 99 ? '99+' : '$count',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                // Support Chat
                _SidebarItem(
                  icon: Icons.support_agent,
                  label: 'Support',
                  isSelected: false,
                  isCollapsed: isCollapsed,
                  onTap: () => GoRouter.of(context).push('/support'),
                ),

                // "Visit Website" — web only, hidden on Android/Windows
                if (showWebsiteLink)
                  _SidebarItem(
                    icon: Icons.language_rounded,
                    label: 'Visit Website',
                    isSelected: false,
                    isCollapsed: isCollapsed,
                    onTap: () {
                      launchUrl(
                        Uri.parse(websiteUrl),
                        webOnlyWindowName: '_self',
                      );
                    },
                  ),
              ],
            ),
          ),

          // User Profile Card (Bottom of Sidebar) - Navigates to Settings
          GestureDetector(
            onTap: () => context.go('/settings/general'),
            child: isCollapsed
                ? Tooltip(
                    message: 'Settings',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSettings
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Theme.of(context).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: isSettings
                            ? Border.all(color: AppColors.primary, width: 1.5)
                            : null,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const GlobalSyncIndicator(),
                          const SizedBox(height: 4),
                          Icon(
                            Icons.settings_outlined,
                            size: 22,
                            color: isSettings
                                ? AppColors.primary
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 6),
                          const PlanBadge(compact: true),
                        ],
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isSettings
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: isSettings
                          ? Border.all(color: AppColors.primary, width: 1.5)
                          : null,
                    ),
                    child: Row(
                      children: [
                        _buildProfileAvatar(
                          user?.profileImagePath,
                          16,
                          isSettings,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                user?.ownerName ?? 'User',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Consumer(
                                builder: (context, ref, _) {
                                  final role = ref.watch(myRoleProvider);
                                  return Text(
                                    role.displayName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  );
                                },
                              ),
                              const SizedBox(height: 4),
                              const PlanBadge(),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const GlobalSyncIndicator(compact: true),
                            const SizedBox(height: 4),
                            Icon(
                              Icons.settings_outlined,
                              size: 18,
                              color: isSettings
                                  ? AppColors.primary
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),

          // App branding footer
          if (!isCollapsed)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                'Powered by Tulasi ERP',
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
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    this.isCollapsed = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final item = Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isCollapsed ? 0 : 12,
              vertical: isCollapsed ? 8 : 12,
            ),
            decoration: BoxDecoration(
              color: isSelected && !isCollapsed
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: isCollapsed
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              width: 1.5,
                            )
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: isSelected
                          ? AppColors.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  )
                : Row(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: isSelected
                            ? AppColors.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? AppColors.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    if (isCollapsed) {
      return Tooltip(message: label, child: item);
    }
    return item;
  }
}

class _WebHeader extends StatelessWidget {
  final String currentPath;

  const _WebHeader({required this.currentPath});

  @override
  Widget build(BuildContext context) {
    String title = 'Dashboard';
    String breadcrumb = 'Home';

    if (currentPath.startsWith(AppRoutes.billing)) {
      title = 'POS / Billing';
      breadcrumb = 'Billing';
    } else if (currentPath.startsWith(AppRoutes.products)) {
      title = 'Inventory Management';
      breadcrumb = 'Inventory';
    } else if (currentPath.startsWith(AppRoutes.dashboard)) {
      title = 'Dashboard';
      breadcrumb = 'Dashboard';
    } else if (currentPath.startsWith(AppRoutes.khata)) {
      title = 'Customer Ledger';
      breadcrumb = 'Khata';
    } else if (currentPath.startsWith(AppRoutes.bills)) {
      title = 'Billing History';
      breadcrumb = 'Bills';
    } else if (currentPath.startsWith(AppRoutes.settings)) {
      title = 'System Settings';
      breadcrumb = 'Settings';
    }

    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: BoxDecoration(color: Theme.of(context).cardColor),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Home',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '/',
                        style: TextStyle(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    Text(
                      breadcrumb,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Header Actions — sync indicator and notification bell
          const GlobalSyncIndicator(),
          const SizedBox(width: 8),
          const NotificationBell(),
        ],
      ),
    );
  }
}
