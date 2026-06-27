import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/features/vendor/models/purchase_model.dart';
import 'package:retaillite/features/vendor/models/vendor_model.dart';
import 'package:retaillite/features/vendor/models/vendor_payment_model.dart';

class VendorService {
  VendorService._();

  static final _firestore = FirebaseFirestore.instance;

  static String get _basePath => ActiveStore.basePath;

  // ─── Vendor CRUD ─────────────────────────────────────────────

  static Future<String> addVendor(VendorModel vendor) async {
    if (_basePath.isEmpty) throw Exception('Not authenticated');
    final ref = _firestore.collection('$_basePath/vendors').doc();
    final data = vendor.toFirestore();
    data['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(data);
    return ref.id;
  }

  static Stream<List<VendorModel>> vendorsStream() {
    if (_basePath.isEmpty) return Stream.value([]);
    return _firestore
        .collection('$_basePath/vendors')
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .where((doc) => doc.id != '_init')
              .map(VendorModel.fromFirestore)
              .toList(),
        );
  }

  static Future<void> updateVendor(VendorModel vendor) async {
    if (_basePath.isEmpty) return;
    await _firestore.doc('$_basePath/vendors/${vendor.id}').update({
      'name': vendor.name,
      'phone': vendor.phone,
      'email': vendor.email,
      'address': vendor.address,
      'gstNumber': vendor.gstNumber,
      'category': vendor.category,
      'isActive': vendor.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteVendor(String vendorId) async {
    if (_basePath.isEmpty) return;
    await _firestore.doc('$_basePath/vendors/$vendorId').delete();
  }

  // ─── Purchases ───────────────────────────────────────────────

  static Future<void> recordPurchase({
    required String vendorId,
    required PurchaseModel purchase,
  }) async {
    if (_basePath.isEmpty) return;
    final batch = _firestore.batch();

    // Save purchase doc
    final purchaseRef = _firestore
        .collection('$_basePath/vendors/$vendorId/purchases')
        .doc();
    batch.set(purchaseRef, purchase.toFirestore());

    // Update vendor balance (increase by due amount)
    final vendorRef = _firestore.doc('$_basePath/vendors/$vendorId');
    batch.update(vendorRef, {
      'balance': FieldValue.increment(purchase.dueAmount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  static Stream<List<PurchaseModel>> purchasesStream(String vendorId) {
    if (_basePath.isEmpty) return Stream.value([]);
    return _firestore
        .collection('$_basePath/vendors/$vendorId/purchases')
        .orderBy('purchaseDate', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PurchaseModel.fromFirestore).toList());
  }

  // ─── Payments ────────────────────────────────────────────────

  static Future<void> recordPayment({
    required String vendorId,
    required VendorPaymentModel payment,
  }) async {
    if (_basePath.isEmpty) return;
    final batch = _firestore.batch();

    // Save payment doc
    final paymentRef = _firestore
        .collection('$_basePath/vendors/$vendorId/payments')
        .doc();
    batch.set(paymentRef, payment.toFirestore());

    // Decrease vendor balance
    final vendorRef = _firestore.doc('$_basePath/vendors/$vendorId');
    batch.update(vendorRef, {
      'balance': FieldValue.increment(-payment.amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  static Stream<List<VendorPaymentModel>> paymentsStream(String vendorId) {
    if (_basePath.isEmpty) return Stream.value([]);
    return _firestore
        .collection('$_basePath/vendors/$vendorId/payments')
        .orderBy('paidAt', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs.map(VendorPaymentModel.fromFirestore).toList(),
        );
  }
}
