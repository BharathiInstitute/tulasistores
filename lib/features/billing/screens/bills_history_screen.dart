/// Bills History Screen - Display all past bills with search, filters, and actions
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/services/data_export_service.dart';
import 'package:retaillite/core/services/demo_data_service.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/utils/formatters.dart';
import 'package:retaillite/core/utils/id_generator.dart';
import 'package:retaillite/core/services/print_helper.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/billing/services/bill_share_service.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';
import 'package:retaillite/models/bill_model.dart';
import 'package:retaillite/models/expense_model.dart';
import 'package:retaillite/features/billing/providers/billing_provider.dart';
import 'package:retaillite/features/reports/providers/reports_provider.dart';
import 'package:retaillite/shared/widgets/sync_badge.dart';

part 'bills_history_widgets.dart';

/// Bills History Screen
class BillsHistoryScreen extends ConsumerWidget {
  const BillsHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(billsFilterProvider);
    final billsAsync = ref.watch(filteredBillsProvider);
    final expensesAsync = ref.watch(filteredExpensesProvider);
    final billsSyncMap = ref.watch(billsSyncStatusProvider).valueOrNull ?? {};
    final expensesSyncMap =
        ref.watch(expensesSyncStatusProvider).valueOrNull ?? {};
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header - Desktop only (hide on mobile & tablet to prevent overflow)
          if (ResponsiveHelper.isDesktop(context))
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(color: Theme.of(context).cardColor),
              child: Row(
                children: [
                  const Spacer(),

                  // Date & Time
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: AppShadows.small,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMM dd, yyyy').format(now),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          DateFormat('hh:mm a').format(now),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Export CSV Button
                  OutlinedButton.icon(
                    onPressed: () => _showExportDialog(context),
                    icon: const Icon(Icons.file_download_outlined, size: 18),
                    label: const Text('Export CSV'),
                  ),
                  const SizedBox(width: 12),

                  // Print Report Button
                  OutlinedButton.icon(
                    onPressed: () {
                      // Print report (not yet implemented)
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Print Report'),
                  ),
                ],
              ),
            ),

          // Filters Section - Responsive
          _buildFiltersSection(context, ref, filter),

