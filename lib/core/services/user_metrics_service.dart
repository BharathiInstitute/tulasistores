/// User metrics service for tracking activity and syncing to Firestore
/// This data is used by the Super Admin Panel
library;

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:retaillite/core/services/error_logging_service.dart';
import 'package:retaillite/core/config/plan_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Subscription plans
enum SubscriptionPlan { free, pro, business }

/// Subscription status
enum SubscriptionStatus { active, trial, expired, cancelled }

/// User subscription model
class UserSubscription {
  final SubscriptionPlan plan;
  final SubscriptionStatus status;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final String? razorpayCustomerId;
  final String? razorpaySubscriptionId;

  UserSubscription({
    this.plan = SubscriptionPlan.free,
    this.status = SubscriptionStatus.active,
    this.startedAt,
    this.expiresAt,
    this.razorpayCustomerId,
    this.razorpaySubscriptionId,
  });

  Map<String, dynamic> toMap() => {
    'plan': plan.name,
    'status': status.name,
    'startedAt': startedAt != null ? Timestamp.fromDate(startedAt!) : null,
    'expiresAt': expiresAt != null ? Timestamp.fromDate(expiresAt!) : null,
    'razorpayCustomerId': razorpayCustomerId,
    'razorpaySubscriptionId': razorpaySubscriptionId,
  };

  factory UserSubscription.fromMap(Map<String, dynamic>? map) {
    if (map == null) return UserSubscription();
    return UserSubscription(
      plan: SubscriptionPlan.values.firstWhere(
        (e) => e.name == map['plan'],
        orElse: () => SubscriptionPlan.free,
      ),
      status: SubscriptionStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => SubscriptionStatus.active,
      ),
      startedAt: (map['startedAt'] as Timestamp?)?.toDate(),
      expiresAt: (map['expiresAt'] as Timestamp?)?.toDate(),
      razorpayCustomerId: map['razorpayCustomerId'] as String?,
      razorpaySubscriptionId: map['razorpaySubscriptionId'] as String?,
    );
  }

  /// Get plan limits
  int get billsLimit => PlanConfig.limitsFor(plan).maxBillsPerMonth;

  int get productsLimit => PlanConfig.limitsFor(plan).maxProducts;

  int get customersLimit => PlanConfig.limitsFor(plan).maxCustomers;

  int get staffLimit => PlanConfig.limitsFor(plan).maxStaff;

  int get storesLimit => PlanConfig.limitsFor(plan).maxStores;

  bool get isActive =>
      status == SubscriptionStatus.active || status == SubscriptionStatus.trial;
}

/// User activity tracking
class UserActivity {
  final DateTime? lastActiveAt;
  final String? appVersion;
  final String? platform;
  final String? deviceModel;

  UserActivity({
    this.lastActiveAt,
    this.appVersion,
    this.platform,
    this.deviceModel,
  });

  Map<String, dynamic> toMap() => {
    'lastActiveAt': lastActiveAt != null
        ? Timestamp.fromDate(lastActiveAt!)
        : FieldValue.serverTimestamp(),
    'appVersion': appVersion,
    'platform': platform,
    'deviceModel': deviceModel,
  };
}

/// User limits tracking
class UserLimits {
  final int billsThisMonth;
  final int billsLimit;
  final int productsCount;
  final int productsLimit;
  final int customersCount;
  final int customersLimit;

  UserLimits({
    this.billsThisMonth = 0,
    this.billsLimit = 50,
    this.productsCount = 0,
    this.productsLimit = 100,
    this.customersCount = 0,
    this.customersLimit = 10,
  });

  Map<String, dynamic> toMap() => {
    'billsThisMonth': billsThisMonth,
    'billsLimit': billsLimit,
    'productsCount': productsCount,
    'productsLimit': productsLimit,
    'customersCount': customersCount,
    'customersLimit': customersLimit,
  };

