import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/staff/models/attendance_model.dart';
import 'package:retaillite/features/staff/models/payout_model.dart';
import 'package:retaillite/features/staff/models/staff_model.dart';
import 'package:retaillite/features/staff/providers/staff_provider.dart';
import 'package:retaillite/features/staff/services/staff_service.dart';
import 'package:retaillite/core/utils/permission_guard.dart';

class StaffDetailScreen extends ConsumerStatefulWidget {
  final String staffId;
  const StaffDetailScreen({super.key, required this.staffId});

  @override
  ConsumerState<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends ConsumerState<StaffDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

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
    final staffAsync = ref.watch(staffListProvider);

    // Use skipLoadingOnReload to avoid flash of loading when provider refreshes
    return staffAsync.when(
      skipLoadingOnReload: true,
      data: (staffList) {
        final staff = staffList
            .where((s) => s.id == widget.staffId)
            .firstOrNull;
        if (staff == null) {
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: const Text('Staff'),
            ),
            body: const Center(child: Text('Staff member not found')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Staff',
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(staff.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Staff',
                onPressed: () => guardAction(
                  context,
                  ref,
                  'staff',
                  PermAction.edit,
                  onAllowed: () => _showEditDialog(staff),
                ),
              ),
              if (staff.isActive)
                TextButton.icon(
                  icon: const Icon(Icons.block, color: Colors.red),
                  label: const Text(
                    'Deactivate',
                    style: TextStyle(color: Colors.red),
                  ),
                  onPressed: () => guardAction(
                    context,
                    ref,
                    'staff',
                    PermAction.delete,
                    onAllowed: () => _confirmDeactivate(staff),
                  ),
                ),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Profile'),
                Tab(text: 'Attendance'),
                Tab(text: 'Payouts'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _ProfileTab(staff: staff),
              _AttendanceTab(
                staffId: staff.id,
                year: _selectedYear,
                month: _selectedMonth,
                onMonthChanged: (y, m) => setState(() {
                  _selectedYear = y;
                  _selectedMonth = m;
                }),
              ),
              _PayoutTab(staff: staff),
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Loading...'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Error'),
        ),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  void _confirmDeactivate(StaffModel staff) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Staff?'),
        content: Text(
          'This will disable ${staff.name}\'s login. They won\'t be able to access the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await StaffService.deactivateStaff(staff.uid);
                ref.invalidate(staffListProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Staff deactivated')),
                  );
                  Navigator.pop(context);
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(StaffModel staff) {
    final nameCtrl = TextEditingController(text: staff.name);
    final phoneCtrl = TextEditingController(text: staff.phone);
    final salaryCtrl = TextEditingController(
      text: staff.salary > 0 ? staff.salary.toStringAsFixed(0) : '',
    );
    final roleCtrl = TextEditingController(text: staff.role.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Staff'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  prefixIcon: Icon(Icons.badge_outlined),
                  hintText: 'e.g. manager, cashier, helper',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: salaryCtrl,
                decoration: const InputDecoration(
                  labelText: 'Salary (monthly)',
                  prefixIcon: Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                final updated = staff.copyWith(
                  name: nameCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  role: StaffRole.fromString(roleCtrl.text.trim()),
                  salary: double.tryParse(salaryCtrl.text.trim()) ?? 0,
                );
                await StaffService.updateStaff(updated);
                ref.invalidate(staffListProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Staff updated'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

// ─── Profile Tab ───────────────────────────────────────────────

class _ProfileTab extends StatelessWidget {
  final StaffModel staff;
  const _ProfileTab({required this.staff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Avatar + Name
          CircleAvatar(
            radius: 48,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              staff.name.isNotEmpty ? staff.name[0].toUpperCase() : '?',
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(staff.name, style: theme.textTheme.headlineSmall),
          Text(
            staff.role.displayName,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),

          // Details card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _detailRow(Icons.email_outlined, 'Email', staff.email),
                  const Divider(),
                  _detailRow(
                    Icons.phone_outlined,
                    'Phone',
                    staff.phone.isEmpty ? 'Not set' : staff.phone,
                  ),
                  const Divider(),
                  _detailRow(
                    Icons.currency_rupee,
                    'Salary',
                    '${AppConstants.currencySymbol}${staff.salary.toStringAsFixed(0)}/month',
                  ),
                  const Divider(),
                  _detailRow(
                    Icons.calendar_today,
                    'Joined',
                    DateFormat('d MMM yyyy').format(staff.joiningDate),
                  ),
                  const Divider(),
                  _detailRow(
                    Icons.circle,
                    'Status',
                    staff.isActive ? 'Active' : 'Inactive',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value),
        ],
      ),
    );
  }
}

// ─── Attendance Tab ────────────────────────────────────────────

class _AttendanceTab extends ConsumerWidget {
  final String staffId;
  final int year;
  final int month;
  final void Function(int year, int month) onMonthChanged;

  const _AttendanceTab({
    required this.staffId,
    required this.year,
    required this.month,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final attendanceAsync = ref.watch(
      staffAttendanceProvider((staffId: staffId, year: year, month: month)),
    );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Month selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  if (month == 1) {
                    onMonthChanged(year - 1, 12);
                  } else {
                    onMonthChanged(year, month - 1);
                  }
                },
              ),
              Text(
                DateFormat('MMMM yyyy').format(DateTime(year, month)),
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  final now = DateTime.now();
                  if (year < now.year ||
                      (year == now.year && month < now.month)) {
                    if (month == 12) {
                      onMonthChanged(year + 1, 1);
                    } else {
                      onMonthChanged(year, month + 1);
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: attendanceAsync.when(
              data: (records) {
                final present = records
                    .where((r) => r.status == AttendanceStatus.present)
                    .length;
                final absent = records
                    .where((r) => r.status == AttendanceStatus.absent)
                    .length;
                final halfDay = records
                    .where((r) => r.status == AttendanceStatus.halfDay)
                    .length;
                final leave = records
                    .where((r) => r.status == AttendanceStatus.leave)
                    .length;

                return Column(
                  children: [
                    // Summary row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _summaryChip('Present', present, Colors.green),
                        _summaryChip('Absent', absent, Colors.red),
                        _summaryChip('Half Day', halfDay, Colors.orange),
                        _summaryChip('Leave', leave, Colors.blue),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Day-by-day list
                    Expanded(
                      child: records.isEmpty
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
                                  const Text(
                                    'No attendance records for this month',
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Mark attendance from the Daily Attendance screen',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: records.length,
                              itemBuilder: (_, i) {
                                final r = records[i];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: _statusColor(
                                      r.status,
                                    ).withValues(alpha: 0.15),
                                    child: Text(r.status.emoji),
                                  ),
                                  title: Text(
                                    DateFormat('EEE, d MMM').format(r.date),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (r.checkIn != null ||
                                          r.checkOut != null)
                                        Text(
                                          '${r.checkIn != null ? DateFormat.jm().format(r.checkIn!) : '--'}'
                                          ' → '
                                          '${r.checkOut != null ? DateFormat.jm().format(r.checkOut!) : '--'}'
                                          '${r.hoursWorked != null ? '  (${r.hoursWorked!.toStringAsFixed(1)}h)' : ''}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      if (r.note != null)
                                        Text(
                                          r.note!,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (r.isAuto)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          margin: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.withValues(
                                              alpha: 0.15,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Text(
                                            'Auto',
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.teal,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      Text(r.status.displayName),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error loading attendance: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
      label: Text(label),
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

// ─── Payout Tab ────────────────────────────────────────────────

class _PayoutTab extends ConsumerStatefulWidget {
  final StaffModel staff;
  const _PayoutTab({required this.staff});

  @override
  ConsumerState<_PayoutTab> createState() => _PayoutTabState();
}

class _PayoutTabState extends ConsumerState<_PayoutTab> {
  bool _calculating = false;
  PayoutModel? _preview;
  final _bonusController = TextEditingController();
  final _advanceController = TextEditingController();

  @override
  void dispose() {
    _bonusController.dispose();
    _advanceController.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    setState(() => _calculating = true);
    try {
      final now = DateTime.now();
      final payout = await StaffService.calculatePayout(
        staff: widget.staff,
        year: now.year,
        month: now.month,
        bonus: double.tryParse(_bonusController.text) ?? 0,
        advance: double.tryParse(_advanceController.text) ?? 0,
      );
      setState(() => _preview = payout);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _calculating = false);
    }
  }

  Future<void> _savePayout() async {
    if (_preview == null) return;
    try {
      await StaffService.savePayout(_preview!);
      ref.invalidate(staffPayoutsProvider(widget.staff.id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payout saved'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _preview = null);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final payoutsAsync = ref.watch(staffPayoutsProvider(widget.staff.id));
    const sym = AppConstants.currencySymbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Calculate section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Calculate Payout', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Text(
                    'For: ${DateFormat('MMMM yyyy').format(DateTime.now())}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _bonusController,
                          decoration: const InputDecoration(
                            labelText: 'Bonus ($sym)',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: _advanceController,
                          decoration: const InputDecoration(
                            labelText: 'Advance Paid ($sym)',
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 16),
                      FilledButton(
                        onPressed: _calculating ? null : _calculate,
                        child: _calculating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Calculate'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Preview
          if (_preview != null) ...[
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payout Preview', style: theme.textTheme.titleMedium),
                    const Divider(),
                    _payRow(
                      'Base Salary',
                      '$sym${_preview!.baseSalary.toStringAsFixed(0)}',
                    ),
                    _payRow(
                      'Days Worked',
                      '${_preview!.daysWorked} / ${_preview!.totalDays}',
                    ),
                    _payRow('Half Days', '${_preview!.halfDays}'),
                    _payRow('Absent Days', '${_preview!.absentDays}'),
                    _payRow('Leave Days', '${_preview!.leaveDays}'),
                    _payRow(
                      'Overtime',
                      '${_preview!.overtimeHours.toStringAsFixed(1)} hrs',
                    ),
                    _payRow(
                      'Overtime Pay',
                      '+$sym${_preview!.overtimePay.toStringAsFixed(0)}',
                    ),
                    _payRow(
                      'Deductions',
                      '-$sym${_preview!.deductions.toStringAsFixed(0)}',
                    ),
                    _payRow(
                      'Bonus',
                      '+$sym${_preview!.bonus.toStringAsFixed(0)}',
                    ),
                    _payRow(
                      'Advance',
                      '-$sym${_preview!.advance.toStringAsFixed(0)}',
                    ),
                    const Divider(),
                    _payRow(
                      'NET PAY',
                      '$sym${_preview!.netPay.toStringAsFixed(0)}',
                      bold: true,
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _savePayout,
                        icon: const Icon(Icons.save),
                        label: const Text('Save & Record Payout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          // History
          const SizedBox(height: 24),
          Text('Payout History', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          payoutsAsync.when(
            data: (payouts) {
              if (payouts.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No payouts recorded yet'),
                );
              }
              return Column(
                children: payouts.map((p) {
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: p.isPaid
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.orange.withValues(alpha: 0.15),
                        child: Icon(
                          p.isPaid ? Icons.check : Icons.pending,
                          color: p.isPaid ? Colors.green : Colors.orange,
                        ),
                      ),
                      title: Text(
                        DateFormat(
                          'MMMM yyyy',
                        ).format(DateFormat('yyyy-MM').parse(p.month)),
                      ),
                      subtitle: Text(
                        '${p.daysWorked}/${p.totalDays} days • ${p.isPaid ? "Paid" : "Pending"}',
                      ),
                      trailing: Text(
                        '$sym${p.netPay.toStringAsFixed(0)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: !p.isPaid ? () => _markPaid(p) : null,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
        ],
      ),
    );
  }

  Future<void> _markPaid(PayoutModel payout) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Paid?'),
        content: Text(
          'Confirm ${AppConstants.currencySymbol}${payout.netPay.toStringAsFixed(0)} paid to ${payout.staffName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mark Paid'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StaffService.markPayoutPaid(payout.staffId, payout.id);
      ref.invalidate(staffPayoutsProvider(widget.staff.id));
    }
  }

  Widget _payRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                : null,
          ),
          Text(
            value,
            style: bold
                ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                : null,
          ),
        ],
      ),
    );
  }
}
