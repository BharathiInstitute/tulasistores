import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/core/config/plan_config.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen for viewing and managing subscription plans.
///
/// All platforms redirect to the website pricing page for payment via
/// Razorpay Checkout.js. The app listens for Firestore subscription
/// changes in real-time, so the UI updates automatically after payment.
class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isAnnual = false;
  final bool _isLoading = false;

  String _currentPlan = 'free';
  String _subscriptionStatus = 'active';
  DateTime? _expiresAt;

  static const _planRank = {'free': 0, 'pro': 1, 'business': 2};

  /// Returns true if [planKey] is a higher tier than the current plan.
  bool _isPlanHigher(String planKey) {
    return (_planRank[planKey] ?? 0) > (_planRank[_currentPlan] ?? 0);
  }

  @override
  void initState() {
    super.initState();
    _loadCurrentSubscription();
  }

  Future<void> _loadCurrentSubscription() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.id)
        .get();
    final sub = doc.data()?['subscription'] as Map<String, dynamic>?;
    if (sub != null && mounted) {
      setState(() {
        _currentPlan = (sub['plan'] as String?) ?? 'free';
        _subscriptionStatus = (sub['status'] as String?) ?? 'active';
        _expiresAt = (sub['expiresAt'] as Timestamp?)?.toDate();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              GoRouter.of(context).go('/billing');
            }
          },
        ),
        title: const Text('Subscription Plans'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Choose the right plan for your business',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            if (_currentPlan != 'free' && _expiresAt != null)
              Text(
                'Current: ${_currentPlan[0].toUpperCase()}${_currentPlan.substring(1)} '
                '($_subscriptionStatus) — expires ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            const SizedBox(height: 16),
            // Monthly / Annual toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Monthly'),
                Switch(
                  value: _isAnnual,
                  onChanged: (v) => setState(() => _isAnnual = v),
                ),
                const Text('Annual'),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Save ~17%',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (!kIsWeb) ...[
              const SizedBox(height: 8),
              Text(
                'You\'ll be redirected to the website to complete payment',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
            const SizedBox(height: 16),
            _buildPlanCard(
              context,
              planKey: 'free',
              name: 'Free',
              monthlyPrice: 0,
              annualPrice: 0,
              features: [
                '${PlanConfig.free.maxBillsPerMonth} bills/month',
                '${PlanConfig.free.maxProducts} products',
                '${PlanConfig.free.maxCustomers} customers',
                '${PlanConfig.free.maxStores} store',
                'Basic reports (today/week)',
                'Print receipts',
                'Barcode scanning',
              ],
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              context,
              planKey: 'pro',
              name: 'Pro',
              monthlyPrice: PlanConfig.proMonthlyPrice,
              annualPrice: PlanConfig.proAnnualPrice,
              features: [
                '${PlanConfig.pro.maxBillsPerMonth} bills/month',
                '${PlanConfig.pro.maxProducts} products',
                'Unlimited customers',
                '${PlanConfig.pro.maxStaff} staff users',
                '${PlanConfig.pro.maxStores} store',
                'Full reports & analytics',
                'Export CSV/PDF',
                'Payment links',
                'Push notifications',
                'Multi-device sync',
              ],
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            _buildPlanCard(
              context,
              planKey: 'business',
              name: 'Business',
              monthlyPrice: PlanConfig.businessMonthlyPrice,
              annualPrice: PlanConfig.businessAnnualPrice,
              features: [
                'Unlimited bills',
                'Unlimited products',
                'Unlimited customers',
                '${PlanConfig.business.maxStaff} staff users',
                '${PlanConfig.business.maxStores} stores',
                'All reports & advanced analytics',
                'Export CSV/PDF',
                'Payment links',
                'Push notifications',
                'Multi-device sync',
                'Priority phone + email support',
              ],
              color: Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanCard(
    BuildContext context, {
    required String planKey,
    required String name,
    required int monthlyPrice,
    required int annualPrice,
    required List<String> features,
    required Color color,
  }) {
    final isCurrent = _currentPlan == planKey;
    final price = _isAnnual ? annualPrice : monthlyPrice;
    final period = planKey == 'free'
        ? 'forever'
        : _isAnnual
        ? '/year'
        : '/month';

    return Card(
      elevation: isCurrent ? 0 : 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrent ? BorderSide(color: color, width: 2) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (isCurrent)
                  Chip(
                    label: const Text('Current'),
                    backgroundColor: color.withValues(alpha: 0.1),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '₹$price',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  TextSpan(
                    text: period,
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: color, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(f)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!isCurrent && planKey != 'free')
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : () => _handleUpgrade(planKey),
                  style: FilledButton.styleFrom(backgroundColor: color),
                  icon: Icon(
                    _isPlanHigher(planKey)
                        ? Icons.open_in_browser
                        : Icons.arrow_downward,
                    size: 18,
                  ),
                  label: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isPlanHigher(planKey)
                              ? 'Upgrade to $name'
                              : 'Downgrade to $name',
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Handle subscription upgrade — opens the website pricing page.
  ///
  /// All platforms (Android, Web, Windows, iOS) redirect to the website
  /// pricing page which handles Razorpay Checkout.js payment. The app
  /// listens for Firestore subscription changes in real-time via
  /// subscriptionPlanProvider, so the UI updates automatically after payment.
  Future<void> _handleUpgrade(String planKey) async {
    final cycle = _isAnnual ? 'annual' : 'monthly';

    // Get a custom token so the pricing page signs in as the correct user
    String? token;
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        // On Windows desktop, the cloud_functions SDK doesn't reliably
        // attach auth headers. Call the function via direct HTTP instead.
        token = await _getPaymentTokenViaHttp();
      } else {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('createPaymentToken');
        final result = await callable.call<Map<String, dynamic>>({});
        token = result.data['token'] as String?;
      }
    } catch (e) {
      debugPrint('Failed to get payment token: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error: $e')),
        );
      }
      return;
    }

    if (token == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not authenticate. Please sign out and sign back in, then try again.',
            ),
          ),
        );
      }
      return;
    }

    final url =
        'https://stores.tulasierp.com/src/pages/pricing.html?plan=$planKey&cycle=$cycle&token=${Uri.encodeComponent(token)}';

    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not open browser. Please visit stores.tulasierp.com/src/pages/pricing.html to upgrade.',
          ),
        ),
      );
    }
  }

  /// Calls createPaymentToken via direct HTTP for Windows desktop,
  /// bypassing the cloud_functions SDK which doesn't reliably attach
  /// auth headers on desktop platforms.
  Future<String?> _getPaymentTokenViaHttp() async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken(true);
    if (idToken == null) throw Exception('Not signed in');

    final response = await http.post(
      Uri.parse(
        'https://asia-south1-login-radha.cloudfunctions.net/createPaymentToken',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: json.encode({'data': {}}),
    );

    if (response.statusCode != 200) {
      throw Exception('Server error ${response.statusCode}: ${response.body}');
    }

    final body = json.decode(response.body) as Map<String, dynamic>;
    final result = body['result'] as Map<String, dynamic>?;
    return result?['token'] as String?;
  }
}
