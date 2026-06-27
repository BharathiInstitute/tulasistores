import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:retaillite/features/store/models/permissions_model.dart';
import 'package:retaillite/features/store/models/store_member_model.dart';
import 'package:retaillite/features/store/models/store_model.dart';

class StoreService {
  StoreService._();

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static final _functions = FirebaseFunctions.instanceFor(
    region: 'asia-south1',
  );

  // ─── Store CRUD ──────────────────────────────────────────────

  /// Create a new store and set the current user as owner.
  static Future<String> createStore({
    required String shopName,
    String? address,
    String? gstNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final storeRef = _firestore.collection('stores').doc();
    final storeId = storeRef.id;
    final now = DateTime.now();

    // Step 1: Create store document first
    // Rule: allow create: if isAuthenticated()
    final store = StoreModel(
      id: storeId,
      shopName: shopName,
      ownerUid: user.uid,
      ownerName: user.displayName ?? '',
      ownerEmail: user.email ?? '',
      address: address,
      gstNumber: gstNumber,
      createdAt: now,
    );
    await storeRef.set(store.toFirestore());

    // Step 2: Add owner as member — store doc now exists so get() in rule works
    // Rule: allow create: if auth.uid==memberUid && role=='owner'
    //       && get(stores/{id}).data.ownerUid == auth.uid
    final member = StoreMemberModel(
      uid: user.uid,
      displayName: user.displayName ?? '',
      email: user.email ?? '',
      role: StoreRole.owner,
      permissions: const PermissionsModel.owner(),
      joinedAt: now,
    );
    await storeRef
        .collection('members')
        .doc(user.uid)
        .set(member.toFirestore());

    // Step 3: Add store ref under user's stores
    await _firestore
        .doc('users/${user.uid}/stores/$storeId')
        .set(
          UserStoreRef(
            storeId: storeId,
            shopName: shopName,
            role: StoreRole.owner,
          ).toFirestore(),
        );

    // Step 4: Initialize empty subcollections with seed documents
    await _initializeStoreCollections(storeRef, shopName);

    debugPrint('\u2705 Store created: $storeId ($shopName)');
    return storeId;
  }

  /// Seed all required subcollections for a newly created store.
  ///
  /// Firestore collections only exist when they contain at least one
  /// document, so we create a lightweight `_init` doc in each one.
  /// The billing counter is seeded with `lastBillNumber: 0` so the
  /// bill-numbering logic works from the start.
  static Future<void> _initializeStoreCollections(
    DocumentReference storeRef,
    String shopName,
  ) async {
    final now = FieldValue.serverTimestamp();

    // Batch 1: core data collections
    final batch1 = _firestore.batch();
    batch1.set(storeRef.collection('counters').doc('billing'), {
      'lastBillNumber': 0,
      'prefix': '',
      'createdAt': now,
    });
    batch1.set(storeRef.collection('products').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch1.set(storeRef.collection('customers').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch1.set(storeRef.collection('bills').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch1.set(storeRef.collection('vendors').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    await batch1.commit();

    // Batch 2: operational collections
    final batch2 = _firestore.batch();
    batch2.set(storeRef.collection('staff').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch2.set(storeRef.collection('expenses').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch2.set(storeRef.collection('transactions').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch2.set(storeRef.collection('notifications').doc('_init'), {
      '_placeholder': true,
      'createdAt': now,
    });
    batch2.set(storeRef.collection('settings').doc('store'), {
      'shopName': shopName,
      'createdAt': now,
    });
    await batch2.commit();
  }

  /// Stream of stores the current user has access to.
  static Stream<List<UserStoreRef>> myStoresStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value([]);
    return _firestore
        .collection('users/$uid/stores')
        .snapshots()
        .map((snap) => snap.docs.map(UserStoreRef.fromFirestore).toList());
  }

  /// Ensures the current user has a default store.
  ///
  /// Uses the user's UID as the store ID so [ActiveStore.basePath] maps it to
  /// the existing `users/{uid}` Firestore path — no data migration required.
  ///
  /// Uses sequential writes (not a batch) so each Firestore security rule
  /// evaluates the already-committed state of prior writes.
  static Future<String> ensureDefaultStore() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final storeId = user.uid; // UID == storeId for backward compat

    // Existence check via user's own store ref — always readable by owner,
    // no circular member-check dependency.
    final userStoreRefDoc = await _firestore
        .doc('users/${user.uid}/stores/$storeId')
        .get();
    if (userStoreRefDoc.exists) return storeId;

    // Fetch shop name from user profile document
    String shopName =
        user.displayName ?? user.email?.split('@').first ?? 'My Store';
    try {
      final userDoc = await _firestore.doc('users/${user.uid}').get();
      if (userDoc.exists) {
        final data = userDoc.data() as Map<String, dynamic>;
        shopName = (data['shopName'] as String?) ?? shopName;
      }
    } catch (_) {}

    final now = DateTime.now();
    final store = StoreModel(
      id: storeId,
      shopName: shopName,
      ownerUid: user.uid,
      ownerName: user.displayName ?? '',
      ownerEmail: user.email ?? '',
      createdAt: now,
    );
    final member = StoreMemberModel(
      uid: user.uid,
      displayName: user.displayName ?? '',
      email: user.email ?? '',
      role: StoreRole.owner,
      permissions: const PermissionsModel.owner(),
      joinedAt: now,
    );

    // Step 1: Create store document.
    // Rule: allow create: if isAuthenticated()  (always allowed)
    // If partial init left the doc already created, the update rule
    // allows it via resource.data.ownerUid == request.auth.uid.
    await _firestore
        .doc('stores/$storeId')
        .set(store.toFirestore(), SetOptions(merge: false))
        .catchError((Object e) async {
          // Doc already exists from a previous partial init — update instead
          if (e is FirebaseException && e.code == 'permission-denied') {
            await _firestore
                .doc('stores/$storeId')
                .set(store.toFirestore(), SetOptions(merge: true));
          } else {
            throw e;
          }
        });

    // Step 2: Create member doc — store now exists, so rule's get() resolves.
    // Rule: allow create: if auth.uid==memberUid && role=='owner'
    //       && get(stores/{storeId}).data.ownerUid == auth.uid
    await _firestore
        .doc('stores/$storeId/members/${user.uid}')
        .set(member.toFirestore());

    // Step 3: Create user store ref — marks initialization complete.
    // Rule: allow write: if isAuthenticated() && isOwner(userId)
    await _firestore
        .doc('users/${user.uid}/stores/$storeId')
        .set(
          UserStoreRef(
            storeId: storeId,
            shopName: shopName,
            role: StoreRole.owner,
          ).toFirestore(),
        );

    debugPrint('✅ Default store initialized: $storeId ($shopName)');
    return storeId;
  }

  /// Get a single store
  static Future<StoreModel?> getStore(String storeId) async {
    final doc = await _firestore.doc('stores/$storeId').get();
    if (!doc.exists) return null;
    return StoreModel.fromFirestore(doc);
  }

  // ─── Members ─────────────────────────────────────────────────

  /// Add a user to a store (calls Cloud Function to create Firebase Auth user if needed)
  static Future<void> addMember({
    required String storeId,
    required String email,
    required String displayName,
    required String password,
    required StoreRole role,
    PermissionsModel? permissions,
  }) async {
    final callable = _functions.httpsCallable('createStoreUser');
    await callable.call<Map<String, dynamic>>({
      'storeId': storeId,
      'email': email,
      'displayName': displayName,
      'password': password,
      'role': role.name,
      'permissions': (permissions ?? PermissionsModel.forRole(role)).toMap(),
    });
  }

  /// Stream all members of a store
  static Stream<List<StoreMemberModel>> membersStream(String storeId) {
    return _firestore
        .collection('stores/$storeId/members')
        .snapshots()
        .map((snap) => snap.docs.map(StoreMemberModel.fromFirestore).toList());
  }

  /// Update a member's role and permissions
  static Future<void> updateMemberRole({
    required String storeId,
    required String memberUid,
    required StoreRole newRole,
    required PermissionsModel permissions,
  }) async {
    // Update in store's members (owner has write access)
    await _firestore.doc('stores/$storeId/members/$memberUid').update({
      'role': newRole.name,
      'permissions': permissions.toMap(),
    });
  }

  /// Update a single module permission for a member
  static Future<void> updateMemberPermission({
    required String storeId,
    required String memberUid,
    required String module,
    required ModulePermission permission,
  }) async {
    await _firestore.doc('stores/$storeId/members/$memberUid').update({
      'permissions.$module': permission.toMap(),
    });
  }

  /// Remove a member from a store
  static Future<void> removeMember({
    required String storeId,
    required String memberUid,
  }) async {
    final callable = _functions.httpsCallable('removeStoreUser');
    await callable.call<Map<String, dynamic>>({
      'storeId': storeId,
      'memberUid': memberUid,
    });
  }

  /// Transfer store ownership to another member
  static Future<void> transferOwnership({
    required String storeId,
    required String newOwnerUid,
  }) async {
    final callable = _functions.httpsCallable('transferStoreOwnership');
    await callable.call<Map<String, dynamic>>({
      'storeId': storeId,
      'newOwnerUid': newOwnerUid,
    });
  }

  // ─── Permissions ─────────────────────────────────────────────

  /// Get current user's permissions for a store
  static Future<StoreMemberModel?> getMyMembership(String storeId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _firestore.doc('stores/$storeId/members/$uid').get();
    if (!doc.exists) return null;
    return StoreMemberModel.fromFirestore(doc);
  }

  /// Check if current user has a specific permission
  static Future<bool> hasPermission(
    String storeId,
    String module,
    String action,
  ) async {
    final member = await getMyMembership(storeId);
    if (member == null) return false;
    if (member.role == StoreRole.owner) return true;

    final perm = member.permissions.forModule(module);
    return switch (action) {
      'view' => perm.view,
      'create' => perm.create,
      'edit' => perm.edit,
      'delete' => perm.delete,
      _ => false,
    };
  }
}
