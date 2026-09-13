import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/models/detergent_model.dart';

void main() {
  group('DetergentModel', () {
    test('additionalPrice is carried through toMapForCreate as-is', () {
      const detergent = DetergentModel(
        id: '',
        name: 'Premium',
        additionalPrice: 30,
      );
      final map = detergent.toMapForCreate();

      expect(map['additionalPrice'], 30);
      expect(map['name'], 'Premium');
      expect(map['status'], 'active');
    });

    test('Regular detergent can have a zero additional price', () {
      const detergent = DetergentModel(id: '', name: 'Regular', additionalPrice: 0);
      expect(detergent.additionalPrice, 0);
    });

    test('two detergents with the same id are equal', () {
      const a = DetergentModel(id: 'd1', name: 'Regular', additionalPrice: 0);
      const b = DetergentModel(id: 'd1', name: 'Regular (renamed)', additionalPrice: 0);
      expect(a, equals(b));
    });

    test('copyWith updates additionalPrice independently of other fields', () {
      const detergent = DetergentModel(id: 'd1', name: 'Premium', additionalPrice: 30);
      final updated = detergent.copyWith(additionalPrice: 40);

      expect(updated.additionalPrice, 40);
      expect(updated.name, 'Premium');
    });

    test('toEditableMap excludes createdAt', () {
      const detergent = DetergentModel(id: 'd1', name: 'Premium', additionalPrice: 30);
      final map = detergent.toEditableMap();
      expect(map.containsKey('createdAt'), isFalse);
    });
  });
}