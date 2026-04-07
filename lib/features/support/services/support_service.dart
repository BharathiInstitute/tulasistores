/// Store-side support service — ticket CRUD and chat messaging
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:retaillite/features/support/models/support_ticket.dart';

class SupportService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static CollectionReference get _ticketsRef =>
      _firestore.collection('support_tickets');

  // ── Tickets ──

  /// Stream of the current user's tickets (real-time, newest first)
  static Stream<List<SupportTicket>> getMyTicketsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return _ticketsRef
        .where('storeId', isEqualTo: uid)
        .orderBy('updatedAt', descending: true)
        .limit(50)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => SupportTicket.fromFirestore(d)).toList(),
        );
  }

  /// Create a new support ticket and send the first message
  static Future<String?> createTicket({
    required String subject,
    required String firstMessage,
    required List<String> tags,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      // Read user doc for shop name
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data() ?? {};
      final shopName = userData['shopName'] as String? ?? 'Unknown Shop';

      final ticketRef = _ticketsRef.doc();
      final ticket = SupportTicket(
        id: ticketRef.id,
        storeId: user.uid,
        storeName: shopName,
        storeEmail: user.email ?? '',
        subject: subject,
        tags: tags,
        lastMessage: firstMessage,
        unreadAdmin: 1,
      );

      final batch = _firestore.batch();

      // Create ticket doc
      batch.set(ticketRef, ticket.toMap());

      // Add first message
      final msgRef = ticketRef.collection('messages').doc();
      batch.set(
        msgRef,
        ChatMessage(
          id: msgRef.id,
          senderId: user.uid,
          senderName: shopName,
          senderRole: 'store',
          text: firstMessage,
        ).toMap(),
      );

      await batch.commit();
      return ticketRef.id;
    } catch (e) {
      debugPrint('❌ SupportService: Failed to create ticket: $e');
      return null;
    }
  }

  // ── Messages ──

  /// Stream of messages for a specific ticket (real-time, oldest first)
  static Stream<List<ChatMessage>> getMessagesStream(String ticketId) {
    return _ticketsRef
        .doc(ticketId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList(),
        );
  }

  /// Send a message from the store user
  static Future<bool> sendMessage({
    required String ticketId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final shopName =
          (userDoc.data()?['shopName'] as String?) ?? 'Unknown Shop';

      final batch = _firestore.batch();

      // Add message
      final msgRef = _ticketsRef.doc(ticketId).collection('messages').doc();
      batch.set(
        msgRef,
        ChatMessage(
          id: msgRef.id,
          senderId: user.uid,
          senderName: shopName,
          senderRole: 'store',
          text: text,
        ).toMap(),
      );

      // Update ticket metadata
      batch.update(_ticketsRef.doc(ticketId), {
        'lastMessage': text,
        'lastSenderRole': 'store',
        'updatedAt': FieldValue.serverTimestamp(),
        'unreadAdmin': FieldValue.increment(1),
        'unreadStore': 0,
        // Re-open if resolved
        'status': FieldValue.increment(0), // no-op; handled below
      });

      await batch.commit();

      // Re-open resolved tickets when store sends a message
      final ticketDoc = await _ticketsRef.doc(ticketId).get();
      final status =
          (ticketDoc.data() as Map<String, dynamic>?)?['status'] as String?;
      if (status == 'resolved') {
        await _ticketsRef.doc(ticketId).update({'status': 'open'});
      }

      return true;
    } catch (e) {
      debugPrint('❌ SupportService: Failed to send message: $e');
      return false;
    }
  }

  /// Mark all messages in a ticket as read by the store user
  static Future<void> markRead(String ticketId) async {
    try {
      await _ticketsRef.doc(ticketId).update({'unreadStore': 0});
    } catch (_) {}
  }

  /// Close a ticket from the store side
  static Future<bool> closeTicket(String ticketId) async {
    try {
      final batch = _firestore.batch();

      batch.update(_ticketsRef.doc(ticketId), {
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // System message
      final msgRef = _ticketsRef.doc(ticketId).collection('messages').doc();
      batch.set(msgRef, {
        'senderId': 'system',
        'senderName': 'System',
        'senderRole': 'system',
        'text': 'Ticket closed by store owner.',
        'type': 'system',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return true;
    } catch (e) {
      debugPrint('❌ SupportService: Failed to close ticket: $e');
      return false;
    }
  }

  /// Get unread ticket count for the badge
  static Stream<int> getUnreadCountStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(0);

    return _ticketsRef
        .where('storeId', isEqualTo: uid)
        .where('unreadStore', isGreaterThan: 0)
        .snapshots()
        .map((snap) => snap.docs.length);
  }
}
