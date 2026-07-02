/// Payment modal for completing bills
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:retaillite/core/utils/id_generator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/services/analytics_service.dart';
import 'package:retaillite/features/billing/services/bill_share_service.dart';
import 'package:retaillite/core/services/offline_storage_service.dart';
import 'package:retaillite/core/services/print_helper.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/router/app_router.dart';
import 'package:retaillite/core/utils/formatters.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/billing/providers/cart_provider.dart';
import 'package:retaillite/features/settings/providers/settings_provider.dart';

import 'package:retaillite/features/khata/providers/khata_provider.dart';
import 'package:retaillite/features/khata/widgets/add_customer_modal.dart';
import 'package:retaillite/features/reports/providers/reports_provider.dart';

import 'package:retaillite/models/bill_model.dart';
import 'package:retaillite/models/customer_model.dart';
import 'package:retaillite/models/user_model.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:retaillite/core/services/payment_link_service.dart';
import 'package:retaillite/core/config/plan_config.dart';
import 'package:retaillite/shared/widgets/feature_gate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:retaillite/shared/widgets/onboarding_checklist.dart';
import 'package:retaillite/features/billing/providers/billing_provider.dart';
import 'package:retaillite/shared/widgets/app_button.dart';

class PaymentModal extends ConsumerStatefulWidget {
  const PaymentModal({super.key});

