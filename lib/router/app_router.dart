/// App routing configuration using go_router (local mode)
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/services/analytics_service.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/auth/screens/desktop_login_bridge_screen.dart';
import 'package:retaillite/features/auth/screens/login_screen.dart';
import 'package:retaillite/features/auth/screens/register_screen.dart';
import 'package:retaillite/features/auth/screens/forgot_password_screen.dart';
import 'package:retaillite/features/auth/screens/shop_setup_screen.dart';
import 'package:retaillite/features/billing/screens/billing_screen.dart';
import 'package:retaillite/features/billing/screens/bills_history_screen.dart';
import 'package:retaillite/features/khata/screens/khata_web_screen.dart';
import 'package:retaillite/features/khata/screens/customer_detail_screen.dart';
import 'package:retaillite/features/products/screens/products_web_screen.dart';
import 'package:retaillite/features/products/screens/product_detail_screen.dart';
import 'package:retaillite/features/reports/screens/dashboard_web_screen.dart';
import 'package:retaillite/features/settings/screens/settings_web_screen.dart';
import 'package:retaillite/features/settings/screens/theme_settings_screen.dart';
import 'package:retaillite/features/shell/app_shell.dart';
import 'package:retaillite/features/super_admin/screens/super_admin_dashboard_screen.dart';
import 'package:retaillite/features/super_admin/screens/users_list_screen.dart';
import 'package:retaillite/features/super_admin/screens/user_detail_screen.dart';
import 'package:retaillite/features/super_admin/screens/subscriptions_screen.dart';
import 'package:retaillite/features/super_admin/screens/analytics_screen.dart';
import 'package:retaillite/features/super_admin/screens/errors_screen.dart';
import 'package:retaillite/features/super_admin/screens/performance_screen.dart';
import 'package:retaillite/features/super_admin/screens/user_costs_screen.dart';
import 'package:retaillite/features/super_admin/screens/manage_admins_screen.dart';
import 'package:retaillite/features/super_admin/screens/admin_shell_screen.dart';
import 'package:retaillite/features/super_admin/screens/super_admin_login_screen.dart';
import 'package:retaillite/features/super_admin/screens/notifications_admin_screen.dart';
import 'package:retaillite/features/super_admin/screens/referrals_admin_screen.dart';
import 'package:retaillite/features/super_admin/screens/support_admin_screen.dart';
import 'package:retaillite/features/super_admin/screens/admin_chat_screen.dart';
import 'package:retaillite/features/super_admin/providers/super_admin_provider.dart';
import 'package:retaillite/features/staff/screens/staff_list_screen.dart';
import 'package:retaillite/features/staff/screens/staff_detail_screen.dart';
import 'package:retaillite/features/staff/screens/attendance_screen.dart';
import 'package:retaillite/features/staff/screens/my_attendance_screen.dart';
import 'package:retaillite/features/vendor/screens/vendor_list_screen.dart';
import 'package:retaillite/features/vendor/screens/vendor_detail_screen.dart';
import 'package:retaillite/features/store/screens/my_stores_screen.dart';
import 'package:retaillite/features/store/screens/user_management_screen.dart';
import 'package:retaillite/features/support/screens/my_tickets_screen.dart';
import 'package:retaillite/features/support/screens/ticket_chat_screen.dart';
import 'package:retaillite/features/notifications/screens/notifications_screen.dart';
import 'package:retaillite/features/subscription/screens/subscription_screen.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/error_logging_service.dart';
import 'package:retaillite/core/services/performance_service.dart';
import 'package:retaillite/core/widgets/splash_screen.dart';

/// Route paths
class AppRoutes {
  AppRoutes._();

  static const String loading = '/loading';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String shopSetup = '/shop-setup';
  static const String billing = '/billing';
  static const String khata = '/khata';
  static const String customerDetail = '/customer/:id';
  static const String products = '/products';
  static const String productDetail = '/product/:id';
  static const String dashboard = '/dashboard';
  static const String bills = '/bills';
  static const String staff = '/staff';
  static const String staffDetail = '/staff/:id';
  static const String attendance = '/attendance';
  static const String myAttendance = '/my-attendance';
  static const String vendors = '/vendors';
  static const String vendorDetail = '/vendors/:id';
  static const String myStores = '/my-stores';
  static const String userManagement = '/user-management';
  static const String settings = '/settings';
  static const String settingsTab = '/settings/:tab';
  static const String themeSettings = '/settings/theme';
  static const String subscription = '/subscription';