          // Records Table (Bills and/or Expenses based on filter)
          Expanded(
            child: _buildRecordsTable(
              context,
              ref,
              filter,
              billsAsync,
              expensesAsync,
              billsSyncMap,
              expensesSyncMap,
            ),
          ),
        ],
      ),
    );
  }

  /// Responsive filters section - adapts to mobile/desktop
  Widget _buildFiltersSection(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;

    if (isMobile) {
      return _buildMobileFilters(context, ref, filter);
    }

    // Desktop/Tablet: Horizontal layout with scrollable filters
    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 24),
      child: Row(
        children: [
          // Scrollable filters
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Search Bar
                  SizedBox(
                    width: screenWidth < 900 ? 200 : 300,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        ref.read(billsFilterProvider.notifier).state = filter
                            .copyWith(searchQuery: value, page: 1);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Date Range Filter
                  _buildDateFilter(context, ref, filter),
                  const SizedBox(width: 12),

                  // Payment Method Filter
                  _buildPaymentFilter(context, ref, filter),
                  const SizedBox(width: 12),

                  // Record Type Filter
                  _buildRecordTypeFilter(context, ref, filter),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // Action Buttons - always visible, pinned to right
          _buildActionButtons(context),
        ],
      ),
    );
  }

  /// Mobile-optimized filters with vertical layout
  Widget _buildMobileFilters(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar - full width
          TextField(
            decoration: InputDecoration(
              hintText: 'Search bills or expenses...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            onChanged: (value) {
              ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                searchQuery: value,
                page: 1,
              );
            },
          ),
          const SizedBox(height: 12),

          // Scrollable filter chips row
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Date filter chip
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    filter.dateRange != null
                        ? '${DateFormat('MMM dd').format(filter.dateRange!.start)} - ${DateFormat('MMM dd').format(filter.dateRange!.end)}'
                        : 'Date',
                  ),
                  onPressed: () async {
                    final isDark =
                        Theme.of(context).brightness == Brightness.dark;
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: filter.dateRange,
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: isDark
                                ? ColorScheme.dark(
                                    primary: AppColors.primary,
                                    onPrimary: Colors.white,
                                    surface: const Color(0xFF1E1E2E),
                                  )
                                : ColorScheme.light(primary: AppColors.primary),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (range != null) {
                      ref.read(billsFilterProvider.notifier).state = filter
                          .copyWith(dateRange: range, page: 1);
                    }
                  },
                ),
                const SizedBox(width: 8),

                // Payment filter chip
                ActionChip(
                  avatar: Text(filter.paymentMethod?.emoji ?? '💳'),
                  label: Text(filter.paymentMethod?.displayName ?? 'Payment'),
                  onPressed: () =>
                      _showPaymentFilterSheet(context, ref, filter),
                ),
                const SizedBox(width: 8),

                // Type filter chip
                ActionChip(
                  label: Text(
                    filter.recordType == RecordType.all
                        ? 'All'
                        : filter.recordType == RecordType.bills
                        ? 'Bills'
                        : 'Expenses',
                  ),
                  onPressed: () => _showTypeFilterSheet(context, ref, filter),
                ),
                const SizedBox(width: 8),

                // Add Expense chip
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Expense'),
                  backgroundColor: Colors.orange.withValues(alpha: 0.12),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => const AddExpensePopup(),
                    );
                  },
                ),
                const SizedBox(width: 8),

                // Export chip
                ActionChip(
                  avatar: const Icon(Icons.download, size: 18),
                  label: const Text('Export'),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                  onPressed: () => _showExportDialog(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Date range filter widget
  Widget _buildDateFilter(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    return InkWell(
      onTap: () async {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
          initialDateRange: filter.dateRange,
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: isDark
                    ? ColorScheme.dark(
                        primary: AppColors.primary,
                        onPrimary: Colors.white,
                        surface: const Color(0xFF1E1E2E),
                      )
                    : ColorScheme.light(primary: AppColors.primary),
              ),
              child: child!,
            );
          },
        );
        if (range != null) {
          ref.read(billsFilterProvider.notifier).state = filter.copyWith(
            dateRange: range,
            page: 1,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: AppShadows.small,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.date_range, size: 18),
            const SizedBox(width: 8),
            Text(
              filter.dateRange != null
                  ? '${DateFormat('MMM dd').format(filter.dateRange!.start)} - ${DateFormat('MMM dd').format(filter.dateRange!.end)}'
                  : 'Date Range',
              style: TextStyle(
                color: filter.dateRange != null
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (filter.dateRange != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  ref.read(billsFilterProvider.notifier).state = filter
                      .copyWith(clearDateRange: true, page: 1);
                },
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Payment method dropdown
  Widget _buildPaymentFilter(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.small,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PaymentMethod?>(
          value: filter.paymentMethod,
          hint: const Text('All Payments'),
          items: [
            const DropdownMenuItem(child: Text('All Payments')),
            ...PaymentMethod.values
                .where((m) => m != PaymentMethod.unknown)
                .map((method) {
                  return DropdownMenuItem(
                    value: method,
                    child: Row(
                      children: [
                        Text(method.emoji),
                        const SizedBox(width: 8),
                        Text(method.displayName),
                      ],
                    ),
                  );
                }),
          ],
          onChanged: (value) {
            ref.read(billsFilterProvider.notifier).state = filter.copyWith(
              paymentMethod: value,
              clearPaymentMethod: value == null,
              page: 1,
            );
          },
        ),
      ),
    );
  }

  /// Record type dropdown
  Widget _buildRecordTypeFilter(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: AppShadows.small,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RecordType>(
          value: filter.recordType,
          items: const [
            DropdownMenuItem(value: RecordType.all, child: Text('📋 All')),
            DropdownMenuItem(value: RecordType.bills, child: Text('🧾 Bills')),
            DropdownMenuItem(
              value: RecordType.expenses,
              child: Text('💸 Expenses'),
            ),
          ],
          onChanged: (value) {
            if (value != null) {
              ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                recordType: value,
                page: 1,
              );
            }
          },
        ),
      ),
    );
  }

  /// Action buttons (Add Expense, Export)
  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => const AddExpensePopup(),
            );
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add Expense'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: BorderSide(color: Colors.orange.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () => _showExportDialog(context),
          icon: const Icon(Icons.download, size: 18),
          label: const Text('Export'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  /// Show payment filter as bottom sheet on mobile
  void _showPaymentFilterSheet(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('All Payments'),
              onTap: () {
                ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                  clearPaymentMethod: true,
                  page: 1,
                );
                Navigator.pop(context);
              },
            ),
            ...PaymentMethod.values
                .where((m) => m != PaymentMethod.unknown)
                .map(
                  (method) => ListTile(
                    leading: Text(
                      method.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                    title: Text(method.displayName),
                    selected: filter.paymentMethod == method,
                    onTap: () {
                      ref.read(billsFilterProvider.notifier).state = filter
                          .copyWith(paymentMethod: method, page: 1);
                      Navigator.pop(context);
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  /// Show type filter as bottom sheet on mobile
  void _showTypeFilterSheet(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Text('📋', style: TextStyle(fontSize: 20)),
              title: const Text('All Records'),
              selected: filter.recordType == RecordType.all,
              onTap: () {
                ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                  recordType: RecordType.all,
                  page: 1,
                );
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text('🧾', style: TextStyle(fontSize: 20)),
              title: const Text('Bills Only'),
              selected: filter.recordType == RecordType.bills,
              onTap: () {
                ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                  recordType: RecordType.bills,
                  page: 1,
                );
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text('💸', style: TextStyle(fontSize: 20)),
              title: const Text('Expenses Only'),
              selected: filter.recordType == RecordType.expenses,
              onTap: () {
                ref.read(billsFilterProvider.notifier).state = filter.copyWith(
                  recordType: RecordType.expenses,
                  page: 1,
                );
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsTable(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
    AsyncValue<List<BillModel>> billsAsync,
    AsyncValue<List<ExpenseModel>> expensesAsync,
    Map<String, bool> billsSyncMap,
    Map<String, bool> expensesSyncMap,
  ) {
    // Handle loading state
    if (billsAsync.isLoading || expensesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Handle error state
    if (billsAsync.hasError) {
      return Center(child: Text('Error: ${billsAsync.error}'));
    }
    if (expensesAsync.hasError) {
      return Center(child: Text('Error: ${expensesAsync.error}'));
    }

    final bills = billsAsync.value ?? [];
    final expenses = expensesAsync.value ?? [];

    // Create combined record list based on filter
    List<dynamic> records = [];
    switch (filter.recordType) {
      case RecordType.bills:
        records = bills;
        break;
      case RecordType.expenses:
        records = expenses;
        break;
      case RecordType.all:
        // Combine and sort by date
        records = [...bills, ...expenses];
        records.sort((a, b) {
          final dateA = a is BillModel
              ? a.createdAt
              : (a as ExpenseModel).createdAt;
          final dateB = b is BillModel
              ? b.createdAt
              : (b as ExpenseModel).createdAt;
          return dateB.compareTo(dateA);
        });
        break;
    }

    if (records.isEmpty) {
      final message = switch (filter.recordType) {
        RecordType.bills => 'No bills found',
        RecordType.expenses => 'No expenses found',
        RecordType.all => 'No records found',
      };
      final icon = switch (filter.recordType) {
        RecordType.bills => Icons.receipt_long_outlined,
        RecordType.expenses => Icons.money_off_outlined,
        RecordType.all => Icons.inbox_outlined,
      };
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    // Pagination
    final totalPages = (records.length / filter.perPage).ceil();
    final startIndex = (filter.page - 1) * filter.perPage;
    final endIndex = (startIndex + filter.perPage).clamp(0, records.length);
    final paginatedRecords = records.sublist(startIndex, endIndex);

    final width = MediaQuery.of(context).size.width;
    final useCardView = width < 900;

    return Column(
      children: [
        // Table or Cards based on screen size
        Expanded(
          child: useCardView
              ? _buildMobileCardList(
                  context,
                  paginatedRecords,
                  billsSyncMap,
                  expensesSyncMap,
                )
              : _buildDesktopTable(
                  context,
                  paginatedRecords,
                  billsSyncMap,
                  expensesSyncMap,
                ),
        ),

        // Pagination Footer
        _buildPagination(
          context,
          ref,
          filter,
          startIndex,
          endIndex,
          records.length,
          totalPages,
        ),
      ],
    );
  }

  /// Mobile card list view
  Widget _buildMobileCardList(
    BuildContext context,
    List<dynamic> records,
    Map<String, bool> billsSyncMap,
    Map<String, bool> expensesSyncMap,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: records.length,
      itemBuilder: (context, index) {
        final record = records[index];
        if (record is BillModel) {
          return _MobileBillCard(
            bill: record,
            hasPendingWrites: billsSyncMap[record.id] ?? false,
          );
        } else if (record is ExpenseModel) {
          return _MobileExpenseCard(expense: record);
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Desktop table view
  Widget _buildDesktopTable(
    BuildContext context,
    List<dynamic> records,
    Map<String, bool> billsSyncMap,
    Map<String, bool> expensesSyncMap,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPad = isTablet ? 12.0 : 24.0;
    final hMargin = isTablet ? 8.0 : 24.0;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: hMargin),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.medium,
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: hPad,
              vertical: isTablet ? 10 : 16,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                if (!isTablet) _headerCell(context, 'TYPE'),
                _headerCell(context, 'REFERENCE', flex: 2),
                _headerCell(context, 'DATE & TIME', flex: 2),
                if (!isTablet) _headerCell(context, 'DETAILS', flex: 2),
                _headerCell(context, 'AMOUNT', flex: 2),
                _headerCell(context, 'PAYMENT', flex: 2),
                _headerCell(context, 'ACTION', flex: 2),
              ],
            ),
          ),
          // Table Rows
          Expanded(
            child: ListView.separated(
              itemCount: records.length,
              separatorBuilder: (_, _) => const SizedBox.shrink(),
              itemBuilder: (context, index) {
                final record = records[index];
                if (record is BillModel) {
                  return _BillRow(
                    bill: record,
                    compact: isTablet,
                    hasPendingWrites: billsSyncMap[record.id] ?? false,
                  );
                } else if (record is ExpenseModel) {
                  return _ExpenseRow(
                    expense: record,
                    compact: isTablet,
                    hasPendingWrites: expensesSyncMap[record.id] ?? false,
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pagination footer widget
  Widget _buildPagination(
    BuildContext context,
    WidgetRef ref,
    BillsFilter filter,
    int startIndex,
    int endIndex,
    int totalRecords,
    int totalPages,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);

    if (isMobile) {
      // Simplified pagination for mobile
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${startIndex + 1}-$endIndex of $totalRecords',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: filter.page > 1
                      ? () => ref.read(billsFilterProvider.notifier).state =
                            filter.copyWith(page: filter.page - 1)
                      : null,
                ),
                Text('${filter.page}/$totalPages'),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: filter.page < totalPages
                      ? () => ref.read(billsFilterProvider.notifier).state =
                            filter.copyWith(page: filter.page + 1)
                      : null,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Desktop pagination
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Text(
            'Showing ${startIndex + 1} to $endIndex of $totalRecords results',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: filter.page > 1
                ? () => ref.read(billsFilterProvider.notifier).state = filter
                      .copyWith(page: filter.page - 1)
                : null,
            child: const Text('Previous'),
          ),
          const SizedBox(width: 8),
          ..._buildPageNumbers(context, filter.page, totalPages, (pageNum) {
            ref.read(billsFilterProvider.notifier).state = filter.copyWith(
              page: pageNum,
            );
          }),
          const SizedBox(width: 8),
          TextButton(
            onPressed: filter.page < totalPages
                ? () => ref.read(billsFilterProvider.notifier).state = filter
                      .copyWith(page: filter.page + 1)
                : null,
            child: const Text('Next'),
          ),
        ],
      ),
    );
  }

  /// Build smart pagination: 1 ... 4 5 [6] 7 8 ... 20
  List<Widget> _buildPageNumbers(
    BuildContext context,
    int currentPage,
    int totalPages,
    void Function(int) onPageTap,
  ) {
    if (totalPages <= 0) return [];

    // Determine which page numbers to show
    final pages = <int>{};
    pages.add(1);
    pages.add(totalPages);
    for (int i = currentPage - 2; i <= currentPage + 2; i++) {
      if (i >= 1 && i <= totalPages) pages.add(i);
    }
    final sorted = pages.toList()..sort();

    final widgets = <Widget>[];
    for (int i = 0; i < sorted.length; i++) {
      // Add ellipsis if gap between consecutive shown pages
      if (i > 0 && sorted[i] - sorted[i - 1] > 1) {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(' \u2026 '),
          ),
        );
      }
      final pageNum = sorted[i];
      final isSelected = pageNum == currentPage;
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            onTap: isSelected ? null : () => onPageTap(pageNum),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                boxShadow: isSelected ? null : AppShadows.small,
              ),
              alignment: Alignment.center,
              child: Text(
                '$pageNum',
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _headerCell(BuildContext context, String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Show export dialog with date range presets and format selection
  void _showExportDialog(BuildContext context) {
    ExportRange selectedRange = ExportRange.last30Days;
    ExportFormat selectedFormat = ExportFormat.csv;
    bool isExporting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.download, size: 22),
              SizedBox(width: 8),
              Text('Export Bills'),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Date Range',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ExportRange.values.map((range) {
                    final isSelected = range == selectedRange;
                    return ChoiceChip(
                      label: Text(range.label),
                      selected: isSelected,
                      onSelected: (_) => setState(() => selectedRange = range),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: isSelected
                            ? AppColors.primary
                            : Theme.of(ctx).colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text(
                  'Format',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: ExportFormat.values.map((format) {
                    final isSelected = format == selectedFormat;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(format.label),
                        selected: isSelected,
                        onSelected: (_) =>
                            setState(() => selectedFormat = format),
                        selectedColor: AppColors.primary.withValues(
                          alpha: 0.15,
                        ),
                        labelStyle: TextStyle(
                          color: isSelected
                              ? AppColors.primary
                              : Theme.of(ctx).colorScheme.onSurface,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Text(
                  selectedFormat.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isExporting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isExporting
                  ? null
                  : () async {
                      setState(() => isExporting = true);
                      final service = DataExportService();
                      final ExportResult result;

                      if (selectedFormat == ExportFormat.csv) {
                        result = await service.exportBillsToCSV(
                          range: selectedRange,
                        );
                      } else {
                        result = await service.exportBillsToJSON(
                          range: selectedRange,
                        );
                      }

                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);

                      if (result.success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'âœ… Exported ${result.recordCount} bills to ${result.filePath}',
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('âŒ ${result.error}'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
              icon: isExporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 18),
              label: Text(isExporting ? 'Exporting...' : 'Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
