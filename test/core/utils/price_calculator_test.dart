import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/utils/price_calculator.dart';

void main() {
  group('PriceCalculator.calculate — unit-agnostic quantity × price', () {
    // The calculator only ever does `price × quantity`; what the
    // quantity *means* (pieces vs kilograms) is decided upstream by
    // `ServiceModel.unit`/`OrderDraft.unit` (Part 1/2) — these two
    // cases are the exact worked examples from the per-piece pricing
    // spec, to lock in that the same formula is correct for both.
    test('3 pcs × ₱150/pc = ₱450 subtotal (piece service)', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 150, // "per piece" price, same field
        weightKg: 3, // piece count
      );
      expect(breakdown.subtotal, 450);
      expect(breakdown.total, 450);
    });

    test('2.5 kg × ₱80/kg = ₱200 subtotal (kg service)', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 80,
        weightKg: 2.5,
      );
      expect(breakdown.subtotal, 200);
      expect(breakdown.total, 200);
    });

    test('1 pc × ₱150/pc = ₱150 subtotal', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 150,
        weightKg: 1,
      );
      expect(breakdown.subtotal, 150);
    });

    test('piece subtotal plus fees and discount totals correctly', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 150,
        weightKg: 3,
        detergentFee: 30,
        pickupFee: 50,
        discount: 20, 
      );
      // 450 + 30 + 50 - 20 = 510
      expect(breakdown.subtotal, 450);
      expect(breakdown.total, 510);
    });
  });

  // PART 6 — the exact worked examples from the Dry Cleaning / Wash &
  // Ironing spec, run straight through `PriceCalculator.calculate`.
  group('PriceCalculator.calculate — PART 6 Dry Cleaning (itemsSubtotal)', () {
    test('2 Suits @ ₱150 + 1 Dress @ ₱150 = ₱450 subtotal', () {
      // Mirrors OrderItemModel.subtotalOf(draft.selectedItems) for a
      // Dry Cleaning draft — the calculator itself never re-sums the
      // items, it just takes the already-computed total (see the
      // library-level doc comment on `itemsSubtotal`).
      const itemsSubtotal = 2 * 150.0 + 1 * 150.0; // 300 + 150
      final breakdown = PriceCalculator.calculate(
        // servicePricePerKg/weightKg are ignored whenever
        // itemsSubtotal is passed — left at their defaults here to
        // prove that (a Dry Cleaning draft's weightKg is always 0).
        itemsSubtotal: itemsSubtotal,
      );
      expect(breakdown.subtotal, 450);
      expect(breakdown.total, 450);
    });

    test('2 Suits + 1 Dress + 3 Pants = ₱720 subtotal, ₱750 total', () {
      // Suit ₱150, Dress ₱150, Pants ₱90 — the full Order Summary
      // example from the spec.
      const itemsSubtotal = 2 * 150.0 + 1 * 150.0 + 3 * 90.0; // 300+150+270
      final breakdown = PriceCalculator.calculate(
        itemsSubtotal: itemsSubtotal,
        pickupFee: 50,
        discount: 20,
      );
      expect(breakdown.subtotal, 720);
      // 720 + 50 - 20 = 750
      expect(breakdown.total, 750);
    });

    test('an itemsSubtotal of 0 is honored as-is (not re-derived from weight)', () {
      // Guards against the exact ₱0-total regression the
      // OrderRepository doc comment describes: passing itemsSubtotal
      // must never fall back to `servicePricePerKg × weightKg`.
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 999,
        weightKg: 999,
        itemsSubtotal: 0,
      );
      expect(breakdown.subtotal, 0);
    });
  });

  group('PriceCalculator.calculate — PART 6 Wash & Ironing (weight × price)', () {
    test('5 KG × ₱80/kg = ₱400 subtotal', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 80,
        weightKg: 5,
      );
      expect(breakdown.subtotal, 400);
      expect(breakdown.total, 400);
    });

    test('full order summary example: subtotal + detergent + pickup - discount = ₱460', () {
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 80,
        weightKg: 5,
        detergentFee: 30,
        pickupFee: 50,
        discount: 20,
      );
      // 400 + 30 + 50 - 20 = 460
      expect(breakdown.subtotal, 400);
      expect(breakdown.detergentFee, 30);
      expect(breakdown.pickupFee, 50);
      expect(breakdown.discount, 20);
      expect(breakdown.total, 460);
    });
  });

  group('PriceCalculator.calculate — invalid input', () {
    test('negative weight throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(servicePricePerKg: 80, weightKg: -1),
        throwsArgumentError,
      );
    });

    test('negative servicePricePerKg throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(servicePricePerKg: -80, weightKg: 5),
        throwsArgumentError,
      );
    });

    test('negative itemsSubtotal throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(itemsSubtotal: -1),
        throwsArgumentError,
      );
    });

    test('negative detergentFee throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(
          servicePricePerKg: 80,
          weightKg: 5,
          detergentFee: -30,
        ),
        throwsArgumentError,
      );
    });

    test('negative pickupFee throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(
          servicePricePerKg: 80,
          weightKg: 5,
          pickupFee: -50,
        ),
        throwsArgumentError,
      );
    });

    test('negative discount (invalid discount) throws ArgumentError', () {
      expect(
        () => PriceCalculator.calculate(
          servicePricePerKg: 80,
          weightKg: 5,
          discount: -20,
        ),
        throwsArgumentError,
      );
    });

    test('a discount larger than the order total is clamped, never negative', () {
      // Not an ArgumentError case — a too-large *positive* discount is
      // valid input, just clamped by `calculate` itself (see its doc
      // comment), so the total can never go below ₱0.
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 80,
        weightKg: 1, // subtotal 80
        discount: 500,
      );
      expect(breakdown.discount, 80);
      expect(breakdown.total, 0);
    });

    test('zero weight is accepted by the calculator itself (0 is non-negative)', () {
      // The calculator only rejects *negative* numbers — "weight must
      // be greater than 0" is an order-level validation rule (see
      // OrderDraft.validate in order_draft_model_test.dart), not a
      // PriceCalculator concern, since a Dry Cleaning draft always
      // has weightKg == 0 and is perfectly valid.
      final breakdown = PriceCalculator.calculate(
        servicePricePerKg: 80,
        weightKg: 0,
      );
      expect(breakdown.subtotal, 0);
    });
  });

  group('PriceCalculator.formatCurrency', () {
    test('formats a whole number with 2 decimals and a peso sign', () {
      expect(PriceCalculator.formatCurrency(410), '₱410.00');
    });

    test('adds thousands separators', () {
      expect(PriceCalculator.formatCurrency(1234.5), '₱1,234.50');
    });

    test('formats a negative amount (e.g. a discount line) with a leading minus', () {
      expect(PriceCalculator.formatCurrency(-20), '-₱20.00');
    });
  });
}