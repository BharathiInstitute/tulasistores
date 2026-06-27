/// Granular permission matrix for a store member.
///
/// Each module has 4 permission flags: view, create, edit, delete.
/// Owner always has full permissions (not stored, implied).
class PermissionsModel {
  final ModulePermission dashboard;
  final ModulePermission billing;
  final ModulePermission inventory;
  final ModulePermission customers;
  final ModulePermission bills;
  final ModulePermission staff;
  final ModulePermission vendors;
  final ModulePermission settings;
  final ModulePermission userManagement;

  const PermissionsModel({
    this.dashboard = const ModulePermission.all(),
    this.billing = const ModulePermission.all(),
    this.inventory = const ModulePermission.all(),
    this.customers = const ModulePermission.all(),
    this.bills = const ModulePermission.all(),
    this.staff = const ModulePermission.all(),
    this.vendors = const ModulePermission.all(),
    this.settings = const ModulePermission.none(),
    this.userManagement = const ModulePermission.none(),
  });

  /// Full access (owner)
  const PermissionsModel.owner()
    : dashboard = const ModulePermission.all(),
      billing = const ModulePermission.all(),
      inventory = const ModulePermission.all(),
      customers = const ModulePermission.all(),
      bills = const ModulePermission.all(),
      staff = const ModulePermission.all(),
      vendors = const ModulePermission.all(),
      settings = const ModulePermission.all(),
      userManagement = const ModulePermission.all();

  /// Manager: full access except settings & user management
  const PermissionsModel.manager()
    : dashboard = const ModulePermission.all(),
      billing = const ModulePermission.all(),
      inventory = const ModulePermission.all(),
      customers = const ModulePermission.all(),
      bills = const ModulePermission.all(),
      staff = const ModulePermission.all(),
      vendors = const ModulePermission.all(),
      settings = const ModulePermission(view: true),
      userManagement = const ModulePermission.none();

  /// Cashier: POS + billing + view inventory
  const PermissionsModel.cashier()
    : dashboard = const ModulePermission(view: true),
      billing = const ModulePermission.all(),
      inventory = const ModulePermission(view: true),
      customers = const ModulePermission(view: true, create: true),
      bills = const ModulePermission(view: true),
      staff = const ModulePermission.none(),
      vendors = const ModulePermission.none(),
      settings = const ModulePermission.none(),
      userManagement = const ModulePermission.none();

  /// Viewer: view-only on all modules
  const PermissionsModel.viewer()
    : dashboard = const ModulePermission(view: true),
      billing = const ModulePermission(view: true),
      inventory = const ModulePermission(view: true),
      customers = const ModulePermission(view: true),
      bills = const ModulePermission(view: true),
      staff = const ModulePermission(view: true),
      vendors = const ModulePermission(view: true),
      settings = const ModulePermission(view: true),
      userManagement = const ModulePermission.none();

  factory PermissionsModel.forRole(StoreRole role) {
    return switch (role) {
      StoreRole.owner => const PermissionsModel.owner(),
      StoreRole.manager => const PermissionsModel.manager(),
      StoreRole.cashier => const PermissionsModel.cashier(),
      StoreRole.viewer => const PermissionsModel.viewer(),
    };
  }

