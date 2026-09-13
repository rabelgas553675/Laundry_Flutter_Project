import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/data/datasources/detergent_datasource.dart';
import 'package:laundry_flutter/data/repositories/detergent_repository.dart';
import 'package:laundry_flutter/models/detergent_model.dart';

class _FakeDetergentDatasource implements DetergentDatasource {
  _FakeDetergentDatasource({this.existingCount = 0, List<DetergentModel>? detergents})
      : _detergents = detergents ?? const [];

  int existingCount;
  List<DetergentModel> _detergents;

  int getActiveDetergentsCallCount = 0;
  int seedDefaultsCallCount = 0;
  List<DetergentModel>? lastSeeded;

  @override
  Future<List<DetergentModel>> getActiveDetergents() async {
    getActiveDetergentsCallCount++;
    return _detergents;
  }

  @override
  Future<List<DetergentModel>> getAllDetergents() async => _detergents;

  @override
  Future<int> countAll() async => existingCount;

  @override
  Future<void> createDetergent(DetergentModel detergent) async {
    _detergents = [..._detergents, detergent];
  }

  @override
  Future<void> seedDefaults(List<DetergentModel> defaults) async {
    seedDefaultsCallCount++;
    lastSeeded = defaults;
    existingCount = defaults.length;
    _detergents = defaults
        .asMap()
        .entries
        .map((e) => LaundryDetergentSeed(e.key, e.value).toModel())
        .toList();
  }

  @override
  Future<void> updateDetergentFields(String id, Map<String, dynamic> fields) async {}
}

/// Tiny helper so seeded fakes get a stable id, keeping the
/// additionalPrice from the original default intact for assertions.
class LaundryDetergentSeed {
  LaundryDetergentSeed(this.index, this.source);
  final int index;
  final DetergentModel source;

  DetergentModel toModel() => DetergentModel(
        id: 'seed-$index',
        name: source.name,
        additionalPrice: source.additionalPrice,
      );
}

void main() {
  group('DetergentRepository', () {
    test('getActiveDetergents caches results', () async {
      final fake = _FakeDetergentDatasource(
        detergents: const [DetergentModel(id: '1', name: 'Regular', additionalPrice: 0)],
      );
      final repo = DetergentRepository(datasource: fake);

      await repo.getActiveDetergents();
      await repo.getActiveDetergents();

      expect(fake.getActiveDetergentsCallCount, 1);
    });

    test('seedDefaultDetergentsIfEmpty seeds Regular, Premium, Hypoallergenic with correct prices', () async {
      final fake = _FakeDetergentDatasource(existingCount: 0);
      final repo = DetergentRepository(datasource: fake);

      await repo.seedDefaultDetergentsIfEmpty();

      expect(fake.seedDefaultsCallCount, 1);
      final seeded = fake.lastSeeded!;
      expect(seeded.map((d) => d.name).toList(), ['Regular', 'Premium', 'Hypoallergenic']);
      expect(seeded.map((d) => d.additionalPrice).toList(), [0, 30, 50]);
    });

    test('seedDefaultDetergentsIfEmpty is a no-op when detergents already exist', () async {
      final fake = _FakeDetergentDatasource(existingCount: 3);
      final repo = DetergentRepository(datasource: fake);

      await repo.seedDefaultDetergentsIfEmpty();

      expect(fake.seedDefaultsCallCount, 0);
    });

    test('after seeding, getActiveDetergents reflects seeded prices', () async {
      final fake = _FakeDetergentDatasource(existingCount: 0);
      final repo = DetergentRepository(datasource: fake);

      await repo.seedDefaultDetergentsIfEmpty();
      final active = await repo.getActiveDetergents(forceRefresh: true);

      final premium = active.firstWhere((d) => d.name == 'Premium');
      expect(premium.additionalPrice, 30);
    });
  });
}