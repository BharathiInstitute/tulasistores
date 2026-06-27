import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/models/payout_model.dart';
import 'package:retaillite/features/staff/models/staff_model.dart';

class StaffService {
  StaffService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );

  static String get _basePath => ActiveStore.basePath;

  // ─── Staff CRUD ──────────────────────────────────────────────

  /// Create a new staff member (calls Cloud Function to create Auth user)
  static Future<String> createStaff({
    required String name,
    required String email,
    required String password,
    required String phone,
    required StaffRole role,
    required double salary,
  }) async {
    final callable = _functions.httpsCallable('createStaffUser');
    final result = await callable.call<Map<String, dynamic>>({
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'role': role.name,
      'salary': salary,
      'storeId': ActiveStore.storeId,
    });

    final data = result.data;
    debugPrint('✅ Staff created: ${data['uid']}');
    return data['uid'] as String;
  }

  /// Stream all staff members.
  ///
  /// In multi-store mode (basePath starts with 'stores/'), reads from
  /// the `members` collection so all store users appear for attendance.
  /// In legacy mode, reads from the `staff` subcollection.
  static Stream<List<StaffModel>> staffStream() {
    if (_basePath.isEmpty) return Stream.value([]);

    // Multi-store: use members as staff source
    if (_basePath.startsWith('stores/')) {
      return _firestore
          .collection('$_basePath/members')
          .snapshots()
          .map(
            (snap) => snap.docs
                .where((doc) => doc.id != '_init')
                .map(_memberToStaff)
                .toList(),
          );
    }

    // Legacy: use staff subcollection
    return _firestore
        .collection('$_basePath/staff')
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs
              .where((doc) => doc.id != '_init')
              .map(StaffModel.fromFirestore)
              .toList(),
        );
  }

  /// Convert a members collection doc to StaffModel
  static StaffModel _memberToStaff(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StaffModel(
      id: doc.id,
      uid: doc.id,
      name: (data['displayName'] as String?) ?? (data['name'] as String?) ?? '',
      email: (data['email'] as String?) ?? '',
      phone: (data['phone'] as String?) ?? '',
      role: StaffRole.fromString((data['role'] as String?) ?? 'helper'),
      salary: (data['salary'] as num?)?.toDouble() ?? 0,
      joiningDate:
          (data['joinedAt'] as Timestamp?)?.toDate() ??
          (data['joiningDate'] as Timestamp?)?.toDate() ??
          DateTime.now(),
      isActive: (data['isActive'] as bool?) ?? true,
      photoUrl: data['photoUrl'] as String?,
      createdAt:
          (data['joinedAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate() ??
          DateTime.now(),
    );
  }

  /// Get a single staff member
  static Future<StaffModel?> getStaff(String staffId) async {
    if (_basePath.isEmpty) return null;
    final doc = await _firestore.doc(_staffDocPath(staffId)).get();
    if (!doc.exists) return null;
    if (_basePath.startsWith('stores/')) return _memberToStaff(doc);
    return StaffModel.fromFirestore(doc);
  }

  /// Update staff details (name, phone, role, salary, etc.)
  static Future<void> updateStaff(StaffModel staff) async {
    if (_basePath.isEmpty) return;
    await _firestore.doc(_staffDocPath(staff.id)).update({
      'name': staff.name,
      if (_basePath.startsWith('stores/')) 'displayName': staff.name,
      'phone': staff.phone,
      'role': staff.role.name,
      'salary': staff.salary,
      'isActive': staff.isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deactivate a staff member (disables their Auth account too)
  static Future<void> deactivateStaff(String staffUid) async {
    final callable = _functions.httpsCallable('deactivateStaffUser');
    await callable.call<Map<String, dynamic>>({'staffUid': staffUid});
  }

  /// Resolves the base collection for a staff/member's subcollections (attendance, payouts).
  /// In multi-store mode, uses `members`; in legacy mode, uses `staff`.
  static String _staffDocPath(String staffId) {
    if (_basePath.startsWith('stores/')) {
      return '$_basePath/members/$staffId';
    }
    return '$_basePath/staff/$staffId';
  }

  // ─── Attendance ──────────────────────────────────────────────

  /// Mark attendance for a staff member on a specific date
  static Future<void> markAttendance({
    required String staffId,
    required DateTime date,
    required AttendanceStatus status,
    DateTime? checkIn,
    DateTime? checkOut,
    double overtimeHours = 0,
    String? note,
    String source = 'manual',
  }) async {
    if (_basePath.isEmpty) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final docRef = _firestore.doc(
      '${_staffDocPath(staffId)}/attendance/$dateStr',
    );

    final data = <String, dynamic>{
      'staffId': staffId,
      'date': Timestamp.fromDate(date),
      'status': status.name,
      'checkIn': checkIn != null ? Timestamp.fromDate(checkIn) : null,
      'checkOut': checkOut != null ? Timestamp.fromDate(checkOut) : null,
      'overtimeHours': overtimeHours,
      'note': note,
      'source': source,
    };

    // Calculate hours worked if both check-in and check-out are set
    if (checkIn != null && checkOut != null) {
      data['hoursWorked'] = checkOut.difference(checkIn).inMinutes / 60.0;
    }

    await docRef.set(data, SetOptions(merge: true));
  }

  /// Get attendance for a staff member for a specific month
  static Stream<List<AttendanceModel>> attendanceStream({
    required String staffId,
    required int year,
    required int month,
  }) {
    if (_basePath.isEmpty) return Stream.value([]);
    final startDate = DateTime(year, month);
    final endDate = DateTime(year, month + 1); // first day of NEXT month

    return _firestore
        .collection('${_staffDocPath(staffId)}/attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(AttendanceModel.fromFirestore).toList());
  }

  /// Get today's attendance for all staff
  static Future<Map<String, AttendanceModel>> getTodayAttendance() async {
    if (_basePath.isEmpty) return {};
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    // Determine the right collection for listing staff/members
    final collectionPath = _basePath.startsWith('stores/')
        ? '$_basePath/members'
        : '$_basePath/staff';
    final staffSnap = await _firestore.collection(collectionPath).get();
    final result = <String, AttendanceModel>{};

    for (final staffDoc in staffSnap.docs) {
      if (staffDoc.id == '_init') continue;
      final attDoc = await _firestore
          .doc('${_staffDocPath(staffDoc.id)}/attendance/$today')
          .get();
      if (attDoc.exists) {
        result[staffDoc.id] = AttendanceModel.fromFirestore(attDoc);
      }
    }
    return result;
  }

  // ─── Self Attendance (Staff Clock In/Out with GPS) ───────────

  /// Staff clocks in themselves with geo location.
  /// Can only clock in once per day; returns the attendance record.
  static Future<AttendanceModel?> selfCheckIn({bool requireGps = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _basePath.isEmpty) return null;
    if (!_basePath.startsWith('stores/')) return null;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docPath = '${_staffDocPath(uid)}/attendance/$today';

    // Check if already clocked in
    final existing = await _firestore.doc(docPath).get();
    if (existing.exists) {
      return AttendanceModel.fromFirestore(existing);
    }

    // Get GPS location
    final position = await _getPosition();
    if (requireGps && position == null) {
      throw Exception(
        'GPS location is required. Please enable location services and try again.',
      );
    }
    final address = await _reverseGeocode(position);

    final now = DateTime.now();
    final data = <String, dynamic>{
      'staffId': uid,
      'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
      'status': AttendanceStatus.present.name,
      'checkIn': Timestamp.fromDate(now),
      'checkOut': null,
      'overtimeHours': 0,
      'note': null,
      'source': 'self',
      'hoursWorked': null,
      'checkInLocation': position != null
          ? GeoPoint(position.latitude, position.longitude)
          : null,
      'checkInAddress': address,
      'checkOutLocation': null,
      'checkOutAddress': null,
    };

    await _firestore.doc(docPath).set(data);
    debugPrint('✅ Self check-in at ${DateFormat.jm().format(now)} — $address');

    return AttendanceModel(
      id: today,
      staffId: uid,
      date: DateTime(now.year, now.month, now.day),
      status: AttendanceStatus.present,
      checkIn: now,
      source: 'self',
      checkInLocation: position != null
          ? GeoPoint(position.latitude, position.longitude)
          : null,
      checkInAddress: address,
    );
  }

  /// Staff clocks out themselves with geo location.
  static Future<AttendanceModel?> selfCheckOut() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _basePath.isEmpty) return null;
    if (!_basePath.startsWith('stores/')) return null;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docPath = '${_staffDocPath(uid)}/attendance/$today';

    // Must have checked in first
    final existing = await _firestore.doc(docPath).get();
    if (!existing.exists) return null;

    final data = existing.data();
    if (data == null) return null;
    // Already checked out
    if (data['checkOut'] != null) {
      return AttendanceModel.fromFirestore(existing);
    }

    // Get GPS location
    final position = await _getPosition();
    final address = await _reverseGeocode(position);

    final now = DateTime.now();
    final checkIn = (data['checkIn'] as Timestamp?)?.toDate();
    final hoursWorked = checkIn != null
        ? now.difference(checkIn).inMinutes / 60.0
        : null;

    await _firestore.doc(docPath).update({
      'checkOut': Timestamp.fromDate(now),
      'hoursWorked': hoursWorked,
      'checkOutLocation': position != null
          ? GeoPoint(position.latitude, position.longitude)
          : null,
      'checkOutAddress': address,
    });

    debugPrint('✅ Self check-out at ${DateFormat.jm().format(now)} — $address');

    final updated = await _firestore.doc(docPath).get();
    return AttendanceModel.fromFirestore(updated);
  }

  /// Get today's attendance record for current user
  static Future<AttendanceModel?> getMyTodayAttendance() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _basePath.isEmpty) return null;
    if (!_basePath.startsWith('stores/')) return null;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docPath = '${_staffDocPath(uid)}/attendance/$today';
    final doc = await _firestore.doc(docPath).get();
    if (!doc.exists) return null;
    return AttendanceModel.fromFirestore(doc);
  }

  /// Stream current user's attendance for a month (for calendar view)
  static Stream<List<AttendanceModel>> myAttendanceStream({
    required int year,
    required int month,
  }) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || _basePath.isEmpty) return Stream.value([]);
    if (!_basePath.startsWith('stores/')) return Stream.value([]);

    final startDate = DateTime(year, month);
    final endDate = DateTime(year, month + 1);

    return _firestore
        .collection('${_staffDocPath(uid)}/attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThan: Timestamp.fromDate(endDate))
        .orderBy('date')
        .snapshots()
        .map((snap) => snap.docs.map(AttendanceModel.fromFirestore).toList());
  }

  // ─── Attendance Settings ───────────────────────────────────────

  static const Map<String, dynamic> _defaultAttendanceSettings = {
    'allowSelfCheckIn': true,
    'requireGps': true,
    'allowMultipleCheckIns': false,
  };

  /// Stream attendance settings from Firestore.
  static Stream<Map<String, dynamic>> attendanceSettingsStream() {
    if (_basePath.isEmpty) {
      return Stream.value(Map.from(_defaultAttendanceSettings));
    }
    return _firestore
        .doc('$_basePath/settings/attendance')
        .snapshots()
        .map(
          (doc) => doc.exists
              ? {..._defaultAttendanceSettings, ...doc.data()!}
              : Map<String, dynamic>.from(_defaultAttendanceSettings),
        );
  }

  /// Save a single attendance setting key/value to Firestore.
  static Future<void> saveAttendanceSetting(String key, bool value) async {
    if (_basePath.isEmpty) return;
    await _firestore.doc('$_basePath/settings/attendance').set({
      key: value,
    }, SetOptions(merge: true));
  }

  /// Get GPS position (with permission handling)
  static Future<Position?> _getPosition() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ GPS failed: $e');
      return null;
    }
  }

  /// Reverse geocode position to address string
  static Future<String?> _reverseGeocode(Position? position) async {
    if (position == null) return null;
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = <String>[
        if (p.street != null && p.street!.isNotEmpty) p.street!,
        if (p.subLocality != null && p.subLocality!.isNotEmpty) p.subLocality!,
        if (p.locality != null && p.locality!.isNotEmpty) p.locality!,
      ];
      return parts.isNotEmpty ? parts.join(', ') : null;
    } catch (e) {
      debugPrint('⚠️ Geocoding failed: $e');
      return null;
    }
  }

  /// Get all members' attendance records for a date range.
  /// Returns a flat list sorted by date, with staffName attached.
  static Future<List<AttendanceRecord>> getAllAttendanceForRange({
    required DateTime from,
    required DateTime to,
  }) async {
    if (_basePath.isEmpty || !_basePath.startsWith('stores/')) return [];

    // Get all members
    final membersSnap = await _firestore.collection('$_basePath/members').get();
    final members = membersSnap.docs.where((d) => d.id != '_init').toList();

    final results = <AttendanceRecord>[];

    for (final memberDoc in members) {
      final memberId = memberDoc.id;
      final data = memberDoc.data();
      final name =
          (data['displayName'] as String?) ?? (data['name'] as String?) ?? '?';

      // Query this member's attendance for the range
      final attSnap = await _firestore
          .collection('$_basePath/members/$memberId/attendance')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where(
            'date',
            isLessThan: Timestamp.fromDate(to.add(const Duration(days: 1))),
          )
          .orderBy('date')
          .get();

      for (final doc in attSnap.docs) {
        final att = AttendanceModel.fromFirestore(doc);
        results.add(AttendanceRecord(staffName: name, attendance: att));
      }
    }

    // Sort by date descending, then by name
    results.sort((a, b) {
      final dateComp = b.attendance.date.compareTo(a.attendance.date);
      if (dateComp != 0) return dateComp;
      return a.staffName.compareTo(b.staffName);
    });

    return results;
  }

  // ─── Payouts ─────────────────────────────────────────────────

  /// Calculate payout for a staff member for a given month
  static Future<PayoutModel> calculatePayout({
    required StaffModel staff,
    required int year,
    required int month,
    double bonus = 0,
    double advance = 0,
  }) async {
    if (_basePath.isEmpty) {
      throw Exception('Not authenticated');
    }

    // Get attendance records for the month
    final startDate = DateTime(year, month);
    final endDate = DateTime(year, month + 1, 0);
    final totalDays = endDate.day;

    final attSnap = await _firestore
        .collection('${_staffDocPath(staff.id)}/attendance')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
        .get();

    final records = attSnap.docs.map(AttendanceModel.fromFirestore).toList();

    int daysWorked = 0;
    int halfDays = 0;
    int absentDays = 0;
    int leaveDays = 0;
    double totalOvertime = 0;

    for (final r in records) {
      switch (r.status) {
        case AttendanceStatus.present:
          daysWorked++;
          totalOvertime += r.overtimeHours;
        case AttendanceStatus.halfDay:
          halfDays++;
        case AttendanceStatus.absent:
          absentDays++;
        case AttendanceStatus.leave:
          leaveDays++;
      }
    }

    // Calculate pay
    final perDayRate = staff.salary / totalDays;
    final overtimeRate = perDayRate / 8; // per hour
    final effectiveDays = daysWorked + (halfDays * 0.5) + leaveDays;
    final deductions = (totalDays - effectiveDays - absentDays >= 0)
        ? absentDays * perDayRate
        : (totalDays - effectiveDays) * perDayRate;
    final overtimePay = totalOvertime * overtimeRate;
    final netPay = (effectiveDays * perDayRate) + overtimePay + bonus - advance;

    final monthStr = DateFormat('yyyy-MM').format(DateTime(year, month));

    return PayoutModel(
      id: '${staff.id}_$monthStr',
      staffId: staff.id,
      staffName: staff.name,
      month: monthStr,
      baseSalary: staff.salary,
      totalDays: totalDays,
      daysWorked: daysWorked,
      halfDays: halfDays,
      absentDays: absentDays,
      leaveDays: leaveDays,
      overtimeHours: totalOvertime,
      overtimeRate: overtimeRate,
      deductions: deductions < 0 ? 0 : deductions,
      overtimePay: overtimePay,
      bonus: bonus,
      advance: advance,
      netPay: netPay < 0 ? 0 : netPay,
      createdAt: DateTime.now(),
    );
  }

  /// Save a finalized payout record
  static Future<void> savePayout(PayoutModel payout) async {
    if (_basePath.isEmpty) return;
    await _firestore
        .doc('${_staffDocPath(payout.staffId)}/payouts/${payout.id}')
        .set(payout.toFirestore());
  }

  /// Mark a payout as paid
  static Future<void> markPayoutPaid(String staffId, String payoutId) async {
    if (_basePath.isEmpty) return;
    await _firestore.doc('${_staffDocPath(staffId)}/payouts/$payoutId').update({
      'isPaid': true,
      'paidAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get payout history for a staff member
  static Stream<List<PayoutModel>> payoutsStream(String staffId) {
    if (_basePath.isEmpty) return Stream.value([]);
    return _firestore
        .collection('${_staffDocPath(staffId)}/payouts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(PayoutModel.fromFirestore).toList());
  }
}
