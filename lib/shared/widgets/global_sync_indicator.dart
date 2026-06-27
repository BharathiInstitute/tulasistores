/// Global sync indicator — shows ☁️✅ or ⚠️ count in AppBar
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/services/sync_status_service.dart';
import 'package:retaillite/core/services/connectivity_service.dart';
import 'package:retaillite/core/design/app_colors.dart';
import 'package:retaillite/shared/widgets/sync_details_sheet.dart';

class GlobalSyncIndicator extends ConsumerWidget {
  final bool compact;
  const GlobalSyncIndicator({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final syncStatus = ref.watch(globalSyncStatusProvider);
    final cs = Theme.of(context).colorScheme;

    final unsyncedCount = syncStatus.when(
      data: (s) => s.totalUnsynced,
      loading: () => 0,
      error: (_, _) => 0,
    );

    return GestureDetector(
      onTap: () => _showSyncDetails(context, ref),
      child: Padding(
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              isOnline
                  ? (unsyncedCount > 0 ? Icons.cloud_upload : Icons.cloud_done)
                  : Icons.cloud_off,
              size: 22,
              color: isOnline
                  ? (unsyncedCount > 0
                        ? Colors.orange.shade600
                        : AppColors.success)
                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            // Badge for unsynced count
            if (unsyncedCount > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unsyncedCount > 9 ? '9+' : '$unsyncedCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showSyncDetails(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SyncDetailsSheet(),
    );
  }
}
