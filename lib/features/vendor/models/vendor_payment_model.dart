import 'package:cloud_firestore/cloud_firestore.dart';

class VendorPaymentModel {
  final String id;
  final String vendorId;
  final double amount;
  final String paymentMode; // Cash, UPI, Bank Transfer
  final String? note;
  final DateTime paidAt;

  const VendorPaymentModel({
    required this.id,
    required this.vendorId,
    required this.amount,
    required this.paymentMode,
    this.note,
    required this.paidAt,
  });

  factory VendorPaymentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VendorPaymentModel(
      id: doc.id,
      vendorId: (data['vendorId'] as String?) ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0,
      paymentMode: (data['paymentMode'] as String?) ?? 'Cash',
      note: data['note'] as String?,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'vendorId': vendorId,
    'amount': amount,
    'paymentMode': paymentMode,
    'note': note,
    'paidAt': Timestamp.fromDate(paidAt),
  };
}
