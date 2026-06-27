import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/vendor/models/vendor_payment_model.dart';
import 'package:retaillite/features/vendor/services/vendor_service.dart';

class RecordPaymentDialog extends ConsumerStatefulWidget {
  final String vendorId;
  final double currentBalance;
  const RecordPaymentDialog({
    super.key,
    required this.vendorId,
    required this.currentBalance,
  });

  @override
  ConsumerState<RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _paymentMode = 'Cash';
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final payment = VendorPaymentModel(
        id: '',
        vendorId: widget.vendorId,
        amount: double.parse(_amountCtrl.text.trim()),
        paymentMode: _paymentMode,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        paidAt: DateTime.now(),
      );

      await VendorService.recordPayment(
        vendorId: widget.vendorId,
        payment: payment,
      );

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment recorded'),
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text('Record Payment', style: theme.textTheme.titleLarge),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Outstanding: \u20B9${widget.currentBalance.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: widget.currentBalance > 0
                        ? Colors.red
                        : Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _amountCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Amount (\u20B9) *',
                    prefixIcon: Icon(Icons.currency_rupee),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final amt = double.tryParse(v);
                    if (amt == null || amt <= 0) return 'Enter valid amount';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMode,
                  decoration: const InputDecoration(
                    labelText: 'Payment Mode',
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: ['Cash', 'UPI', 'Bank Transfer']
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMode = v);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note / Reference',
                    prefixIcon: Icon(Icons.note_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _loading ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _submit,
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_loading ? 'Saving...' : 'Pay'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
