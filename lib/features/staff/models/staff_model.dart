import 'package:cloud_firestore/cloud_firestore.dart';

/// Roles a staff member can have
enum StaffRole {
  cashier('Cashier', 'Can create bills and view inventory'),
  manager('Manager', 'Full access except settings'),
  helper('Helper', 'View-only access');

  final String displayName;
  final String description;
  const StaffRole(this.displayName, this.description);

  static StaffRole fromString(String value) {
    return StaffRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => StaffRole.helper,
    );
  }
}

class StaffModel {
  final String id;
  final String uid; // Firebase Auth UID for this staff member
  final String name;
  final String email;
  final String phone;
  final StaffRole role;
  final double salary; // monthly salary
  final DateTime joiningDate;
  final bool isActive;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const StaffModel({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.salary,
    required this.joiningDate,
    this.isActive = true,
    this.photoUrl,
    required this.createdAt,
    this.updatedAt,
  });

  factory StaffModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StaffModel(
      id: doc.id,
      uid: (data['uid'] as String?) ?? '',
      name: (data['name'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      role: StaffRole.fromString((data['role'] as String?) ?? 'helper'),
      salary: (data['salary'] as num?)?.toDouble() ?? 0,
      joiningDate:
          (data['joiningDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: (data['isActive'] as bool?) ?? true,
      photoUrl: data['photoUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'uid': uid,
    'name': name,
    'email': email,
    'phone': phone,
    'role': role.name,
    'salary': salary,
    'joiningDate': Timestamp.fromDate(joiningDate),
    'isActive': isActive,
    'photoUrl': photoUrl,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
  };

  StaffModel copyWith({
    String? name,
    String? email,
    String? phone,
    StaffRole? role,
    double? salary,
    DateTime? joiningDate,
    bool? isActive,
    String? photoUrl,
  }) {
    return StaffModel(
      id: id,
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      salary: salary ?? this.salary,
      joiningDate: joiningDate ?? this.joiningDate,
      isActive: isActive ?? this.isActive,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
