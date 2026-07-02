/// Feature gate widget and helper for plan-based access control.
/// Wraps any widget/action that requires a specific plan feature.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/config/plan_config.dart';
import 'package:retaillite/features/subscription/providers/subscription_provider.dart';
import 'package:retaillite/shared/widgets/upgrade_prompt_modal.dart';

/// Widget that shows its child only if the user's plan has the required feature.
/// Otherwise shows a locked placeholder or nothing.
class FeatureGate extends ConsumerWidget {
  final PlanFeature feature;
  final Widget child;
  final Widget? lockedChild;

  const FeatureGate({
    super.key,
    required this.feature,
    required this.child,
    this.lockedChild,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final planAsync = ref.watch(subscriptionPlanProvider);
    return planAsync.when(
      data: (planName) {
        if (PlanConfig.canAccessByName(planName, feature)) {
          return child;
        }
        return lockedChild ?? const SizedBox.shrink();
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => child, // fail open on error
    );
  }
}

/// Helper class to check feature access and show upgrade prompt if needed.
class FeatureAccess {
  FeatureAccess._();

  /// Check if the current plan allows a feature. If not, shows upgrade prompt.
  /// Returns true if access is granted, false if blocked.
  static bool check(
    BuildContext context,
    WidgetRef ref,
    PlanFeature feature,
  ) {
    final planAsync = ref.read(subscriptionPlanProvider);
    final planName = planAsync.valueOrNull ?? 'free';

    if (PlanConfig.canAccessByName(planName, feature)) {
      return true;
    }

    // Show upgrade prompt
    UpgradePromptModal.show(context, trigger: UpgradeTrigger.featureGated);
    return false;
  }

  /// Check staff limit. Returns true if can add more staff.
  static bool checkStaffLimit(
    BuildContext context,
    WidgetRef ref,
    int currentStaffCount,
  ) {
    final planAsync = ref.read(subscriptionPlanProvider);
    final planName = planAsync.valueOrNull ?? 'free';
    final limits = PlanConfig.limitsForName(planName);

    if (currentStaffCount < limits.maxStaff) {
      return true;
    }

    UpgradePromptModal.show(context, trigger: UpgradeTrigger.featureGated);
    return false;
  }

  /// Check store limit. Returns true if can add more stores.
  static bool checkStoreLimit(
    BuildContext context,
    WidgetRef ref,
    int currentStoreCount,
  ) {
    final planAsync = ref.read(subscriptionPlanProvider);
    final planName = planAsync.valueOrNull ?? 'free';
    final limits = PlanConfig.limitsForName(planName);

    if (currentStoreCount < limits.maxStores) {
      return true;
    }

    UpgradePromptModal.show(context, trigger: UpgradeTrigger.featureGated);
    return false;
  }
}
