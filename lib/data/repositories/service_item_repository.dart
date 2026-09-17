import 'package:flutter/foundation.dart';

import '../datasources/service_item_datasource.dart';
import '../../models/service_item_model.dart';
import '../../models/service_model.dart';

/// PART 1 — business rules on top of [ServiceItemDatasource] for a
/// service's per-item catalog (currently only Dry Cleaning's garment
/// price list — see [ServiceType.isItemized]). Same repository/
/// datasource split as every other catalog in this project
/// (ServiceRepository, LaundryItemRepository, DetergentRepository).
class ServiceItemRepository {
  ServiceItemRepository({ServiceItemDatasource? datasource})
      : _datasource = datasource ?? ServiceItemDatasource();

  final ServiceItemDatasource _datasource;

  /// Session cache keyed by serviceId — avoids re-fetching the same
  /// short, rarely-changing catalog on every rebuild of the order
  /// form (PART 2). Cleared via [clearCache].
  final Map<String, List<ServiceItemModel>> _cachedActiveByService = {};

  Future<List<ServiceItemModel>> getActiveItems(
    String serviceId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedActiveByService.containsKey(serviceId)) {
      return _cachedActiveByService[serviceId]!;
    }
    final items = await _datasource.getActiveItems(serviceId);
    _cachedActiveByService[serviceId] = items;
    return items;
  }

  Future<List<ServiceItemModel>> getAllItems(String serviceId) {
    return _datasource.getAllItems(serviceId);
  }

  /// Idempotent: only writes [kDryCleaningDefaultCatalog] /
  /// [kWashAndIroningDefaultCatalog] the very first time a given
  /// service has zero item documents, so re-running the app never
  /// duplicates the catalog. Safe to call from a widget's build path
  /// — same pattern as LaundryItemRepository.seedDefaultItemsIfEmpty
  /// and ServiceRepository.seedDefaultServicesIfEmpty.
  ///
  /// Does nothing for a service whose [ServiceType] has no default
  /// catalog (only Dry Cleaning and Wash & Ironing do — see PART 1's
  /// two default maps in `service_item_model.dart`).
  Future<void> seedDefaultItemsIfEmpty(String serviceId, ServiceType serviceType) async {
    final defaults = _defaultCatalogFor(serviceType);
    if (defaults.isEmpty) return;

    final existing = await _datasource.countAll(serviceId);
    if (existing > 0) return;

    try {
      final entries = defaults.entries.toList();
      final items = [
        for (var i = 0; i < entries.length; i++)
          ServiceItemModel(
            id: '',
            serviceId: serviceId,
            serviceType: serviceType,
            name: entries[i].key,
            price: entries[i].value,
            sortOrder: i,
          ),
      ];
      await _datasource.seedDefaults(serviceId, items);
      _cachedActiveByService.remove(serviceId); // force a fresh read next call
    } catch (e, stackTrace) {
      // Best-effort, same reasoning as ServiceRepository.seedDefaultServicesIfEmpty
      // — firestore.rules only allows admins to write the catalog, so a
      // regular customer's seed attempt is expected to fail with
      // permission-denied on a fresh project until an admin has opened
      // the order screen (or seeded it manually) at least once.
      debugPrint('ServiceItemRepository: seeding default items skipped: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Map<String, double> _defaultCatalogFor(ServiceType serviceType) {
    switch (serviceType) {
      case ServiceType.dryCleaning:
        return kDryCleaningDefaultCatalog;
      case ServiceType.washAndIroning:
        return kWashAndIroningDefaultCatalog;
      case ServiceType.quickWash:
      case ServiceType.standardWash:
      case ServiceType.premiumWash:
        return const {};
    }
  }

  Future<void> createItem(ServiceItemModel item) async {
    await _datasource.createItem(item);
    _cachedActiveByService.remove(item.serviceId);
  }

  Future<void> updateItem(ServiceItemModel updated) async {
    await _datasource.updateItemFields(updated.serviceId, updated.id, updated.toEditableMap());
    _cachedActiveByService.remove(updated.serviceId);
  }

  void clearCache() {
    _cachedActiveByService.clear();
  }
}