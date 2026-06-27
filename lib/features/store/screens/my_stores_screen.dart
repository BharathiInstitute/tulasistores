import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:retaillite/core/services/active_store.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/models/store_model.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/features/store/widgets/create_store_dialog.dart';

class MyStoresScreen extends ConsumerWidget {
  const MyStoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storesAsync = ref.watch(myStoresProvider);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: theme.colorScheme.primary,
                      child: Text(
                        (user?.displayName ?? user?.email ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Stores',
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            user?.email ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => const CreateStoreDialog(),
                      ),
                      icon: const Icon(Icons.store),
                      label: const Text('Create Store'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) context.go('/login');
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Logout'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a store to manage or create a new one',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 24),

                // Store list
                Expanded(
                  child: storesAsync.when(
                    data: (stores) {
                      if (stores.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.store_outlined,
                                size: 64,
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No stores yet',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create your first store to get started',
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () => showDialog(
                                  context: context,
                                  builder: (_) => const CreateStoreDialog(),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('Create Store'),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.separated(
                        itemCount: stores.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, i) {
                          final store = stores[i];
                          return _StoreCard(
                            store: store,
                            onOpen: () {
                              ActiveStore.activeStoreId = store.storeId;
                              ref.read(activeStoreIdProvider.notifier).state =
                                  store.storeId;
                              context.go('/billing');
                            },
                          );
                        },
                      );
                    },
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('Error: $e')),
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

class _StoreCard extends StatelessWidget {
  final UserStoreRef store;
  final VoidCallback onOpen;
  const _StoreCard({required this.store, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.store),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(store.shopName, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip(
                        icon: store.role == StoreRole.owner
                            ? Icons.verified
                            : Icons.person,
                        label: store.role.displayName,
                        color: store.role == StoreRole.owner
                            ? Colors.blue
                            : Colors.grey,
                      ),
                      _chip(
                        icon: Icons.tag,
                        label: store.storeId.length > 8
                            ? store.storeId.substring(0, 8)
                            : store.storeId,
                        color: Colors.grey,
                      ),
                      if (store.isActive)
                        _chip(
                          icon: Icons.check_circle,
                          label: 'active',
                          color: Colors.green,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            FilledButton(onPressed: onOpen, child: const Text('Open')),
          ],
        ),
      ),
    );
  }

  Widget _chip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 12, color: color)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }
}