  // Super Admin routes
  static const String superAdminLogin = '/super-admin/login';
  static const String superAdmin = '/super-admin';
  static const String superAdminUsers = '/super-admin/users';
  static const String superAdminUserDetail = '/super-admin/users/:id';
  static const String superAdminSubscriptions = '/super-admin/subscriptions';
  static const String superAdminAnalytics = '/super-admin/analytics';
  static const String superAdminErrors = '/super-admin/errors';
  static const String superAdminPerformance = '/super-admin/performance';
  static const String superAdminUserCosts = '/super-admin/user-costs';
  static const String superAdminManageAdmins = '/super-admin/manage-admins';
  static const String superAdminNotifications = '/super-admin/notifications';
  static const String superAdminReferrals = '/super-admin/referrals';
  static const String superAdminSupport = '/super-admin/support';
  static const String superAdminSupportChat = '/super-admin/support/:ticketId';
  static const String support = '/support';
  static const String supportChat = '/support/:ticketId';
  static const String notifications = '/notifications';
}

// Super admin emails imported from super_admin_provider.dart (single source of truth)

/// Bridge between Riverpod auth state and GoRouter's refreshListenable.
/// This notifies GoRouter to re-evaluate redirects when auth state changes,
/// WITHOUT recreating the entire GoRouter instance.
class _AuthChangeNotifier extends ChangeNotifier {
  _AuthChangeNotifier(Ref ref) {
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      notifyListeners();
    });
  }
}

/// Key for persisting the last route in SharedPreferences
const String _lastRouteKey = 'last_route';

/// Debounce timer for route persistence (avoids excessive SharedPrefs writes)
Timer? _routePersistTimer;

/// Debounced route persistence — writes to SharedPrefs after 1s idle
void _persistRoute(String fullUri) {
  _routePersistTimer?.cancel();
  _routePersistTimer = Timer(const Duration(seconds: 1), () {
    OfflineStorageService.prefs?.setString(_lastRouteKey, fullUri);
  });
}

/// Read the last saved route from SharedPreferences (sync, prefs already init'd)
String _getRestoredInitialLocation() {
  final saved = OfflineStorageService.prefs?.getString(_lastRouteKey);
  if (saved != null && saved.isNotEmpty && saved.startsWith('/')) {
    debugPrint('🔄 Restoring initial location from SharedPreferences: $saved');
    return saved;
  }
  return AppRoutes.billing;
}

