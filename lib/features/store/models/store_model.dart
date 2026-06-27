import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';

/// A store entity — the top-level container for all business data.
///
/// Stored at `stores/{storeId}`.
/// For existing users, `storeId == ownerUid` (backward compatible).
class StoreModel {
  final String id;
  final String shopName;
  final String ownerUid;
  final String ownerName;
  final String ownerEmail;
  final String? address;
  final String? gstNumber;
  final String? shopLogoPath;
  final String? upiId;
  final String currency;
  final String timezone;
  final DateTime createdAt;

  const StoreModel({
    required this.id,
    required this.shopName,
    required this.ownerUid,
    required this.ownerName,
    required this.ownerEmail,
    this.address,
    this.gstNumber,
    this.shopLogoPath,
    this.upiId,
    this.currency = 'INR',
    this.timezone = 'Asia/Kolkata',
    required this.createdAt,
  });

  factory StoreModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StoreModel(
      id: doc.id,
      shopName: (data['shopName'] as String?) ?? '',
      ownerUid: (data['ownerUid'] as String?) ?? '',
      ownerName: (data['ownerName'] as String?) ?? '',
      ownerEmail: (data['ownerEmail'] as String?) ?? '',
      address: data['address'] as String?,
      gstNumber: data['gstNumber'] as String?,
      shopLogoPath: data['shopLogoPath'] as String?,
      upiId: data['upiId'] as String?,
      currency: (data['currency'] as String?) ?? 'INR',
      timezone: (data['timezone'] as String?) ?? 'Asia/Kolkata',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'shopName': shopName,
    'ownerUid': ownerUid,
    'ownerName': ownerName,
    'ownerEmail': ownerEmail,
    'address': address,
    'gstNumber': gstNumber,
    'shopLogoPath': shopLogoPath,
    'upiId': upiId,
    'currency': currency,
    'timezone': timezone,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  StoreModel copyWith({
    String? shopName,
    String? address,
    String? gstNumber,
    String? shopLogoPath,
    String? upiId,
  }) {
    return StoreModel(
      id: id,
      shopName: shopName ?? this.shopName,
      ownerUid: ownerUid,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
      address: address ?? this.address,
      gstNumber: gstNumber ?? this.gstNumber,
      shopLogoPath: shopLogoPath ?? this.shopLogoPath,
      upiId: upiId ?? this.upiId,
      currency: currency,
      timezone: timezone,
      createdAt: createdAt,
    );
  }
}

/// Lightweight reference stored in `users/{uid}/stores/{storeId}`
/// for the "My Stores" listing.
class UserStoreRef {
  final String storeId;
  final String shopName;
  final StoreRole role;
  final bool isActive;

  const UserStoreRef({
    required this.storeId,
    required this.shopName,
    required this.role,
    this.isActive = true,
  });

  factory UserStoreRef.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserStoreRef(
      storeId: doc.id,
      shopName: (data['shopName'] as String?) ?? '',
      role: StoreRole.fromString((data['role'] as String?) ?? 'viewer'),
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'shopName': shopName,
    'role': role.name,
    'isActive': isActive,
  };
}
