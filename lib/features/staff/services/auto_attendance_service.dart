import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';

/// Automatic attendance service — marks check-in on login, check-out on logout.
///
/// Works in multi-store mode: writes to `stores/{storeId}/members/{uid}/attendance/`.
/// Safe to call multiple times per day — only creates record on first call.
class AutoAttendanceService {
  AutoAttendanceService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _checkedInToday = false;

  /// Call on app startup / auth state change.
  /// Auto-marks "present" with check-in time if no record exists for today.
  static Future<void> autoCheckIn() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      final basePath = ActiveStore.basePath;
      if (basePath.isEmpty) return;

      // Only auto-check-in for multi-store mode (staff/members)
      if (!basePath.startsWith('stores/')) return;

      final storeId = ActiveStore.storeId;
      final uid = user.uid;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docPath = 'stores/$storeId/members/$uid/attendance/$today';

      // Check if already marked today
      final doc = await _firestore.doc(docPath).get();
      if (doc.exists) {
        _checkedInToday = true;
        debugPrint('📋 Auto-attendance: already checked in today');
        return;
      }

      // Create auto check-in record
      final now = DateTime.now();
      await _firestore.doc(docPath).set({
        'staffId': uid,
        'date': Timestamp.fromDate(DateTime(now.year, now.month, now.day)),
        'status': AttendanceStatus.present.name,
        'checkIn': Timestamp.fromDate(now),
        'checkOut': null,
        'overtimeHours': 0,
        'note': null,
        'source': 'auto',
        'hoursWorked': null,
      });

      _checkedInToday = true;
      debugPrint(
        '✅ Auto-attendance: checked in at ${DateFormat.jm().format(now)}',
      );
    } catch (e) {
      debugPrint('⚠️ Auto-attendance check-in failed (non-fatal): $e');
    }
  }

  /// Call on logout or app going to background.
  /// Records check-out time and calculates hours worked.
  static Future<void> autoCheckOut() async {
    try {
      if (!_checkedInToday) return;

      final user = _auth.currentUser;
      if (user == null) return;

      final basePath = ActiveStore.basePath;
      if (basePath.isEmpty || !basePath.startsWith('stores/')) return;

      final storeId = ActiveStore.storeId;
      final uid = user.uid;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final docPath = 'stores/$storeId/members/$uid/attendance/$today';

      final doc = await _firestore.doc(docPath).get();
      if (!doc.exists) return;

      final data = doc.data();
      if (data == null) return;

      // Only update if source is 'auto' (don't overwrite admin's manual entry)
      if (data['source'] != 'auto') return;

      final now = DateTime.now();
      final checkIn = (data['checkIn'] as Timestamp?)?.toDate();
      final hoursWorked = checkIn != null
          ? now.difference(checkIn).inMinutes / 60.0
          : null;

      await _firestore.doc(docPath).update({
        'checkOut': Timestamp.fromDate(now),
        'hoursWorked': hoursWorked,
      });

      debugPrint(
        '✅ Auto-attendance: checked out at ${DateFormat.jm().format(now)}'
        '${hoursWorked != null ? ' (${hoursWorked.toStringAsFixed(1)}h)' : ''}',
      );
    } catch (e) {
      debugPrint('⚠️ Auto-attendance check-out failed (non-fatal): $e');
    }
  }

  /// Reset state (call on logout)
  static void reset() {
    _checkedInToday = false;
  }
}
