import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/utils/service_unit.dart';
import 'package:laundry_flutter/features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'package:laundry_flutter/models/detergent_model.dart';
import 'package:laundry_flutter/models/location_area_model.dart';
import 'package:laundry_flutter/models/order_draft_model.dart';
import 'package:laundry_flutter/models/order_item_model.dart';
import 'package:laundry_flutter/models/service_item_model.dart';
import 'package:laundry_flutter/models/service_model.dart';

const _detergent = DetergentModel(id: 'd1', name: 'Regular', additionalPrice: 0);
const _premiumDetergent = DetergentModel(id: 'd2', name: 'Premium', additionalPrice: 30);

const _dryCleaningService = ServiceModel(
  id: 's1',
  name: 'Dry Cleaning',
  description: '',
  pricePerKg: 150,
  estimatedTime: '48 hours',
  unit: ServiceUnit.piece,
  serviceType: ServiceType.dryCleaning,
  pricingType: PricingType.perItem,
);

const _washIroningService = ServiceModel(
  id: 's3',
  name: 'Wash & Ironing',
  description: '',
  pricePerKg: 80,
  estimatedTime: '24 hours',
  unit: ServiceUnit.kilogram,
  serviceType: ServiceType.washAndIroning,
  pricingType: PricingType.perKg,
);

const _standardWashService = ServiceModel(
  id: 's2',
  name: 'Standard Wash',
  description: '',
  pricePerKg: 70,
  estimatedTime: '24 hours',
  unit: ServiceUnit.kilogram,
);

const _suit = ServiceItemModel(
  id: 'suit',
  serviceId: 's1',
  serviceType: ServiceType.dryCleaning,
  name: 'Suit',
  price: 150,
);
const _dress = ServiceItemModel(
  id: 'dress',
  serviceId: 's1',
  serviceType: ServiceType.dryCleaning,
  name: 'Dress',
  price: 150,
);

const _pickupArea = LocationAreaModel(id: 'poblacion', label: 'Zone 1 – Poblacion');

OrderDraft _draftFor(ServiceModel service, {double weightKg = 3}) {
  return OrderDraft(
    service: service,
    items: const {},
    weightKg: weightKg,
    detergent: _detergent,
    deliveryMethod: DeliveryMethod.dropoff,
  );
}