  factory UserLimits.fromMap(Map<String, dynamic>? map) {
    if (map == null) return UserLimits();
    return UserLimits(
      billsThisMonth: (map['billsThisMonth'] as num?)?.toInt() ?? 0,
      billsLimit: (map['billsLimit'] as num?)?.toInt() ?? 50,
      productsCount: (map['productsCount'] as num?)?.toInt() ?? 0,
      productsLimit: (map['productsLimit'] as num?)?.toInt() ?? 100,
      customersCount: (map['customersCount'] as num?)?.toInt() ?? 0,
      customersLimit: (map['customersLimit'] as num?)?.toInt() ?? 10,
    );
  }

  bool get canCreateBill => billsThisMonth < billsLimit;
  bool get canAddProduct => productsCount < productsLimit;
  bool get canAddCustomer => customersCount < customersLimit;
  int get billsRemaining => billsLimit - billsThisMonth;
  int get productsRemaining => productsLimit - productsCount;
  int get customersRemaining => customersLimit - customersCount;
}

/// Service for tracking user metrics and syncing to Firestore
class UserMetricsService {
  UserMetricsService._();

  static String _appVersion = '10.0.3';
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static SharedPreferences? _prefs;

  // Local cache keys
  static const String _billsThisMonthKey = 'bills_this_month';
  static const String _userIdKey = 'user_id';

