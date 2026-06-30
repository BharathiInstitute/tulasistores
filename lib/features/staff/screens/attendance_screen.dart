import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/models/staff_model.dart';
import 'package:retaillite/features/staff/providers/staff_provider.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/core/utils/permission_guard.dart';

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  DateTime _selectedDate = DateTime.now();
  final Map<String, AttendanceStatus> _todayStatus = {};
  final Map<String, TimeOfDay?> _clockIn = {};
  final Map<String, TimeOfDay?> _clockOut = {};
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _loading = true);
    try {
      final attendance = await StaffService.getTodayAttendance();
      if (mounted) {
        setState(() {
          _todayStatus.clear();
          _clockIn.clear();
          _clockOut.clear();
          for (final entry in attendance.entries) {
            _todayStatus[entry.key] = entry.value.status;
            if (entry.value.checkIn != null) {
              _clockIn[entry.key] = TimeOfDay.fromDateTime(
                entry.value.checkIn!,
              );
            }
            if (entry.value.checkOut != null) {
              _clockOut[entry.key] = TimeOfDay.fromDateTime(
                entry.value.checkOut!,
              );
            }
          }
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveAttendance(List<StaffModel> staffList) async {
    setState(() => _saving = true);
    try {
      for (final staff in staffList) {
        final status = _todayStatus[staff.id];
        if (status != null) {
          final cin = _clockIn[staff.id];
          final cout = _clockOut[staff.id];
          DateTime? checkIn;
          DateTime? checkOut;
          if (cin != null) {
            checkIn = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              cin.hour,
              cin.minute,
            );
          }
          if (cout != null) {
            checkOut = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              cout.hour,
              cout.minute,
            );
          }
          await StaffService.markAttendance(
            staffId: staff.id,
            date: _selectedDate,
            status: status,
            checkIn: checkIn,
            checkOut: checkOut,
          );
        }
      }
      ref.invalidate(todayAttendanceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance saved'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickTime(String staffId, {required bool isClockIn}) async {
    final initial = isClockIn
        ? (_clockIn[staffId] ?? const TimeOfDay(hour: 9, minute: 0))
        : (_clockOut[staffId] ?? const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (isClockIn) {
          _clockIn[staffId] = picked;
        } else {
          _clockOut[staffId] = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffAsync = ref.watch(activeStaffProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text('Daily Attendance', style: theme.textTheme.headlineMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () {
                    final staffList = staffAsync.valueOrNull ?? [];
                    setState(() {
                      for (final s in staffList) {
                        _todayStatus[s.id] = AttendanceStatus.present;
                      }
                    });
                  },
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('All Present'),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedDate = _selectedDate.subtract(
                        const Duration(days: 1),
                      );
                    });
                    _loadAttendance();
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(
                    DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                    style: theme.textTheme.titleMedium,
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedDate,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => _selectedDate = picked);
                      unawaited(_loadAttendance());
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      _selectedDate.isBefore(
                        DateTime.now().subtract(const Duration(days: 1)),
                      )
                      ? () {
                          setState(() {
                            _selectedDate = _selectedDate.add(
                              const Duration(days: 1),
                            );
                          });
                          _loadAttendance();
                        }
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Column headers
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  const SizedBox(width: 56),
                  Expanded(
                    flex: 2,
                    child: Text('Name', style: theme.textTheme.labelMedium),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text('Clock In', style: theme.textTheme.labelMedium),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Clock Out',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text('Status', style: theme.textTheme.labelMedium),
                  ),
                ],
              ),
            ),
            const Divider(),

            // Staff list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : staffAsync.when(
                      data: (staffList) {
                        if (staffList.isEmpty) {
                          return const Center(
                            child: Text('No active staff members'),
                          );
                        }
                        return ListView.separated(
                          itemCount: staffList.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, index) {
                            final staff = staffList[index];
                            return _buildRow(context, staff);
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                    ),
            ),

            // Save
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving || _todayStatus.isEmpty
                    ? null
                    : () => guardAction(
                        context,
                        ref,
                        'staff',
                        PermAction.edit,
                        onAllowed: () =>
                            _saveAttendance(staffAsync.valueOrNull ?? []),
                      ),
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: Text(
                  _saving
                      ? 'Saving...'
                      : 'Save Attendance (${_todayStatus.length} marked)',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, StaffModel staff) {
    final theme = Theme.of(context);
    final status = _todayStatus[staff.id];
    final cin = _clockIn[staff.id];
    final cout = _clockOut[staff.id];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
              style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(staff.name, style: theme.textTheme.titleSmall),
                Text(
                  staff.role.displayName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          // Clock In
          Expanded(
            flex: 2,
            child: _timeButton(
              context,
              icon: Icons.login,
              color: Colors.green.shade700,
              time: cin,
              onTap: () => _pickTime(staff.id, isClockIn: true),
            ),
          ),
          const SizedBox(width: 6),
          // Clock Out
          Expanded(
            flex: 2,
            child: _timeButton(
              context,
              icon: Icons.logout,
              color: Colors.red.shade700,
              time: cout,
              onTap: () => _pickTime(staff.id, isClockIn: false),
            ),
          ),
          const SizedBox(width: 6),
          // Status
          Expanded(
            flex: 3,
            child: Row(
              children: AttendanceStatus.values.map((s) {
                final isSelected = status == s;
                return Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: ChoiceChip(
                    label: Text(s.emoji),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _todayStatus[staff.id] = s),
                    selectedColor: _statusColor(s).withValues(alpha: 0.2),
                    tooltip: s.displayName,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeButton(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required TimeOfDay? time,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              time != null ? time.format(context) : '--:--',
              style: TextStyle(
                fontSize: 13,
                color: time != null ? color : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(AttendanceStatus s) {
    return switch (s) {
      AttendanceStatus.present => Colors.green,
      AttendanceStatus.absent => Colors.red,
      AttendanceStatus.halfDay => Colors.orange,
      AttendanceStatus.leave => Colors.blue,
    };
  }
}