void main() {
  group('OrderDraft.unit', () {
    test('reads piece from a piece-based service', () {
      expect(_draftFor(_dryCleaningService).unit, ServiceUnit.piece);
    });

    test('reads kilogram from a kg-based service', () {
      expect(_draftFor(_standardWashService).unit, ServiceUnit.kilogram);
    });
  });

  group('OrderDraft.isItemized / itemsSubtotal — PART 1/3', () {
    test('a Dry Cleaning draft is itemized', () {
      final draft = OrderDraft(
        service: _dryCleaningService,
        selectedItems: [OrderItemModel.priced(catalogItem: _suit, quantity: 1)],
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
      );
      expect(draft.isItemized, isTrue);
    });

    test('a Wash & Ironing draft is not itemized', () {
      final draft = _draftFor(_washIroningService, weightKg: 5);
      expect(draft.isItemized, isFalse);
      expect(draft.itemsSubtotal, 0);
    });

    test('itemsSubtotal sums 2 Suits + 1 Dress = ₱450 (PART 6 example)', () {
      final draft = OrderDraft(
        service: _dryCleaningService,
        selectedItems: [
          OrderItemModel.priced(catalogItem: _suit, quantity: 2),
          OrderItemModel.priced(catalogItem: _dress, quantity: 1),
        ],
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
      );
      expect(draft.itemsSubtotal, 450);
    });
  });

  group('OrderDraft.validate — Dry Cleaning', () {
    test('valid: at least one item at quantity > 0', () {
      final draft = OrderDraft(
        service: _dryCleaningService,
        selectedItems: [OrderItemModel.priced(catalogItem: _suit, quantity: 2)],
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
      );
      expect(draft.validate(), isEmpty);
      expect(draft.isValid, isTrue);
    });

    test('invalid: empty items list', () {
      final draft = OrderDraft(
        service: _dryCleaningService,
        selectedItems: const [],
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
      );
      expect(draft.isValid, isFalse);
      expect(draft.validate(), contains('Select at least one item and its quantity.'));
    });

    test('invalid: zero quantity on a selected item', () {
      final draft = OrderDraft(
        service: _dryCleaningService,
        selectedItems: [OrderItemModel.priced(catalogItem: _suit, quantity: 0)],
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
      );
      expect(draft.isValid, isFalse);
    });
  });

  group('OrderDraft.validate — Wash & Ironing / weight-based services', () {
    test('valid: weight greater than 0', () {
      final draft = _draftFor(_washIroningService, weightKg: 5);
      expect(draft.isValid, isTrue);
    });

    test('invalid: zero weight', () {
      final draft = _draftFor(_washIroningService, weightKg: 0);
      expect(draft.isValid, isFalse);
      expect(draft.validate(), contains('Weight must be greater than 0.'));
    });

    test('invalid: negative weight', () {
      final draft = _draftFor(_washIroningService, weightKg: -2);
      expect(draft.isValid, isFalse);
    });
  });

  group('OrderDraft.validate — Pickup requires address and phone', () {
    test('invalid: Pickup with no address and no phone', () {
      final draft = OrderDraft(
        service: _washIroningService,
        weightKg: 5,
        detergent: _premiumDetergent,
        deliveryMethod: DeliveryMethod.pickup,
        pickupLocation: _pickupArea,
      );
      final errors = draft.validate();
      expect(errors, contains('Pickup requires an address.'));
      expect(errors, contains('Pickup requires a phone number.'));
    });

    test('invalid: Pickup with a blank (whitespace-only) address', () {
      final draft = OrderDraft(
        service: _washIroningService,
        weightKg: 5,
        detergent: _premiumDetergent,
        deliveryMethod: DeliveryMethod.pickup,
        pickupAddress: '   ',
        pickupPhone: '09171234567',
        pickupLocation: _pickupArea,
      );
      expect(draft.validate(), contains('Pickup requires an address.'));
    });

    test('valid: Pickup with address and phone provided', () {
      final draft = OrderDraft(
        service: _washIroningService,
        weightKg: 5,
        detergent: _premiumDetergent,
        deliveryMethod: DeliveryMethod.pickup,
        pickupAddress: '123 Rizal Street',
        pickupPhone: '09171234567',
        pickupLandmark: 'Near the plaza',
        pickupLocation: _pickupArea,
      );
      expect(draft.isValid, isTrue);
    });

    test('valid: Drop-off never requires address/phone', () {
      final draft = _draftFor(_washIroningService, weightKg: 5);
      expect(draft.isPickup, isFalse);
      expect(draft.isValid, isTrue);
    });
  });

  group('OrderDraft.validate — discount', () {
    test('invalid: negative discount', () {
      final draft = OrderDraft(
        service: _washIroningService,
        weightKg: 5,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.dropoff,
        discount: -20,
      );
      expect(draft.isValid, isFalse);
      expect(draft.validate(), contains('Discount cannot be negative.'));
    });

    test('valid: zero discount', () {
      final draft = _draftFor(_washIroningService, weightKg: 5);
      expect(draft.isValid, isTrue);
    });
  });

  group('OrderDraft.validate — multiple simultaneous failures', () {
    test('zero weight AND missing pickup phone both get reported', () {
      final draft = OrderDraft(
        service: _washIroningService,
        weightKg: 0,
        detergent: _detergent,
        deliveryMethod: DeliveryMethod.pickup,
        pickupAddress: '123 Rizal Street',
        pickupLocation: _pickupArea,
      );
      final errors = draft.validate();
      expect(errors.length, 2);
      expect(errors, contains('Weight must be greater than 0.'));
      expect(errors, contains('Pickup requires a phone number.'));
    });
  });
}