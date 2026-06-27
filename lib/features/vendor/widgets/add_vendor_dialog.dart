import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/vendor/models/vendor_model.dart';
import 'package:retaillite/features/vendor/providers/vendor_provider.dart';
import 'package:retaillite/features/vendor/services/vendor_service.dart';

class AddVendorDialog extends ConsumerStatefulWidget {
  final VendorModel? existing; // null = add, non-null = edit
  const AddVendorDialog({super.key, this.existing});

  @override
  ConsumerState<AddVendorDialog> createState() => _AddVendorDialogState();
}

class _AddVendorDialogState extends ConsumerState<AddVendorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _gstCtrl;
  late final TextEditingController _categoryCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    _nameCtrl = TextEditingController(text: v?.name ?? '');
    _phoneCtrl = TextEditingController(text: v?.phone ?? '');
    _emailCtrl = TextEditingController(text: v?.email ?? '');
    _addressCtrl = TextEditingController(text: v?.address ?? '');
    _gstCtrl = TextEditingController(text: v?.gstNumber ?? '');
    _categoryCtrl = TextEditingController(text: v?.category ?? 'General');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _gstCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      if (widget.existing != null) {
        await VendorService.updateVendor(
          widget.existing!.copyWith(
            name: _nameCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            email: _emailCtrl.text.trim().isEmpty
                ? null
                : _emailCtrl.text.trim(),
            address: _addressCtrl.text.trim().isEmpty
                ? null
                : _addressCtrl.text.trim(),
            gstNumber: _gstCtrl.text.trim().isEmpty
                ? null
                : _gstCtrl.text.trim(),
            category: _categoryCtrl.text.trim(),
          ),
        );
      } else {
        final vendor = VendorModel(
          id: '',
          name: _nameCtrl.text.trim(),
          phone: _phoneCtrl.text.trim(),
          email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
          address: _addressCtrl.text.trim().isEmpty
              ? null
              : _addressCtrl.text.trim(),
          gstNumber: _gstCtrl.text.trim().isEmpty ? null : _gstCtrl.text.trim(),
          category: _categoryCtrl.text.trim().isEmpty
              ? 'General'
              : _categoryCtrl.text.trim(),
          createdAt: DateTime.now(),
        );
        await VendorService.addVendor(vendor);
      }
      ref.invalidate(vendorListProvider);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing != null
                  ? 'Vendor updated'
                  : '${_nameCtrl.text.trim()} added',
            ),
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
    final isEdit = widget.existing != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
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
                        isEdit ? Icons.edit : Icons.store,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isEdit ? 'Edit Vendor' : 'Add Vendor',
                        style: theme.textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Vendor Name *',
                      prefixIcon: Icon(Icons.store_outlined),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Phone *',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _gstCtrl,
                    decoration: const InputDecoration(
                      labelText: 'GST Number',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _categoryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                      hintText: 'e.g. Dairy, FMCG, Stationery',
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 24),
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
                            : Icon(isEdit ? Icons.save : Icons.add),
                        label: Text(
                          _loading
                              ? 'Saving...'
                              : isEdit
                              ? 'Save'
                              : 'Add Vendor',
                        ),
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
