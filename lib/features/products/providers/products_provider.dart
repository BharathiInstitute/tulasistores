/// Products provider for CRUD operations (Firestore-based with offline support)
/// Supports demo mode with local in-memory data
library;

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retaillite/core/constants/app_constants.dart';
import 'package:retaillite/core/utils/id_generator.dart';
import 'package:retaillite/core/services/user_metrics_service.dart';
import 'package:retaillite/core/services/demo_data_service.dart';
import 'package:retaillite/core/services/performance_service.dart';
import 'package:retaillite/core/services/sync_status_service.dart';
import 'package:retaillite/features/auth/providers/auth_provider.dart';
import 'package:retaillite/models/product_model.dart';

/// Firestore instance (Firebase singletons — safe as top-level)
final _firestore = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

/// Get user's products collection path.
/// Throws if no user is signed in to prevent accidental writes to a
/// global 'products' collection.
String get _productsPath {
  final uid = _auth.currentUser?.uid;
  if (uid == null) {
    throw StateError('Cannot access products: no user signed in');
  }
  return 'users/$uid/products';
}

/// Products list provider - reads from Firestore OR demo data
/// Per-product sync status cache — updated by productsProvider
Map<String, bool> _lastProductSyncStatus = {};

final productsProvider = StreamProvider.autoDispose<List<ProductModel>>((ref) {
  final isDemoMode = ref.watch(isDemoModeProvider);

  // Demo mode: return local demo data as a stream
  if (isDemoMode) {
    debugPrint('📦 productsProvider: Demo mode - returning local data');
    _lastProductSyncStatus = {};
    return Stream.value(DemoDataService.getProducts().toList());
  }

  // Firebase mode: stream from Firestore
  // Safety cap at 2000 products to prevent massive reads if a user
  // accidentally imports a huge inventory
  debugPrint('📦 productsProvider: Listening to Firestore products...');
  return _firestore
      .collection(_productsPath)
      .orderBy('name')
      .limit(AppConstants.queryLimitProducts)
      .snapshots()
      .map((snapshot) {
        final products = snapshot.docs
            .map((doc) => ProductModel.fromFirestore(doc))
            .toList();
        // Report sync status
        final pendingCount = snapshot.docs
            .where((d) => d.metadata.hasPendingWrites)
            .length;
        SyncStatusService.updateCollection(
          'products',
          totalDocs: products.length,
          unsyncedDocs: pendingCount,
          hasPendingWrites: snapshot.metadata.hasPendingWrites,
        );
        // Cache per-product sync status for productsSyncStatusProvider
        _lastProductSyncStatus = {
          for (final doc in snapshot.docs)
            doc.id: doc.metadata.hasPendingWrites,
        };
        if (products.length >= 1000) {
          debugPrint(
            '⚠️ productsProvider: Large inventory (${products.length} products) — '
            'consider pagination for better performance',
          );
        }
        debugPrint('📦 productsProvider: Got ${products.length} products');
        return products;
      });
});

/// Paginated products fetch — returns (products, lastDocument) for cursor pagination.
Future<(List<ProductModel>, DocumentSnapshot?)> fetchProductsPage({
  int pageSize = 50,
  DocumentSnapshot? startAfter,
}) async {
  var query = _firestore
      .collection(_productsPath)
      .orderBy('name')
      .limit(pageSize);
  if (startAfter != null) query = query.startAfterDocument(startAfter);
  final snap = await query.get();
  final products = snap.docs.map((d) => ProductModel.fromFirestore(d)).toList();
  final lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
  return (products, lastDoc);
}

/// Per-product sync status — derived from productsProvider snapshot data
/// (no extra Firestore listener)
final productsSyncStatusProvider =
    Provider.autoDispose<AsyncValue<Map<String, bool>>>((ref) {
      // Watch productsProvider to ensure sync status cache is up-to-date
      final productsAsync = ref.watch(productsProvider);
      return productsAsync.whenData((_) => _lastProductSyncStatus);
    });

/// Single product by ID — uses dedicated Firestore document stream
/// to avoid watching the entire products collection.
final productByIdProvider = StreamProvider.autoDispose
    .family<ProductModel?, String>((ref, id) {
      final isDemoMode = ref.watch(isDemoModeProvider);

      if (isDemoMode) {
        final products = DemoDataService.getProducts();
        final match = products.where((p) => p.id == id).firstOrNull;
        return Stream.value(match);
      }

      try {
        return _firestore
            .collection(_productsPath)
            .doc(id)
            .snapshots()
            .map((doc) => doc.exists ? ProductModel.fromFirestore(doc) : null);
      } catch (e) {
        // Fallback: derive from cached productsProvider
        final productsAsync = ref.watch(productsProvider);
        return productsAsync.when(
          data: (products) =>
              Stream.value(products.where((p) => p.id == id).firstOrNull),
          loading: () => const Stream.empty(),
          error: (e, _) => Stream.error(e),
        );
      }
    });

/// Low stock products provider
final lowStockProductsProvider = Provider<List<ProductModel>>((ref) {
  final products = ref.watch(productsProvider);
  return products.when(
    data: (list) => list.where((p) => p.isLowStock || p.isOutOfStock).toList(),
    loading: () => [],
    error: (e, _) => [],
  );
});

