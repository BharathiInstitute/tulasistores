/// Referrals Admin Screen for Super Admin
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/features/super_admin/providers/super_admin_provider.dart';
import 'package:retaillite/features/super_admin/screens/admin_shell_screen.dart';
import 'package:retaillite/features/super_admin/services/admin_firestore_service.dart';

class ReferralsAdminScreen extends ConsumerWidget {
  const ReferralsAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(referralStatsProvider);
    final topReferrersAsync = ref.watch(topReferrersProvider);
    final recentAsync = ref.watch(recentReferralsProvider);
    final promoAsync = ref.watch(promoCodesProvider);
    final isWide = MediaQuery.of(context).size.width > 800;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Referrals'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        leading: MediaQuery.of(context).size.width >= 1024
            ? null
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  adminShellScaffoldKey.currentState?.openDrawer();
                },
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(referralStatsProvider);
              ref.invalidate(topReferrersProvider);
              ref.invalidate(recentReferralsProvider);
              ref.invalidate(promoCodesProvider);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats Cards ──
            statsAsync.when(
              data: (stats) => _buildStatsRow(context, stats, isWide),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
            ),

            const SizedBox(height: 24),

            // ── Main Content ──
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTopReferrersCard(context, topReferrersAsync),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildRecentActivityCard(context, recentAsync),
                  ),
                ],
              )
            else ...[
              _buildTopReferrersCard(context, topReferrersAsync),
              const SizedBox(height: 16),
              _buildRecentActivityCard(context, recentAsync),
            ],

            const SizedBox(height: 24),

            // ── Promo Codes Card ──
            _buildPromoCodesCard(context, ref, promoAsync),
          ],
        ),
      ),
    );
  }

  // ── Stats Row ──

  Widget _buildStatsRow(
    BuildContext context,
    ReferralStats stats,
    bool isWide,
  ) {
    final cards = [
      _StatCard(
        icon: Icons.people_outline,
        label: 'Total Referrals',
        value: stats.totalReferrals.toString(),
        color: Colors.blue,
      ),
      _StatCard(
        icon: Icons.card_giftcard,
        label: 'Rewards Issued',
        value: stats.totalRewardsIssued.toString(),
        color: Colors.green,
      ),
      _StatCard(
        icon: Icons.calendar_today,
        label: 'Days Gifted',
        value: stats.totalDaysGifted.toString(),
        color: Colors.orange,
      ),
    ];

    if (isWide) {
      return Row(
        children: cards
            .map(
              (c) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: c,
                ),
              ),
            )
            .toList(),
      );
    }

    return Column(
      children: cards
          .map(
            (c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: c),
          )
          .toList(),
    );
  }

  // ── Top Referrers Card ──

  Widget _buildTopReferrersCard(
    BuildContext context,
    AsyncValue<List<ReferrerInfo>> async,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: cs.primaryContainer,
            child: Row(
              children: [
                Icon(Icons.leaderboard, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Top Referrers',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
          async.when(
            data: (referrers) {
              if (referrers.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No referrals yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return DataTable(
                columnSpacing: 16,
                horizontalMargin: 16,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Shop')),
                  DataColumn(label: Text('Referrals'), numeric: true),
                  DataColumn(label: Text('Days Earned'), numeric: true),
                ],
                rows: referrers.asMap().entries.map((entry) {
                  final i = entry.key;
                  final r = entry.value;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontWeight: i < 3
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: i == 0
                                ? Colors.amber.shade700
                                : i == 1
                                ? Colors.grey.shade600
                                : i == 2
                                ? Colors.brown
                                : null,
                          ),
                        ),
                      ),
                      DataCell(
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.shopName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (r.email.isNotEmpty)
                              Text(
                                r.email,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      DataCell(Text(r.referralCount.toString())),
                      DataCell(Text('+${r.daysEarned}d')),
                    ],
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Recent Activity Card ──

  Widget _buildRecentActivityCard(
    BuildContext context,
    AsyncValue<List<ReferralActivity>> async,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: cs.secondaryContainer,
            child: Row(
              children: [
                Icon(Icons.history, color: cs.onSecondaryContainer),
                const SizedBox(width: 8),
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          async.when(
            data: (activities) {
              if (activities.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No activity yet',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: activities.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final a = activities[index];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.green.shade50,
                      child: Icon(
                        Icons.card_giftcard,
                        size: 16,
                        color: Colors.green.shade700,
                      ),
                    ),
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: a.referrerName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' referred '),
                          TextSpan(
                            text: a.refereeName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      '${a.bothRewarded ? "Both" : "Referrer"} +${a.rewardDays}d  •  '
                      '${a.rewardedAt != null ? _timeAgo(a.rewardedAt!) : 'Unknown'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
          ),
        ],
      ),
    );
  }

  // ── Promo Codes Card ──

  Widget _buildPromoCodesCard(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PromoCode>> async,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: cs.primaryContainer,
            child: Row(
              children: [
                Icon(Icons.confirmation_number, color: cs.onPrimaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Promo Codes',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _showCreatePromoDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Generate'),
                ),
              ],
            ),
          ),
          async.when(
            data: (codes) {
              if (codes.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'No promo codes yet. Tap Generate to create one.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }

              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: codes.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final c = codes[index];
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: c.isUsed
                          ? Colors.grey.shade200
                          : Colors.green.shade50,
                      child: Icon(
                        c.isUsed
                            ? Icons.check_circle
                            : Icons.confirmation_number,
                        size: 18,
                        color: c.isUsed
                            ? Colors.grey.shade500
                            : Colors.green.shade700,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          c.code,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: c.isUsed ? Colors.grey : null,
                            decoration: c.isUsed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.plan == 'business'
                                ? Colors.purple.shade50
                                : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            c.plan.toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: c.plan == 'business'
                                  ? Colors.purple.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '+${c.rewardDays}d',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      c.isUsed
                          ? 'Used by ${c.usedBy ?? "?"} • ${c.usedAt != null ? _timeAgo(c.usedAt!) : ""}'
                          : c.note.isNotEmpty
                          ? c.note
                          : 'Created ${c.createdAt != null ? _timeAgo(c.createdAt!) : ""}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    trailing: c.isUsed
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                tooltip: 'Copy code',
                                onPressed: () {
                                  Clipboard.setData(
                                    ClipboardData(text: c.code),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Code copied!'),
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: Colors.red.shade400,
                                ),
                                tooltip: 'Delete',
                                onPressed: () async {
                                  final ok =
                                      await AdminFirestoreService.deletePromoCode(
                                        c.code,
                                      );
                                  if (ok) ref.invalidate(promoCodesProvider);
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          ok ? 'Deleted' : 'Cannot delete',
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                  );
                },
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: $e'),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreatePromoDialog(BuildContext context, WidgetRef ref) {
    final codeCtrl = TextEditingController();
    final daysCtrl = TextEditingController(text: '30');
    final noteCtrl = TextEditingController();
    String selectedPlan = 'pro';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Generate Promo Code'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. DIWALI2026',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.casino),
                      tooltip: 'Random code',
                      onPressed: () {
                        codeCtrl.text = _randomCode();
                        setDialogState(() {});
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: daysCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reward Days',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedPlan,
                        decoration: const InputDecoration(
                          labelText: 'Plan',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'pro', child: Text('Pro')),
                          DropdownMenuItem(
                            value: 'business',
                            child: Text('Business'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedPlan = v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. Festival campaign',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final code = codeCtrl.text.trim().toUpperCase();
                final days = int.tryParse(daysCtrl.text) ?? 30;
                if (code.isEmpty || days <= 0) return;

                final result = await AdminFirestoreService.createPromoCode(
                  code: code,
                  rewardDays: days,
                  plan: selectedPlan,
                  note: noteCtrl.text.trim(),
                );

                if (ctx.mounted) Navigator.pop(ctx);

                if (result != null) {
                  ref.invalidate(promoCodesProvider);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Code $result created!')),
                    );
                  }
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed — code may already exist'),
                      ),
                    );
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  static String _randomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(8, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // ── Helpers ──

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d, yyyy').format(date);
  }
}

// ── Stat Card Widget ──

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    label,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