  @override
  ConsumerState<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends ConsumerState<PaymentModal> {
  PaymentMethod _selectedMethod = PaymentMethod.cash;
  final _udharAmountController = TextEditingController();
  bool _isLoading = false;
  CustomerModel? _selectedCustomer;

  @override
  void dispose() {
    _udharAmountController.dispose();
    super.dispose();
  }

  double get _udharAmount {
    return double.tryParse(_udharAmountController.text) ?? 0;
  }

  void _syncUdharAmount() {
    if (_selectedMethod == PaymentMethod.udhar && _selectedCustomer != null) {
      final cart = ref.read(cartProvider);
      _udharAmountController.text = cart.total.toInt().toString();
    }
  }

  Future<void> _maybeRequestReview() async {
    if (kIsWeb) return;
    try {
      final limits = await UserMetricsService.getUserLimits();
      if (limits.billsThisMonth == 3) {
        final review = InAppReview.instance;
        if (await review.isAvailable()) {
          await review.requestReview();
        }
      }
    } catch (_) {
      // Review request is best-effort — never block billing flow
    }
  }

  Future<void> _completeBill() async {
    final cart = ref.read(cartProvider);

    if (cart.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cart is empty')));
      return;
    }

    setState(() => _isLoading = true);

    // Validate udhar amount
    final udharAmount = _selectedMethod == PaymentMethod.udhar
        ? _udharAmount
        : 0.0;
    if (_selectedMethod == PaymentMethod.udhar && _selectedCustomer != null) {
      if (udharAmount <= 0 || udharAmount > cart.total) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              udharAmount <= 0
                  ? 'Enter an amount to add to khata'
                  : 'Khata amount cannot exceed bill total',
            ),
          ),
        );
        return;
      }
    }

    try {
      // Check bill limit before creating
      final allowed = await UserMetricsService.trackBillCreated();
      if (!allowed) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                '🚫 Monthly bill limit reached. Upgrade to Pro for 500 bills/month.',
              ),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Upgrade',
                onPressed: () => context.push(AppRoutes.subscription),
              ),
            ),
          );
        }
        return;
      }

      BillModel bill;

      // Create bill locally
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      bill = BillModel(
        id: generateSafeId('bill'),
        billNumber: await OfflineStorageService.getNextBillNumber(),
        items: cart.items,
        total: cart.total,
        paymentMethod: _selectedMethod,
        customerId: _selectedCustomer?.id ?? cart.customerId,
        customerName: _selectedCustomer?.name ?? cart.customerName,
        receivedAmount: cart.total,
        createdAt: now,
        date: dateStr,
      );

      // Save bill to local storage for Reports
      // For Udhar/Credit payments, atomically save bill + update khata balance
      if (_selectedMethod == PaymentMethod.udhar && _selectedCustomer != null) {
        await OfflineStorageService.saveBillWithUdharAtomic(
          bill: bill,
          customerId: _selectedCustomer!.id,
          amount: udharAmount,
        );
      } else {
        await OfflineStorageService.saveBillLocally(bill);
      }

      // Mark onboarding "first bill" step as done
      unawaited(markOnboardingBillDone());

      // Request Play Store review after the 3rd bill
      unawaited(_maybeRequestReview());

      // Log analytics event (non-blocking)
      unawaited(
        AnalyticsService.logBillCreated(
          amount: bill.total,
          itemCount: bill.items.length,
          paymentMode: bill.paymentMethod.name,
        ),
      );

      if (mounted) {
        // Invalidate reports providers to refresh data
        ref.invalidate(periodBillsProvider);
        ref.invalidate(salesSummaryProvider);
        ref.invalidate(topProductsProvider);
        ref.invalidate(filteredBillsProvider);
        ref.invalidate(dashboardBillsProvider);

        // Invalidate customers if a customer was selected
        if (_selectedCustomer != null) {
          ref.invalidate(customersProvider);
        }

        ref.read(cartProvider.notifier).clearCart();

        // Capture everything we need BEFORE popping the modal.
        // After pop() the PaymentModalState is disposed — ref.read() and
        // ScaffoldMessenger.of(context) would both fail or silently no-op.
        final billingMessenger = ScaffoldMessenger.of(context);
        final capturedPrinterState = ref.read(printerProvider);
        final capturedUser = ref.read(currentUserProvider);

        Navigator.of(context).pop();

        _showBillCompleteDialog(
          bill,
          billingMessenger,
          capturedPrinterState,
          capturedUser,
        );
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString().toLowerCase();
        final isLimitError =
            errorStr.contains('permission-denied') ||
            errorStr.contains('permission_denied') ||
            errorStr.contains('missing or insufficient permissions');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isLimitError
                  ? '🚫 Subscription limit reached. Upgrade your plan to continue.'
                  : 'Failed to create bill: $e',
            ),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
            action: isLimitError
                ? SnackBarAction(
                    label: 'Upgrade',
                    textColor: Colors.white,
                    onPressed: () => context.push(AppRoutes.subscription),
                  )
                : null,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showBillCompleteDialog(
    BillModel bill,
    ScaffoldMessengerState billingMessenger,
    PrinterState printerState,
    UserModel? user,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.success,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                'Bill Complete!',
                style: Theme.of(dialogContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('Bill No: #${bill.billNumber}'),
              Text(
                bill.total.asCurrency,
                style: Theme.of(dialogContext).textTheme.headlineSmall
                    ?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),
              // Print button
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        // Use the pre-captured printerState & user — the
                        // PaymentModalState is disposed at this point so ref
                        // is no longer accessible.
                        await PrintHelper.printReceipt(
                          bill: bill,
                          printerState: printerState,
                          user: user,
                          scaffoldMessenger: billingMessenger,
                          onRetry: () => PrintHelper.printReceipt(
                            bill: bill,
                            printerState: printerState,
                            user: user,
                            scaffoldMessenger: billingMessenger,
                          ),
                        );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Print'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Share options - WhatsApp, SMS, Email
              Row(
                children: [
                  // WhatsApp button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        final phone = _selectedCustomer?.phone;
                        if (phone != null && phone.isNotEmpty) {
                          await BillShareService.shareViaWhatsApp(
                            bill,
                            phone,
                            context: context,
                          );
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('No customer phone available'),
                                backgroundColor: AppColors.warning,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.chat, color: AppColors.success),
                      label: const Text('WhatsApp'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.success,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // SMS button (only on mobile)
                  if (!kIsWeb)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          final phone = _selectedCustomer?.phone;
                          if (phone != null && phone.isNotEmpty) {
                            await BillShareService.shareViaSms(
                              bill,
                              phone,
                              context: context,
                            );
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('No customer phone available'),
                                  backgroundColor: AppColors.warning,
                                ),
                              );
                            }
                          }
                        },
                        icon: Icon(Icons.sms, color: AppColors.primary),
                        label: const Text('SMS'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                        ),
                      ),
                    ),
                  if (!kIsWeb) const SizedBox(width: 8),
                  // PDF Download button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await BillShareService.downloadPdf(
                          bill,
                          context: context,
                        );
                      },
                      icon: const Icon(
                        Icons.picture_as_pdf,
                        color: AppColors.upi,
                      ),
                      label: const Text('PDF'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.upi,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('NEW BILL'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomerSelector() {
    final customersAsync = ref.watch(customersProvider);

    return customersAsync.when(
      data: (customers) {
        if (customers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              boxShadow: AppShadows.small,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'No customers in Khata. Add from Khata screen.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppShadows.small,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CustomerModel?>(
              value: _selectedCustomer != null
                  ? customers.cast<CustomerModel?>().firstWhere(
                      (c) => c?.id == _selectedCustomer!.id,
                      orElse: () => null,
                    )
                  : null,
              hint: Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Select customer',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              isExpanded: true,
              items: [
                // Option to clear selection
                DropdownMenuItem<CustomerModel?>(
                  child: Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No customer',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // Customer list
                ...customers.map(
                  (customer) => DropdownMenuItem<CustomerModel?>(
                    value: customer,
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Text(
                            customer.name.isNotEmpty
                                ? customer.name[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${customer.name} • ${customer.phone}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (customer.balance > 0)
                          Text(
                            customer.balance.asCurrency,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.udhar,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              onChanged: (customer) {
                setState(() {
                  _selectedCustomer = customer;
                  _syncUdharAmount();
                });
              },
            ),
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.all(12),
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(12),
        child: const Text(
          'Could not load customers',
          style: TextStyle(color: AppColors.error),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.payment, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Payment',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Total
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Total: '),
                    Text(
                      cart.total.asCurrency,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Customer selection
              Row(
                children: [
                  Text(
                    'Customer (Optional)',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.person_add, size: 20),
                    tooltip: 'Add Customer',
                    onPressed: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const AddCustomerModal(),
                      );
                    },
                  ),
                ],
              ),
              _buildCustomerSelector(),
              const SizedBox(height: 12),

              // Payment method selection
              Text(
                'Payment Method',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Row(
                children: PaymentMethod.values
                    .where((m) => m != PaymentMethod.unknown)
                    .map((method) {
                      final isSelected = _selectedMethod == method;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: method != PaymentMethod.udhar ? 8 : 0,
                          ),
                          child: _PaymentMethodButton(
                            method: method,
                            isSelected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedMethod = method;
                                _syncUdharAmount();
                              });
                            },
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: 12),

              // Send Payment Link button (UPI selected)
              if (_selectedMethod == PaymentMethod.upi) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (!FeatureAccess.check(context, ref, PlanFeature.paymentLinks)) return;
                      if (_selectedCustomer == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a customer first'),
                          ),
                        );
                        return;
                      }
                      final upiId = PaymentLinkService.upiId;
                      if (upiId.isEmpty ||
                          !PaymentLinkService.isValidUpiId(upiId)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please set your UPI ID in Settings first',
                            ),
                          ),
                        );
                        return;
                      }
                      final user = ref.read(currentUserProvider);
                      final shopName =
                          (user != null && user.shopName.isNotEmpty)
                          ? user.shopName
                          : 'Store';
                      final amount = cart.total;
                      final payUrl = PaymentLinkService.generatePaymentPageUrl(
                        upiId: upiId,
                        amount: amount,
                        payeeName: shopName,
                        transactionNote: 'Payment to $shopName',
                      );
                      final msg =
                          'Hi ${_selectedCustomer!.name},\n\n'
                          'Your bill amount is *Rs ${amount.toStringAsFixed(0)}*.\n\n'
                          'Pay via UPI:\n'
                          'Click here to pay:\n'
                          '$payUrl\n\n'
                          'Thank you\n'
                          '\u2014 $shopName';
                      final phone = '91${_selectedCustomer!.phone}';
                      final url = Uri.https('wa.me', '/$phone', {'text': msg});
                      launchUrl(url, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Send Payment Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Udhar amount editor
              if (_selectedMethod == PaymentMethod.udhar) ...[
                if (_selectedCustomer != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Amount to add to ${_selectedCustomer!.name}\'s khata',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _udharAmountController,
                    keyboardType: TextInputType.number,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      prefixStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.warning,
                      ),
                      hintText: '0',
                      filled: true,
                      fillColor: AppColors.warning.withValues(alpha: 0.08),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.warning.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: AppColors.warning,
                          width: 2,
                        ),
                      ),
                      suffixIcon: TextButton(
                        onPressed: () {
                          _udharAmountController.text = cart.total
                              .toInt()
                              .toString();
                          setState(() {});
                        },
                        child: const Text('Full'),
                      ),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_udharAmount > 0 && _udharAmount < cart.total) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            size: 16,
                            color: AppColors.success,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${(cart.total - _udharAmount).asCurrency} paid now, ${_udharAmount.asCurrency} on credit',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber, color: AppColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Please select a customer for Udhar payment',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // Complete button
              AppButton(
                label: 'COMPLETE BILL',
                onPressed:
                    (_selectedMethod == PaymentMethod.udhar &&
                        _selectedCustomer == null)
                    ? null
                    : _completeBill,
                isLoading: _isLoading,
                backgroundColor: AppColors.success,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentMethodButton extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodButton({
    required this.method,
    required this.isSelected,
    required this.onTap,
  });

  Color get _color {
    switch (method) {
      case PaymentMethod.cash:
        return AppColors.cash;
      case PaymentMethod.upi:
        return AppColors.upi;
      case PaymentMethod.udhar:
        return AppColors.udhar;
      case PaymentMethod.unknown:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? _color.withValues(alpha: 0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: _color, width: 2) : null,
            boxShadow: isSelected ? null : AppShadows.small,
          ),
          child: Column(
            children: [
              Text(method.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 2),
              Text(
                method.displayName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isSelected ? _color : null,
                  fontWeight: isSelected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
