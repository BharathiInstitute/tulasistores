import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/features/vendor/models/vendor_model.dart';
import 'package:retaillite/features/vendor/providers/vendor_provider.dart';
import 'package:retaillite/features/vendor/widgets/add_vendor_dialog.dart';
import 'package:retaillite/core/utils/permission_guard.dart';

class VendorListScreen extends ConsumerStatefulWidget {
  const VendorListScreen({super.key});

  @override
  ConsumerState<VendorListScreen> createState() => _VendorListScreenState();
}

class _VendorListScreenState extends ConsumerState<VendorListScreen> {
  String _search = '';
  bool _showInactive = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendorsAsync = ref.watch(vendorListProvider);
    final totalDueAsync = ref.watch(totalVendorDueProvider);
    const sym = AppConstants.currencySymbol;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vendors', style: theme.textTheme.headlineMedium),
                      const SizedBox(height: 4),
                      totalDueAsync.when(
                        data: (total) => Text(
                          'Total Outstanding: $sym${total.toStringAsFixed(0)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: total > 0 ? Colors.red : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (e2, st2) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                FilterChip(
                  label: const Text('Inactive'),
                  selected: _showInactive,
                  onSelected: (v) => setState(() => _showInactive = v),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => guardAction(
                    context,
                    ref,
                    'vendors',
                    PermAction.create,
                    onAllowed: () => showDialog(
                      context: context,
                      builder: (_) => const AddVendorDialog(),
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Vendor'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Search
            SizedBox(
              width: 360,
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Search vendor...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _search = v.toLowerCase()),
              ),
            ),
            const SizedBox(height: 16),

            // Vendor list
            Expanded(
              child: vendorsAsync.when(
                data: (vendors) {
                  var filtered = _showInactive
                      ? vendors
                      : vendors.where((v) => v.isActive).toList();
                  if (_search.isNotEmpty) {
                    filtered = filtered
                        .where(
                          (v) =>
                              v.name.toLowerCase().contains(_search) ||
                              v.phone.contains(_search) ||
                              v.category.toLowerCase().contains(_search),
                        )
                        .toList();
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.storefront_outlined,
                            size: 64,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.3,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No vendors yet',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: () => showDialog(
                              context: context,
                              builder: (_) => const AddVendorDialog(),
                            ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Vendor'),
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
                          childAspectRatio: 2.4,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _VendorCard(
                          vendor: filtered[i],
                          onTap: () => context.go('/vendors/${filtered[i].id}'),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    Center(child: Text('Error loading vendors: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VendorCard extends StatelessWidget {
  final VendorModel vendor;
  final VoidCallback onTap;
  const _VendorCard({required this.vendor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const sym = AppConstants.currencySymbol;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  vendor.name.isNotEmpty ? vendor.name[0].toUpperCase() : '?',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            vendor.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!vendor.isActive)
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
                      vendor.category,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      vendor.balance > 0
                          ? 'Due: $sym${vendor.balance.toStringAsFixed(0)}'
                          : 'No dues',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: vendor.balance > 0 ? Colors.red : Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
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
