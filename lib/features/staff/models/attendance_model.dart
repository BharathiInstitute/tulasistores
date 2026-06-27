import 'package:cloud_firestore/cloud_firestore.dart';

/// Daily attendance status
enum AttendanceStatus {
  present('Present', '✅'),
  absent('Absent', '❌'),
  halfDay('Half Day', '🕐'),
  leave('Leave', '🏖️');

  final String displayName;
  final String emoji;
  const AttendanceStatus(this.displayName, this.emoji);

  static AttendanceStatus fromString(String value) {
    return AttendanceStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => AttendanceStatus.absent,
    );
  }
}

class AttendanceModel {
  final String id; // date string: YYYY-MM-DD
  final String staffId;
  final DateTime date;
  final AttendanceStatus status;
  final DateTime? checkIn;
  final DateTime? checkOut;
  final double overtimeHours;
  final String? note;
  final String source; // "auto", "manual", or "self"
  final double? hoursWorked;
  final GeoPoint? checkInLocation;
  final GeoPoint? checkOutLocation;
  final String? checkInAddress;
  final String? checkOutAddress;

  const AttendanceModel({
    required this.id,
    required this.staffId,
    required this.date,
    required this.status,
    this.checkIn,
    this.checkOut,
    this.overtimeHours = 0,
    this.note,
    this.source = 'manual',
    this.hoursWorked,
    this.checkInLocation,
    this.checkOutLocation,
    this.checkInAddress,
    this.checkOutAddress,
  });

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceModel(
      id: doc.id,
      staffId: (data['staffId'] as String?) ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: AttendanceStatus.fromString(
        (data['status'] as String?) ?? 'absent',
      ),
      checkIn: (data['checkIn'] as Timestamp?)?.toDate(),
      checkOut: (data['checkOut'] as Timestamp?)?.toDate(),
      overtimeHours: (data['overtimeHours'] as num?)?.toDouble() ?? 0,
      note: data['note'] as String?,
      source: (data['source'] as String?) ?? 'manual',
      hoursWorked: (data['hoursWorked'] as num?)?.toDouble(),
      checkInLocation: data['checkInLocation'] as GeoPoint?,
      checkOutLocation: data['checkOutLocation'] as GeoPoint?,
      checkInAddress: data['checkInAddress'] as String?,
      checkOutAddress: data['checkOutAddress'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'staffId': staffId,
    'date': Timestamp.fromDate(date),
    'status': status.name,
    'checkIn': checkIn != null ? Timestamp.fromDate(checkIn!) : null,
    'checkOut': checkOut != null ? Timestamp.fromDate(checkOut!) : null,
    'overtimeHours': overtimeHours,
    'note': note,
    'source': source,
    'hoursWorked': hoursWorked,
    'checkInLocation': checkInLocation,
    'checkOutLocation': checkOutLocation,
    'checkInAddress': checkInAddress,
    'checkOutAddress': checkOutAddress,
  };

  bool get isAuto => source == 'auto';
  bool get isSelf => source == 'self';

  AttendanceModel copyWith({
    AttendanceStatus? status,
    DateTime? checkIn,
    DateTime? checkOut,
    double? overtimeHours,
    String? note,
    String? source,
    double? hoursWorked,
  }) {
    return AttendanceModel(
      id: id,
      staffId: staffId,
      date: date,
      status: status ?? this.status,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      overtimeHours: overtimeHours ?? this.overtimeHours,
      note: note ?? this.note,
      source: source ?? this.source,
      hoursWorked: hoursWorked ?? this.hoursWorked,
      checkInLocation: checkInLocation,
      checkOutLocation: checkOutLocation,
      checkInAddress: checkInAddress,
      checkOutAddress: checkOutAddress,
    );
  }
}

/// A combined record with staff name for range queries.
class AttendanceRecord {
  final String staffName;
  final AttendanceModel attendance;

  const AttendanceRecord({required this.staffName, required this.attendance});
}
