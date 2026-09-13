import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/models/laundry_item_model.dart';

void main() {
  group('LaundryItemModel', () {
    test('two items with the same id are equal, regardless of other fields', () {
      const a = LaundryItemModel(id: 'item1', name: 'Clothes');
      const b = LaundryItemModel(id: 'item1', name: 'Renamed Clothes');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('items with different ids are not equal', () {
      const a = LaundryItemModel(id: 'item1', name: 'Clothes');
      const b = LaundryItemModel(id: 'item2', name: 'Clothes');
      expect(a, isNot(equals(b)));
    });

    test('a Set dedupes by id, enabling multi-selection', () {
      const a = LaundryItemModel(id: 'item1', name: 'Clothes');
      const aAgain = LaundryItemModel(id: 'item1', name: 'Clothes');
      const b = LaundryItemModel(id: 'item2', name: 'Bedsheets');

      final selected = <LaundryItemModel>{}
        ..add(a)
        ..add(aAgain)
        ..add(b);
      expect(selected.length, 2);
    });

    test('toMapForCreate includes name, description, icon, status', () {
      const item = LaundryItemModel(
        id: '',
        name: 'Towels',
        description: 'Bath towels',
        icon: 'dry_cleaning',
        status: LaundryItemStatus.active,
      );
      final map = item.toMapForCreate();

      expect(map['name'], 'Towels');
      expect(map['description'], 'Bath towels');
      expect(map['icon'], 'dry_cleaning');
      expect(map['status'], 'active');
      expect(map.containsKey('createdAt'), isTrue);
    });

    test('copyWith only overrides the given fields', () {
      const item = LaundryItemModel(id: 'item1', name: 'Clothes', icon: 'checkroom');
      final updated = item.copyWith(name: 'Casual Clothes');

      expect(updated.id, 'item1');
      expect(updated.name, 'Casual Clothes');
      expect(updated.icon, 'checkroom'); // unchanged
    });

    test('LaundryItemStatusX.fromValue defaults unknown values to active', () {
      expect(LaundryItemStatusX.fromValue('active'), LaundryItemStatus.active);
      expect(LaundryItemStatusX.fromValue('inactive'), LaundryItemStatus.inactive);
      expect(LaundryItemStatusX.fromValue(null), LaundryItemStatus.active);
      expect(LaundryItemStatusX.fromValue('garbage'), LaundryItemStatus.active);
    });
  });
}