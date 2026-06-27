import 'package:cloud_firestore/cloud_firestore.dart';

class PayoutModel {
  final String id;
  final String staffId;
  final String staffName;
  final String month; // "2026-06" format
  final double baseSalary;
  final int totalDays; // working days in the month
  final int daysWorked; // full days present
  final int halfDays;
  final int absentDays;
  final int leaveDays;
  final double overtimeHours;
  final double overtimeRate; // per hour
  final double deductions; // absent-day deductions
  final double overtimePay;
  final double bonus;
  final double advance; // already-paid advances
  final double netPay; // final calculated amount
  final DateTime? paidAt;
  final bool isPaid;
  final DateTime createdAt;

  const PayoutModel({
    required this.id,
    required this.staffId,
    required this.staffName,
    required this.month,
    required this.baseSalary,
    required this.totalDays,
    required this.daysWorked,
    this.halfDays = 0,
    this.absentDays = 0,
    this.leaveDays = 0,
    this.overtimeHours = 0,
    this.overtimeRate = 0,
    this.deductions = 0,
    this.overtimePay = 0,
    this.bonus = 0,
    this.advance = 0,
    required this.netPay,
    this.paidAt,
    this.isPaid = false,
    required this.createdAt,
  });

  factory PayoutModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PayoutModel(
      id: doc.id,
      staffId: (data['staffId'] as String?) ?? '',
      staffName: (data['staffName'] as String?) ?? '',
      month: (data['month'] as String?) ?? '',
      baseSalary: (data['baseSalary'] as num?)?.toDouble() ?? 0,
      totalDays: (data['totalDays'] as num?)?.toInt() ?? 0,
      daysWorked: (data['daysWorked'] as num?)?.toInt() ?? 0,
      halfDays: (data['halfDays'] as num?)?.toInt() ?? 0,
      absentDays: (data['absentDays'] as num?)?.toInt() ?? 0,
      leaveDays: (data['leaveDays'] as num?)?.toInt() ?? 0,
      overtimeHours: (data['overtimeHours'] as num?)?.toDouble() ?? 0,
      overtimeRate: (data['overtimeRate'] as num?)?.toDouble() ?? 0,
      deductions: (data['deductions'] as num?)?.toDouble() ?? 0,
      overtimePay: (data['overtimePay'] as num?)?.toDouble() ?? 0,
      bonus: (data['bonus'] as num?)?.toDouble() ?? 0,
      advance: (data['advance'] as num?)?.toDouble() ?? 0,
      netPay: (data['netPay'] as num?)?.toDouble() ?? 0,
      paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      isPaid: (data['isPaid'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
    'staffId': staffId,
    'staffName': staffName,
    'month': month,
    'baseSalary': baseSalary,
    'totalDays': totalDays,
    'daysWorked': daysWorked,
    'halfDays': halfDays,
    'absentDays': absentDays,
    'leaveDays': leaveDays,
    'overtimeHours': overtimeHours,
    'overtimeRate': overtimeRate,
    'deductions': deductions,
    'overtimePay': overtimePay,
    'bonus': bonus,
    'advance': advance,
    'netPay': netPay,
    'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
    'isPaid': isPaid,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  PayoutModel copyWith({
    double? bonus,
    double? advance,
    double? netPay,
    bool? isPaid,
    DateTime? paidAt,
  }) {
    return PayoutModel(
      id: id,
      staffId: staffId,
      staffName: staffName,
      month: month,
      baseSalary: baseSalary,
      totalDays: totalDays,
      daysWorked: daysWorked,
      halfDays: halfDays,
      absentDays: absentDays,
      leaveDays: leaveDays,
      overtimeHours: overtimeHours,
      overtimeRate: overtimeRate,
      deductions: deductions,
      overtimePay: overtimePay,
      bonus: bonus ?? this.bonus,
      advance: advance ?? this.advance,
      netPay: netPay ?? this.netPay,
      isPaid: isPaid ?? this.isPaid,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt,
    );
  }
}
