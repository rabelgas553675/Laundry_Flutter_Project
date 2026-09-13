import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/laundry_item_model.dart';

/// Raw Firestore access for the `laundryItems` collection.
/// No business rules here — just reads/writes, same split as
/// ServiceDatasource/ServiceRepository.
class LaundryItemDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _itemsRef =>
      FirebaseService.firestore.collection('laundryItems');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  /// NOTE: Sorts client-side rather than via `.orderBy('createdAt')`
  /// chained onto `.where('status', ...)`. That combination requires
  /// a Firestore composite index that doesn't exist yet, and throws
  /// `failed-precondition` until it's created. Same fix as
  /// ServiceDatasource.getActiveServices.
  Future<List<LaundryItemModel>> getActiveItems() async {
    final snapshot = await _itemsRef
        .where('status', isEqualTo: LaundryItemStatus.active.value)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading laundry items'));

    final items = snapshot.docs.map(LaundryItemModel.fromFirestore).toList();
    items.sort(_byCreatedAt);
    return items;
  }

  /// Reserved for future Admin laundry-item management, which will
  /// need inactive items too (to reactivate them) — same reasoning as
  /// ServiceDatasource.getAllServices.
  Future<List<LaundryItemModel>> getAllItems() async {
    final snapshot = await _itemsRef
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading laundry items'));

    final items = snapshot.docs.map(LaundryItemModel.fromFirestore).toList();
    items.sort(_byCreatedAt);
    return items;
  }

  int _byCreatedAt(LaundryItemModel a, LaundryItemModel b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  }

  Future<int> countAll() async {
    final agg = await _itemsRef
        .count()
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking laundry items'));
    return agg.count ?? 0;
  }

  Future<void> createItem(LaundryItemModel item) {
    return _itemsRef
        .doc(item.id.isEmpty ? null : item.id)
        .set(item.toMapForCreate())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the laundry item'));
  }

  /// Batch-writes the PART 09 default catalog (Clothes, Bedsheets,
  /// Blankets, Towels) in one round trip — mirrors
  /// ServiceDatasource.seedDefaults.
  Future<void> seedDefaults(List<LaundryItemModel> defaults) async {
    final batch = FirebaseService.firestore.batch();
    for (final item in defaults) {
      batch.set(_itemsRef.doc(), item.toMapForCreate());
    }
    await batch
        .commit()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('seeding default laundry items'));
  }

  Future<void> updateItemFields(String id, Map<String, dynamic> fields) {
    return _itemsRef
        .doc(id)
        .update(fields)
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the laundry item'));
  }
}