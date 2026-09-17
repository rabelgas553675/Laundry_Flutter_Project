import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/utils/service_unit.dart';
import 'package:laundry_flutter/features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'package:laundry_flutter/models/order_model.dart';
import 'package:laundry_flutter/models/user_model.dart';
import 'package:laundry_flutter/services/pdf_service.dart';

/// Part 3 (per-piece pricing) — the receipt is the last stop in the
/// per-unit-pricing pipeline, so these tests focus on exactly what
/// used to be wrong before this part: [OrderReceiptData] silently
/// dropping the order's unit, and the PDF table hard-coding "kg"/
/// `.toStringAsFixed(1)` regardless of what the order actually was.
OrderModel _order({
  required ServiceUnit serviceUnit,
  required String serviceName,
  required double weight,
  double subtotal = 0,
}) {
  return OrderModel(
    orderNumber: 'ORD-20260916-0001',
    userId: 'user1',
    serviceId: 'service1',
    serviceName: serviceName,
    weight: weight,
    serviceUnit: serviceUnit,
    detergentId: 'detergent1',
    detergentName: 'Regular Detergent',
    method: DeliveryMethod.dropoff,
    subtotal: subtotal,
    total: subtotal,
    status: OrderStatus.completed,
  );
}

const _customer = UserModel(
  uid: 'user1',
  name: 'Juan Dela Cruz',
  email: 'juan@example.com',
  phone: '09171234567',
  address: '123 Rizal St.',
  role: UserRole.user,
);

void main() {
  group('OrderReceiptData.fromOrder — Part 3 unit awareness', () {
    test('carries the piece unit for a Dry Cleaning order, not the current service config', () {
      final order = _order(
        serviceUnit: ServiceUnit.piece,
        serviceName: 'Dry Cleaning',
        weight: 3,
        subtotal: 450,
      );
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);

      expect(receipt.serviceUnit, ServiceUnit.piece);
      expect(receipt.weightKg, 3);
    });

    test('carries the kilogram unit for a kg-based order', () {
      final order = _order(
        serviceUnit: ServiceUnit.kilogram,
        serviceName: 'Standard Wash',
        weight: 3,
        subtotal: 240,
      );
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);

      expect(receipt.serviceUnit, ServiceUnit.kilogram);
      expect(receipt.weightKg, 3);
    });

    test('a historical order (unit inferred from name) still produces a piece receipt', () {
      // No explicit `serviceUnit` passed in — mirrors an order document
      // written before this field existed, which `OrderModel.fromMap`
      // resolves via `ServiceUnitParsing.fromServiceName`.
      final restored = OrderModel.fromMap({
        'orderNumber': 'ORD-20260101-0007',
        'userId': 'user1',
        'serviceId': 'service1',
        'serviceName': 'Wash & Ironing',
        'weight': 2,
        'detergentId': 'detergent1',
        'method': 'dropoff',
        'subtotal': 300,
        'total': 300,
        'status': 'completed',
      });

      final receipt = OrderReceiptData.fromOrder(restored, customer: _customer);

      expect(receipt.serviceUnit, ServiceUnit.piece);
      expect(ServiceUnitFormat.formatQuantity(receipt.serviceUnit, receipt.weightKg), '2 pcs');
    });
  });

  group('PdfService.buildOrderReceiptPdf — Part 3 unit-aware rendering', () {
    test('generates a non-empty PDF for a piece-based (Dry Cleaning) receipt', () async {
      final order = _order(
        serviceUnit: ServiceUnit.piece,
        serviceName: 'Dry Cleaning',
        weight: 3,
        subtotal: 450,
      );
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);

      final bytes = await PdfService.buildOrderReceiptPdf(receipt);

      expect(bytes, isNotEmpty);
    });

    test('generates a non-empty PDF for a kg-based (Standard Wash) receipt', () async {
      final order = _order(
        serviceUnit: ServiceUnit.kilogram,
        serviceName: 'Standard Wash',
        weight: 3,
        subtotal: 240,
      );
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);

      final bytes = await PdfService.buildOrderReceiptPdf(receipt);

      expect(bytes, isNotEmpty);
    });

    test('does not throw for a zero-weight edge case (rate falls back gracefully)', () async {
      final order = _order(
        serviceUnit: ServiceUnit.piece,
        serviceName: 'Dry Cleaning',
        weight: 0,
        subtotal: 0,
      );
      final receipt = OrderReceiptData.fromOrder(order, customer: _customer);

      expect(() => PdfService.buildOrderReceiptPdf(receipt), returnsNormally);
    });
  });
}