  factory PermissionsModel.fromMap(Map<String, dynamic> map) {
    return PermissionsModel(
      dashboard: ModulePermission.fromMap(
        map['dashboard'] as Map<String, dynamic>? ?? {},
      ),
      billing: ModulePermission.fromMap(
        map['billing'] as Map<String, dynamic>? ?? {},
      ),
      inventory: ModulePermission.fromMap(
        map['inventory'] as Map<String, dynamic>? ?? {},
      ),
      customers: ModulePermission.fromMap(
        map['customers'] as Map<String, dynamic>? ?? {},
      ),
      bills: ModulePermission.fromMap(
        map['bills'] as Map<String, dynamic>? ?? {},
      ),
      staff: ModulePermission.fromMap(
        map['staff'] as Map<String, dynamic>? ?? {},
      ),
      vendors: ModulePermission.fromMap(
        map['vendors'] as Map<String, dynamic>? ?? {},
      ),
      settings: ModulePermission.fromMap(
        map['settings'] as Map<String, dynamic>? ?? {},
      ),
      userManagement: ModulePermission.fromMap(
        map['userManagement'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  Map<String, dynamic> toMap() => {
    'dashboard': dashboard.toMap(),
    'billing': billing.toMap(),
    'inventory': inventory.toMap(),
    'customers': customers.toMap(),
    'bills': bills.toMap(),
    'staff': staff.toMap(),
    'vendors': vendors.toMap(),
    'settings': settings.toMap(),
    'userManagement': userManagement.toMap(),
  };

  /// Get permission for a module by name
  ModulePermission forModule(String module) {
    return switch (module) {
      'dashboard' => dashboard,
      'billing' => billing,
      'inventory' => inventory,
      'customers' => customers,
      'bills' => bills,
      'staff' => staff,
      'vendors' => vendors,
      'settings' => settings,
      'userManagement' => userManagement,
      _ => const ModulePermission.none(),
    };
  }

  PermissionsModel copyWithModule(String module, ModulePermission perm) {
    return PermissionsModel(
      dashboard: module == 'dashboard' ? perm : dashboard,
      billing: module == 'billing' ? perm : billing,
      inventory: module == 'inventory' ? perm : inventory,
      customers: module == 'customers' ? perm : customers,
      bills: module == 'bills' ? perm : bills,
      staff: module == 'staff' ? perm : staff,
      vendors: module == 'vendors' ? perm : vendors,
      settings: module == 'settings' ? perm : settings,
      userManagement: module == 'userManagement' ? perm : userManagement,
    );
  }

  /// All module names for iteration
  static const List<String> moduleNames = [
    'dashboard',
    'billing',
    'inventory',
    'customers',
    'bills',
    'staff',
    'vendors',
    'settings',
    'userManagement',
  ];

  /// Display labels for modules
  static const Map<String, String> moduleLabels = {
    'dashboard': 'Dashboard',
    'billing': 'POS / Billing',
    'inventory': 'Inventory (Products)',
    'customers': 'Khata / Customers',
    'bills': 'Bills History',
    'staff': 'Staff',
    'vendors': 'Vendors',
    'settings': 'Settings',
    'userManagement': 'User Management',
  };
}

/// Permission flags for a single module
class ModulePermission {
  final bool view;
  final bool create;
  final bool edit;
  final bool delete;

  const ModulePermission({
    this.view = false,
    this.create = false,
    this.edit = false,
    this.delete = false,
  });

  const ModulePermission.all()
    : view = true,
      create = true,
      edit = true,
      delete = true;

  const ModulePermission.none()
    : view = false,
      create = false,
      edit = false,
      delete = false;

  factory ModulePermission.fromMap(Map<String, dynamic> map) {
    return ModulePermission(
      view: (map['view'] as bool?) ?? false,
      create: (map['create'] as bool?) ?? false,
      edit: (map['edit'] as bool?) ?? false,
      delete: (map['delete'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'view': view,
    'create': create,
    'edit': edit,
    'delete': delete,
  };

  ModulePermission copyWith({
    bool? view,
    bool? create,
    bool? edit,
    bool? delete,
  }) {
    return ModulePermission(
      view: view ?? this.view,
      create: create ?? this.create,
      edit: edit ?? this.edit,
      delete: delete ?? this.delete,
    );
  }

  bool get hasAny => view || create || edit || delete;
}

/// Roles a user can have in a store
enum StoreRole {
  owner('Owner'),
  manager('Manager'),
  cashier('Cashier'),
  viewer('Viewer');

  final String displayName;
  const StoreRole(this.displayName);

  static StoreRole fromString(String value) {
    return StoreRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => StoreRole.viewer,
    );
  }
}
