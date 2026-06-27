/// Khata providers for customers and transactions
/// Supports demo mode with local in-memory data
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/demo_data_service.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:retaillite/core/utils/id_generator.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/models/customer_model.dart';
import 'package:retaillite/models/transaction_model.dart';

/// Customers list provider — real-time stream from Firestore
/// Uses autoDispose to release Firestore listener when no longer watched.
final customersProvider = StreamProvider.autoDispose<List<CustomerModel>>((
  ref,
) {
  final isDemoMode = ref.watch(isDemoModeProvider);
  ref.watch(activeStoreIdProvider); // re-subscribe on store change
  debugPrint(
    '🧾 customersProvider: isDemoMode=$isDemoMode, DemoDataService.isLoaded=${DemoDataService.isLoaded}',
  );

  if (isDemoMode) {
    final customers = DemoDataService.getCustomers().toList();
    debugPrint('🧾 Returning ${customers.length} demo customers');
    return Stream.value(customers);
  }

  return OfflineStorageService.customersStream();
});

/// Single customer provider — real-time stream from Firestore
/// Uses autoDispose to release per-customer listener when screen is popped.
final customerProvider = StreamProvider.autoDispose
    .family<CustomerModel?, String>((ref, customerId) {
      final isDemoMode = ref.watch(isDemoModeProvider);
      ref.watch(activeStoreIdProvider);

      if (isDemoMode) {
        return Stream.value(DemoDataService.getCustomer(customerId));
      }

      return OfflineStorageService.customerStream(customerId);
    });

/// Customer transactions provider — real-time stream from Firestore
/// Uses autoDispose to release per-customer transaction listener.
final customerTransactionsProvider = StreamProvider.autoDispose
    .family<List<TransactionModel>, String>((ref, customerId) {
      final isDemoMode = ref.watch(isDemoModeProvider);
      ref.watch(activeStoreIdProvider);

      if (isDemoMode) {
        return Stream.value(
          DemoDataService.getCustomerTransactions(customerId),
        );
      }

      return OfflineStorageService.customerTransactionsStream(customerId);
    });

/// Khata service for CRUD operations
/// Automatically routes to demo data or Firestore based on mode
class KhataService {
  final bool _isDemoMode;

  KhataService({required bool isDemoMode}) : _isDemoMode = isDemoMode;

  /// Add new customer
  Future<String> addCustomer(CustomerModel customer) async {
    if (_isDemoMode) {
      return DemoDataService.addCustomer(customer);
    }

    // Check customer limit before adding
    final limits = await UserMetricsService.getUserLimits();
    if (!limits.canAddCustomer) {
      throw Exception(
        'Customer limit reached (${limits.customersLimit}). Upgrade your plan to add more customers.',
      );
    }

    final id = generateSafeId('customer');
    final newCustomer = CustomerModel(
      id: id,
      name: customer.name,
      phone: customer.phone,
      address: customer.address,
      balance: customer.balance,
      createdAt: DateTime.now(),
    );
    await OfflineStorageService.saveCustomer(newCustomer);
    unawaited(UserMetricsService.trackCustomerAdded());
    return id;
  }

  /// Update customer
  Future<void> updateCustomer(CustomerModel customer) async {
    if (_isDemoMode) {
      DemoDataService.updateCustomer(customer);
      return;
    }
    await OfflineStorageService.saveCustomer(customer);
  }

  /// Record payment from customer
  Future<void> recordPayment({
    required String customerId,
    required double amount,
    String? note,
    String paymentMode = 'cash',
  }) async {
    if (_isDemoMode) {
      // Update customer balance (subtract payment)
      DemoDataService.updateCustomerBalance(customerId, -amount);
      // Add transaction
      DemoDataService.addTransaction(
        customerId: customerId,
        type: TransactionType.payment,
        amount: amount,
        note: note ?? paymentMode,
      );
      return;
    }

    // Atomic: update balance + save transaction in a single WriteBatch
    await OfflineStorageService.recordPaymentAtomic(
      customerId: customerId,
      amount: amount,
      note: note,
      paymentMode: paymentMode,
    );
  }

  /// Add credit (udhar) for customer
  Future<void> addCredit({
    required String customerId,
    required double amount,
    String? billId,
  }) async {
    if (_isDemoMode) {
      // Update customer balance
      DemoDataService.updateCustomerBalance(customerId, amount);
      // Add transaction
      DemoDataService.addTransaction(
        customerId: customerId,
        type: TransactionType.purchase,
        amount: amount,
        billId: billId,
      );
      return;
    }

    // Atomic: update balance + save transaction in a single WriteBatch
    await OfflineStorageService.addCreditAtomic(
      customerId: customerId,
      amount: amount,
      billId: billId,
    );
  }

  /// Delete customer
  Future<void> deleteCustomer(String customerId) async {
    if (_isDemoMode) {
      DemoDataService.deleteCustomer(customerId);
      return;
    }
    await OfflineStorageService.deleteCustomer(customerId);
  }
}

/// Khata service provider - auto-detects demo mode
final khataServiceProvider = Provider<KhataService>((ref) {
  final isDemoMode = ref.watch(isDemoModeProvider);
  return KhataService(isDemoMode: isDemoMode);
});

/// Per-customer sync status — maps customer ID → hasPendingWrites
final customersSyncStatusProvider =
    StreamProvider.autoDispose<Map<String, bool>>((ref) {
      final isDemoMode = ref.watch(isDemoModeProvider);
      ref.watch(activeStoreIdProvider);
      if (isDemoMode) return Stream.value({});
      return OfflineStorageService.customersSyncStream();
    });
