import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/features/vendor/models/purchase_model.dart';
import 'package:retaillite/features/vendor/models/vendor_model.dart';
import 'package:retaillite/features/vendor/models/vendor_payment_model.dart';
import 'package:retaillite/features/vendor/services/vendor_service.dart';

/// Stream of all vendors
final vendorListProvider = StreamProvider<List<VendorModel>>((ref) {
  ref.watch(activeStoreIdProvider); // re-subscribe on store change
  return VendorService.vendorsStream();
});

/// Active vendors only
final activeVendorsProvider = Provider<AsyncValue<List<VendorModel>>>((ref) {
  return ref
      .watch(vendorListProvider)
      .whenData((list) => list.where((v) => v.isActive).toList());
});

/// Total outstanding balance across all vendors
final totalVendorDueProvider = Provider<AsyncValue<double>>((ref) {
  return ref
      .watch(vendorListProvider)
      .whenData((list) => list.fold<double>(0, (sum, v) => sum + v.balance));
});

/// Purchases for a specific vendor
final vendorPurchasesProvider =
    StreamProvider.family<List<PurchaseModel>, String>((ref, vendorId) {
      ref.watch(activeStoreIdProvider); // re-subscribe on store change
      return VendorService.purchasesStream(vendorId);
    });

/// Payments for a specific vendor
final vendorPaymentsProvider =
    StreamProvider.family<List<VendorPaymentModel>, String>((ref, vendorId) {
      ref.watch(activeStoreIdProvider); // re-subscribe on store change
      return VendorService.paymentsStream(vendorId);
    });
