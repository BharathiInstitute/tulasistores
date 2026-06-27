import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/vendor/providers/vendor_provider.dart';
import 'package:retaillite/features/vendor/services/vendor_service.dart';
import 'package:retaillite/features/vendor/widgets/add_vendor_dialog.dart';
import 'package:retaillite/features/vendor/widgets/record_payment_dialog.dart';
import 'package:retaillite/features/vendor/widgets/record_purchase_dialog.dart';
import 'package:retaillite/core/utils/permission_guard.dart';

class VendorDetailScreen extends ConsumerStatefulWidget {
  final String vendorId;
  const VendorDetailScreen({super.key, required this.vendorId});

  @override
  ConsumerState<VendorDetailScreen> createState() => _VendorDetailScreenState();
}

class _VendorDetailScreenState extends ConsumerState<VendorDetailScreen>
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
    final vendorsAsync = ref.watch(vendorListProvider);
    const sym = AppConstants.currencySymbol;

    return vendorsAsync.when(
      skipLoadingOnReload: true,
      data: (vendors) {
        final vendor = vendors
            .where((v) => v.id == widget.vendorId)
            .firstOrNull;
        if (vendor == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Vendor')),
            body: const Center(child: Text('Vendor not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(vendor.name),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Back to Vendors',
              onPressed: () => Navigator.of(context).pop(),
            ),
            actions: [
              // Edit
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: 'Edit Vendor',
                onPressed: () => guardAction(
                  context,
                  ref,
                  'vendors',
                  PermAction.edit,
                  onAllowed: () => showDialog(
                    context: context,
                    builder: (_) => AddVendorDialog(existing: vendor),
                  ),
                ),
              ),
              // Record purchase
              FilledButton.tonalIcon(
                onPressed: () => guardAction(
                  context,
                  ref,
                  'vendors',
                  PermAction.create,
                  onAllowed: () => showDialog(
                    context: context,
                    builder: (_) => RecordPurchaseDialog(vendorId: vendor.id),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart, size: 18),
                label: const Text('Purchase'),
              ),
              const SizedBox(width: 8),
              // Record payment
              FilledButton.icon(
                onPressed: () => guardAction(
                  context,
                  ref,
                  'vendors',
                  PermAction.create,
                  onAllowed: () => showDialog(
                    context: context,
                    builder: (_) => RecordPaymentDialog(
                      vendorId: vendor.id,
                      currentBalance: vendor.balance,
                    ),
                  ),
                ),
                icon: const Icon(Icons.payments, size: 18),
                label: const Text('Pay'),
              ),
              const SizedBox(width: 8),
            ],
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Purchases'),
                Tab(text: 'Payments'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              // ─── Overview Tab ───
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Balance card
                    Card(
                      color: vendor.balance > 0
                          ? Colors.red.withValues(alpha: 0.08)
                          : Colors.green.withValues(alpha: 0.08),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              vendor.balance > 0
                                  ? Icons.warning_amber_rounded
                                  : Icons.check_circle,
                              color: vendor.balance > 0
                                  ? Colors.red
                                  : Colors.green,
                              size: 32,
                            ),
                            const SizedBox(width: 16),
                            Column(
                              children: [
                                Text(
                                  'Outstanding Balance',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                Text(
                                  '$sym${vendor.balance.toStringAsFixed(0)}',
                                  style: theme.textTheme.headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: vendor.balance > 0
                                            ? Colors.red
                                            : Colors.green,
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Details card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _row(Icons.store_outlined, 'Name', vendor.name),
                            const Divider(),
                            _row(Icons.phone_outlined, 'Phone', vendor.phone),
                            const Divider(),
                            _row(
                              Icons.email_outlined,
                              'Email',
                              vendor.email ?? 'Not set',
                            ),
                            const Divider(),
                            _row(
                              Icons.location_on_outlined,
                              'Address',
                              vendor.address ?? 'Not set',
                            ),
                            const Divider(),
                            _row(
                              Icons.receipt_long_outlined,
                              'GST',
                              vendor.gstNumber ?? 'Not set',
                            ),
                            const Divider(),
                            _row(
                              Icons.category_outlined,
                              'Category',
                              vendor.category,
                            ),
                            const Divider(),
                            _row(
                              Icons.calendar_today,
                              'Added',
                              DateFormat('d MMM yyyy').format(vendor.createdAt),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Deactivate
                    if (vendor.isActive) ...[
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Deactivate Vendor?'),
                              content: Text(
                                'This will hide ${vendor.name} from the active list.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Deactivate'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await VendorService.updateVendor(
                              vendor.copyWith(isActive: false),
                            );
                            ref.invalidate(vendorListProvider);
                          }
                        },
                        icon: const Icon(Icons.block),
                        label: const Text('Deactivate Vendor'),
                      ),
                    ],
                  ],
                ),
              ),

              // ─── Purchases Tab ───
              _PurchasesTab(vendorId: widget.vendorId),

              // ─── Payments Tab ───
              _PaymentsTab(vendorId: widget.vendorId),
            ],
          ),
        );
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

// ─── Purchases Tab ─────────────────────────────────────────────

class _PurchasesTab extends ConsumerWidget {
  final String vendorId;
  const _PurchasesTab({required this.vendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final purchasesAsync = ref.watch(vendorPurchasesProvider(vendorId));
    const sym = AppConstants.currencySymbol;

    return purchasesAsync.when(
      data: (purchases) {
        if (purchases.isEmpty) {
          return const Center(child: Text('No purchases recorded'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: purchases.length,
          itemBuilder: (context, i) {
            final p = purchases[i];
            return Card(
              child: ExpansionTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: const Icon(Icons.shopping_cart, size: 18),
                ),
                title: Text(
                  '${p.invoiceNumber ?? "Purchase"} \u2022 $sym${p.totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  '${DateFormat('d MMM yyyy').format(p.purchaseDate)} \u2022 Due: $sym${p.dueAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        // Items table
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(3),
                            1: FlexColumnWidth(),
                            2: FlexColumnWidth(),
                            3: FlexColumnWidth(1.5),
                          },
                          children: [
                            TableRow(
                              children: [
                                Text('Item', style: theme.textTheme.labelSmall),
                                Text('Qty', style: theme.textTheme.labelSmall),
                                Text('Rate', style: theme.textTheme.labelSmall),
                                Text(
                                  'Total',
                                  style: theme.textTheme.labelSmall,
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                            ...p.items.map(
                              (item) => TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(item.name),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      item.quantity.toStringAsFixed(0),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '$sym${item.rate.toStringAsFixed(0)}',
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      '$sym${item.total.toStringAsFixed(0)}',
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Paid'),
                            Text('$sym${p.paidAmount.toStringAsFixed(0)}'),
                          ],
                        ),
                        if (p.note != null && p.note!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.note, size: 14),
                                const SizedBox(width: 4),
                                Text(p.note!, style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─── Payments Tab ──────────────────────────────────────────────

class _PaymentsTab extends ConsumerWidget {
  final String vendorId;
  const _PaymentsTab({required this.vendorId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final paymentsAsync = ref.watch(vendorPaymentsProvider(vendorId));
    const sym = AppConstants.currencySymbol;

    return paymentsAsync.when(
      data: (payments) {
        if (payments.isEmpty) {
          return const Center(child: Text('No payments recorded'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: payments.length,
          itemBuilder: (context, i) {
            final p = payments[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.withValues(alpha: 0.15),
                  child: const Icon(Icons.check, color: Colors.green),
                ),
                title: Text(
                  '$sym${p.amount.toStringAsFixed(0)}',
                  style: theme.textTheme.titleSmall,
                ),
                subtitle: Text(
                  '${DateFormat('d MMM yyyy, h:mm a').format(p.paidAt)} \u2022 ${p.paymentMode}',
                ),
                trailing: p.note != null && p.note!.isNotEmpty
                    ? Tooltip(
                        message: p.note!,
                        child: const Icon(Icons.note, size: 18),
                      )
                    : null,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}
