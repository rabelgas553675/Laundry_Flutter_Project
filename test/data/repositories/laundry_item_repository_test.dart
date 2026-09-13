import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/data/datasources/laundry_item_datasource.dart';
import 'package:laundry_flutter/data/repositories/laundry_item_repository.dart';
import 'package:laundry_flutter/models/laundry_item_model.dart';

/// Fake that never touches Firestore — just returns/queues canned
/// data so the repository's caching/seeding LOGIC can be verified in
/// isolation, same spirit as your integration_test file testing real
/// behavior end-to-end while this tests the unit in between.
class _FakeLaundryItemDatasource implements LaundryItemDatasource {
  _FakeLaundryItemDatasource({this.existingCount = 0, List<LaundryItemModel>? items})
      : _items = items ?? const [];

  int existingCount;
  List<LaundryItemModel> _items;

  int getActiveItemsCallCount = 0;
  int seedDefaultsCallCount = 0;
  List<LaundryItemModel>? lastSeeded;

  @override
  Future<List<LaundryItemModel>> getActiveItems() async {
    getActiveItemsCallCount++;
    return _items;
  }

  @override
  Future<List<LaundryItemModel>> getAllItems() async => _items;

  @override
  Future<int> countAll() async => existingCount;

  @override
  Future<void> createItem(LaundryItemModel item) async {
    _items = [..._items, item];
  }

  @override
  Future<void> seedDefaults(List<LaundryItemModel> defaults) async {
    seedDefaultsCallCount++;
    lastSeeded = defaults;
    existingCount = defaults.length;
    _items = defaults
        .asMap()
        .entries
        .map((e) => LaundryItemModel(id: 'seed-${e.key}', name: e.value.name))
        .toList();
  }

  @override
  Future<void> updateItemFields(String id, Map<String, dynamic> fields) async {}
}

void main() {
  group('LaundryItemRepository', () {
    test('getActiveItems caches results — datasource is hit only once', () async {
      final fake = _FakeLaundryItemDatasource(
        items: const [LaundryItemModel(id: '1', name: 'Clothes')],
      );
      final repo = LaundryItemRepository(datasource: fake);

      await repo.getActiveItems();
      await repo.getActiveItems();

      expect(fake.getActiveItemsCallCount, 1);
    });

    test('forceRefresh bypasses the cache', () async {
      final fake = _FakeLaundryItemDatasource(
        items: const [LaundryItemModel(id: '1', name: 'Clothes')],
      );
      final repo = LaundryItemRepository(datasource: fake);

      await repo.getActiveItems();
      await repo.getActiveItems(forceRefresh: true);

      expect(fake.getActiveItemsCallCount, 2);
    });

    test('clearCache forces the next call to hit the datasource again', () async {
      final fake = _FakeLaundryItemDatasource(
        items: const [LaundryItemModel(id: '1', name: 'Clothes')],
      );
      final repo = LaundryItemRepository(datasource: fake);

      await repo.getActiveItems();
      repo.clearCache();
      await repo.getActiveItems();

      expect(fake.getActiveItemsCallCount, 2);
    });

    test('seedDefaultItemsIfEmpty seeds all 4 defaults when collection is empty', () async {
      final fake = _FakeLaundryItemDatasource(existingCount: 0);
      final repo = LaundryItemRepository(datasource: fake);

      await repo.seedDefaultItemsIfEmpty();

      expect(fake.seedDefaultsCallCount, 1);
      expect(fake.lastSeeded?.length, 4);
      expect(
        fake.lastSeeded?.map((i) => i.name).toList(),
        ['Clothes', 'Bedsheets', 'Blankets', 'Towels'],
      );
    });

    test('seedDefaultItemsIfEmpty is a no-op when items already exist', () async {
      final fake = _FakeLaundryItemDatasource(existingCount: 4);
      final repo = LaundryItemRepository(datasource: fake);

      await repo.seedDefaultItemsIfEmpty();

      expect(fake.seedDefaultsCallCount, 0);
    });

    test('seedDefaultItemsIfEmpty never duplicates on repeated calls (idempotent)', () async {
      final fake = _FakeLaundryItemDatasource(existingCount: 0);
      final repo = LaundryItemRepository(datasource: fake);

      await repo.seedDefaultItemsIfEmpty(); // seeds
      await repo.seedDefaultItemsIfEmpty(); // should skip — existingCount is now 4

      expect(fake.seedDefaultsCallCount, 1);
    });
  });
}