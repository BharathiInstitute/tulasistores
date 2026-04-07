/// Support ticket and chat message models
library;

import 'package:cloud_firestore/cloud_firestore.dart';

/// Ticket status lifecycle: open → in-progress → resolved → closed
///                                    ↑                ↓
///                              re-opened  ←───────────┘
enum TicketStatus { open, inProgress, resolved, closed }

enum TicketPriority { low, medium, high, urgent }

/// Preset tags for categorising tickets
const List<String> kTicketTags = [
  'billing',
  'bug',
  'feature-request',
  'account',
  'printing',
  'sync-issue',
  'subscription',
  'general',
];

class SupportTicket {
  final String id;
  final String storeId;
  final String storeName;
  final String storeEmail;
  final String subject;
  final TicketStatus status;
  final TicketPriority priority;
  final List<String> tags;
  final String? assignedAdmin;
  final String lastMessage;
  final String lastSenderRole; // 'store' | 'admin' | 'system'
  final int unreadAdmin;
  final int unreadStore;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? closedAt;

  const SupportTicket({
    required this.id,
    required this.storeId,
    required this.storeName,
    this.storeEmail = '',
    required this.subject,
    this.status = TicketStatus.open,
    this.priority = TicketPriority.medium,
    this.tags = const [],
    this.assignedAdmin,
    this.lastMessage = '',
    this.lastSenderRole = 'store',
    this.unreadAdmin = 0,
    this.unreadStore = 0,
    this.createdAt,
    this.updatedAt,
    this.closedAt,
  });

  factory SupportTicket.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return SupportTicket(
      id: doc.id,
      storeId: _asString(d['storeId']),
      storeName: _asString(d['storeName']),
      storeEmail: _asString(d['storeEmail']),
      subject: _asString(d['subject']),
      status: _parseStatus(_asStringOrNull(d['status'])),
      priority: _parsePriority(_asStringOrNull(d['priority'])),
      tags: List<String>.from(d['tags'] as List? ?? []),
      assignedAdmin: _asStringOrNull(d['assignedAdmin']),
      lastMessage: _asString(d['lastMessage']),
      lastSenderRole: _asString(d['lastSenderRole'], fallback: 'store'),
      unreadAdmin: (d['unreadAdmin'] as num?)?.toInt() ?? 0,
      unreadStore: (d['unreadStore'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      closedAt: (d['closedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Safely convert any Firestore value to String (handles int, bool, etc.)
  static String _asString(Object? v, {String fallback = ''}) =>
      v == null ? fallback : v.toString();

  /// Safely convert any Firestore value to String? (handles int, bool, etc.)
  static String? _asStringOrNull(Object? v) => v?.toString();

  Map<String, dynamic> toMap() => {
    'storeId': storeId,
    'storeName': storeName,
    'storeEmail': storeEmail,
    'subject': subject,
    'status': status.name,
    'priority': priority.name,
    'tags': tags,
    'assignedAdmin': assignedAdmin,
    'lastMessage': lastMessage,
    'lastSenderRole': lastSenderRole,
    'unreadAdmin': unreadAdmin,
    'unreadStore': unreadStore,
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
  };

  static TicketStatus _parseStatus(String? s) => switch (s) {
    'inProgress' => TicketStatus.inProgress,
    'resolved' => TicketStatus.resolved,
    'closed' => TicketStatus.closed,
    _ => TicketStatus.open,
  };

  static TicketPriority _parsePriority(String? s) => switch (s) {
    'low' => TicketPriority.low,
    'high' => TicketPriority.high,
    'urgent' => TicketPriority.urgent,
    _ => TicketPriority.medium,
  };

  String get statusLabel => switch (status) {
    TicketStatus.open => 'Open',
    TicketStatus.inProgress => 'In Progress',
    TicketStatus.resolved => 'Resolved',
    TicketStatus.closed => 'Closed',
  };

  bool get isActive =>
      status == TicketStatus.open || status == TicketStatus.inProgress;
}

/// A single chat message within a support ticket
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String senderRole; // 'store' | 'admin' | 'system'
  final String text;
  final String? attachmentUrl;
  final String type; // 'text' | 'image' | 'system'
  final DateTime? createdAt;
  final DateTime? readAt;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderRole,
    required this.text,
    this.attachmentUrl,
    this.type = 'text',
    this.createdAt,
    this.readAt,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ChatMessage(
      id: doc.id,
      senderId: d['senderId']?.toString() ?? '',
      senderName: d['senderName']?.toString() ?? '',
      senderRole: d['senderRole']?.toString() ?? 'store',
      text: d['text']?.toString() ?? '',
      attachmentUrl: d['attachmentUrl']?.toString(),
      type: d['type']?.toString() ?? 'text',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      readAt: (d['readAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'senderId': senderId,
    'senderName': senderName,
    'senderRole': senderRole,
    'text': text,
    'attachmentUrl': attachmentUrl,
    'type': type,
    'createdAt': FieldValue.serverTimestamp(),
    'readAt': readAt != null ? Timestamp.fromDate(readAt!) : null,
  };

  bool get isSystem => type == 'system';
  bool get isAdmin => senderRole == 'admin';
  bool get isStore => senderRole == 'store';
}
