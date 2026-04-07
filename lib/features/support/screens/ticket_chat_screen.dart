/// Store-side ticket chat wrapper — AppBar + ChatScreen
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:retaillite/features/support/models/support_ticket.dart';
import 'package:retaillite/features/support/screens/chat_screen.dart';
import 'package:retaillite/features/support/services/support_service.dart';

class TicketChatScreen extends StatelessWidget {
  final String ticketId;
  const TicketChatScreen({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
                  ticket.statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onPrimary.withAlpha(180),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'close') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Close Ticket?'),
                    content: const Text(
                      'This will close the support ticket. You can always create a new one.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await SupportService.closeTicket(ticketId);
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'close',
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, size: 18),
                    SizedBox(width: 8),
                    Text('Close Ticket'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: ChatScreen(ticketId: ticketId),
    );
  }
}
