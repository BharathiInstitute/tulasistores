/// Khata statistics providers for aggregated data
/// Supports demo mode with local in-memory data
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/demo_data_service.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/khata/providers/khata_provider.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/models/customer_model.dart';
import 'package:retaillite/models/transaction_model.dart';

/// Khata statistics model
class KhataStats {
  final double totalOutstanding;
  final double collectedToday;
  final int activeCustomers;
  final int customersWithDue;

  const KhataStats({
    required this.totalOutstanding,
    required this.collectedToday,
    required this.activeCustomers,
    required this.customersWithDue,
  });

  factory KhataStats.empty() => const KhataStats(
    totalOutstanding: 0,
    collectedToday: 0,
    activeCustomers: 0,
    customersWithDue: 0,
  );
}

/// Real-time stream of today's collected payment total.
/// Uses a Firestore stream on non-demo, DemoDataService on demo.
final _todayPaymentTotalProvider = StreamProvider<double>((ref) {
  final isDemoMode = ref.watch(isDemoModeProvider);
  ref.watch(activeStoreIdProvider);
  if (isDemoMode) {
    final today = DateTime.now();
    final startOfDay = DateTime(today.year, today.month, today.day);
    final customers = ref.watch(customersProvider).valueOrNull ?? [];
    double total = 0;
    for (final customer in customers) {
      for (final tx in DemoDataService.getCustomerTransactions(customer.id)) {
        if (tx.type == TransactionType.payment &&
            tx.createdAt.isAfter(startOfDay)) {
          total += tx.amount;
        }
      }
    }
    return Stream.value(total);
  }
  return OfflineStorageService.todayPaymentTotalStream();
});

/// Provider for khata statistics — derives from customers + payments streams
final khataStatsProvider = Provider<AsyncValue<KhataStats>>((ref) {
  final isDemoMode = ref.watch(isDemoModeProvider);
  debugPrint('📊 khataStatsProvider: isDemoMode=$isDemoMode');

  // Watch the customers stream — this auto-updates when customers change
  final customersAsync = ref.watch(customersProvider);
  final collectedAsync = ref.watch(_todayPaymentTotalProvider);

  // Combine: both must be loaded
  final customers = customersAsync.valueOrNull ?? [];
  final collectedToday = collectedAsync.valueOrNull ?? 0.0;

  // If either is still loading for the first time, propagate loading
  if (customersAsync is AsyncLoading && !customersAsync.hasValue) {
    return const AsyncValue.loading();
  }

  // Calculate total outstanding (sum of positive balances)
  final totalOutstanding = customers.fold<double>(
    0,
    (sum, c) => sum + (c.balance > 0 ? c.balance : 0),
  );

  // Count customers with due
  final customersWithDue = customers.where((c) => c.balance > 0).length;

  debugPrint(
    '📊 KhataStats: ${customers.length} customers, outstanding: $totalOutstanding, collected: $collectedToday',
  );

  return AsyncValue.data(
    KhataStats(
      totalOutstanding: totalOutstanding,
      collectedToday: collectedToday,
      activeCustomers: customers.length,
      customersWithDue: customersWithDue,
    ),
  );
});

/// Selected customer provider for master-detail view
final selectedCustomerIdProvider = StateProvider<String?>((ref) => null);

/// Sort option for customer list
enum CustomerSortOption { highestDebt, recentlyActive, alphabetical, oldestDue }

final customerSortProvider = StateProvider<CustomerSortOption>(
  (ref) => CustomerSortOption.highestDebt,
);

/// Sorted and filtered customers provider — derives from customers stream
final sortedCustomersProvider = Provider<AsyncValue<List<CustomerModel>>>((
  ref,
) {
  final customersAsync = ref.watch(customersProvider);
  final sortOption = ref.watch(customerSortProvider);

  return customersAsync.whenData((customers) {
    debugPrint('📋 sortedCustomersProvider: ${customers.length} customers');
    final sorted = List<CustomerModel>.from(customers);

    switch (sortOption) {
      case CustomerSortOption.highestDebt:
        sorted.sort((a, b) => b.balance.compareTo(a.balance));
        break;
      case CustomerSortOption.recentlyActive:
        sorted.sort((a, b) {
          final aDate = a.lastTransactionAt ?? DateTime(1970);
          final bDate = b.lastTransactionAt ?? DateTime(1970);
          return bDate.compareTo(aDate);
        });
        break;
      case CustomerSortOption.alphabetical:
        sorted.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        break;
      case CustomerSortOption.oldestDue:
        sorted.sort((a, b) {
          final aDate = a.lastTransactionAt ?? DateTime.now();
          final bDate = b.lastTransactionAt ?? DateTime.now();
          return aDate.compareTo(bDate);
        });
        break;
    }

    return sorted;
  });
});
