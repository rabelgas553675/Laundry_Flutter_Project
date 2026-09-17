import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/utils/service_unit.dart';
import 'package:laundry_flutter/features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'package:laundry_flutter/models/order_model.dart';

OrderModel _order({
  ServiceUnit serviceUnit = ServiceUnit.kilogram,
  String serviceName = 'Standard Wash',
}) {
  return OrderModel(
    orderNumber: 'ORD-20260916-0001',
    userId: 'user1',
    serviceId: 'service1',
    serviceName: serviceName,
    weight: 3,
    serviceUnit: serviceUnit,
    detergentId: 'detergent1',
    method: DeliveryMethod.dropoff,
    subtotal: 210,
    total: 210,
  );
}

void main() {
  group('OrderModel.serviceUnit', () {
    test('defaults to kilogram when not passed, matching ServiceModel', () {
      final order = OrderModel(
        orderNumber: 'ORD-20260916-0002',
        userId: 'user1',
        serviceId: 'service1',
        serviceName: 'Standard Wash',
        weight: 3,
        detergentId: 'detergent1',
        method: DeliveryMethod.dropoff,
        subtotal: 210,
        total: 210,
      );
      expect(order.serviceUnit, ServiceUnit.kilogram);
    });

    test('toMap writes the unit as its Firestore-safe string value', () {
      final order = _order(serviceUnit: ServiceUnit.piece, serviceName: 'Dry Cleaning');
      expect(order.toMap()['serviceUnit'], 'piece');
    });

    test('fromMap round-trips a piece order', () {
      final order = _order(serviceUnit: ServiceUnit.piece, serviceName: 'Dry Cleaning');
      final restored = OrderModel.fromMap(order.toMap(), id: 'doc1');
      expect(restored.serviceUnit, ServiceUnit.piece);
    });

    test('fromMap round-trips a kilogram order', () {
      final order = _order(serviceUnit: ServiceUnit.kilogram, serviceName: 'Standard Wash');
      final restored = OrderModel.fromMap(order.toMap(), id: 'doc1');
      expect(restored.serviceUnit, ServiceUnit.kilogram);
    });

    test(
      'falls back to inferring the unit from serviceName for orders '
      'persisted before this field existed',
      () {
        final legacyMap = _order(serviceName: 'Dry Cleaning').toMap()
          ..remove('serviceUnit');
        final restored = OrderModel.fromMap(legacyMap, id: 'doc1');
        expect(restored.serviceUnit, ServiceUnit.piece);
      },
    );

    test(
      'a stored unit is trusted over the name heuristic '
      '(e.g. an admin explicitly overrode it)',
      () {
        final map = _order(serviceUnit: ServiceUnit.kilogram, serviceName: 'Dry Cleaning').toMap();
        final restored = OrderModel.fromMap(map, id: 'doc1');
        expect(restored.serviceUnit, ServiceUnit.kilogram);
      },
    );

    test('does not change when the current service catalog changes later', () {
      // Simulates: order was placed while "Dry Cleaning" was piece-based,
      // then an admin later reconfigures that service to kilogram. The
      // *order's* stored unit must stay piece regardless of what the
      // service now says.
      final placedOrderMap = _order(serviceUnit: ServiceUnit.piece, serviceName: 'Dry Cleaning').toMap();
      final reloaded = OrderModel.fromMap(placedOrderMap, id: 'doc1');
      expect(reloaded.serviceUnit, ServiceUnit.piece);
    });

    test('toJson/fromJson round-trips the unit', () {
      final order = _order(serviceUnit: ServiceUnit.piece, serviceName: 'Wash & Ironing');
      final restored = OrderModel.fromJson(order.toJson());
      expect(restored.serviceUnit, ServiceUnit.piece);
    });

    test('copyWith preserves serviceUnit', () {
      final order = _order(serviceUnit: ServiceUnit.piece, serviceName: 'Dry Cleaning');
      final updated = order.copyWith(status: OrderStatus.received);
      expect(updated.serviceUnit, ServiceUnit.piece);
    });
  });
}