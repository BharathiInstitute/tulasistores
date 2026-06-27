/// Notifications inbox screen — shows all user notifications
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/features/notifications/models/notification_model.dart';
import 'package:retaillite/features/notifications/providers/notification_provider.dart';
import 'package:retaillite/features/notifications/services/notification_firestore_service.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final userId = ref.watch(authNotifierProvider).user?.id;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/billing'),
        ),
        actions: [
          if (userId != null)
            TextButton.icon(
              onPressed: () =>
                  NotificationFirestoreService.markAllAsRead(userId),
              icon: const Icon(Icons.done_all, size: 18),
              label: const Text('Mark all read'),
            ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "You're all caught up!",
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final notif = notifications[index];
              return _NotificationTile(notification: notif, userId: userId!);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final String userId;

  const _NotificationTile({required this.notification, required this.userId});

  @override
  Widget build(BuildContext context) {
    final timeAgo = _formatTimeAgo(notification.createdAt);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) {
        NotificationFirestoreService.deleteNotification(
          userId,
          notification.id,
        );
      },
      child: ListTile(
        onTap: () {
          // Mark as read on tap
          if (!notification.read) {
            NotificationFirestoreService.markAsRead(userId, notification.id);
          }
          // Show notification detail in a popup dialog
          _showNotificationDetail(context);
        },
        tileColor: notification.read
            ? null
            : Colors.blue.withValues(alpha: 0.04),
        leading: CircleAvatar(
          backgroundColor: _getTypeColor(
            notification.type,
          ).withValues(alpha: 0.15),
          child: Icon(
            _getTypeIcon(notification.type),
            color: _getTypeColor(notification.type),
            size: 20,
          ),
        ),
        title: Text(
          notification.title,
          style: TextStyle(
            fontWeight: notification.read ? FontWeight.normal : FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              notification.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              timeAgo,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: notification.read
            ? null
            : Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }

  IconData _getTypeIcon(NotificationType type) {
    switch (type) {
      case NotificationType.announcement:
        return Icons.campaign;
      case NotificationType.alert:
        return Icons.warning_amber;
      case NotificationType.reminder:
        return Icons.alarm;
      case NotificationType.system:
        return Icons.info_outline;
    }
  }

  Color _getTypeColor(NotificationType type) {
    switch (type) {
      case NotificationType.announcement:
        return Colors.blue;
      case NotificationType.alert:
        return Colors.orange;
      case NotificationType.reminder:
        return Colors.green;
      case NotificationType.system:
        return Colors.grey;
    }
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('MMM d').format(date);
  }

  void _showNotificationDetail(BuildContext context) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon and close
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _getTypeColor(
                        notification.type,
                      ).withValues(alpha: 0.15),
                      child: Icon(
                        _getTypeIcon(notification.type),
                        color: _getTypeColor(notification.type),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        notification.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // Body
                Text(notification.body, style: theme.textTheme.bodyLarge),
                const SizedBox(height: 16),
                // Timestamp
                Text(
                  DateFormat(
                    'EEEE, d MMMM yyyy • h:mm a',
                  ).format(notification.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 20),
                // Close button
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
