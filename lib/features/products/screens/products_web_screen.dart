import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/services/product_csv_service.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:retaillite/core/utils/formatters.dart';
import 'package:retaillite/features/products/providers/products_provider.dart';
import 'package:retaillite/features/products/widgets/add_product_modal.dart';
import 'package:retaillite/l10n/app_localizations.dart';
import 'package:retaillite/models/product_model.dart';
import 'package:retaillite/shared/widgets/loading_states.dart';
import 'package:retaillite/shared/widgets/sync_badge.dart';
import 'package:retaillite/core/config/plan_config.dart';
import 'package:retaillite/shared/widgets/feature_gate.dart';
import 'package:retaillite/shared/widgets/upgrade_prompt_modal.dart';

class ProductsWebScreen extends ConsumerStatefulWidget {
  const ProductsWebScreen({super.key});

  @override
  ConsumerState<ProductsWebScreen> createState() => _ProductsWebScreenState();
}

class _ProductsWebScreenState extends ConsumerState<ProductsWebScreen> {
  String _searchQuery = '';
  int _currentPage = 0;
  static const int _pageSize = 20;
  bool _isGridView = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _changePage(int newPage) {
    setState(() => _currentPage = newPage);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final productsAsync = ref.watch(productsProvider);
    final syncStatus = ref.watch(productsSyncStatusProvider).valueOrNull ?? {};
    final isMobile = ResponsiveHelper.isMobile(context);
    final isTablet = ResponsiveHelper.isTablet(context);

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by shell
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 12.0 : (isTablet ? 16.0 : 16.0)),
        child: Column(
          children: [
            // Top Bar: Search + Actions
            if (isMobile) ...[
              // Mobile: Stacked layout
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  prefixIcon: const Icon(Icons.search),
                  fillColor: Theme.of(context).cardColor,
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (value) => setState(() {
                  _searchQuery = value.toLowerCase();
                  _currentPage = 0;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // View toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _viewToggleButton(
                          icon: Icons.view_list,
                          selected: !_isGridView,
                          onTap: () => setState(() => _isGridView = false),
                        ),
                        _viewToggleButton(
                          icon: Icons.grid_view,
                          selected: _isGridView,
                          onTap: () => setState(() => _isGridView = true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleExportCsv(),
                      icon: const Icon(Icons.file_download_outlined, size: 18),
                      label: const Text('Export'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleImportCsv(),
                      icon: const Icon(Icons.file_upload_outlined, size: 18),
                      label: const Text('Import'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Theme.of(context).cardColor,
                        side: BorderSide(color: Theme.of(context).dividerColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddProductModal(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(l10n.addProduct),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Desktop: Original single row
              Row(
                children: [
                  // Search Input
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText:
                              'Search by product name, SKU, or category...',
                          prefixIcon: const Icon(Icons.search),
                          fillColor: Theme.of(context).cardColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onChanged: (value) => setState(() {
                          _searchQuery = value.toLowerCase();
                          _currentPage = 0;
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // View toggle
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _viewToggleButton(
                          icon: Icons.view_list,
                          selected: !_isGridView,
                          onTap: () => setState(() => _isGridView = false),
                        ),
                        _viewToggleButton(
                          icon: Icons.grid_view,
                          selected: _isGridView,
                          onTap: () => setState(() => _isGridView = true),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),

                  // Actions
                  OutlinedButton.icon(
                    onPressed: () => _handleExportCsv(),
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Export CSV'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Theme.of(context).cardColor,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () => _handleImportCsv(),
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Import CSV'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Theme.of(context).cardColor,
                      side: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () => _showAddProductModal(),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addProduct),
                  ),
                ],
              ),
            ],
            SizedBox(height: isMobile ? 12 : 16),

            // Main Content: Data Table Card
            Expanded(
              child: Card(
                child: productsAsync.when(
                  data: (products) {
                    final filtered = _filterProducts(products);
                    final totalItems = filtered.length;
                    final totalPages = (totalItems / _pageSize).ceil();
                    if (_currentPage >= totalPages && totalPages > 0) {
                      _currentPage = totalPages - 1;
                    }
                    final startIndex = _currentPage * _pageSize;
                    final endIndex = (startIndex + _pageSize).clamp(
                      0,
                      totalItems,
                    );
                    final pageItems = filtered.sublist(startIndex, endIndex);
                    if (filtered.isEmpty) {
                      return EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: l10n.noProducts,
                        subtitle: _searchQuery.isEmpty
                            ? l10n.addFirstProduct
                            : l10n.noData,
                        actionLabel: _searchQuery.isEmpty
                            ? l10n.addProduct
                            : null,
                        onAction: _searchQuery.isEmpty
                            ? () => _showAddProductModal()
                            : null,
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isMobile) ...[
                          // Mobile: Grid or Card list
                          if (_isGridView)
                            Expanded(
                              child: _buildProductGrid(
                                pageItems,
                                syncStatus,
                                controller: _scrollController,
                              ),
                            )
                          else
                            Expanded(
                              child: ListView.separated(
                                controller: _scrollController,
                                itemCount: pageItems.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final product = pageItems[index];
                                  return _MobileProductCard(
                                    product: product,
                                    hasPendingWrites:
                                        syncStatus[product.id] ?? false,
                                    onEdit: () =>
                                        _showAddProductModal(product: product),
                                  );
                                },
                              ),
                            ),
                          // Mobile pagination footer
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Showing ${startIndex + 1} to $endIndex of $totalItems products',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                                Row(
                                  children: [
                                    OutlinedButton(
                                      onPressed: _currentPage > 0
                                          ? () => _changePage(_currentPage - 1)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        minimumSize: Size.zero,
                                      ),
                                      child: const Text(
                                        'Prev',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: _currentPage < totalPages - 1
                                          ? () => _changePage(_currentPage + 1)
                                          : null,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        minimumSize: Size.zero,
                                      ),
                                      child: const Text(
                                        'Next',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Desktop: Grid or Table
                          if (_isGridView) ...[
                            Expanded(
                              child: _buildProductGrid(
                                pageItems,
                                syncStatus,
                                controller: _scrollController,
                              ),
                            ),
                          ] else ...[
                            // Desktop: DataTable
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _scrollController,
                                padding: const EdgeInsets.all(0),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(
                                      Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainerHighest,
                                    ),
                                    headingRowHeight: 44,
                                    dataRowMinHeight: 48,
                                    dataRowMaxHeight: 56,
                                    horizontalMargin: 16,
                                    columnSpacing: 16,
                                    columns: [
                                      DataColumn(
                                        label: Text(
                                          'Product Name',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'SKU',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'Category',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'Stock Level',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'Price',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                      DataColumn(
                                        label: Text(
                                          'Actions',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        numeric: true,
                                      ),
                                    ],
                                    rows: pageItems.map((product) {
                                      return DataRow(
                                        cells: [
                                          DataCell(
                                            Row(
                                              children: [
                                                Container(
                                                  width: 32,
                                                  height: 32,
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(
                                                      context,
                                                    ).scaffoldBackgroundColor,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    image:
                                                        product.imageUrl != null
                                                        ? DecorationImage(
                                                            image: NetworkImage(
                                                              product.imageUrl!,
                                                            ),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : null,
                                                  ),
                                                  child:
                                                      product.imageUrl == null
                                                      ? Icon(
                                                          Icons
                                                              .image_not_supported_outlined,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.outline,
                                                          size: 16,
                                                        )
                                                      : null,
                                                ),
                                                const SizedBox(width: 10),
                                                Flexible(
                                                  child: Text(
                                                    product.name,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                SyncBadge(
                                                  hasPendingWrites:
                                                      syncStatus[product.id] ??
                                                      false,
                                                ),
                                              ],
                                            ),
                                            onTap: () => _showAddProductModal(
                                              product: product,
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              product.barcode ?? 'N/A',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontFamily: 'monospace',
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              product.category ?? '—',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: product.category != null
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant
                                                    : Theme.of(
                                                        context,
                                                      ).colorScheme.outline,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          DataCell(
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: product.isOutOfStock
                                                    ? AppColors.error
                                                          .withValues(
                                                            alpha: 0.1,
                                                          )
                                                    : (product.isLowStock
                                                          ? AppColors.warning
                                                                .withValues(
                                                                  alpha: 0.1,
                                                                )
                                                          : AppColors.success
                                                                .withValues(
                                                                  alpha: 0.1,
                                                                )),
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Text(
                                                product.isOutOfStock
                                                    ? 'Out of stock'
                                                    : (product.isLowStock
                                                          ? '${product.stock} (Low)'
                                                          : '${product.stock} in stock'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color: product.isOutOfStock
                                                      ? AppColors.error
                                                      : (product.isLowStock
                                                            ? AppColors.warning
                                                            : AppColors
                                                                  .success),
                                                ),
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              product.price.asCurrency,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            IconButton(
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              onPressed: () =>
                                                  _showAddProductModal(
                                                    product: product,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          // Desktop pagination footer
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 10,
                              horizontal: 16,
                            ),
                            decoration: const BoxDecoration(),
                            child: Row(
                              children: [
                                Text(
                                  'Showing ${startIndex + 1} to $endIndex of $totalItems results',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    fontSize: 14,
                                  ),
                                ),
                                const Spacer(),
                                OutlinedButton(
                                  onPressed: _currentPage > 0
                                      ? () => _changePage(_currentPage - 1)
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Previous'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  onPressed: _currentPage < totalPages - 1
                                      ? () => _changePage(_currentPage + 1)
                                      : null,
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('Next'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => const Center(child: LoadingIndicator()),
                  error: (error, _) => ErrorState(
                    message: l10n.somethingWentWrong,
                    onRetry: () => ref.invalidate(productsProvider),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewToggleButton({
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 20,
          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildProductGrid(
    List<ProductModel> products,
    Map<String, bool> syncStatus, {
    ScrollController? controller,
  }) {
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = width < 600
        ? 2
        : width < 1024
        ? 3
        : width < 1440
        ? 4
        : 5;

    return GridView.builder(
      controller: controller,
      padding: const EdgeInsets.all(12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final product = products[index];
        return _ProductGridTile(
          product: product,
          hasPendingWrites: syncStatus[product.id] ?? false,
          onTap: () => _showAddProductModal(product: product),
        );
      },
    );
  }

  // Logic copied from products_screen.dart
  List<ProductModel> _filterProducts(List<ProductModel> products) {
    var result = products;
    // Simple filter support (only search implemented in UI header for simplicity)
    if (_searchQuery.isNotEmpty) {
      result = result.where((p) {
        return p.name.toLowerCase().contains(_searchQuery) ||
            (p.barcode?.toLowerCase().contains(_searchQuery) ?? false) ||
            (p.category?.toLowerCase().contains(_searchQuery) ?? false);
      }).toList();
    }
    return result;
  }

  void _showAddProductModal({ProductModel? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddProductModal(product: product),
    );
  }

  Future<void> _handleExportCsv() async {
    if (!FeatureAccess.check(context, ref, PlanFeature.exportData)) return;
    final productsAsync = ref.read(productsProvider);
    final products = productsAsync.valueOrNull;
    if (products == null || products.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No products to export'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }
    try {
      final path = await ProductCsvService.exportToDownloads(products);
      if (mounted && path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Exported ${products.length} products to CSV'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleImportCsv() async {
    // Step 1: Pick and parse CSV file
    final CsvImportResult result;
    try {
      result = await ProductCsvService.importProducts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // User cancelled file picker
    if (result.imported == 0 && result.errors.isEmpty) return;

    // CSV had only errors (missing columns, empty file, etc.)
    if (result.imported == 0 && result.hasErrors) {
      if (mounted) _showImportResultDialog(0, 0, result.skipped, result.errors);
      return;
    }

    // Check product limit before importing
    try {
      final limits = await UserMetricsService.getUserLimits();
      final remaining = limits.productsLimit - limits.productsCount;
      if (result.products.length > remaining) {
        if (mounted) {
          await UpgradePromptModal.show(
            context,
            trigger: UpgradeTrigger.productLimit,
          );
        }
        return;
      }
    } catch (_) {
      // If limits check fails, proceed anyway
    }

    if (!mounted) return;

    // Step 2: Show progress dialog and start batch upload
    final progressNotifier = ValueNotifier<int>(0);
    final total = result.products.length;
    int lastKnownAdded = 0;

    // Start upload immediately (runs in background while dialog is open)
    final service = ref.read(productsServiceProvider);
    final uploadFuture = service.addProductsBatch(
      result.products,
      onProgress: (added, t) {
        lastKnownAdded = added;
        progressNotifier.value = added;
      },
    );

    // Show progress dialog
    if (mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          // Wait for upload to finish, then close dialog
          uploadFuture
              .then((_) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              })
              .catchError((Object _) {
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              });

          return ValueListenableBuilder<int>(
            valueListenable: progressNotifier,
            builder: (context, addedSoFar, _) {
              final progress = total > 0 ? addedSoFar / total : 0.0;
              return AlertDialog(
                title: const Row(
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    SizedBox(width: 12),
                    Text('Importing Products...'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text(
                      '$addedSoFar / $total products uploaded',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (result.skipped > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${result.skipped} rows skipped',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      );
    }

    // Dialog closed — show result
    progressNotifier.dispose();

    try {
      final added = await uploadFuture;
      if (mounted) {
        _showImportResultDialog(added, total, result.skipped, result.errors);
      }
    } catch (e) {
      if (mounted) {
        _showImportResultDialog(lastKnownAdded, total, result.skipped, [
          ...result.errors,
          'Upload failed: $e',
        ]);
      }
    }
  }

  void _showImportResultDialog(
    int added,
    int total,
    int skipped,
    List<String> errors,
  ) {
    final hasErrors = errors.isNotEmpty;
    final allFailed = added == 0 && hasErrors;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          allFailed
              ? Icons.error_outline
              : hasErrors
              ? Icons.warning_amber_rounded
              : Icons.check_circle_outline,
          color: allFailed
              ? AppColors.error
              : hasErrors
              ? AppColors.warning
              : AppColors.success,
          size: 48,
        ),
        title: Text(
          allFailed
              ? 'Import Failed'
              : hasErrors
              ? 'Import Completed with Warnings'
              : 'Import Successful',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (added > 0)
              _resultRow(
                Icons.check,
                '$added products added',
                AppColors.success,
              ),
            if (skipped > 0)
              _resultRow(
                Icons.skip_next,
                '$skipped rows skipped',
                AppColors.warning,
              ),
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Errors:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final err in errors)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '• $err',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.error),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(color: color)),
        ],
      ),
    );
  }
}

/// Mobile-friendly product card for list display
class _MobileProductCard extends StatelessWidget {
  final ProductModel product;
  final bool hasPendingWrites;
  final VoidCallback onEdit;

  const _MobileProductCard({
    required this.product,
    this.hasPendingWrites = false,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppShadows.small,
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // Product Image
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(8),
                image: product.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(product.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: product.imageUrl == null
                  ? Icon(
                      Icons.image_not_supported_outlined,
                      color: Theme.of(context).colorScheme.outline,
                      size: 20,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // Product Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      SyncBadge(hasPendingWrites: hasPendingWrites),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // Stock Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: product.isOutOfStock
                              ? AppColors.error.withValues(alpha: 0.1)
                              : (product.isLowStock
                                    ? AppColors.warning.withValues(alpha: 0.1)
                                    : AppColors.success.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          product.isOutOfStock
                              ? 'Out'
                              : (product.isLowStock
                                    ? '${product.stock} low'
                                    : '${product.stock} in stock'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: product.isOutOfStock
                                ? AppColors.error
                                : (product.isLowStock
                                      ? AppColors.warning
                                      : AppColors.success),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Price and Edit
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  product.price.asCurrency,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid tile for product grid view
class _ProductGridTile extends StatelessWidget {
  final ProductModel product;
  final bool hasPendingWrites;
  final VoidCallback onTap;

  const _ProductGridTile({
    required this.product,
    this.hasPendingWrites = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: AppShadows.small,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              Expanded(
                child: Center(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                      image: product.imageUrl != null
                          ? DecorationImage(
                              image: NetworkImage(product.imageUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: product.imageUrl == null
                        ? Icon(
                            Icons.inventory_2_outlined,
                            size: 36,
                            color: cs.outline,
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Product name + sync
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SyncBadge(hasPendingWrites: hasPendingWrites),
                ],
              ),
              const SizedBox(height: 4),
              // Price
              Text(
                product.price.asCurrency,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 4),
              // Stock badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: product.isOutOfStock
                      ? AppColors.error.withValues(alpha: 0.1)
                      : (product.isLowStock
                            ? AppColors.warning.withValues(alpha: 0.1)
                            : AppColors.success.withValues(alpha: 0.1)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  product.isOutOfStock
                      ? 'Out of stock'
                      : (product.isLowStock
                            ? '${product.stock} low'
                            : '${product.stock} in stock'),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: product.isOutOfStock
                        ? AppColors.error
                        : (product.isLowStock
                              ? AppColors.warning
                              : AppColors.success),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
