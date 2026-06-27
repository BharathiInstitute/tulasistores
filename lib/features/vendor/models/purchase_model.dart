import 'package:cloud_firestore/cloud_firestore.dart';

class PurchaseItem {
  final String name;
  final double quantity;
  final double rate;
  final double total;

  const PurchaseItem({
    required this.name,
    required this.quantity,
    required this.rate,
    required this.total,
  });

  factory PurchaseItem.fromMap(Map<String, dynamic> map) {
    return PurchaseItem(
      name: (map['name'] as String?) ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      rate: (map['rate'] as num?)?.toDouble() ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'quantity': quantity,
    'rate': rate,
    'total': total,
  };
}

class PurchaseModel {
  final String id;
  final String vendorId;
  final List<PurchaseItem> items;
  final double totalAmount;
  final double paidAmount;
  final double dueAmount;
  final String? invoiceNumber;
  final DateTime purchaseDate;
  final String? note;
  final DateTime createdAt;

  const PurchaseModel({
    required this.id,
    required this.vendorId,
    required this.items,
    required this.totalAmount,
    this.paidAmount = 0,
    required this.dueAmount,
    this.invoiceNumber,
    required this.purchaseDate,
    this.note,
    required this.createdAt,
  });

  factory PurchaseModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final itemsList =
        (data['items'] as List<dynamic>?)
            ?.map((e) => PurchaseItem.fromMap(e as Map<String, dynamic>))
            .toList() ??
        [];
    return PurchaseModel(
      id: doc.id,
      vendorId: (data['vendorId'] as String?) ?? '',
      items: itemsList,
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0,
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0,
      dueAmount: (data['dueAmount'] as num?)?.toDouble() ?? 0,
      invoiceNumber: data['invoiceNumber'] as String?,
      purchaseDate:
          (data['purchaseDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      note: data['note'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'vendorId': vendorId,
    'items': items.map((e) => e.toMap()).toList(),
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'dueAmount': dueAmount,
    'invoiceNumber': invoiceNumber,
    'purchaseDate': Timestamp.fromDate(purchaseDate),
    'note': note,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}