/// Products service for CRUD operations
/// Automatically routes to demo data or Firestore based on mode
class ProductsService {
  final bool _isDemoMode;
  final CollectionReference? _collection;

  ProductsService({required bool isDemoMode})
    : _isDemoMode = isDemoMode,
      _collection = isDemoMode ? null : _firestore.collection(_productsPath);

  /// Add new product
  Future<String> addProduct(ProductModel product) async {
    if (_isDemoMode) {
      return DemoDataService.addProduct(product);
    }

    final id = generateSafeId('product');
    final newProduct = ProductModel(
      id: id,
      name: product.name,
      price: product.price,
      purchasePrice: product.purchasePrice,
      stock: product.stock,
      lowStockAlert: product.lowStockAlert,
      barcode: product.barcode,
      imageUrl: product.imageUrl,
      category: product.category,
      hsnCode: product.hsnCode,
      unit: product.unit,
      createdAt: DateTime.now(),
    );
    await PerformanceService.trackOperation(
      'addProduct',
      'firestore',
      () async {
        await _collection!.doc(id).set(newProduct.toFirestore());
      },
    );
    unawaited(UserMetricsService.trackProductAdded());
    return id;
  }

  /// Batch-add multiple products using WriteBatch (P14)
  /// More efficient than sequential addProduct calls for CSV/catalog imports.
  /// [onProgress] reports (addedSoFar, total) after each batch commit.
  Future<int> addProductsBatch(
    List<ProductModel> products, {
    void Function(int added, int total)? onProgress,
  }) async {
    if (_isDemoMode) {
      for (final p in products) {
        DemoDataService.addProduct(p);
      }
      onProgress?.call(products.length, products.length);
      return products.length;
    }

    // Firestore batches limited to 500 operations
    const batchLimit = 490;
    int added = 0;
    for (var i = 0; i < products.length; i += batchLimit) {
      final chunk = products.skip(i).take(batchLimit).toList();
      final batch = _firestore.batch();
      for (final product in chunk) {
        final id = generateSafeId('product');
        final newProduct = ProductModel(
          id: id,
          name: product.name,
          price: product.price,
          purchasePrice: product.purchasePrice,
          stock: product.stock,
          lowStockAlert: product.lowStockAlert,
          barcode: product.barcode,
          imageUrl: product.imageUrl,
          category: product.category,
          hsnCode: product.hsnCode,
          unit: product.unit,
          createdAt: DateTime.now(),
        );
        batch.set(_collection!.doc(id), newProduct.toFirestore());
      }
      await batch.commit();
      added += chunk.length;
      onProgress?.call(added, products.length);
    }
    unawaited(UserMetricsService.trackProductAdded());
    return added;
  }

  /// Update product
  Future<void> updateProduct(ProductModel product) async {
    if (_isDemoMode) {
      DemoDataService.updateProduct(product);
      return;
    }
    await PerformanceService.trackOperation(
      'updateProduct',
      'firestore',
      () async {
        await _collection!.doc(product.id).update(product.toFirestore());
      },
    );
  }

  /// Delete product
  Future<void> deleteProduct(String productId) async {
    if (_isDemoMode) {
      DemoDataService.deleteProduct(productId);
      return;
    }
    await PerformanceService.trackOperation(
      'deleteProduct',
      'firestore',
      () async {
        await _collection!.doc(productId).delete();
      },
    );
    unawaited(UserMetricsService.trackProductDeleted());
  }

  /// Update stock
  Future<void> updateStock(String productId, int newStock) async {
    if (_isDemoMode) {
      DemoDataService.updateStock(productId, newStock);
      return;
    }
    final collection = _collection;
    if (collection == null) {
      throw StateError(
        'Firestore collection is not initialized in Firebase mode.',
      );
    }
    await collection.doc(productId).update({'stock': newStock});
  }

  /// Decrement stock (for billing)
  Future<void> decrementStock(String productId, int quantity) async {
    if (_isDemoMode) {
      DemoDataService.decrementStock(productId, quantity);
      return;
    }

    final collection = _collection;
    if (collection == null) {
      throw StateError(
        'Firestore collection is not initialized in Firebase mode.',
      );
    }

    // Use FieldValue.increment for atomic stock decrement — prevents
    // race conditions when two concurrent sales of the same product
    // happen simultaneously.
    await collection.doc(productId).update({
      'stock': FieldValue.increment(-quantity),
    });
  }

  /// Find product by barcode
  Future<ProductModel?> findByBarcode(String barcode) async {
    if (_isDemoMode) {
      return DemoDataService.getProductByBarcode(barcode);
    }

    final snapshot = await _collection!
        .where('barcode', isEqualTo: barcode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return ProductModel.fromFirestore(snapshot.docs.first);
  }
}

/// Products service provider - auto-detects demo mode
final productsServiceProvider = Provider<ProductsService>((ref) {
  final isDemoMode = ref.watch(isDemoModeProvider);
  return ProductsService(isDemoMode: isDemoMode);
});
