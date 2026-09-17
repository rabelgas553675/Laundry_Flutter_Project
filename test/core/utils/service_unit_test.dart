import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/utils/service_unit.dart';

void main() {
  group('ServiceUnitX', () {
    test('isPiece / isKilogram reflect the enum value', () {
      expect(ServiceUnit.piece.isPiece, isTrue);
      expect(ServiceUnit.piece.isKilogram, isFalse);
      expect(ServiceUnit.kilogram.isKilogram, isTrue);
      expect(ServiceUnit.kilogram.isPiece, isFalse);
    });

    test('requiresWholeNumberQuantity is true only for piece', () {
      expect(ServiceUnit.piece.requiresWholeNumberQuantity, isTrue);
      expect(ServiceUnit.kilogram.requiresWholeNumberQuantity, isFalse);
    });

    test('value round-trips through fromValue', () {
      expect(ServiceUnit.piece.value, 'piece');
      expect(ServiceUnit.kilogram.value, 'kilogram');
    });
  });

  group('ServiceUnitParsing.fromValue', () {
    test('parses known values', () {
      expect(ServiceUnitParsing.fromValue('piece'), ServiceUnit.piece);
      expect(ServiceUnitParsing.fromValue('kilogram'), ServiceUnit.kilogram);
    });

    test('returns null for missing/unrecognized values', () {
      expect(ServiceUnitParsing.fromValue(null), isNull);
      expect(ServiceUnitParsing.fromValue(''), isNull);
      expect(ServiceUnitParsing.fromValue('lbs'), isNull);
    });
  });

  group('ServiceUnitParsing.fromServiceName (migration fallback)', () {
    test('Dry Cleaning infers piece', () {
      expect(ServiceUnitParsing.fromServiceName('Dry Cleaning'), ServiceUnit.piece);
    });

    test('Wash & Ironing infers piece', () {
      expect(ServiceUnitParsing.fromServiceName('Wash & Ironing'), ServiceUnit.piece);
    });

    test('is case-insensitive', () {
      expect(ServiceUnitParsing.fromServiceName('DRY CLEANING'), ServiceUnit.piece);
    });

    test('existing kg services infer kilogram', () {
      expect(ServiceUnitParsing.fromServiceName('Quick Wash'), ServiceUnit.kilogram);
      expect(ServiceUnitParsing.fromServiceName('Standard Wash'), ServiceUnit.kilogram);
      expect(ServiceUnitParsing.fromServiceName('Premium Wash'), ServiceUnit.kilogram);
    });
  });

  group('ServiceUnitParsing.resolve (backwards-compatible deserialization)', () {
    test('uses the stored value when present, ignoring the name', () {
      // A service literally named "Dry Cleaning" that was explicitly
      // saved as kilogram (e.g. an admin override) must NOT be
      // silently coerced back to piece by the name heuristic.
      expect(
        ServiceUnitParsing.resolve('kilogram', 'Dry Cleaning'),
        ServiceUnit.kilogram,
      );
      expect(
        ServiceUnitParsing.resolve('piece', 'Quick Wash'),
        ServiceUnit.piece,
      );
    });

    test('falls back to the name heuristic when the field is missing '
        '(pre-Part-1 persisted documents)', () {
      expect(ServiceUnitParsing.resolve(null, 'Dry Cleaning'), ServiceUnit.piece);
      expect(ServiceUnitParsing.resolve(null, 'Wash & Ironing'), ServiceUnit.piece);
      expect(ServiceUnitParsing.resolve(null, 'Quick Wash'), ServiceUnit.kilogram);
    });

    test('falls back to the name heuristic when the field is an unrecognized value', () {
      expect(ServiceUnitParsing.resolve('bogus', 'Dry Cleaning'), ServiceUnit.piece);
    });
  });

  group('ServiceUnitFormat.shortUnitLabel', () {
    test('kilogram is always "kg" regardless of quantity', () {
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.kilogram, 1), 'kg');
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.kilogram, 3), 'kg');
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.kilogram, 2.5), 'kg');
    });

    test('piece is "pc" for 1 and "pcs" otherwise', () {
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.piece, 1), 'pc');
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.piece, 3), 'pcs');
      expect(ServiceUnitFormat.shortUnitLabel(ServiceUnit.piece, 0), 'pcs');
    });
  });

  group('ServiceUnitFormat.formatQuantity', () {
    test('piece quantities render as whole numbers', () {
      expect(ServiceUnitFormat.formatQuantity(ServiceUnit.piece, 1), '1 pc');
      expect(ServiceUnitFormat.formatQuantity(ServiceUnit.piece, 3), '3 pcs');
    });

    test('kilogram quantities drop a trailing .0', () {
      expect(ServiceUnitFormat.formatQuantity(ServiceUnit.kilogram, 1), '1 kg');
      expect(ServiceUnitFormat.formatQuantity(ServiceUnit.kilogram, 3), '3 kg');
    });

    test('kilogram quantities keep one decimal place otherwise', () {
      expect(ServiceUnitFormat.formatQuantity(ServiceUnit.kilogram, 2.5), '2.5 kg');
    });

    test('never renders "3.0 kg"-style output for a piece service', () {
      // Guards against the exact regression called out in the spec:
      // a piece-based quantity must never look like a decimal weight.
      final formatted = ServiceUnitFormat.formatQuantity(ServiceUnit.piece, 3);
      expect(formatted, isNot(contains('.0')));
      expect(formatted, isNot(contains('kg')));
    });
  });

  group('ServiceUnitFormat.formatPricePerUnit', () {
    test('appends /pc for piece services', () {
      expect(ServiceUnitFormat.formatPricePerUnit(ServiceUnit.piece, '₱150'), '₱150/pc');
    });

    test('appends /kg for kilogram services', () {
      expect(ServiceUnitFormat.formatPricePerUnit(ServiceUnit.kilogram, '₱80'), '₱80/kg');
    });
  });

  group('ServiceUnitFormat.priceFieldLabel', () {
    test('reflects the selected unit', () {
      expect(ServiceUnitFormat.priceFieldLabel(ServiceUnit.kilogram), 'Price per kg (₱)');
      expect(ServiceUnitFormat.priceFieldLabel(ServiceUnit.piece), 'Price per piece (₱)');
    });
  });
}