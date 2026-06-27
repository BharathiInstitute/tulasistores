import 'package:cloud_firestore/cloud_firestore.dart';

class VendorModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String? gstNumber;
  final String category;
  final double balance; // positive = you owe vendor
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const VendorModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.gstNumber,
    this.category = 'General',
    this.balance = 0,
    this.isActive = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory VendorModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VendorModel(
      id: doc.id,
      name: (data['name'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      email: data['email'] as String?,
      address: data['address'] as String?,
      gstNumber: data['gstNumber'] as String?,
      category: (data['category'] as String?) ?? 'General',
      balance: (data['balance'] as num?)?.toDouble() ?? 0,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'gstNumber': gstNumber,
    'category': category,
    'balance': balance,
    'isActive': isActive,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
  };

  VendorModel copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
    String? gstNumber,
    String? category,
    double? balance,
    bool? isActive,
  }) {
    return VendorModel(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      gstNumber: gstNumber ?? this.gstNumber,
      category: category ?? this.category,
      balance: balance ?? this.balance,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
