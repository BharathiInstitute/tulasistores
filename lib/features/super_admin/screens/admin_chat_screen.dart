/// Admin-side ticket chat screen with sidebar for ticket management
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:retaillite/features/super_admin/services/admin_firestore_service.dart';
import 'package:retaillite/features/support/models/support_ticket.dart';
import 'package:retaillite/features/support/screens/chat_screen.dart';

class AdminChatScreen extends StatelessWidget {
  final String ticketId;
  const AdminChatScreen({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('support_tickets')
              .doc(ticketId)
              .snapshots(),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) {
              return const Text('Support Chat');
            }
            final ticket = SupportTicket.fromFirestore(snap.data!);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ticket.subject,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${ticket.storeName} • ${ticket.statusLabel}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onPrimary.withAlpha(180),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      body: isWide
          ? Row(
              children: [
                Expanded(flex: 3, child: _buildChat()),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                SizedBox(width: 280, child: _TicketSidebar(ticketId: ticketId)),
              ],
            )
          : _buildChatWithBottomSheet(),
    );
  }

  Widget _buildChat() {
    final user = FirebaseAuth.instance.currentUser;
    final adminName = user?.displayName ?? user?.email ?? 'Admin';

    return ChatScreen(
      ticketId: ticketId,
      viewerRole: 'admin',
      onSendAdmin: (id, text) => AdminFirestoreService.sendAdminMessage(
        ticketId: id,
        text: text,
        adminName: adminName,
      ),
      onOpen: () => AdminFirestoreService.markTicketReadAdmin(ticketId),
    );
  }

  Widget _buildChatWithBottomSheet() {
    return Builder(
      builder: (context) {
        return Stack(
          children: [
            _buildChat(),
            Positioned(
              top: 8,
              right: 8,
              child: FloatingActionButton.small(
                heroTag: 'ticket_info',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => DraggableScrollableSheet(
                      initialChildSize: 0.6,
                      maxChildSize: 0.9,
                      minChildSize: 0.3,
                      expand: false,
                      builder: (_, controller) => SingleChildScrollView(
                        controller: controller,
                        child: _TicketSidebar(ticketId: ticketId),
                      ),
                    ),
                  );
                },
                child: const Icon(Icons.info_outline, size: 18),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Ticket Sidebar for managing ticket properties ──

class _TicketSidebar extends StatelessWidget {
  final String ticketId;
  const _TicketSidebar({required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('support_tickets')
          .doc(ticketId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Center(child: CircularProgressIndicator());
        }
        final ticket = SupportTicket.fromFirestore(snap.data!);

        return ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            // Header
            Text(
              'Ticket Details',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 12),

            // Store info
            _InfoRow(label: 'Store', value: ticket.storeName),
            _InfoRow(label: 'Email', value: ticket.storeEmail),
            _InfoRow(label: 'ID', value: ticket.storeId),
            const Divider(height: 24),

            // Status
            _DropdownAction(
              label: 'Status',
              value: ticket.status.name,
              items: TicketStatus.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s.name,
                      child: Text(
                        s.name == 'inProgress'
                            ? 'In Progress'
                            : s.name[0].toUpperCase() + s.name.substring(1),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null && val != ticket.status.name) {
                  AdminFirestoreService.updateTicketStatus(ticketId, val);
                }
              },
            ),
            const SizedBox(height: 12),

            // Priority
            _DropdownAction(
              label: 'Priority',
              value: ticket.priority.name,
              items: TicketPriority.values
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.name,
                      child: Text(
                        p.name[0].toUpperCase() + p.name.substring(1),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null && val != ticket.priority.name) {
                  AdminFirestoreService.updateTicketPriority(ticketId, val);
                }
              },
            ),
            const Divider(height: 24),

            // Tags
            Text(
              'Tags',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withAlpha(180),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: kTicketTags.map((tag) {
                final selected = ticket.tags.contains(tag);
                return FilterChip(
                  label: Text(tag, style: const TextStyle(fontSize: 11)),
                  selected: selected,
                  onSelected: (on) {
                    final newTags = List<String>.from(ticket.tags);
                    if (on) {
                      newTags.add(tag);
                    } else {
                      newTags.remove(tag);
                    }
                    AdminFirestoreService.updateTicketTags(ticketId, newTags);
                  },
                  selectedColor: cs.primaryContainer,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const Divider(height: 24),

            // Timestamps
            _InfoRow(
              label: 'Created',
              value: ticket.createdAt != null
                  ? _formatDate(ticket.createdAt!)
                  : '-',
            ),
            _InfoRow(
              label: 'Updated',
              value: ticket.updatedAt != null
                  ? _formatDate(ticket.updatedAt!)
                  : '-',
            ),
            if (ticket.closedAt != null)
              _InfoRow(label: 'Closed', value: _formatDate(ticket.closedAt!)),

            const Divider(height: 24),

            // Contact buttons
            Text(
              'Contact Store',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withAlpha(180),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final subject = Uri.encodeComponent(
                        'Re: ${ticket.subject} [Ticket #${ticketId.substring(0, 8)}]',
                      );
                      final body = Uri.encodeComponent(
                        'Hi ${ticket.storeName},\n\n'
                        'Regarding your support ticket: ${ticket.subject}\n\n',
                      );
                      launchUrl(
                        Uri.parse(
                          'mailto:${ticket.storeEmail}?subject=$subject&body=$body',
                        ),
                      );
                    },
                    icon: const Icon(Icons.email_outlined, size: 16),
                    label: const Text('Email', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      final text = Uri.encodeComponent(
                        'Hi ${ticket.storeName}, this is regarding your support ticket: '
                        '${ticket.subject} [#${ticketId.substring(0, 8)}]',
                      );
                      launchUrl(
                        Uri.parse('https://wa.me/?text=$text'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    icon: const Icon(Icons.chat, size: 16, color: Colors.green),
                    label: const Text(
                      'WhatsApp',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _formatDate(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year} $h:$m';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

class _DropdownAction extends StatelessWidget {
  final String label;
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;
  const _DropdownAction({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: value,
            items: items,
            onChanged: onChanged,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }
}
