/// Admin support dashboard — list of all support tickets with filters
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/features/super_admin/screens/admin_shell_screen.dart';
import 'package:retaillite/features/super_admin/services/admin_firestore_service.dart';
import 'package:retaillite/features/support/models/support_ticket.dart';

/// Stream provider for all admin tickets (no server-side filter — avoids composite index)
final _allAdminTicketsProvider = StreamProvider<List<SupportTicket>>((ref) {
  return AdminFirestoreService.getAllTicketsStream();
});

class SupportAdminScreen extends ConsumerStatefulWidget {
  const SupportAdminScreen({super.key});

  @override
  ConsumerState<SupportAdminScreen> createState() => _SupportAdminScreenState();
}

class _SupportAdminScreenState extends ConsumerState<SupportAdminScreen> {
  String _statusFilter = '';

  static const _filters = [
    ('', 'All'),
    ('open', 'Open'),
    ('inProgress', 'In Progress'),
    ('resolved', 'Resolved'),
    ('closed', 'Closed'),
  ];

  @override
  Widget build(BuildContext context) {
    final ticketsAsync = ref.watch(_allAdminTicketsProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Tickets'),
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
      ),
      body: Column(
        children: [
          // Filter chips
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(bottom: BorderSide(color: cs.outlineVariant)),
            ),
            child: Wrap(
              spacing: 8,
              children: _filters.map((f) {
                final (value, label) = f;
                final selected = _statusFilter == value;
                return FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) => setState(() => _statusFilter = value),
                  selectedColor: cs.primaryContainer,
                );
              }).toList(),
            ),
          ),

          // Tickets list
          Expanded(
            child: ticketsAsync.when(
              data: (allTickets) {
                final tickets = _statusFilter.isEmpty
                    ? allTickets
                    : allTickets
                          .where((t) => t.status.name == _statusFilter)
                          .toList();
                if (tickets.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _statusFilter.isEmpty
                              ? 'No support tickets yet'
                              : 'No $_statusFilter tickets',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: tickets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final t = tickets[index];
                    return _AdminTicketTile(ticket: t);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminTicketTile extends StatelessWidget {
  final SupportTicket ticket;
  const _AdminTicketTile({required this.ticket});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasUnread = ticket.unreadAdmin > 0;

    final priorityColor = switch (ticket.priority) {
      TicketPriority.urgent => Colors.red,
      TicketPriority.high => Colors.orange,
      TicketPriority.medium => Colors.blue,
      TicketPriority.low => Colors.grey,
    };

    final statusColor = switch (ticket.status) {
      TicketStatus.open => Colors.blue,
      TicketStatus.inProgress => Colors.orange,
      TicketStatus.resolved => Colors.green,
      TicketStatus.closed => Colors.grey,
    };

    return Card(
      elevation: hasUnread ? 3 : 1,
      child: InkWell(
        onTap: () => context.push('/super-admin/support/${ticket.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Priority indicator
              Container(
                width: 4,
                height: 48,
                decoration: BoxDecoration(
                  color: priorityColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Subject + unread dot
                    Row(
                      children: [
                        if (hasUnread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: cs.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            ticket.subject,
                            style: TextStyle(
                              fontWeight: hasUnread
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),

                    // Store name
                    Text(
                      '${ticket.storeName} • ${ticket.storeEmail}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Last message
                    Text(
                      ticket.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withAlpha(140),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Tags
                    Wrap(
                      spacing: 4,
                      children: ticket.tags
                          .take(3)
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Status + time
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(
                      ticket.statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    ticket.updatedAt != null ? _timeAgo(ticket.updatedAt!) : '',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  if (hasUnread)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${ticket.unreadAdmin}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cs.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _timeAgo(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }
}
