import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/models/laundry_item_model.dart';
import 'package:laundry_flutter/models/order_item_model.dart';
import 'package:laundry_flutter/models/service_item_model.dart';
import 'package:laundry_flutter/models/service_model.dart';

/// PART 1 catalog rows matching the PART 6 spec's worked example:
/// 2 Suits @ ₱150, 1 Dress @ ₱150, 3 Pants @ ₱90.
const _suit = ServiceItemModel(
  id: 'suit',
  serviceId: 'dry-cleaning',
  serviceType: ServiceType.dryCleaning,
  name: 'Suit',
  price: 150,
);
const _dress = ServiceItemModel(
  id: 'dress',
  serviceId: 'dry-cleaning',
  serviceType: ServiceType.dryCleaning,
  name: 'Dress',
  price: 150,
);
const _pants = ServiceItemModel(
  id: 'pants',
  serviceId: 'dry-cleaning',
  serviceType: ServiceType.dryCleaning,
  name: 'Formal Pants',
  price: 90,
);

void main() {
  group('OrderItemModel.priced — Dry Cleaning lines', () {
    test('2 Suits @ ₱150 => totalPrice ₱300', () {
      final line = OrderItemModel.priced(catalogItem: _suit, quantity: 2);
      expect(line.itemName, 'Suit');
      expect(line.quantity, 2);
      expect(line.unitPrice, 150);
      expect(line.totalPrice, 300);
    });

    test('1 Dress @ ₱150 => totalPrice ₱150', () {
      final line = OrderItemModel.priced(catalogItem: _dress, quantity: 1);
      expect(line.totalPrice, 150);
    });

    test('3 Formal Pants @ ₱90 => totalPrice ₱270', () {
      final line = OrderItemModel.priced(catalogItem: _pants, quantity: 3);
      expect(line.totalPrice, 270);
    });
  });

  group('OrderItemModel.subtotalOf — PART 6 worked example', () {
    test('2 Suits + 1 Dress = ₱450', () {
      final lines = [
        OrderItemModel.priced(catalogItem: _suit, quantity: 2),
        OrderItemModel.priced(catalogItem: _dress, quantity: 1),
      ];
      expect(OrderItemModel.subtotalOf(lines), 450);
    });

    test('2 Suits + 1 Dress + 3 Pants = ₱720', () {
      final lines = [
        OrderItemModel.priced(catalogItem: _suit, quantity: 2),
        OrderItemModel.priced(catalogItem: _dress, quantity: 1),
        OrderItemModel.priced(catalogItem: _pants, quantity: 3),
      ];
      expect(OrderItemModel.subtotalOf(lines), 720);
    });

    test('empty list => ₱0', () {
      expect(OrderItemModel.subtotalOf(const []), 0);
    });
  });

  group('OrderItemModel.fromLaundryItem — Wash & Ironing category tags', () {
    const shirtTag = LaundryItemModel(
      id: 'tshirt',
      name: 'T-Shirt',
      description: '',
      icon: 'checkroom',
    );

    test('is unpriced: quantity 1, unitPrice 0, totalPrice 0', () {
      final line = OrderItemModel.fromLaundryItem(shirtTag);
      expect(line.quantity, 1);
      expect(line.unitPrice, 0);
      expect(line.totalPrice, 0);
    });

    test('multiple category tags never contribute to itemsSubtotal', () {
      final lines = [
        OrderItemModel.fromLaundryItem(shirtTag),
        OrderItemModel.fromLaundryItem(
          const LaundryItemModel(id: 'polo', name: 'Polo', description: '', icon: 'checkroom'),
        ),
      ];
      expect(OrderItemModel.subtotalOf(lines), 0);
    });
  });

  group('OrderItemModel map round-trip', () {
    test('toMap/fromMap preserves quantity and unitPrice', () {
      final line = OrderItemModel.priced(catalogItem: _suit, quantity: 2);
      final restored = OrderItemModel.fromMap(line.toMap());
      expect(restored.itemId, line.itemId);
      expect(restored.itemName, 'Suit');
      expect(restored.quantity, 2);
      expect(restored.unitPrice, 150);
      expect(restored.totalPrice, 300);
    });

    test('fromMap defaults missing quantity/unitPrice to a pre-PART-1 unpriced tag', () {
      final restored = OrderItemModel.fromMap({'itemId': 'towel', 'itemName': 'Towel'});
      expect(restored.quantity, 1);
      expect(restored.unitPrice, 0);
    });

    test('listToMap/listFromMap round-trips a full Dry Cleaning order', () {
      final lines = [
        OrderItemModel.priced(catalogItem: _suit, quantity: 2),
        OrderItemModel.priced(catalogItem: _dress, quantity: 1),
        OrderItemModel.priced(catalogItem: _pants, quantity: 3),
      ];
      final restored = OrderItemModel.listFromMap(OrderItemModel.listToMap(lines));
      expect(restored.length, 3);
      expect(OrderItemModel.subtotalOf(restored), 720);
    });
  });
}