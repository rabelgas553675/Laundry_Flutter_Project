import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/service_item_model.dart';

/// PART 1 — raw Firestore access for a service's per-item catalog,
/// stored at the `services/{serviceId}/items` subcollection (see
/// [ServiceItemModel]'s class doc comment). No business rules here —
/// just reads/writes, same split as ServiceDatasource/ServiceRepository
/// and LaundryItemDatasource/LaundryItemRepository.
class ServiceItemDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> _itemsRef(String serviceId) =>
      FirebaseService.firestore.collection('services').doc(serviceId).collection('items');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  /// NOTE: sorts client-side rather than chaining `.orderBy('sortOrder')`
  /// onto `.where('isActive', ...)` — same composite-index avoidance
  /// reasoning as ServiceDatasource.getActiveServices /
  /// LaundryItemDatasource.getActiveItems.
  Future<List<ServiceItemModel>> getActiveItems(String serviceId) async {
    final snapshot = await _itemsRef(serviceId)
        .where('isActive', isEqualTo: true)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading items'));

    final items = snapshot.docs.map(ServiceItemModel.fromFirestore).toList();
    items.sort(_bySortOrder);
    return items;
  }

  /// Reserved for future Admin catalog management, which will need
  /// inactive items too (to reactivate them) — same reasoning as
  /// ServiceDatasource.getAllServices.
  Future<List<ServiceItemModel>> getAllItems(String serviceId) async {
    final snapshot = await _itemsRef(serviceId)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading items'));

    final items = snapshot.docs.map(ServiceItemModel.fromFirestore).toList();
    items.sort(_bySortOrder);
    return items;
  }

  int _bySortOrder(ServiceItemModel a, ServiceItemModel b) {
    final bySort = a.sortOrder.compareTo(b.sortOrder);
    if (bySort != 0) return bySort;
    return a.name.compareTo(b.name);
  }

  Future<int> countAll(String serviceId) async {
    final agg = await _itemsRef(serviceId)
        .count()
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking items'));
    return agg.count ?? 0;
  }

  Future<void> createItem(ServiceItemModel item) {
    return _itemsRef(item.serviceId)
        .doc(item.id.isEmpty ? null : item.id)
        .set(item.toMapForCreate())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the item'));
  }

  /// Batch-writes a service's default catalog in one round trip —
  /// mirrors ServiceDatasource.seedDefaults / LaundryItemDatasource.seedDefaults.
  Future<void> seedDefaults(String serviceId, List<ServiceItemModel> defaults) async {
    if (defaults.isEmpty) return;
    final batch = FirebaseService.firestore.batch();
    for (final item in defaults) {
      batch.set(_itemsRef(serviceId).doc(), item.toMapForCreate());
    }
    await batch
        .commit()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('seeding default items'));
  }

  Future<void> updateItemFields(String serviceId, String id, Map<String, dynamic> fields) {
    return _itemsRef(serviceId)
        .doc(id)
        .update(fields)
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the item'));
  }
}