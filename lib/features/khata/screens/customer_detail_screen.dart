/// Customer detail screen
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/design/design_system.dart';
import 'package:retaillite/core/services/payment_link_service.dart';
import 'package:retaillite/core/utils/formatters.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/khata/providers/khata_provider.dart';
import 'package:retaillite/features/khata/widgets/add_customer_modal.dart';
import 'package:retaillite/features/khata/widgets/give_udhaar_modal.dart';
import 'package:retaillite/features/khata/widgets/record_payment_modal.dart';
import 'package:retaillite/core/utils/permission_guard.dart';
import 'package:retaillite/l10n/app_localizations.dart';
import 'package:retaillite/models/customer_model.dart';
import 'package:retaillite/models/transaction_model.dart';
import 'package:retaillite/shared/widgets/loading_states.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerDetailScreen extends ConsumerWidget {
  final String customerId;

  const CustomerDetailScreen({super.key, required this.customerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerAsync = ref.watch(customerProvider(customerId));
    final transactionsAsync = ref.watch(
      customerTransactionsProvider(customerId),
    );

    return customerAsync.when(
      data: (customer) {
        if (customer == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Customer Details')),
            body: const Center(child: Text('Customer not found')),
          );
        }

        final isMobile = ResponsiveHelper.isMobile(context);
        final maxWidth = isMobile ? double.infinity : 800.0;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: isMobile
                ? IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/khata');
                      }
                    },
                  )
                : null,
            title: const Text('Customer Details'),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => guardAction(
                  context,
                  ref,
                  'customers',
                  PermAction.edit,
                  onAllowed: () => _showEditModal(context, customer),
                ),
                tooltip: 'Edit Details',
              ),
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
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: isMobile
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Fixed customer info + balance card at top
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              gradient: customer.hasDue
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.error,
                                        Color(0xFFDC2626),
                                      ],
                                    )
                                  : AppColors.successGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Customer info row
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 22,
                                      backgroundColor: Colors.white24,
                                      child: Text(
                                        customer.name[0].toUpperCase(),
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            customer.name,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          GestureDetector(
                                            onTap: () => launchUrl(
                                              Uri.parse(
                                                'tel:${customer.phone}',
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.phone,
                                                  size: 14,
                                                  color: Colors.white70,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  Formatters.phone(
                                                    customer.phone,
                                                  ),
                                                  style: const TextStyle(
                                                    color: Colors.white70,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Balance on the right
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'Total Due',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(color: Colors.white70),
                                        ),
                                        Text(
                                          customer.balance.abs().asCurrency,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Transactions header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          child: Text(
                            'TRANSACTIONS',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        // Scrollable transactions list
                        Expanded(
                          child: transactionsAsync.when(
                            data: (transactions) {
                              if (transactions.isEmpty) {
                                return const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text('No transactions yet'),
                                  ),
                                );
                              }

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  itemCount: transactions.length,
                                  separatorBuilder: (e, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) =>
                                      _TransactionTile(
                                        transaction: transactions[index],
                                      ),
                                ),
                              );
                            },
                            loading: () => const LoadingIndicator(),
                            error: (e, _) =>
                                const Text('Failed to load transactions'),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Desktop: Keep original card layout
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                children: [
                                  CircleAvatar(
                                    radius: 40,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    child: Text(
                                      customer.name[0].toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    customer.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '📞 ${Formatters.phone(customer.phone)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                  if (customer.address != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '📍 ${customer.address}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.outline,
                                          ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Balance card
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: customer.hasDue
                                  ? const LinearGradient(
                                      colors: [
                                        AppColors.error,
                                        Color(0xFFDC2626),
                                      ],
                                    )
                                  : AppColors.successGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  'कुल बाकी (Total Due)',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: Colors.white70),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  customer.balance.abs().asCurrency,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                                if (!customer.hasDue)
                                  const Text(
                                    '✅ Fully Paid',
                                    style: TextStyle(color: Colors.white),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Transactions section
                          Text(
                            'TRANSACTIONS',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 12),

                          transactionsAsync.when(
                            data: (transactions) {
                              if (transactions.isEmpty) {
                                return const Card(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: Text('No transactions yet'),
                                    ),
                                  ),
                                );
                              }

                              // Cap visible list to avoid rendering all items at once
                              const maxVisible = 50;
                              final visibleCount =
                                  transactions.length > maxVisible
                                  ? maxVisible
                                  : transactions.length;

                              return Card(
                                child: Column(
                                  children: [
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      itemCount: visibleCount,
                                      separatorBuilder: (e, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) =>
                                          _TransactionTile(
                                            transaction: transactions[index],
                                          ),
                                    ),
                                    if (transactions.length > maxVisible)
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(
                                          '${transactions.length - maxVisible} more transactions not shown',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                            loading: () => const LoadingIndicator(),
                            error: (e, _) =>
                                const Text('Failed to load transactions'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          bottomNavigationBar: _buildCombinedBottomBar(context, ref, customer),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Customer Details')),
        body: const LoadingIndicator(),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Customer Details')),
        body: const ErrorState(message: 'Failed to load customer'),
      ),
    );
  }

  Widget _buildCombinedBottomBar(
    BuildContext context,
    WidgetRef ref,
    CustomerModel customer,
  ) {
    final isMobile = ResponsiveHelper.isMobile(context);
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: AppShadows.medium,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Action buttons row
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 16,
                vertical: isMobile ? 8 : 12,
              ),
              child: Row(
                children: [
                  if (customer.hasDue)
                    Expanded(
                      child: _ActionButton(
                        onPressed: () =>
                            _sendPaymentLink(context, ref, customer),
                        icon: Icons.link,
                        label: 'Link',
                        isOutlined: true,
                      ),
                    ),
                  if (customer.hasDue) const SizedBox(width: 6),
                  if (customer.hasDue)
                    Expanded(
                      child: _ActionButton(
                        onPressed: () =>
                            _sendWhatsAppReminder(context, ref, customer),
                        icon: Icons.message,
                        label: 'Remind',
                        isOutlined: true,
                      ),
                    ),
                  if (customer.hasDue) const SizedBox(width: 6),
                  Expanded(
                    child: _ActionButton(
                      onPressed: () => guardAction(
                        context,
                        ref,
                        'customers',
                        PermAction.create,
                        onAllowed: () => _showUdhaarModal(context, customer),
                      ),
                      icon: Icons.add_circle_outline,
                      label: 'Udhaar',
                      isOutlined: true,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _ActionButton(
                      onPressed: () => guardAction(
                        context,
                        ref,
                        'customers',
                        PermAction.create,
                        onAllowed: () => _showPaymentModal(context, customer),
                      ),
                      icon: Icons.currency_rupee,
                      label: 'Pay',
                      isOutlined: false,
                      color: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            // Divider
            const Divider(height: 1),
            // Main bottom navigation
            BottomNavigationBar(
              currentIndex: 1, // Khata tab is selected
              onTap: (index) => _onNavTapped(context, index),
              type: BottomNavigationBarType.fixed,
              selectedFontSize: 11,
              unselectedFontSize: 10,
              iconSize: 22,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.point_of_sale_outlined),
                  activeIcon: Icon(Icons.point_of_sale),
                  label: 'POS',
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.people_outline),
                  activeIcon: const Icon(Icons.people),
                  label: l10n.khata,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.inventory_2_outlined),
                  activeIcon: const Icon(Icons.inventory_2),
                  label: l10n.products,
                ),
                BottomNavigationBarItem(
                  icon: const Icon(Icons.dashboard_outlined),
                  activeIcon: const Icon(Icons.dashboard),
                  label: l10n.dashboard,
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_outlined),
                  activeIcon: Icon(Icons.receipt),
                  label: 'Bills',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _onNavTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/pos');
        break;
      case 1:
        context.go('/khata');
        break;
      case 2:
        context.go('/products');
        break;
      case 3:
        context.go('/dashboard');
        break;
      case 4:
        context.go('/bills');
        break;
    }
  }

  void _sendWhatsAppReminder(
    BuildContext context,
    WidgetRef ref,
    CustomerModel customer,
  ) async {
    // Build reminder message with UPI link if configured
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
    if (hasUpi) {
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
    } else {
      messageText =
          'Hi ${customer.name},\n\n'
          'You have a pending balance of *Rs $amt*.\n'
          'Please pay at your earliest convenience.\n\n'
          'Thank you';
    }

    final phone = '91${customer.phone}';

    try {
      // On web, always use wa.me URL (whatsapp:// scheme doesn't work in browsers)
      // On mobile, try native scheme first, fallback to wa.me
      if (kIsWeb) {
        final webUrl = Uri.https('wa.me', '/$phone', {'text': messageText});
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      } else {
        final message = Uri.encodeComponent(messageText);
        final url = Uri.parse('whatsapp://send?phone=$phone&text=$message');
        if (await canLaunchUrl(url)) {
          await launchUrl(url);
        } else {
          final webUrl = Uri.https('wa.me', '/$phone', {'text': messageText});
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open WhatsApp'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showEditModal(BuildContext context, CustomerModel customer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddCustomerModal(customer: customer),
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

  /// Send a payment link via WhatsApp
  void _sendPaymentLink(
    BuildContext context,
    WidgetRef ref,
    CustomerModel customer,
  ) async {
    final shopName = ref.read(currentUserProvider)?.shopName;

    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Creating payment link...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    final result = await PaymentLinkService.createPaymentLink(
      amount: customer.balance,
      customerName: customer.name,
      customerPhone: customer.phone,
      description: 'Khata balance payment',
      shopName: shopName,
    );

    if (!context.mounted) return;

    if (result.success && result.paymentLink != null) {
      // Share via WhatsApp
      final success = await PaymentLinkService.shareViaWhatsApp(
        paymentLink: result.paymentLink!,
        amount: customer.balance,
        customerPhone: customer.phone,
        shopName: shopName,
        customerName: customer.name,
      );

      if (!success && context.mounted) {
        // Fallback to generic share
        await PaymentLinkService.shareGeneric(
          paymentLink: result.paymentLink!,
          amount: customer.balance,
          shopName: shopName,
          customerName: customer.name,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to create payment link'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _showDeleteConfirmation(
    BuildContext context,
    WidgetRef ref,
    CustomerModel customer,
  ) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

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
                await ref
                    .read(khataServiceProvider)
                    .deleteCustomer(customer.id);

                ref.invalidate(customersProvider);

                navigator.pop(); // Go back to list
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
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel transaction;

  const _TransactionTile({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isPurchase = transaction.type == TransactionType.purchase;
    final isMobile = ResponsiveHelper.isMobile(context);

    return ListTile(
      dense: isMobile,
      visualDensity: isMobile ? VisualDensity.compact : null,
      contentPadding: isMobile
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4)
          : null,
      leading: CircleAvatar(
        radius: isMobile ? 18 : 20,
        backgroundColor: isPurchase
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.success.withValues(alpha: 0.1),
        child: Icon(
          isPurchase ? Icons.shopping_cart : Icons.payments,
          color: isPurchase ? AppColors.error : AppColors.success,
          size: isMobile ? 16 : 20,
        ),
      ),
      title: Text(
        transaction.type.displayName,
        style: isMobile ? Theme.of(context).textTheme.bodyMedium : null,
      ),
      subtitle: Text(
        transaction.createdAt.formattedDateTime,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(fontSize: isMobile ? 11 : null),
      ),
      trailing: Text(
        '${isPurchase ? '+' : '-'}${transaction.amount.asCurrency}',
        style:
            (isMobile
                    ? Theme.of(context).textTheme.titleSmall
                    : Theme.of(context).textTheme.titleMedium)
                ?.copyWith(
                  color: isPurchase ? AppColors.error : AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool isOutlined;
  final Color? color;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.isOutlined,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? Theme.of(context).colorScheme.primary;

    if (isOutlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: effectiveColor,
          side: BorderSide(color: effectiveColor, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          minimumSize: const Size(0, 48),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: effectiveColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        minimumSize: const Size(0, 48),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
