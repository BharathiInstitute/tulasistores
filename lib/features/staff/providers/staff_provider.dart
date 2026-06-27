import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/models/payout_model.dart';
import 'package:retaillite/features/staff/models/staff_model.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';

/// Stream of all staff members
final staffListProvider = StreamProvider<List<StaffModel>>((ref) {
  ref.watch(activeStoreIdProvider); // re-subscribe on store change
  return StaffService.staffStream();
});

/// Filtered list: active staff only
final activeStaffProvider = Provider<AsyncValue<List<StaffModel>>>((ref) {
  return ref
      .watch(staffListProvider)
      .whenData((list) => list.where((s) => s.isActive).toList());
});

/// Attendance stream for a specific staff + month
final staffAttendanceProvider =
    StreamProvider.family<
      List<AttendanceModel>,
      ({String staffId, int year, int month})
    >((ref, params) {
      ref.watch(activeStoreIdProvider);
      return StaffService.attendanceStream(
        staffId: params.staffId,
        year: params.year,
        month: params.month,
      );
    });

/// Payout history for a staff member
final staffPayoutsProvider = StreamProvider.family<List<PayoutModel>, String>((
  ref,
  staffId,
) {
  ref.watch(activeStoreIdProvider);
  return StaffService.payoutsStream(staffId);
});

/// Today's attendance for all staff (one-shot)
final todayAttendanceProvider = FutureProvider<Map<String, AttendanceModel>>((
  ref,
) {
  ref.watch(activeStoreIdProvider);
  return StaffService.getTodayAttendance();
});
