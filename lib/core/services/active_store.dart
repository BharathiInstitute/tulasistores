import 'package:firebase_auth/firebase_auth.dart';

/// Resolved store path for Firestore data access.
///
/// After the multi-store migration, all data lives under `stores/{storeId}/`.
/// For backward compatibility with existing single-user data, `storeId`
/// defaults to the current user's UID when no store is explicitly selected.
///
/// Set [activeStoreId] from the store provider after the user picks a store.
class ActiveStore {
  ActiveStore._();

  /// The currently selected store ID. Set by the store provider.
  static String? activeStoreId;

  /// The resolved store path prefix for Firestore documents.
  ///
  /// When [activeStoreId] equals the current user's UID, returns
  /// `users/{uid}` to preserve backward compatibility with existing data.
  /// Otherwise returns `stores/{activeStoreId}` for multi-store mode.
  static String get basePath {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';

    if (activeStoreId != null && activeStoreId!.isNotEmpty) {
      // If the selected store IS the user's personal store (storeId == uid),
      // route to the legacy users/{uid} path so existing data is preserved.
      if (activeStoreId == uid) return 'users/$uid';
      return 'stores/$activeStoreId';
    }
    // No store selected — fall back to legacy path
    return 'users/$uid';
  }

  /// The current store ID (or user UID as fallback).
  static String get storeId {
    if (activeStoreId != null && activeStoreId!.isNotEmpty) {
      return activeStoreId!;
    }
    return FirebaseAuth.instance.currentUser?.uid ?? '';
  }
}
