import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/models/store_member_model.dart';
import 'package:retaillite/features/store/models/store_model.dart';
import 'package:retaillite/features/store/services/store_service.dart';

// ─── Active Store ──────────────────────────────────────────────

/// The currently selected store ID. Set after the user picks a store
/// from the "My Stores" screen. ALL data services read from this.
final activeStoreIdProvider = StateProvider<String?>((ref) => null);

/// The active store's full model (loaded once on selection).
final activeStoreProvider = FutureProvider<StoreModel?>((ref) {
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return null;
  return StoreService.getStore(storeId);
});

/// Current user's membership/role in the active store.
final myMembershipProvider = FutureProvider<StoreMemberModel?>((ref) {
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return null;
  return StoreService.getMyMembership(storeId);
});

/// Current user's permissions in the active store.
final myPermissionsProvider = Provider<PermissionsModel>((ref) {
  final membership = ref.watch(myMembershipProvider).valueOrNull;
  if (membership == null) {
    return const PermissionsModel.owner(); // default to owner for backward compat
  }
  return membership.permissions;
});

/// Current user's role in the active store.
final myRoleProvider = Provider<StoreRole>((ref) {
  final membership = ref.watch(myMembershipProvider).valueOrNull;
  if (membership == null) return StoreRole.owner;
  return membership.role;
});

// ─── My Stores ─────────────────────────────────────────────────

/// Stream of stores the current user belongs to.
final myStoresProvider = StreamProvider<List<UserStoreRef>>((ref) {
  return StoreService.myStoresStream();
});

// ─── Store Members ─────────────────────────────────────────────

/// Stream of all members in the active store.
final storeMembersProvider = StreamProvider<List<StoreMemberModel>>((ref) {
  final storeId = ref.watch(activeStoreIdProvider);
  if (storeId == null) return Stream.value([]);
  return StoreService.membersStream(storeId);
});

/// Attendance settings for the active store (allowSelfCheckIn, requireGps, etc.)
final attendanceSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return StaffService.attendanceSettingsStream();
});

// ─── Auto-Initialization ────────────────────────────────────────

/// Ensures a default store exists and auto-selects the first available store.
///
/// Called once on app startup from [AppShell]. Handles both new users
/// (creates default store using UID as storeId for backward compat) and
/// returning users (picks the first store from their list).
final storeInitializerProvider = FutureProvider<void>((ref) async {
  try {
    final stores = await ref.watch(myStoresProvider.future);
    final current = ref.read(activeStoreIdProvider);

    if (stores.isEmpty) {
      // No stores yet — create the default store (storeId == uid)
      final storeId = await StoreService.ensureDefaultStore();
      ActiveStore.activeStoreId = storeId;
      ref.read(activeStoreIdProvider.notifier).state = storeId;
    } else if (current == null) {
      // Stores exist but none selected yet — pick the first
      final storeId = stores.first.storeId;
      ActiveStore.activeStoreId = storeId;
      ref.read(activeStoreIdProvider.notifier).state = storeId;
    }
  } catch (e) {
    // Log but don't rethrow — the app works without multi-store (falls back to users/{uid})
    debugPrint('⚠️ Store init error (non-fatal): $e');
  }
});
