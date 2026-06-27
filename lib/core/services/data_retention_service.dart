/// Data retention service for managing data lifecycle
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Retention period options
enum RetentionPeriod {
  days30(30, 'Keep 30 days', 'Recommended for daily operations'),
  days90(90, 'Keep 90 days', 'Good for quarterly reports'),
  year1(365, 'Keep 1 year', 'Required for GST filing'),
  forever(-1, 'Keep forever', 'High storage usage');

  const RetentionPeriod(this.days, this.label, this.description);

  final int days;
  final String label;
  final String description;

  /// Check if data should be retained (never expire)
  bool get neverExpires => days < 0;

  /// Get the cutoff date for data to keep
  DateTime? get cutoffDate {
    if (neverExpires) return null;
    return DateTime.now().subtract(Duration(days: days));
  }

  /// Create from stored value
  static RetentionPeriod fromDays(int days) {
    return RetentionPeriod.values.firstWhere(
      (p) => p.days == days,
      orElse: () => RetentionPeriod.days90,
    );
  }
}

/// Data retention service for cleanup and archival
class DataRetentionService {
  DataRetentionService(this._period);

  final RetentionPeriod _period;
  static final _firestore = FirebaseFirestore.instance;
  static SharedPreferences? _prefs;

  /// Get user's base path
  static String get _basePath => ActiveStore.basePath;

  /// Initialize the service
  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Get count of expired bills that would be deleted
  Future<int> getExpiredBillsCount() async {
    if (_period.neverExpires || _basePath.isEmpty) return 0;

    final cutoff = _period.cutoffDate;
    if (cutoff == null) return 0;

    try {
      final snapshot = await _firestore
          .collection('$_basePath/bills')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get count of expired expenses that would be deleted
  Future<int> getExpiredExpensesCount() async {
    if (_period.neverExpires || _basePath.isEmpty) return 0;

    final cutoff = _period.cutoffDate;
    if (cutoff == null) return 0;

    try {
      final snapshot = await _firestore
          .collection('$_basePath/expenses')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
          .count()
          .get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// Get storage statistics
  Future<Map<String, dynamic>> getStorageStats() async {
    if (_basePath.isEmpty) {
      return {'error': 'Not logged in'};
    }

    try {
      final billsSnapshot = await _firestore
          .collection('$_basePath/bills')
          .count()
          .get();
      final productsSnapshot = await _firestore
          .collection('$_basePath/products')
          .count()
          .get();
      final customersSnapshot = await _firestore
          .collection('$_basePath/customers')
          .count()
          .get();

      return {
        'billsCount': billsSnapshot.count ?? 0,
        'productsCount': productsSnapshot.count ?? 0,
        'customersCount': customersSnapshot.count ?? 0,
        'pendingSyncCount': 0, // Firebase handles sync
        'expiredBillsCount': await getExpiredBillsCount(),
        'expiredExpensesCount': await getExpiredExpensesCount(),
        'retentionPeriod': _period.label,
        'cutoffDate': _period.cutoffDate?.toIso8601String(),
      };
    } catch (e) {
      return {'error': 'Failed to get storage stats: $e'};
    }
  }

  /// Delete documents in chunked batches (Firestore max 500 per batch)
  Future<int> _deleteInBatches(
    List<QueryDocumentSnapshot> docs, {
    bool dryRun = false,
  }) async {
    if (dryRun || docs.isEmpty) return docs.length;

    const batchSize = 450; // Safe margin below 500 limit
    for (var i = 0; i < docs.length; i += batchSize) {
      final batch = _firestore.batch();
      final end = (i + batchSize).clamp(0, docs.length);
      for (var j = i; j < end; j++) {
        batch.delete(docs[j].reference);
      }
      await batch.commit();
    }
    return docs.length;
  }

  /// Cleanup expired data from Firestore
  /// Deletes expired bills and expenses in safe chunked batches
  Future<CleanupResult> cleanupExpiredData({bool dryRun = false}) async {
    if (_period.neverExpires || _basePath.isEmpty) {
      return CleanupResult(
        billsDeleted: 0,
        expensesDeleted: 0,
        bytesFreed: 0,
        skipped: true,
        reason: _period.neverExpires
            ? 'Retention set to "forever"'
            : 'Not logged in',
      );
    }

    final cutoff = _period.cutoffDate;
    if (cutoff == null) {
      return const CleanupResult(
        billsDeleted: 0,
        expensesDeleted: 0,
        bytesFreed: 0,
        skipped: true,
        reason: 'No cutoff date',
      );
    }

    int billsDeleted = 0;
    int expensesDeleted = 0;

    try {
      // 1. Delete expired bills (paginated to avoid OOM)
      final billsSnapshot = await _firestore
          .collection('$_basePath/bills')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
          .limit(450)
          .get();
      billsDeleted = await _deleteInBatches(billsSnapshot.docs, dryRun: dryRun);

      // 2. Delete expired expenses (paginated)
      final expensesSnapshot = await _firestore
          .collection('$_basePath/expenses')
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
          .limit(450)
          .get();
      expensesDeleted = await _deleteInBatches(
        expensesSnapshot.docs,
        dryRun: dryRun,
      );

      // Update last cleanup time
      if (!dryRun) {
        await _prefs?.setString(
          SettingsKeys.lastCleanupTime,
          DateTime.now().toIso8601String(),
        );
      }

      debugPrint(
        '🧹 Cleanup: $billsDeleted bills, $expensesDeleted expenses '
        '(dryRun=$dryRun, period=${_period.label})',
      );

      return CleanupResult(
        billsDeleted: billsDeleted,
        expensesDeleted: expensesDeleted,
        bytesFreed: (billsDeleted + expensesDeleted) * 500,
        dryRun: dryRun,
      );
    } catch (e) {
      debugPrint('🧹 Cleanup error: $e');
      return CleanupResult(
        billsDeleted: billsDeleted,
        expensesDeleted: expensesDeleted,
        bytesFreed: 0,
        skipped: true,
        reason: 'Error: $e',
      );
    }
  }

  /// Get the last cleanup time
  static DateTime? getLastCleanupTime() {
    final str = _prefs?.getString(SettingsKeys.lastCleanupTime);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  /// Check if cleanup is due (more than 7 days since last cleanup)
  static bool isCleanupDue() {
    final lastCleanup = getLastCleanupTime();
    if (lastCleanup == null) return true;
    return DateTime.now().difference(lastCleanup).inDays >= 7;
  }
}

/// Result of a cleanup operation
class CleanupResult {
  const CleanupResult({
    required this.billsDeleted,
    required this.expensesDeleted,
    required this.bytesFreed,
    this.skipped = false,
    this.dryRun = false,
    this.reason,
  });

  final int billsDeleted;
  final int expensesDeleted;
  final int bytesFreed;
  final bool skipped;
  final bool dryRun;
  final String? reason;

  int get totalDeleted => billsDeleted + expensesDeleted;

  String get bytesFreedFormatted {
    if (bytesFreed < 1024) return '$bytesFreed B';
    if (bytesFreed < 1024 * 1024) {
      return '${(bytesFreed / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytesFreed / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Provider for data retention service — reads retention period from user settings
final dataRetentionServiceProvider = Provider<DataRetentionService>((ref) {
  final settings = ref.watch(settingsProvider);
  return DataRetentionService(settings.retentionPeriod);
});

/// Provider for current retention period
final retentionPeriodProvider = StateProvider<RetentionPeriod>((ref) {
  return RetentionPeriod.days90; // Default
});

/// Provider for storage stats
final storageStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(dataRetentionServiceProvider);
  return service.getStorageStats();
});