/// Router provider
final routerProvider = Provider<GoRouter>((ref) {
  final authChangeNotifier = _AuthChangeNotifier(ref);
  ref.onDispose(() => authChangeNotifier.dispose());

  // Use the last saved route as initialLocation.
  // On fresh install this is /billing; after that, it's whatever page the user was on.
  final restoredLocation = _getRestoredInitialLocation();

  // In-memory variable to remember the pre-loading URL during auth initialization.
  // Because initialLocation = restoredLocation, the first redirect sees the correct path.
  String? pendingRedirect;

  return GoRouter(
    initialLocation: restoredLocation,
    debugLogDiagnostics: true,
    // Re-evaluate redirects when auth state changes (no GoRouter recreation)
    refreshListenable: authChangeNotifier,
    // Track route changes for error context
    observers: [_ErrorRouteObserver()],

    redirect: (context, state) {
      // Read auth state inside redirect (not watch — GoRouter is not recreated)
      final authState = ref.read(authNotifierProvider);
      final isLoggedIn = authState.isLoggedIn;
      final isShopSetupComplete = authState.isShopSetupComplete;
      final isLoading = authState.isLoading;
      final userEmail = authState.user?.email?.toLowerCase().trim() ?? '';
      final isSuperAdminUser = superAdminEmails.contains(userEmail);

      final currentPath = state.matchedLocation;
      final fullUri = state.uri.toString();
      final isLoadingRoute = currentPath == AppRoutes.loading;

      // While auth is initializing, show the loading screen.
      // Capture the current URL so we can restore after auth resolves.
      if (isLoading) {
        if (!isLoadingRoute) {
          pendingRedirect = fullUri;
        }
        return isLoadingRoute ? null : AppRoutes.loading;
      }

      // Auth is resolved — leave the loading screen
      if (isLoadingRoute) {
        final destination = !isLoggedIn
            ? AppRoutes.login
            : (!isShopSetupComplete && !isSuperAdminUser)
            ? AppRoutes.shopSetup
            : (pendingRedirect ?? restoredLocation);
        if (!isLoggedIn || (isShopSetupComplete || isSuperAdminUser)) {
          pendingRedirect = null;
        }
        // If the restored target is a super-admin route, only allow if admin
        if (destination.startsWith('/super-admin') && !isSuperAdminUser) {
          return AppRoutes.billing;
        }
        return destination;
      }

      final isAuthRoute =
          currentPath == AppRoutes.login ||
          currentPath == AppRoutes.register ||
          currentPath == AppRoutes.forgotPassword ||
          currentPath == AppRoutes.superAdminLogin ||
          currentPath == '/desktop-login';
      final isShopSetupRoute = currentPath == AppRoutes.shopSetup;
      final isSuperAdminRoute = currentPath.startsWith('/super-admin');
      final isGoingToSuperAdmin = fullUri.startsWith('/super-admin');

      // Not logged in
      if (!isLoggedIn) {
        // Allow auth routes (including super admin login)
        if (isAuthRoute) return null;
        // Redirect to login
        return AppRoutes.login;
      }

      // Allow super admin routes only for authorized admin emails
      if (isSuperAdminRoute || isGoingToSuperAdmin) {
        if (isSuperAdminUser) {
          // Already logged in admin on login page → go to dashboard
          if (currentPath == AppRoutes.superAdminLogin) {
            return '/super-admin';
          }
          // Persist super-admin route for refresh restoration
          _persistRoute(fullUri);
          return null; // Authorized — allow
        }
        return AppRoutes.billing; // Not authorized — send to store
      }

      // Regular user: Logged in but shop setup not complete
      // Super admins bypass shop setup entirely
      // Users with store memberships (created via Add User) also bypass
      if (!isShopSetupComplete && !isSuperAdminUser) {
        // Allow shop setup route and my-stores route
        if (isShopSetupRoute || currentPath == AppRoutes.myStores) return null;
        // Redirect to shop setup
        return AppRoutes.shopSetup;
      }

      // Logged in and setup complete (or super admin)
      if (isAuthRoute || isShopSetupRoute) {
        // Redirect auth routes to billing
        return AppRoutes.billing;
      }

      // ── Persist current route for restoration after web refresh ──
      // Save all app routes (but not auth/login pages)
      if (isLoggedIn && !isAuthRoute) {
        _persistRoute(fullUri);
      }

      return null;
    },

    routes: [
      // Loading route — shown while Firebase Auth initializes
      // Uses _LoadingGuard to actively watch auth state and force GoRouter
      // to re-evaluate redirect when auth resolves (workaround for
      // refreshListenable not always firing on web).
      GoRoute(
        path: AppRoutes.loading,
        builder: (context, state) => const _LoadingGuard(),
      ),

      // Auth routes (outside shell)
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      // Desktop login bridge — used by Windows app for Google Sign-In
      GoRoute(
        path: '/desktop-login',
        builder: (context, state) {
          final code = state.uri.queryParameters['code'];
          return DesktopLoginBridgeScreen(linkCode: code);
        },
      ),
      GoRoute(
        path: AppRoutes.shopSetup,
        builder: (context, state) => const ShopSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.myStores,
        builder: (context, state) => const MyStoresScreen(),
      ),

      // Main app shell with tabs
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.billing,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BillingScreen()),
          ),
          GoRoute(
            path: AppRoutes.khata,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: KhataWebScreen()),
          ),
          GoRoute(
            path: AppRoutes.products,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ProductsWebScreen()),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: DashboardWebScreen()),
          ),
          GoRoute(
            path: AppRoutes.bills,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: BillsHistoryScreen()),
          ),
          GoRoute(
            path: AppRoutes.staff,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: StaffListScreen()),
          ),
          GoRoute(
            path: AppRoutes.attendance,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AttendanceScreen()),
          ),
          GoRoute(
            path: AppRoutes.myAttendance,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: MyAttendanceScreen()),
          ),
          GoRoute(
            path: AppRoutes.staffDetail,
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return NoTransitionPage(child: StaffDetailScreen(staffId: id));
            },
          ),
          GoRoute(
            path: AppRoutes.vendors,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: VendorListScreen()),
          ),
          GoRoute(
            path: AppRoutes.vendorDetail,
            pageBuilder: (context, state) {
              final id = state.pathParameters['id'] ?? '';
              return NoTransitionPage(child: VendorDetailScreen(vendorId: id));
            },
          ),
          GoRoute(
            path: AppRoutes.userManagement,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: UserManagementScreen()),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.settingsTab,
        pageBuilder: (context, state) {
          final tab = state.pathParameters['tab'] ?? 'general';
          return NoTransitionPage(child: SettingsWebScreen(initialTab: tab));
        },
      ),

      // Detail screens (outside shell)
      GoRoute(
        path: AppRoutes.customerDetail,
        builder: (context, state) {
          final customerId = state.pathParameters['id']!;
          return CustomerDetailScreen(customerId: customerId);
        },
      ),
      GoRoute(
        path: AppRoutes.productDetail,
        builder: (context, state) {
          final productId = state.pathParameters['id']!;
          return ProductDetailScreen(productId: productId);
        },
      ),
      // Redirect bare /settings to /settings/general
      GoRoute(
        path: AppRoutes.settings,
        redirect: (context, state) => '/settings/general',
      ),
      GoRoute(
        path: AppRoutes.themeSettings,
        builder: (context, state) => const ThemeSettingsScreen(),
      ),

      // Subscription / upgrade screen
      GoRoute(
        path: AppRoutes.subscription,
        builder: (context, state) => const SubscriptionScreen(),
      ),

      // User notifications inbox (outside main shell)
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Store-side support tickets
      GoRoute(
        path: AppRoutes.support,
        builder: (context, state) => const MyTicketsScreen(),
      ),
      GoRoute(
        path: AppRoutes.supportChat,
        builder: (context, state) {
          final ticketId = state.pathParameters['ticketId']!;
          return TicketChatScreen(ticketId: ticketId);
        },
      ),

      // Super Admin login (outside shell)
      GoRoute(
        path: AppRoutes.superAdminLogin,
        builder: (context, state) => const SuperAdminLoginScreen(),
      ),

      // Super Admin pages (inside admin shell with persistent sidebar)
      ShellRoute(
        builder: (context, state, child) => AdminShellScreen(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.superAdmin,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SuperAdminDashboardScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminUsers,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: UsersListScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminUserDetail,
            pageBuilder: (context, state) {
              final userId = state.pathParameters['id']!;
              return NoTransitionPage(child: UserDetailScreen(userId: userId));
            },
          ),
          GoRoute(
            path: AppRoutes.superAdminSubscriptions,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SubscriptionsScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminAnalytics,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: AnalyticsScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminErrors,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ErrorsScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminPerformance,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: PerformanceScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminUserCosts,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: UserCostsScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminManageAdmins,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ManageAdminsScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminNotifications,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: NotificationsAdminScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminReferrals,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: ReferralsAdminScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminSupport,
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SupportAdminScreen()),
          ),
          GoRoute(
            path: AppRoutes.superAdminSupportChat,
            pageBuilder: (context, state) {
              final ticketId = state.pathParameters['ticketId']!;
              return NoTransitionPage(
                child: AdminChatScreen(ticketId: ticketId),
              );
            },
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('Page not found: ${state.uri}'))),
  );
});

