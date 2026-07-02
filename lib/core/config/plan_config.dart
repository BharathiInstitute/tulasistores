/// Centralized subscription plan configuration
/// Single source of truth for all plan limits and feature flags.
library;

import 'package:retaillite/core/services/user_metrics_service.dart';

/// Features that can be gated behind subscription plans
enum PlanFeature {
  /// Export data to CSV/PDF
  exportData,

  /// Create and share payment links
  paymentLinks,

  /// View advanced analytics and reports (all time periods)
  advancedReports,

  /// Multi-device sync
  multiDeviceSync,

  /// Push notifications
  pushNotifications,

  /// Staff management
  staffManagement,

  /// Multi-store support
  multiStore,
}

/// Configuration for a single subscription plan
class PlanLimits {
  final int maxBillsPerMonth;
  final int maxProducts;
  final int maxCustomers;
  final int maxStaff;
  final int maxStores;
  final Set<PlanFeature> enabledFeatures;

  const PlanLimits({
    required this.maxBillsPerMonth,
    required this.maxProducts,
    required this.maxCustomers,
    required this.maxStaff,
    required this.maxStores,
    required this.enabledFeatures,
  });

  bool hasFeature(PlanFeature feature) => enabledFeatures.contains(feature);
}

/// Central plan configuration — single source of truth
class PlanConfig {
  PlanConfig._();

  // ─── Limits ────────────────────────────────────────────────────

  static const PlanLimits free = PlanLimits(
    maxBillsPerMonth: 50,
    maxProducts: 100,
    maxCustomers: 10,
    maxStaff: 0,
    maxStores: 1,
    enabledFeatures: {
      // Free gets basic features only
    },
  );

  static const PlanLimits pro = PlanLimits(
    maxBillsPerMonth: 500,
    maxProducts: 1000,
    maxCustomers: 999999,
    maxStaff: 2,
    maxStores: 1,
    enabledFeatures: {
      PlanFeature.exportData,
      PlanFeature.paymentLinks,
      PlanFeature.advancedReports,
      PlanFeature.multiDeviceSync,
      PlanFeature.pushNotifications,
      PlanFeature.staffManagement,
    },
  );

  static const PlanLimits business = PlanLimits(
    maxBillsPerMonth: 999999,
    maxProducts: 999999,
    maxCustomers: 999999,
    maxStaff: 10,
    maxStores: 5,
    enabledFeatures: {
      PlanFeature.exportData,
      PlanFeature.paymentLinks,
      PlanFeature.advancedReports,
      PlanFeature.multiDeviceSync,
      PlanFeature.pushNotifications,
      PlanFeature.staffManagement,
      PlanFeature.multiStore,
    },
  );

  // ─── Pricing (INR) ────────────────────────────────────────────

  static const int proMonthlyPrice = 299;
  static const int proAnnualPrice = 2390;
  static const int businessMonthlyPrice = 999;
  static const int businessAnnualPrice = 7990;

  // ─── Helpers ──────────────────────────────────────────────────

  /// Get plan limits by plan enum
  static PlanLimits limitsFor(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.free:
        return free;
      case SubscriptionPlan.pro:
        return pro;
      case SubscriptionPlan.business:
        return business;
    }
  }

  /// Get plan limits by plan name string (from Firestore)
  static PlanLimits limitsForName(String planName) {
    switch (planName) {
      case 'pro':
        return pro;
      case 'business':
        return business;
      default:
        return free;
    }
  }

  /// Check if a plan has a specific feature
  static bool canAccess(SubscriptionPlan plan, PlanFeature feature) {
    return limitsFor(plan).hasFeature(feature);
  }

  /// Check if a plan name string has a specific feature
  static bool canAccessByName(String planName, PlanFeature feature) {
    return limitsForName(planName).hasFeature(feature);
  }

  /// Get display name for plan
  static String displayName(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.free:
        return 'Free';
      case SubscriptionPlan.pro:
        return 'Pro';
      case SubscriptionPlan.business:
        return 'Business';
    }
  }

  /// Get monthly price for plan
  static int monthlyPrice(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.pro:
        return proMonthlyPrice;
      case SubscriptionPlan.business:
        return businessMonthlyPrice;
    }
  }

  /// Get annual price for plan
  static int annualPrice(SubscriptionPlan plan) {
    switch (plan) {
      case SubscriptionPlan.free:
        return 0;
      case SubscriptionPlan.pro:
        return proAnnualPrice;
      case SubscriptionPlan.business:
        return businessAnnualPrice;
    }
  }
}