  /// Initialize
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    // Get real version from PackageInfo
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = '${info.version}+${info.buildNumber}';
    } catch (e) {
      debugPrint('ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â PackageInfo unavailable: $e');
    }
    // Enforce subscription expiry on every app launch (fire and forget)
    _checkAndEnforceSubscription().ignore();
  }

  /// Checks if current subscription has expired and downgrades to free if so.
  /// Safe to call on every launch ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â reads one document from Firestore.
  static Future<void> _checkAndEnforceSubscription() async {
    final userId = _getUserId();
    if (userId == null) return;
    try {
      final snap = await _firestore.collection('users').doc(userId).get();
      if (!snap.exists) return;
      final sub = UserSubscription.fromMap(
        snap.data()?['subscription'] as Map<String, dynamic>?,
      );
      // Only enforce for paid plans that have an expiry date
      if (sub.plan == SubscriptionPlan.free) return;
      if (sub.expiresAt == null) return;
      if (!DateTime.now().isAfter(sub.expiresAt!)) return;

      // Subscription expired ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â downgrade to free limits
      await _firestore.collection('users').doc(userId).update({
        'subscription.status': SubscriptionStatus.expired.name,
        'subscription.plan': SubscriptionPlan.free.name,
        'limits.billsLimit': UserSubscription().billsLimit, // 50
        'limits.productsLimit': UserSubscription().productsLimit, // 100
        'limits.customersLimit': 10, // Free tier: 10 customers
      });
      debugPrint('ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â UserMetrics: Subscription expired ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â downgraded to free');
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Subscription expiry check failed: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        metadata: {'context': 'Subscription expiry enforcement'},
      ).ignore();
    }
  }

  /// Get current user ID (from auth or settings)
  static String? _getUserId() {
    // Try Firebase Auth first
    final user = _auth.currentUser;
    if (user != null) return user.uid;
    // Fallback to stored user ID
    return _prefs?.getString(_userIdKey);
  }

  /// Quick connectivity check ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â returns true when device has no network.
  static Future<bool> _isDeviceOffline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result == ConnectivityResult.none;
    } catch (_) {
      return false; // Assume online if check fails
    }
  }

  /// Track user activity (call on app launch and key actions)
  static Future<void> trackActivity() async {
    final userId = _getUserId();
    if (userId == null) return;

    try {
      String platform = 'unknown';

      if (!kIsWeb) {
        if (Platform.isAndroid) {
          platform = 'android';
        } else if (Platform.isIOS) {
          platform = 'ios';
        } else if (Platform.isWindows) {
          platform = 'windows';
        } else if (Platform.isMacOS) {
          platform = 'macos';
        } else if (Platform.isLinux) {
          platform = 'linux';
        }
      } else {
        platform = 'web';
      }

      await _firestore.collection('users').doc(userId).set({
        'activity': {
          'lastActiveAt': FieldValue.serverTimestamp(),
          'appVersion': _appVersion,
          'platform': platform,
        },
      }, SetOptions(merge: true));

      debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  UserMetrics: Activity tracked');
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to track activity: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'trackActivity'},
      ).ignore();
    }
  }

  /// Track bill creation ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â uses a Firestore transaction as the single source
  /// of truth (prevents limit bypass via app reinstall / cache clear).
  static Future<bool> trackBillCreated() async {
    final userId = _getUserId();
    if (userId == null) return true; // Allow if not logged in

    try {
      final userRef = _firestore.collection('users').doc(userId);
      bool allowed = false;
      int newCount = 0;
      int limit = 50;

      // Use simple get+update instead of runTransaction when:
      // 1. Windows ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â the C++ Firestore SDK crashes Flutter with transactions
      // 2. Mobile offline ÃƒÂ¢Ã¢â€šÂ¬Ã¢â‚¬Â transactions require a server round-trip and
      //    throw 'unavailable' when the device is offline. Simple writes
      //    queue in Firestore's offline cache and sync when back online.
      final isOffline = !kIsWeb && await _isDeviceOffline();
      final useSimpleWrite = (!kIsWeb && Platform.isWindows) || isOffline;

      if (useSimpleWrite) {
        final snap = await userRef.get();
        final data = snap.data() ?? {};
        final limitsMap = data['limits'] as Map<String, dynamic>? ?? {};
        final subMap = data['subscription'] as Map<String, dynamic>? ?? {};
        final now = DateTime.now();
        final currentMonth =
            '${now.year}-${now.month.toString().padLeft(2, '0')}';
        final lastResetMonth = (limitsMap['lastResetMonth'] as String?) ?? '';
        final isNewMonth = lastResetMonth != currentMonth;
        final billsThisMonth = isNewMonth
            ? 0
            : ((limitsMap['billsThisMonth'] as int?) ?? 0);
        final storedLimit = (limitsMap['billsLimit'] as int?) ?? 50;
        // Always derive the effective limit from the subscription plan so
        // users who upgraded don't get blocked by a stale Firestore value.
        final sub = UserSubscription.fromMap(subMap);
        limit = sub.isActive ? sub.billsLimit : storedLimit;
        allowed = billsThisMonth < limit;
        if (allowed) {
          newCount = billsThisMonth + 1;
          await userRef.update({
            'limits.billsThisMonth': newCount,
            'limits.billsLimit': limit, // keep Firestore in sync with plan
            'limits.lastResetMonth': currentMonth,
            'activity.lastActiveAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await _firestore.runTransaction((txn) async {
          final snap = await txn.get(userRef);
          final data = snap.data() ?? {};
          final limitsMap = data['limits'] as Map<String, dynamic>? ?? {};
          final subMap = data['subscription'] as Map<String, dynamic>? ?? {};
          final now = DateTime.now();
          final currentMonth =
              '${now.year}-${now.month.toString().padLeft(2, '0')}';
          final lastResetMonth = (limitsMap['lastResetMonth'] as String?) ?? '';
          final isNewMonth = lastResetMonth != currentMonth;
          final billsThisMonth = isNewMonth
              ? 0
              : ((limitsMap['billsThisMonth'] as int?) ?? 0);
          final storedLimit = (limitsMap['billsLimit'] as int?) ?? 50;
          final sub = UserSubscription.fromMap(subMap);
          limit = sub.isActive ? sub.billsLimit : storedLimit;
          allowed = billsThisMonth < limit;
          if (allowed) {
            newCount = billsThisMonth + 1;
            txn.update(userRef, {
              'limits.billsThisMonth': newCount,
              'limits.billsLimit': limit, // keep Firestore in sync with plan
              'limits.lastResetMonth': currentMonth,
              'activity.lastActiveAt': FieldValue.serverTimestamp(),
            });
          }
        });
      }

      if (allowed) {
        // Mirror to SharedPreferences only as a non-authoritative UI cache
        await _prefs?.setInt(_billsThisMonthKey, newCount);
        debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  UserMetrics: Bill tracked ($newCount/$limit)');
      } else {
        debugPrint('ÃƒÂ¢Ã…Â¡Ã‚Â ÃƒÂ¯Ã‚Â¸Ã‚Â UserMetrics: Bill limit reached ($limit/$limit)');
      }
      return allowed;
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to track bill: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'trackBillCreated'},
      ).ignore();
      return true; // Don't block billing on transient Firestore errors
    }
  }

  /// Track product added
  static Future<void> trackProductAdded() async {
    final userId = _getUserId();
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).set({
        'limits': {'productsCount': FieldValue.increment(1)},
      }, SetOptions(merge: true));
      debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  UserMetrics: Product tracked');
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to track product: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'trackProductAdded'},
      ).ignore();
    }
  }

  /// Track product deleted
  static Future<void> trackProductDeleted() async {
    final userId = _getUserId();
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).set({
        'limits': {'productsCount': FieldValue.increment(-1)},
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to track product deletion: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'trackProductDeleted'},
      ).ignore();
    }
  }

  /// Track customer added
  static Future<void> trackCustomerAdded() async {
    final userId = _getUserId();
    if (userId == null) return;

    try {
      await _firestore.collection('users').doc(userId).set({
        'limits': {'customersCount': FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to track customer: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'trackCustomerAdded'},
      ).ignore();
    }
  }

  /// Get user's current limits
  static Future<UserLimits> getUserLimits() async {
    final userId = _getUserId();
    if (userId == null) return UserLimits();

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return UserLimits();

      final data = doc.data();
      return UserLimits.fromMap(data?['limits'] as Map<String, dynamic>?);
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to get limits: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'getUserLimits'},
      ).ignore();
      return UserLimits();
    }
  }

  /// Get user's subscription
  static Future<UserSubscription> getUserSubscription() async {
    final userId = _getUserId();
    if (userId == null) return UserSubscription();

    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (!doc.exists) return UserSubscription();

      final data = doc.data();
      return UserSubscription.fromMap(
        data?['subscription'] as Map<String, dynamic>?,
      );
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to get subscription: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        severity: ErrorSeverity.warning,
        metadata: {'context': 'getUserSubscription'},
      ).ignore();
      return UserSubscription();
    }
  }

  // Monthly reset is now handled atomically inside trackBillCreated.

  /// Initialize user document with default values
  static Future<void> initializeUser({
    required String userId,
    required String email,
    required String shopName,
    required String ownerName,
    String? phone,
  }) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'email': email,
        'shopName': shopName,
        'ownerName': ownerName,
        'phone': phone,
        'createdAt': FieldValue.serverTimestamp(),
        'subscription': UserSubscription().toMap(),
        'limits': UserLimits().toMap(),
        'activity': {
          'lastActiveAt': FieldValue.serverTimestamp(),
          'appVersion': _appVersion,
          'platform': kIsWeb
              ? 'web'
              : (Platform.isAndroid
                    ? 'android'
                    : (Platform.isWindows ? 'windows' : 'ios')),
        },
      }, SetOptions(merge: true));

      // Save user ID locally
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString(_userIdKey, userId);

      debugPrint('ÃƒÂ°Ã…Â¸Ã¢â‚¬Å“Ã…Â  UserMetrics: User initialized in Firestore');
    } catch (e, st) {
      debugPrint('ÃƒÂ¢Ã‚ÂÃ…â€™ UserMetrics: Failed to initialize user: $e');
      ErrorLoggingService.logError(
        error: e,
        stackTrace: st,
        metadata: {'context': 'initializeUser'},
      ).ignore();
    }
  }
}
