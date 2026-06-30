import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/models/staff_model.dart';
import 'package:retaillite/features/staff/providers/staff_provider.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/features/staff/widgets/add_staff_dialog.dart';
import 'package:retaillite/core/utils/permission_guard.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Wait for membership to resolve before checking role
    final membershipAsync = ref.watch(myMembershipProvider);
    // While loading, show spinner — don't redirect yet
    if (membershipAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final role = ref.watch(myRoleProvider);
    final isAdmin = role == StoreRole.owner || role == StoreRole.manager;

    // Non-admin staff: redirect to their own profile
    if (!isAdmin) {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/staff/$uid');
        });
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Column(
        children: [
          // Header + Tabs
          Container(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Staff Management', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 4),
                Text(
                  'Manage your team, attendance, and payouts',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 16),
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(icon: Icon(Icons.people), text: 'Team'),
                    Tab(icon: Icon(Icons.event_available), text: 'Attendance'),
                    Tab(icon: Icon(Icons.settings), text: 'Settings'),
                  ],
                ),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _TeamTab(),
                _AttendanceAdminTab(),
                _AttendanceSettingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Team Tab ──────────────────────────────────────────────────

class _TeamTab extends ConsumerStatefulWidget {
  const _TeamTab();

  @override
  ConsumerState<_TeamTab> createState() => _TeamTabState();
}

class _TeamTabState extends ConsumerState<_TeamTab> {
  bool _showInactive = false;

  void _openAddDialog() {
    guardAction(
      context,
      ref,
      'staff',
      PermAction.create,
      onAllowed: () {
        showDialog<bool>(
          context: context,
          builder: (_) => const AddStaffDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staffAsync = ref.watch(staffListProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              FilterChip(
                label: const Text('Show Inactive'),
                selected: _showInactive,
                onSelected: (v) => setState(() => _showInactive = v),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _openAddDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Staff'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: staffAsync.when(
              skipLoadingOnReload: true,
              data: (staffList) {
                final filtered = _showInactive
                    ? staffList
                    : staffList.where((s) => s.isActive).toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('No staff members yet'),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _openAddDialog,
                          icon: const Icon(Icons.person_add),
                          label: const Text('Add Staff'),
                        ),
                      ],
                    ),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final crossCount = constraints.maxWidth > 900
                        ? 3
                        : (constraints.maxWidth > 600 ? 2 : 1);
                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        childAspectRatio: 2.2,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final staff = filtered[index];
                        return _StaffCard(
                          staff: staff,
                          onTap: () => context.push('/staff/${staff.id}'),
                        );
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attendance Admin Tab (Date Range View) ────────────────────

class _AttendanceAdminTab extends ConsumerStatefulWidget {
  const _AttendanceAdminTab();

  @override
  ConsumerState<_AttendanceAdminTab> createState() =>
      _AttendanceAdminTabState();
}

class _AttendanceAdminTabState extends ConsumerState<_AttendanceAdminTab> {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 6));
  DateTime _toDate = DateTime.now();
  List<AttendanceRecord> _records = [];
  bool _loading = false;
  bool _showSummary = false; // toggle between records and staff summary

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _loading = true);
    try {
      final records = await StaffService.getAllAttendanceForRange(
        from: _fromDate,
        to: _toDate,
      );
      if (mounted) {
        setState(() {
          _records = records;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Calculate summary
    final present = _records
        .where((r) => r.attendance.status == AttendanceStatus.present)
        .length;
    final absent = _records
        .where((r) => r.attendance.status == AttendanceStatus.absent)
        .length;
    final halfDay = _records
        .where((r) => r.attendance.status == AttendanceStatus.halfDay)
        .length;
    final leave = _records
        .where((r) => r.attendance.status == AttendanceStatus.leave)
        .length;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Range Selector
          Row(
            children: [
              // From
              _DatePickerChip(
                label: 'From',
                date: _fromDate,
                onTap: () => _pickDate(isFrom: true),
              ),
              const SizedBox(width: 16),
              // To
              _DatePickerChip(
                label: 'To',
                date: _toDate,
                onTap: () => _pickDate(isFrom: false),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: _loading ? null : _loadRecords,
                icon: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search, size: 18),
                label: const Text('View'),
              ),
              const Spacer(),
              // Toggle view
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Records'),
                    icon: Icon(Icons.list, size: 16),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Staff Summary'),
                    icon: Icon(Icons.people, size: 16),
                  ),
                ],
                selected: {_showSummary},
                onSelectionChanged: (v) =>
                    setState(() => _showSummary = v.first),
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 12),
              // Summary chips
              if (_records.isNotEmpty) ...[
                _summaryBadge('P', present, Colors.green),
                const SizedBox(width: 6),
                _summaryBadge('A', absent, Colors.red),
                const SizedBox(width: 6),
                _summaryBadge('H', halfDay, Colors.orange),
                const SizedBox(width: 6),
                _summaryBadge('L', leave, Colors.blue),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    'Date',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    'Name',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Clock In',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Clock Out',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Hours',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Records or Staff Summary
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.event_busy,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        const Text('No attendance records found'),
                        const SizedBox(height: 8),
                        Text(
                          'Select a date range and tap View',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : _showSummary
                ? _buildStaffSummary(context)
                : ListView.builder(
                    itemCount: _records.length,
                    itemBuilder: (context, index) {
                      final r = _records[index];
                      return _buildRecordRow(context, r);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordRow(BuildContext context, AttendanceRecord record) {
    final theme = Theme.of(context);
    final att = record.attendance;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('d MMM').format(att.date),
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    record.staffName.isNotEmpty
                        ? record.staffName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.staffName,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              att.checkIn != null ? DateFormat.jm().format(att.checkIn!) : '--',
              style: TextStyle(
                fontSize: 12,
                color: att.checkIn != null
                    ? Colors.green.shade700
                    : Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              att.checkOut != null
                  ? DateFormat.jm().format(att.checkOut!)
                  : '--',
              style: TextStyle(
                fontSize: 12,
                color: att.checkOut != null ? Colors.red.shade700 : Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              att.hoursWorked != null
                  ? '${att.hoursWorked!.toStringAsFixed(1)}h'
                  : '--',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(att.status).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    att.status.displayName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _statusColor(att.status),
                    ),
                  ),
                ),
                if (att.isSelf || att.isAuto) ...[
                  const SizedBox(width: 4),
                  Icon(
                    att.isSelf ? Icons.location_on : Icons.auto_mode,
                    size: 14,
                    color: Colors.teal,
                  ),
                ],
              ],
            ),
          ),
          // Edit button
          IconButton(
            icon: const Icon(Icons.edit, size: 16),
            tooltip: 'Edit Record',
            onPressed: () => _showEditDialog(record),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Staff Summary view — grouped by staff with totals
  Widget _buildStaffSummary(BuildContext context) {
    final theme = Theme.of(context);
    // Group records by staff name
    final grouped = <String, List<AttendanceRecord>>{};
    for (final r in _records) {
      grouped.putIfAbsent(r.staffName, () => []).add(r);
    }

    final staffList = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return ListView.builder(
      itemCount: staffList.length,
      itemBuilder: (context, index) {
        final entry = staffList[index];
        final name = entry.key;
        final records = entry.value;
        final totalDays = records
            .where(
              (r) =>
                  r.attendance.status == AttendanceStatus.present ||
                  r.attendance.status == AttendanceStatus.halfDay,
            )
            .length;
        final totalHours = records.fold<double>(
          0,
          (sum, r) => sum + (r.attendance.hoursWorked ?? 0),
        );
        final hoursStr =
            '${totalHours.toInt()}:${((totalHours % 1) * 60).toInt().toString().padLeft(2, '0')}';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: TextStyle(color: theme.colorScheme.onPrimaryContainer),
              ),
            ),
            title: Text(name, style: theme.textTheme.titleSmall),
            subtitle: Row(
              children: [
                _miniChip('Days: $totalDays'),
                const SizedBox(width: 8),
                _miniChip('Hours: $hoursStr'),
                const SizedBox(width: 8),
                _miniChip('Records: ${records.length}'),
              ],
            ),
            children: records.map((r) {
              final att = r.attendance;
              return ListTile(
                dense: true,
                title: Text(DateFormat('dd/MM/yyyy').format(att.date)),
                subtitle: Row(
                  children: [
                    Text(
                      'IN: ${att.checkIn != null ? DateFormat.jm().format(att.checkIn!) : '--'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'OUT: ${att.checkOut != null ? DateFormat.jm().format(att.checkOut!) : '--'}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade700,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      'DUR: ${att.hoursWorked != null ? '${att.hoursWorked!.toStringAsFixed(1)}h' : '--'}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  onPressed: () => _showEditDialog(r),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _miniChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }

  /// Edit attendance record dialog
  void _showEditDialog(AttendanceRecord record) {
    final att = record.attendance;
    TimeOfDay? editIn = att.checkIn != null
        ? TimeOfDay.fromDateTime(att.checkIn!)
        : null;
    TimeOfDay? editOut = att.checkOut != null
        ? TimeOfDay.fromDateTime(att.checkOut!)
        : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('Edit ${DateFormat('yyyy-MM-dd').format(att.date)}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff: ${record.staffName}',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                // Clock In
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime:
                          editIn ?? const TimeOfDay(hour: 9, minute: 0),
                    );
                    if (picked != null) setDialogState(() => editIn = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.login, color: Colors.green, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'In:  ${editIn != null ? editIn!.format(ctx) : '--:--'}',
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.green),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Clock Out
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: ctx,
                      initialTime:
                          editOut ?? const TimeOfDay(hour: 18, minute: 0),
                    );
                    if (picked != null) setDialogState(() => editOut = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.5),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.logout, color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Out: ${editOut != null ? editOut!.format(ctx) : '--:--'}',
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.red),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Build updated times
                  DateTime? checkIn;
                  DateTime? checkOut;
                  if (editIn != null) {
                    checkIn = DateTime(
                      att.date.year,
                      att.date.month,
                      att.date.day,
                      editIn!.hour,
                      editIn!.minute,
                    );
                  }
                  if (editOut != null) {
                    checkOut = DateTime(
                      att.date.year,
                      att.date.month,
                      att.date.day,
                      editOut!.hour,
                      editOut!.minute,
                    );
                  }
                  await StaffService.markAttendance(
                    staffId: att.staffId,
                    date: att.date,
                    status: att.status,
                    checkIn: checkIn,
                    checkOut: checkOut,
                  );
                  unawaited(_loadRecords()); // refresh
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Record updated'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Color _statusColor(AttendanceStatus s) => switch (s) {
    AttendanceStatus.present => Colors.green,
    AttendanceStatus.absent => Colors.red,
    AttendanceStatus.halfDay => Colors.orange,
    AttendanceStatus.leave => Colors.blue,
  };
}

class _DatePickerChip extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$label: ', style: theme.textTheme.labelMedium),
            const Icon(Icons.calendar_today, size: 14),
            const SizedBox(width: 4),
            Text(
              DateFormat('d MMM yyyy').format(date),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Settings Tab ──────────────────────────────────────────────

class _AttendanceSettingsTab extends ConsumerWidget {
  const _AttendanceSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(attendanceSettingsProvider);
    final settings = settingsAsync.valueOrNull ?? {};
    final allowSelf = settings['allowSelfCheckIn'] as bool? ?? true;
    final requireGps = settings['requireGps'] as bool? ?? true;
    final allowMultiple = settings['allowMultipleCheckIns'] as bool? ?? false;
    final requireGeoFence = settings['requireGeoFence'] as bool? ?? false;
    final geoFenceRadius = (settings['geoFenceRadius'] as num?)?.toInt() ?? 100;
    final storeLat = (settings['storeLatitude'] as num?)?.toDouble();
    final storeLng = (settings['storeLongitude'] as num?)?.toDouble();
    final hasStoreLocation = storeLat != null && storeLng != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Attendance Settings', style: theme.textTheme.titleLarge),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Work Hours', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  const ListTile(
                    leading: Icon(Icons.access_time),
                    title: Text('Standard Shift'),
                    subtitle: Text('9:00 AM — 6:00 PM'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.timer),
                    title: Text('Late Threshold'),
                    subtitle: Text('15 minutes after shift start'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                  const Divider(),
                  const ListTile(
                    leading: Icon(Icons.calendar_month),
                    title: Text('Working Days'),
                    subtitle: Text('Monday — Saturday'),
                    trailing: Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Self Attendance', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Allow Staff Self Check-in'),
                    subtitle: const Text(
                      'Staff can clock in/out from their own device',
                    ),
                    value: allowSelf,
                    onChanged: (val) => StaffService.saveAttendanceSetting(
                      'allowSelfCheckIn',
                      val,
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Require GPS Location'),
                    subtitle: const Text(
                      'Record location when staff checks in',
                    ),
                    value: requireGps,
                    onChanged: allowSelf
                        ? (val) => StaffService.saveAttendanceSetting(
                            'requireGps',
                            val,
                          )
                        : null,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Allow Multiple Check-ins'),
                    subtitle: const Text(
                      'Staff can clock in/out more than once per day',
                    ),
                    value: allowMultiple,
                    onChanged: allowSelf
                        ? (val) => StaffService.saveAttendanceSetting(
                            'allowMultipleCheckIns',
                            val,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Geo-Fence', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Restrict check-in/out to store vicinity',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('Require Geo-Fence'),
                    subtitle: const Text(
                      'Staff must be near store to clock in/out',
                    ),
                    value: requireGeoFence,
                    onChanged: allowSelf
                        ? (val) => StaffService.saveAttendanceSetting(
                            'requireGeoFence',
                            val,
                          )
                        : null,
                  ),
                  if (requireGeoFence) ...[
                    const Divider(),
                    ListTile(
                      leading: Icon(
                        Icons.location_on,
                        color: hasStoreLocation ? Colors.green : Colors.orange,
                      ),
                      title: const Text('Store Location'),
                      subtitle: Text(
                        hasStoreLocation
                            ? '${storeLat.toStringAsFixed(5)}, ${storeLng.toStringAsFixed(5)}'
                            : 'Not set — tap to use current location',
                      ),
                      trailing: const Icon(Icons.my_location),
                      onTap: () async {
                        try {
                          final position = await Geolocator.getCurrentPosition(
                            locationSettings: const LocationSettings(
                              accuracy: LocationAccuracy.high,
                              timeLimit: Duration(seconds: 10),
                            ),
                          );
                          await StaffService.saveStoreLocation(
                            position.latitude,
                            position.longitude,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Store location saved successfully',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to get location: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.radar),
                      title: const Text('Allowed Radius'),
                      subtitle: Text('$geoFenceRadius meters'),
                      trailing: SizedBox(
                        width: 200,
                        child: Slider(
                          value: geoFenceRadius.toDouble(),
                          min: 50,
                          max: 500,
                          divisions: 9,
                          label: '${geoFenceRadius}m',
                          onChanged: (val) {
                            StaffService.saveAttendanceSettingValue(
                              'geoFenceRadius',
                              val.round(),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Staff Card ────────────────────────────────────────────────

class _StaffCard extends StatelessWidget {
  final StaffModel staff;
  final VoidCallback onTap;

  const _StaffCard({required this.staff, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            staff.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!staff.isActive)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Inactive',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.red,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      staff.role.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${AppConstants.currencySymbol}${staff.salary.toStringAsFixed(0)}/month',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Arrow
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
