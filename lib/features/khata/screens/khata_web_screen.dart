/// Khata Web Screen - Redesigned with master-detail layout
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/utils/formatters.dart';
import 'package:retaillite/features/khata/providers/khata_provider.dart';
import 'package:retaillite/features/khata/providers/khata_stats_provider.dart';
import 'package:retaillite/features/khata/widgets/add_customer_modal.dart';
import 'package:retaillite/features/khata/widgets/give_udhaar_modal.dart';
import 'package:retaillite/features/khata/widgets/record_payment_modal.dart';
import 'package:retaillite/core/utils/permission_guard.dart';
import 'package:retaillite/l10n/app_localizations.dart';
import 'package:retaillite/models/customer_model.dart';
import 'package:retaillite/models/transaction_model.dart';
import 'package:retaillite/shared/widgets/loading_states.dart';
import 'package:retaillite/core/services/payment_link_service.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:retaillite/shared/widgets/sync_badge.dart';

class KhataWebScreen extends ConsumerStatefulWidget {
  const KhataWebScreen({super.key});

  @override
  ConsumerState<KhataWebScreen> createState() => _KhataWebScreenState();
}

class _KhataWebScreenState extends ConsumerState<KhataWebScreen> {
  String _searchQuery = '';
  String? _selectedCustomerId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final customersAsync = ref.watch(sortedCustomersProvider);
    final statsAsync = ref.watch(khataStatsProvider);
    final sortOption = ref.watch(customerSortProvider);
    final customersSyncMap =
        ref.watch(customersSyncStatusProvider).valueOrNull ?? {};
    final isDesktop = ResponsiveHelper.isDesktop(context);
    final isTablet = ResponsiveHelper.isTablet(context);
    final screenWidth = MediaQuery.of(context).size.width;
    // At narrow tablet (< 768px), master-detail layout is too cramped.
    // Use mobile layout (list only) instead.
    final useMasterDetail = (isDesktop || isTablet) && screenWidth >= 768;
    final isMobile = !useMasterDetail;

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(l10n, isMobile),
            SizedBox(height: isMobile ? 10 : 12),

            // Summary Cards
            statsAsync.when(
              data: (stats) =>
                  _buildSummaryCards(stats, isDesktop, isTablet, isMobile),
              loading: () => const SizedBox(height: 80),
              error: (e, _) => const SizedBox(height: 80),
            ),
            SizedBox(height: isMobile ? 10 : 12),

            // Search and Sort Bar
            _buildSearchSortBar(sortOption, isMobile),
            SizedBox(height: isMobile ? 8 : 10),

