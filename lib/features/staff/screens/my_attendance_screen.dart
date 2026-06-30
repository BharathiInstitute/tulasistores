import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';

class MyAttendanceScreen extends ConsumerStatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  ConsumerState<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends ConsumerState<MyAttendanceScreen> {
  AttendanceModel? _today;
  bool _loading = true;
  bool _actionLoading = false;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _loadToday();
  }

  Future<void> _loadToday() async {
    setState(() => _loading = true);
    try {
      final record = await StaffService.getMyTodayAttendance();
      if (mounted) {
        setState(() {
          _today = record;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clockIn() async {
    final settings = ref.read(attendanceSettingsProvider).valueOrNull ?? {};
    final requireGps = settings['requireGps'] as bool? ?? true;
    setState(() => _actionLoading = true);
    try {
      final record = await StaffService.selfCheckIn(requireGps: requireGps);
      if (mounted) {
        setState(() {
          _today = record;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Clocked in at ${DateFormat.jm().format(DateTime.now())}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clockOut() async {
    setState(() => _actionLoading = true);
    try {
      final record = await StaffService.selfCheckOut();
      if (mounted) {
        setState(() {
          _today = record;
          _actionLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Clocked out at ${DateFormat.jm().format(DateTime.now())}',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _actionLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(attendanceSettingsProvider).valueOrNull ?? {};
    final allowSelfCheckIn = settings['allowSelfCheckIn'] as bool? ?? true;

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Text('My Attendance', style: theme.textTheme.headlineMedium),
            Text(
              DateFormat('EEEE, d MMMM yyyy').format(DateTime.now()),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),

            // Blocked state
            if (!allowSelfCheckIn)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 500),
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.lock_outline,
                            size: 48,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Self Check-in Disabled',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your admin has disabled self attendance.\nContact your manager to mark attendance.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            // Clock In / Clock Out Card
            else if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              _buildClockCard(theme),

            const SizedBox(height: 32),

            // Monthly History
            _buildMonthlyHistory(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildClockCard(ThemeData theme) {
    final settings = ref.watch(attendanceSettingsProvider).valueOrNull ?? {};
    final allowMultiple = settings['allowMultipleCheckIns'] as bool? ?? true;

    final hasCheckedIn = _today?.checkIn != null;
    final hasCheckedOut = _today?.checkOut != null;
    // For multi-mode: check if there's an open session
    final hasOpenSession = _today?.hasOpenSession ?? false;
    final sessions = _today?.sessions ?? [];

    // Determine current state for multi-mode
    final bool canClockIn;
    final bool canClockOut;
    final String statusText;
    final IconData statusIcon;
    final Color statusColor;

    if (allowMultiple && hasCheckedIn) {
      // Multi-mode: allow re-clock-in after clock-out
      canClockOut = hasOpenSession;
      canClockIn = !hasOpenSession;
      if (hasOpenSession) {
        statusText = 'Checked In';
        statusIcon = Icons.access_time;
        statusColor = Colors.green;
      } else {
        statusText = sessions.isNotEmpty
            ? '${sessions.length} session${sessions.length > 1 ? 's' : ''} today'
            : 'Ready to Clock In';
        statusIcon = Icons.replay;
        statusColor = Colors.blue;
      }
    } else {
      canClockIn = !hasCheckedIn;
      canClockOut = hasCheckedIn && !hasCheckedOut;
      if (hasCheckedOut) {
        statusText = 'Day Complete';
        statusIcon = Icons.check_circle;
        statusColor = Colors.grey;
      } else if (hasCheckedIn) {
        statusText = 'Checked In';
        statusIcon = Icons.access_time;
        statusColor = Colors.green;
      } else {
        statusText = 'Not Checked In';
        statusIcon = Icons.login;
        statusColor = Colors.orange;
      }
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                // Status Icon
                CircleAvatar(
                  radius: 40,
                  backgroundColor: statusColor.withValues(alpha: 0.2),
                  child: Icon(statusIcon, size: 40, color: statusColor),
                ),
                const SizedBox(height: 16),

                // Status Text
                Text(
                  statusText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Sessions list for multi-mode
                if (allowMultiple && sessions.isNotEmpty) ...[
                  ...sessions.asMap().entries.map((entry) {
                    final i = entry.key;
                    final s = entry.value;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '#${i + 1}  ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.login,
                            size: 14,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            DateFormat.jm().format(s.checkIn),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.green,
                            ),
                          ),
                          if (s.checkOut != null) ...[
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.logout,
                              size: 14,
                              color: Colors.red,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              DateFormat.jm().format(s.checkOut!),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.red,
                              ),
                            ),
                            if (s.hoursWorked != null)
                              Text(
                                '  (${s.hoursWorked!.toStringAsFixed(1)}h)',
                                style: theme.textTheme.bodySmall,
                              ),
                          ] else
                            Text(
                              '  — working',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.green.shade300,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    'Total: ${_today!.totalSessionHours.toStringAsFixed(1)} hours',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ] else if (hasCheckedIn && !allowMultiple) ...[
                  // Legacy single session display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.login, size: 16, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'In: ${DateFormat.jm().format(_today!.checkIn!)}',
                        style: const TextStyle(color: Colors.green),
                      ),
                      if (hasCheckedOut) ...[
                        const SizedBox(width: 16),
                        const Icon(Icons.logout, size: 16, color: Colors.red),
                        const SizedBox(width: 4),
                        Text(
                          'Out: ${DateFormat.jm().format(_today!.checkOut!)}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                  if (_today!.hoursWorked != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_today!.hoursWorked!.toStringAsFixed(1)} hours worked',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],

                if (_today?.checkInAddress != null &&
                    !(allowMultiple && sessions.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _today!.checkInAddress!,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                // Action Button
                if (canClockIn || canClockOut)
                  SizedBox(
                    width: 200,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _actionLoading
                          ? null
                          : (canClockOut ? _clockOut : _clockIn),
                      style: FilledButton.styleFrom(
                        backgroundColor: canClockOut
                            ? Colors.red
                            : Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _actionLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(canClockOut ? Icons.logout : Icons.login),
                      label: Text(
                        _actionLoading
                            ? 'Please wait...'
                            : canClockOut
                            ? 'CLOCK OUT'
                            : 'CLOCK IN',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                if (hasCheckedOut && !allowMultiple)
                  Text(
                    'See you tomorrow! 👋',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyHistory(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Month selector
        Row(
          children: [
            Text('Attendance History', style: theme.textTheme.titleMedium),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  if (_selectedMonth == 1) {
                    _selectedYear--;
                    _selectedMonth = 12;
                  } else {
                    _selectedMonth--;
                  }
                });
              },
            ),
            Text(
              DateFormat(
                'MMM yyyy',
              ).format(DateTime(_selectedYear, _selectedMonth)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                final now = DateTime.now();
                if (_selectedYear < now.year ||
                    (_selectedYear == now.year && _selectedMonth < now.month)) {
                  setState(() {
                    if (_selectedMonth == 12) {
                      _selectedYear++;
                      _selectedMonth = 1;
                    } else {
                      _selectedMonth++;
                    }
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Records list
        StreamBuilder<List<AttendanceModel>>(
          stream: StaffService.myAttendanceStream(
            year: _selectedYear,
            month: _selectedMonth,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final records = snapshot.data ?? [];
            if (records.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No records for this month'),
                ),
              );
            }

            // Summary
            final present = records
                .where((r) => r.status == AttendanceStatus.present)
                .length;
            final absent = records
                .where((r) => r.status == AttendanceStatus.absent)
                .length;
            final halfDay = records
                .where((r) => r.status == AttendanceStatus.halfDay)
                .length;

            return Column(
              children: [
                // Summary chips
                Row(
                  children: [
                    _chip('Present', present, Colors.green),
                    const SizedBox(width: 8),
                    _chip('Absent', absent, Colors.red),
                    const SizedBox(width: 8),
                    _chip('Half Day', halfDay, Colors.orange),
                  ],
                ),
                const SizedBox(height: 16),
                // List
                ...records.map(
                  (r) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _statusColor(
                          r.status,
                        ).withValues(alpha: 0.15),
                        child: Text(r.status.emoji),
                      ),
                      title: Text(DateFormat('EEE, d MMM').format(r.date)),
                      subtitle: r.checkIn != null
                          ? Text(
                              '${DateFormat.jm().format(r.checkIn!)} → '
                              '${r.checkOut != null ? DateFormat.jm().format(r.checkOut!) : '--'}'
                              '${r.hoursWorked != null ? '  (${r.hoursWorked!.toStringAsFixed(1)}h)' : ''}',
                              style: const TextStyle(fontSize: 12),
                            )
                          : null,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (r.checkInAddress != null)
                            Tooltip(
                              message: r.checkInAddress!,
                              child: const Icon(
                                Icons.location_on,
                                size: 16,
                                color: Colors.teal,
                              ),
                            ),
                          const SizedBox(width: 4),
                          if (r.isSelf)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Self',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.teal,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Text(
                            r.status.displayName,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _chip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 12,
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
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
