import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/providers/store_provider.dart';

/// Permission action types
enum PermAction { view, create, edit, delete }

/// Check if the current user can perform [action] on [module].
/// Returns true for owners (always full access).
bool canDo(WidgetRef ref, String module, PermAction action) {
  final role = ref.read(myRoleProvider);
  if (role == StoreRole.owner) return true;

  final perms = ref.read(myPermissionsProvider);
  final modulePerm = perms.forModule(module);
  return switch (action) {
    PermAction.view => modulePerm.view,
    PermAction.create => modulePerm.create,
    PermAction.edit => modulePerm.edit,
    PermAction.delete => modulePerm.delete,
  };
}

/// Check if the current user can view a module (for sidebar visibility).
bool canView(WidgetRef ref, String module) {
  return canDo(ref, module, PermAction.view);
}

/// Guard an action — if permitted, runs [onAllowed]. Otherwise shows a popup.
/// Returns true if the action was allowed.
bool guardAction(
  BuildContext context,
  WidgetRef ref,
  String module,
  PermAction action, {
  VoidCallback? onAllowed,
}) {
  if (canDo(ref, module, action)) {
    onAllowed?.call();
    return true;
  }
  _showPermissionDenied(context, module, action);
  return false;
}

/// Show "Permission Denied" popup
void _showPermissionDenied(
  BuildContext context,
  String module,
  PermAction action,
) {
  final moduleLabel = PermissionsModel.moduleLabels[module] ?? module;
  final actionLabel = switch (action) {
    PermAction.view => 'view',
    PermAction.create => 'create',
    PermAction.edit => 'edit',
    PermAction.delete => 'delete',
  };

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      icon: const Icon(Icons.lock, size: 48, color: Colors.orange),
      title: const Text('Permission Denied'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "You don't have permission to $actionLabel in $moduleLabel.",
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Contact your store owner to update your permissions.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