            // Main Content - Master Detail or List only
            Expanded(
              child: customersAsync.when(
                data: (customers) {
                  final filtered = _filterCustomers(customers);

                  if (filtered.isEmpty) {
                    return _buildEmptyState(l10n);
                  }

                  // Mobile: List only
                  if (isMobile) {
                    return _buildCustomerList(filtered, null, customersSyncMap);
                  }

                  // Tablet/Desktop: Master-Detail
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer List
                      SizedBox(
                        width: isDesktop ? 420 : 340,
                        child: _buildCustomerList(
                          filtered,
                          _selectedCustomerId,
                          customersSyncMap,
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Detail Panel
                      Expanded(
                        child: _selectedCustomerId != null
                            ? _CustomerDetailPanel(
                                customerId: _selectedCustomerId!,
                                onClose: () =>
                                    setState(() => _selectedCustomerId = null),
                              )
                            : _buildSelectCustomerPrompt(),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: LoadingIndicator()),
                error: (e, _) =>
                    const Center(child: Text('Error loading data')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, bool isMobile) {
    if (isMobile) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _downloadReport(),
              icon: const Icon(Icons.download, size: 16),
              label: const Text(
                'Download Report',
                style: TextStyle(fontSize: 12),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _showAddCustomerModal,
              icon: const Icon(Icons.person_add, size: 16),
              label: const Text(
                'Add New Customer',
                style: TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: () => _downloadReport(),
          icon: const Icon(Icons.download, size: 16),
          label: const Text('Download Report', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _showAddCustomerModal,
          icon: const Icon(Icons.person_add, size: 16),
          label: const Text('Add New Customer', style: TextStyle(fontSize: 13)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  /// Generate and download khata report
  void _downloadReport() {
    final customersAsync = ref.read(sortedCustomersProvider);
    final statsAsync = ref.read(khataStatsProvider);

    customersAsync.whenData((customers) {
      statsAsync.whenData((stats) {
        final now = DateTime.now();
        final timestamp =
            '${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}';

        final buffer = StringBuffer();
        buffer.writeln('=' * 50);
        buffer.writeln('          KHATA REPORT - CUSTOMER LEDGER');
        buffer.writeln('=' * 50);
        buffer.writeln('Generated: $timestamp');
        buffer.writeln();
        buffer.writeln('─' * 50);
        buffer.writeln('SUMMARY');
        buffer.writeln('─' * 50);
        buffer.writeln(
          'Total Outstanding:   ${Formatters.currency(stats.totalOutstanding)}',
        );
        buffer.writeln('Customers with Due:  ${stats.customersWithDue}');
        buffer.writeln('Active Customers:    ${stats.activeCustomers}');
        buffer.writeln(
          'Collected Today:     ${Formatters.currency(stats.collectedToday)}',
        );
        buffer.writeln();

        // List customers with due balance
        final customersWithDue = customers.where((c) => c.balance > 0).toList();
        if (customersWithDue.isNotEmpty) {
          buffer.writeln('─' * 50);
          buffer.writeln('CUSTOMERS WITH PENDING BALANCE');
          buffer.writeln('─' * 50);
          buffer.writeln();

          for (int i = 0; i < customersWithDue.length; i++) {
            final c = customersWithDue[i];
            buffer.writeln('${i + 1}. ${c.name}');
            buffer.writeln('   Phone: ${c.phone}');
            buffer.writeln('   Balance Due: ${Formatters.currency(c.balance)}');
            if (c.lastTransactionAt != null) {
              buffer.writeln(
                '   Last Activity: ${DateFormat('dd/MM/yyyy').format(c.lastTransactionAt!)}',
              );
            }
            buffer.writeln();
          }
        }

        buffer.writeln('=' * 50);
        buffer.writeln('Generated by ${AppConstants.appName}');
        buffer.writeln('=' * 50);

        // Share the report
        Share.share(
          buffer.toString(),
          subject: 'Khata Report - ${DateFormat('dd MMM yyyy').format(now)}',
        );
      });
    });
  }

  Widget _buildSummaryCards(
    KhataStats stats,
    bool isDesktop,
    bool isTablet,
    bool isMobile,
  ) {
    final cards = [
      _SummaryCard(
        title: isMobile ? 'Outstanding' : 'Total Outstanding (Udhaar)',
        value: Formatters.currency(stats.totalOutstanding),
        icon: Icons.trending_up,
        iconColor: AppColors.error,
        subtitle: '${stats.customersWithDue} customers with due',
        compact: isMobile,
      ),
      _SummaryCard(
        title: isMobile ? 'Collected' : 'Collected Today',
        value: Formatters.currency(stats.collectedToday),
        icon: Icons.account_balance_wallet,
        iconColor: AppColors.success,
        subtitle: 'Payments received',
        compact: isMobile,
      ),
      _SummaryCard(
        title: isMobile ? 'Customers' : 'Active Customers',
        value: '${stats.activeCustomers}',
        icon: Icons.people,
        iconColor: AppColors.primary,
        subtitle: 'Total customer base',
        compact: isMobile,
      ),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: cards
              .map(
                (card) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(width: 140, child: card),
                ),
              )
              .toList(),
        ),
      );
    }

    return Row(
      children: [
        Expanded(child: cards[0]),
        const SizedBox(width: 10),
        Expanded(child: cards[1]),
        const SizedBox(width: 10),
        Expanded(child: cards[2]),
      ],
    );
  }

  Widget _buildSearchSortBar(CustomerSortOption sortOption, bool isMobile) {
    return Row(
      children: [
        Expanded(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isMobile ? double.infinity : 400,
            ),
            child: TextField(
              style: TextStyle(fontSize: isMobile ? 13 : 14),
              decoration: InputDecoration(
                hintText: isMobile
                    ? 'Search...'
                    : 'Search by Name or Mobile Number...',
                hintStyle: TextStyle(fontSize: isMobile ? 13 : 14),
                prefixIcon: Icon(
                  Icons.search,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: isMobile ? 18 : 24,
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                contentPadding: EdgeInsets.symmetric(
                  vertical: isMobile ? 8 : 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.primary),
                ),
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
          ),
        ),
        SizedBox(width: isMobile ? 8 : 16),
        Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: AppShadows.small,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CustomerSortOption>(
              value: sortOption,
              icon: Icon(Icons.keyboard_arrow_down, size: isMobile ? 18 : 24),
              style: TextStyle(
                fontSize: isMobile ? 12 : 14,
                color: Theme.of(context).colorScheme.onSurface,
              ),
              items: [
                DropdownMenuItem(
                  value: CustomerSortOption.highestDebt,
                  child: Text(isMobile ? 'Highest Debt' : 'Highest Debt First'),
                ),
                DropdownMenuItem(
                  value: CustomerSortOption.recentlyActive,
                  child: Text(isMobile ? 'Recent' : 'Recently Active'),
                ),
                DropdownMenuItem(
                  value: CustomerSortOption.alphabetical,
                  child: Text(isMobile ? 'A-Z' : 'Alphabetical A-Z'),
                ),
                DropdownMenuItem(
                  value: CustomerSortOption.oldestDue,
                  child: Text(isMobile ? 'Oldest Due' : 'Oldest Due First'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  ref.read(customerSortProvider.notifier).state = value;
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerList(
    List<CustomerModel> customers,
    String? selectedId,
    Map<String, bool> syncMap,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.medium,
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(8),
        itemCount: customers.length,
        separatorBuilder: (e, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final customer = customers[index];
          final isSelected = customer.id == selectedId;
          return _CustomerCard(
            customer: customer,
            isSelected: isSelected,
            hasPendingWrites: syncMap[customer.id] ?? false,
            onTap: () {
              if (ResponsiveHelper.isDesktop(context) ||
                  ResponsiveHelper.isTablet(context)) {
                setState(() => _selectedCustomerId = customer.id);
              } else {
                // Mobile: Navigate to detail screen
                context.push('/customer/${customer.id}');
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildSelectCustomerPrompt() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.medium,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Select a customer to view details',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: EmptyState(
        icon: Icons.people_outline,
        title: l10n.noCustomers,
        subtitle: l10n.addFirstCustomer,
        actionLabel: l10n.addCustomer,
        onAction: _showAddCustomerModal,
      ),
    );
  }

  List<CustomerModel> _filterCustomers(List<CustomerModel> customers) {
    if (_searchQuery.isEmpty) return customers;
    return customers.where((c) {
      return c.name.toLowerCase().contains(_searchQuery) ||
          c.phone.contains(_searchQuery);
    }).toList();
  }

  void _showAddCustomerModal({CustomerModel? customer}) {
    final action = customer != null ? PermAction.edit : PermAction.create;
    guardAction(
      context,
      ref,
      'customers',
      action,
      onAllowed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AddCustomerModal(customer: customer),
        );
      },
    );
  }
}

// ============ SUMMARY CARD ============
class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final String? subtitle;
  final bool compact;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.subtitle,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.small,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: compact ? 11 : 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: compact ? 16 : 20, color: iconColor),
              ),
            ],
          ),
          SizedBox(height: compact ? 8 : 8),
          Text(
            value,
            style: TextStyle(
              fontSize: compact ? 20 : 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          if (subtitle != null) ...[
            SizedBox(height: compact ? 2 : 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: compact ? 10 : 12,
                color: Theme.of(context).colorScheme.outline,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ============ CUSTOMER CARD ============
class _CustomerCard extends StatelessWidget {
  final CustomerModel customer;
  final bool isSelected;
  final bool hasPendingWrites;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.customer,
    required this.isSelected,
    this.hasPendingWrites = false,
    required this.onTap,
  });

  Color _getAvatarColor(String name) {
    final colors = [
      AppColors.primary, // green
      const Color(0xFF8B5CF6), // purple
      AppColors.warning, // amber
      AppColors.error, // red
      AppColors.info, // blue
      const Color(0xFFEC4899), // pink
    ];
    final index = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return colors[index];
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : '?';
  }

  String _getLastActivityText(DateTime? lastTransaction) {
    if (lastTransaction == null) return 'No activity';
    final now = DateTime.now();
    final diff = now.difference(lastTransaction);

    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) {
      return '${(diff.inDays / 7).floor()} week${diff.inDays >= 14 ? "s" : ""} ago';
    }
    return DateFormat('MMM dd').format(lastTransaction);
  }

  @override
  Widget build(BuildContext context) {
    final hasDue = customer.balance > 0;
    final avatarColor = _getAvatarColor(customer.name);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.success.withValues(alpha: 0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: AppColors.success, width: 2)
              : null,
          boxShadow: isSelected ? null : AppShadows.small,
        ),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 20,
              backgroundColor: avatarColor.withValues(alpha: 0.15),
              child: Text(
                _getInitials(customer.name),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: avatarColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Name & Phone
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasPendingWrites) ...[
                    const SizedBox(width: 4),
                    SyncBadge(hasPendingWrites: hasPendingWrites),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        Icons.phone,
                        size: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${AppConstants.countryCode} ${Formatters.phoneShort(customer.phone)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Balance & Status
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'DUE BALANCE',
                  style: TextStyle(
                    fontSize: 9,
                    color: Theme.of(context).colorScheme.outline,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDue ? Formatters.currency(customer.balance) : '₹0',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: hasDue ? AppColors.error : AppColors.success,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasDue
                      ? 'Last: ${_getLastActivityText(customer.lastTransactionAt)}'
                      : 'Settled',
                  style: TextStyle(
                    fontSize: 10,
                    color: hasDue
                        ? Theme.of(context).colorScheme.outline
                        : AppColors.success,
                  ),
                ),
                if (customer.isOverdue) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'OVERDUE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============ CUSTOMER DETAIL PANEL ============
class _CustomerDetailPanel extends ConsumerStatefulWidget {
  final String customerId;
  final VoidCallback onClose;

  const _CustomerDetailPanel({required this.customerId, required this.onClose});

  @override
  ConsumerState<_CustomerDetailPanel> createState() =>
      _CustomerDetailPanelState();
}

class _CustomerDetailPanelState extends ConsumerState<_CustomerDetailPanel> {
  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerProvider(widget.customerId));
    final transactionsAsync = ref.watch(
      customerTransactionsProvider(widget.customerId),
    );

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.medium,
      ),
      child: customerAsync.when(
        data: (customer) {
          if (customer == null) {
            return const Center(child: Text('Customer not found'));
          }
          return Column(
            children: [
              // Customer Header
              _buildCustomerHeader(context, customer),
              const Divider(height: 1),

              // Current Outstanding
              _buildOutstandingSection(customer),
              const Divider(height: 1),

              // Transaction History
              Expanded(
                child: _buildTransactionHistory(context, transactionsAsync),
              ),

              // Action Buttons
              _buildActionButtons(context, customer),
            ],
          );
        },
        loading: () => const Center(child: LoadingIndicator()),
        error: (e, _) => const Center(child: Text('Error loading customer')),
      ),
    );
  }

  Widget _buildCustomerHeader(BuildContext context, CustomerModel customer) {
    final avatarColor = _getAvatarColor(customer.name);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: avatarColor.withValues(alpha: 0.15),
            child: Text(
              _getInitials(customer.name),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: avatarColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${AppConstants.countryCode} ${Formatters.phoneShort(customer.phone)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // WhatsApp button
          IconButton(
            onPressed: () => _openWhatsApp(customer),
            icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
            tooltip: 'WhatsApp',
          ),
          // Call button
          IconButton(
            onPressed: () => _makeCall(customer.phone),
            icon: Icon(Icons.phone, color: AppColors.primary),
            tooltip: 'Call',
          ),
          // Edit button
          IconButton(
            onPressed: () => _showAddCustomerModal(customer: customer),
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Details',
          ),
          // Delete menu
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'delete') {
                guardAction(
                  context,
                  ref,
                  'customers',
                  PermAction.delete,
                  onAllowed: () =>
                      _showDeleteConfirmation(context, ref, customer),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete, color: AppColors.error),
                    SizedBox(width: 8),
                    Text(
                      'Delete Customer',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showAddCustomerModal({CustomerModel? customer}) {
    final action = customer != null ? PermAction.edit : PermAction.create;
    guardAction(
      context,
      ref,
      'customers',
      action,
      onAllowed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AddCustomerModal(customer: customer),
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    CustomerModel customer,
  ) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Customer?'),
        content: Text(
          'Are you sure you want to delete ${customer.name}? '
          'This action cannot be undone and will remove all their transaction history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext); // Close dialog

              try {
                // Delete
                await ref
                    .read(khataServiceProvider)
                    .deleteCustomer(customer.id);

                // Close panel
                widget.onClose();

                // Refresh list (derived providers cascade automatically)
                ref.invalidate(customersProvider);

                scaffoldMessenger.showSnackBar(
                  const SnackBar(
                    content: Text('Customer deleted successfully'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Failed to delete customer: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

  Widget _buildOutstandingSection(CustomerModel customer) {
    final hasDue = customer.balance > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Current Outstanding',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            hasDue ? Formatters.currency(customer.balance) : '₹0',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: hasDue ? AppColors.error : AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory(
    BuildContext context,
    AsyncValue<List<TransactionModel>> transactionsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            'HISTORY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.outline,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: transactionsAsync.when(
            data: (transactions) {
              if (transactions.isEmpty) {
                return Center(
                  child: Text(
                    'No transactions yet',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  return _TransactionItem(transaction: tx);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                const Center(child: Text('Error loading transactions')),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, CustomerModel customer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => guardAction(
                context,
                ref,
                'customers',
                PermAction.create,
                onAllowed: () => _showUdhaarModal(context, customer),
              ),
              icon: const Icon(Icons.remove_circle_outline, size: 16),
              label: const Text('Give Udhaar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => guardAction(
                context,
                ref,
                'customers',
                PermAction.create,
                onAllowed: () => _showPaymentModal(context, customer),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Receive Pay'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPaymentModal(BuildContext context, CustomerModel customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RecordPaymentModal(customer: customer),
    );
  }

  void _showUdhaarModal(BuildContext context, CustomerModel customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => GiveUdhaarModal(customer: customer),
    );
  }

  void _openWhatsApp(CustomerModel customer) async {
    final phone = '91${customer.phone}';
    final upiId = PaymentLinkService.upiId;
    final hasUpi = upiId.isNotEmpty && PaymentLinkService.isValidUpiId(upiId);
    final atIdx = upiId.indexOf('@');
    final maskedUpi = hasUpi && atIdx > 2
        ? '${upiId.substring(0, 2)}${'*' * (atIdx - 2)}${upiId.substring(atIdx)}'
        : upiId;
    final user = ref.read(currentUserProvider);
    final shopName = (user?.shopName.isNotEmpty == true)
        ? user!.shopName
        : 'Store';

    final amt = customer.balance.toStringAsFixed(0);
    String messageText;
    if (customer.balance > 0 && hasUpi) {
      final payUrl = PaymentLinkService.generatePaymentPageUrl(
        upiId: upiId,
        amount: customer.balance,
        payeeName: shopName,
        transactionNote: 'Payment to $shopName',
      );
      messageText =
          'Hi ${customer.name},\n\n'
          'You have a pending balance of *Rs $amt*.\n\n'
          'Pay via UPI:\n'
          '━━━━━━━━━━━━━━\n'
          'UPI ID: *$maskedUpi*\n'
          'Amount: *Rs $amt*\n'
          '━━━━━━━━━━━━━━\n\n'
          'Click here to pay:\n'
          '$payUrl\n\n'
          'Thank you\n'
          '— $shopName';
    } else if (customer.balance > 0) {
      messageText =
          'Hi ${customer.name},\n\n'
          'You have a pending balance of *Rs $amt*.\n'
          'Please pay at your earliest convenience.\n\n'
          'Thank you';
    } else {
      messageText = ''; // No due, just open chat
    }

    try {
      final url = messageText.isNotEmpty
          ? Uri.https('wa.me', '/$phone', {'text': messageText})
          : Uri.https('wa.me', '/$phone');
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error opening WhatsApp: $e');
    }
  }

  void _makeCall(String phone) async {
    final url = Uri.parse('tel:${AppConstants.countryCode}$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Color _getAvatarColor(String name) {
    final colors = [
      AppColors.primary,
      const Color(0xFF8B5CF6),
      AppColors.warning,
      AppColors.error,
      AppColors.info,
      const Color(0xFFEC4899),
    ];
    final index = name.isNotEmpty ? name.codeUnitAt(0) % colors.length : 0;
    return colors[index];
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty
        ? name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase()
        : '?';
  }
}

// ============ TRANSACTION ITEM ============
class _TransactionItem extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionItem({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isPurchase = transaction.type == TransactionType.purchase;
    final color = isPurchase ? AppColors.error : AppColors.success;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isPurchase ? Icons.add : Icons.remove,
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isPurchase ? 'Purchase (Credit)' : 'Payment Received',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                Text(
                  transaction.note ?? (isPurchase ? 'Credit given' : 'cash'),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Amount & Time
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${isPurchase ? "+" : "-"} ${Formatters.currency(transaction.amount)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: color,
                ),
              ),
              Text(
                DateFormat('MMM dd, hh:mm a').format(transaction.createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
