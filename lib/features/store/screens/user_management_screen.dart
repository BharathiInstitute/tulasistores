import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/models/store_member_model.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';
import 'package:retaillite/features/store/services/store_service.dart';
import 'package:retaillite/features/store/widgets/add_user_dialog.dart';

class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final storeId = ref.watch(activeStoreIdProvider);
    final storeAsync = ref.watch(activeStoreProvider);
    final membersAsync = ref.watch(storeMembersProvider);
    final myRole = ref.watch(myRoleProvider);

    if (storeId == null) {
      return const Center(child: Text('No store selected'));
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.people_alt, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'User Management',
                      style: theme.textTheme.headlineSmall,
                    ),
                    Text(
                      'Manage team members and their roles',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Store Owner card
            storeAsync.when(
              data: (store) {
                if (store == null) return const SizedBox.shrink();
                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.verified,
                          color: theme.colorScheme.primary,
                          size: 28,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Store Owner',
                              style: theme.textTheme.labelMedium,
                            ),
                            Text(
                              '${store.ownerName}  (${store.ownerEmail})',
                              style: theme.textTheme.titleSmall,
                            ),
                          ],
                        ),
                        const Spacer(),
                        if (myRole == StoreRole.owner)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _showTransferDialog(context, ref, storeId),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: const Text('Transfer'),
                          ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                if (myRole == StoreRole.owner || myRole == StoreRole.manager)
                  FilledButton.icon(
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => AddUserDialog(storeId: storeId),
                    ),
                    icon: const Icon(Icons.person_add),
                    label: const Text('Add User'),
                  ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(storeMembersProvider),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Members list
            membersAsync.when(
              data: (members) {
                if (members.isEmpty) {
                  return const Center(child: Text('No team members'));
                }
                return Column(
                  children: members.map((m) {
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _roleColor(
                            m.role,
                          ).withValues(alpha: 0.15),
                          child: Text(
                            m.displayName.isNotEmpty
                                ? m.displayName[0].toUpperCase()
                                : '?',
                            style: TextStyle(color: _roleColor(m.role)),
                          ),
                        ),
                        title: Text(m.displayName),
                        subtitle: Row(
                          children: [
                            Icon(
                              Icons.email,
                              size: 14,
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(m.email),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _roleColor(
                                  m.role,
                                ).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                m.role.displayName.toUpperCase(),
                                style: TextStyle(
                                  color: _roleColor(m.role),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            if (myRole == StoreRole.owner &&
                                m.role != StoreRole.owner)
                              PopupMenuButton<String>(
                                onSelected: (action) => _handleMemberAction(
                                  context,
                                  ref,
                                  storeId,
                                  m,
                                  action,
                                ),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'permissions',
                                    child: ListTile(
                                      leading: Icon(Icons.security),
                                      title: Text('Permissions'),
                                      dense: true,
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.person_remove,
                                        color: Colors.red,
                                      ),
                                      title: Text(
                                        'Remove',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      dense: true,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ],
        ),
      ),
    );
  }

  Color _roleColor(StoreRole role) {
    return switch (role) {
      StoreRole.owner => Colors.amber.shade700,
      StoreRole.manager => Colors.blue,
      StoreRole.cashier => Colors.green,
      StoreRole.viewer => Colors.grey,
    };
  }

  void _handleMemberAction(
    BuildContext context,
    WidgetRef ref,
    String storeId,
    StoreMemberModel member,
    String action,
  ) {
    if (action == 'permissions') {
      context.findAncestorStateOfType<NavigatorState>()?.push(
        MaterialPageRoute(
          builder: (_) =>
              _PermissionsEditScreen(storeId: storeId, member: member),
        ),
      );
    } else if (action == 'remove') {
      _confirmRemove(context, ref, storeId, member);
    }
  }

  void _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    String storeId,
    StoreMemberModel member,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove User?'),
        content: Text('Remove ${member.displayName} from this store?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await StoreService.removeMember(
                  storeId: storeId,
                  memberUid: member.uid,
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('User removed')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog(
    BuildContext context,
    WidgetRef ref,
    String storeId,
  ) {
    final membersAsync = ref.read(storeMembersProvider);
    final members = membersAsync.valueOrNull ?? [];
    final nonOwners = members.where((m) => m.role != StoreRole.owner).toList();

    if (nonOwners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other members to transfer to')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer Ownership'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: nonOwners.map((m) {
            return ListTile(
              title: Text(m.displayName),
              subtitle: Text(m.email),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  await StoreService.transferOwnership(
                    storeId: storeId,
                    newOwnerUid: m.uid,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Ownership transferred to ${m.displayName}',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ─── Permissions Edit Screen ───────────────────────────────────

class _PermissionsEditScreen extends ConsumerStatefulWidget {
  final String storeId;
  final StoreMemberModel member;
  const _PermissionsEditScreen({required this.storeId, required this.member});

  @override
  ConsumerState<_PermissionsEditScreen> createState() =>
      _PermissionsEditScreenState();
}

class _PermissionsEditScreenState
    extends ConsumerState<_PermissionsEditScreen> {
  late PermissionsModel _permissions;

  @override
  void initState() {
    super.initState();
    _permissions = widget.member.permissions;
  }

  Future<void> _save() async {
    try {
      await StoreService.updateMemberRole(
        storeId: widget.storeId,
        memberUid: widget.member.uid,
        newRole: widget.member.role,
        permissions: _permissions,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permissions updated'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Permissions — ${widget.member.displayName}'),
        actions: [
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: PermissionsModel.moduleNames.map((module) {
            final perm = _permissions.forModule(module);
            final label = PermissionsModel.moduleLabels[module] ?? module;

            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _permCheckbox('View', perm.view, (v) {
                          setState(() {
                            _permissions = _permissions.copyWithModule(
                              module,
                              perm.copyWith(view: v),
                            );
                          });
                        }),
                        _permCheckbox('Create', perm.create, (v) {
                          setState(() {
                            _permissions = _permissions.copyWithModule(
                              module,
                              perm.copyWith(create: v),
                            );
                          });
                        }),
                        _permCheckbox('Edit', perm.edit, (v) {
                          setState(() {
                            _permissions = _permissions.copyWithModule(
                              module,
                              perm.copyWith(edit: v),
                            );
                          });
                        }),
                        _permCheckbox('Delete', perm.delete, (v) {
                          setState(() {
                            _permissions = _permissions.copyWithModule(
                              module,
                              perm.copyWith(delete: v),
                            );
                          });
                        }),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _permCheckbox(String label, bool value, ValueChanged<bool> onChanged) {
    return Expanded(
      child: CheckboxListTile(
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