/// Route observer that auto-tracks current screen for error context
class _ErrorRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _trackRoute(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (newRoute != null) _trackRoute(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (previousRoute != null) _trackRoute(previousRoute);
  }

  void _trackRoute(Route<dynamic> route) {
    final name = route.settings.name;
    if (name != null && name.isNotEmpty) {
      ErrorLoggingService.setCurrentScreen(name);
      // Log screen view to Firebase Analytics
      AnalyticsService.logScreenView(name);
      // Track screen load timing for performance dashboard
      PerformanceService.startScreenTiming(name);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        PerformanceService.endScreenTiming(name);
      });
    }
  }
}

/// Loading screen wrapper that actively watches auth state.
/// When auth resolves (isLoading becomes false), it forces GoRouter to
/// re-evaluate its redirect, navigating away from the loading screen.
/// This is needed because GoRouter's refreshListenable can miss state
/// changes that happen during async stream callbacks on web.
class _LoadingGuard extends ConsumerStatefulWidget {
  const _LoadingGuard();

  @override
  ConsumerState<_LoadingGuard> createState() => _LoadingGuardState();
}

class _LoadingGuardState extends ConsumerState<_LoadingGuard> {
  @override
  void initState() {
    super.initState();
    // Also poll as a safety net in case ref.listen doesn't trigger
    _pollAuth();
  }

  void _pollAuth() {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      final authState = ref.read(authNotifierProvider);
      if (!authState.isLoading) {
        ref.read(routerProvider).refresh();
      } else {
        _pollAuth(); // Keep polling
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(
      authNotifierProvider.select((s) => s.isLoading),
    );

    // When auth resolves, force GoRouter to re-evaluate redirect
    if (!isLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(routerProvider).refresh();
        }
      });
    }

    return const SplashScreen(message: 'Loading...');
  }
}
