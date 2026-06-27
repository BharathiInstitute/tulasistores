import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/vendor/models/purchase_model.dart';
import 'package:retaillite/features/vendor/services/vendor_service.dart';

class RecordPurchaseDialog extends ConsumerStatefulWidget {
  final String vendorId;
  const RecordPurchaseDialog({super.key, required this.vendorId});

  @override
  ConsumerState<RecordPurchaseDialog> createState() =>
      _RecordPurchaseDialogState();
}

class _RecordPurchaseDialogState extends ConsumerState<RecordPurchaseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _invoiceCtrl = TextEditingController();
  final _paidCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  final List<_ItemEntry> _items = [_ItemEntry()];
  bool _loading = false;

  double get _totalAmount => _items.fold(0, (sum, item) => sum + item.total);

  double get _dueAmount =>
      _totalAmount - (double.tryParse(_paidCtrl.text) ?? 0);

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _paidCtrl.dispose();
    _noteCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(_ItemEntry()));
  }

  void _removeItem(int index) {
    if (_items.length > 1) {
      setState(() {
        _items[index].dispose();
        _items.removeAt(index);
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item with amount')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final purchase = PurchaseModel(
        id: '',
        vendorId: widget.vendorId,
        items: _items
            .where((i) => i.nameCtrl.text.trim().isNotEmpty)
            .map(
              (i) => PurchaseItem(
                name: i.nameCtrl.text.trim(),
                quantity: double.tryParse(i.qtyCtrl.text) ?? 1,
                rate: double.tryParse(i.rateCtrl.text) ?? 0,
                total: i.total,
              ),
            )
            .toList(),
        totalAmount: _totalAmount,
        paidAmount: double.tryParse(_paidCtrl.text) ?? 0,
        dueAmount: _dueAmount > 0 ? _dueAmount : 0,
        invoiceNumber: _invoiceCtrl.text.trim().isEmpty
            ? null
            : _invoiceCtrl.text.trim(),
        purchaseDate: DateTime.now(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        createdAt: DateTime.now(),
      );

      await VendorService.recordPurchase(
        vendorId: widget.vendorId,
        purchase: purchase,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase recorded'),
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shopping_cart,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Record Purchase',
                        style: theme.textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Invoice number
                  TextFormField(
                    controller: _invoiceCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Invoice Number',
                      prefixIcon: Icon(Icons.receipt_outlined),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Items header
                  Row(
                    children: [
                      Text('Items', style: theme.textTheme.titleSmall),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _addItem,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Item'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Item rows
                  ...List.generate(_items.length, (i) {
                    final item = _items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: item.nameCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Item name',
                                isDense: true,
                              ),
                              validator: (v) =>
                                  i == 0 && (v == null || v.trim().isEmpty)
                                  ? 'Required'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: item.qtyCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Qty',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: item.rateCtrl,
                              decoration: const InputDecoration(
                                hintText: 'Rate',
                                isDense: true,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '\u20B9${item.total.toStringAsFixed(0)}',
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          if (_items.length > 1)
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 20,
                                color: Colors.red,
                              ),
                              onPressed: () => _removeItem(i),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                    );
                  }),

                  const Divider(),

                  // Total
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: theme.textTheme.titleSmall),
                      Text(
                        '\u20B9${_totalAmount.toStringAsFixed(0)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Paid amount
                  TextFormField(
                    controller: _paidCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Paid Now (\u20B9)',
                      prefixIcon: Icon(Icons.payments_outlined),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),

                  // Due
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Due Amount', style: theme.textTheme.titleSmall),
                      Text(
                        '\u20B9${_dueAmount > 0 ? _dueAmount.toStringAsFixed(0) : '0'}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _dueAmount > 0 ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Note
                  TextFormField(
                    controller: _noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      prefixIcon: Icon(Icons.note_outlined),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _loading
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_loading ? 'Saving...' : 'Record Purchase'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ItemEntry {
  final nameCtrl = TextEditingController();
  final qtyCtrl = TextEditingController(text: '1');
  final rateCtrl = TextEditingController();

  double get total =>
      (double.tryParse(qtyCtrl.text) ?? 0) *
      (double.tryParse(rateCtrl.text) ?? 0);

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    rateCtrl.dispose();
  }
}
