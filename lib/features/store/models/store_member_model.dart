import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';

/// A user's membership in a specific store.
///
/// Stored in two places (dual write):
///   1. `stores/{storeId}/members/{uid}` — for store-scoped queries
///   2. `users/{uid}/stores/{storeId}`  — for user-scoped "my stores" queries
class StoreMemberModel {
  final String uid;
  final String displayName;
  final String email;
  final StoreRole role;
  final PermissionsModel permissions;
  final DateTime joinedAt;
  final bool isActive;

  const StoreMemberModel({
    required this.uid,
    required this.displayName,
    required this.email,
    required this.role,
    required this.permissions,
    required this.joinedAt,
    this.isActive = true,
  });

  factory StoreMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StoreMemberModel(
      uid: doc.id,
      displayName: (data['displayName'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      role: StoreRole.fromString((data['role'] as String?) ?? 'viewer'),
      permissions: data['permissions'] is Map<String, dynamic>
          ? PermissionsModel.fromMap(
              data['permissions'] as Map<String, dynamic>,
            )
          : PermissionsModel.forRole(
              StoreRole.fromString((data['role'] as String?) ?? 'viewer'),
            ),
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: (data['isActive'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'displayName': displayName,
    'email': email,
    'role': role.name,
    'permissions': permissions.toMap(),
    'joinedAt': Timestamp.fromDate(joinedAt),
    'isActive': isActive,
  };

  StoreMemberModel copyWith({
    StoreRole? role,
    PermissionsModel? permissions,
    bool? isActive,
  }) {
    return StoreMemberModel(
      uid: uid,
      displayName: displayName,
      email: email,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      joinedAt: joinedAt,
      isActive: isActive ?? this.isActive,
    );
  }
}
