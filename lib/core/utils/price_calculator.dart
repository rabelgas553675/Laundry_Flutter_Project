/// PART 11.1 / PART 3 — reusable, UI-independent laundry order price
/// calculator.
///
/// Two ways to price the "subtotal" line, depending on the service:
///
/// - Weight/piece-count services (Standard Wash, Wash & Ironing, ...):
///     Subtotal = Service Price (per kg/pc) × Weight or Quantity
///   Example (Wash & Ironing): 5 kg × ₱80/kg = ₱400 subtotal.
///
/// - Itemized services (Dry Cleaning):
///     Subtotal = Σ(quantity × item price) across every selected
///     garment — e.g. 2 Suits × ₱150 + 1 Dress × ₱150 + 3 Pants × ₱90
///     = ₱300 + ₱150 + ₱270 = ₱720. This calculator never re-derives
///     that sum itself (it stays UI/model-independent — see the class
///     doc comment on [calculate]); the caller passes the already-
///     summed total in via [calculate]'s `itemsSubtotal` parameter,
///     computed once by `OrderItemModel.subtotalOf`/
///     `OrderDraft.itemsSubtotal` — never re-implemented a third time
///     here or in a screen.
///
/// Either way:
///   Total = Subtotal + Detergent Fee + Pickup Fee − Discount
///
/// Full example (matches the PART 11 spec):
///   Standard Wash, 5 kg × ₱70/kg = ₱350 subtotal
///   + Detergent fee   ₱30
///   + Pickup fee      ₱50
///   − Discount        ₱20
///   = Total           ₱410
///
/// This file has zero Flutter/widget/Firebase dependencies — it's
/// plain Dart — so PART 11.2's OrderSummaryScreen (and anything else
/// later, e.g. an admin sales report) can import and reuse it without
/// dragging in UI code, and it can be unit-tested in isolation.
library;

/// Immutable result of a price calculation.
///
/// Every field is rounded to 2 decimal places so the pieces always
/// sum exactly to [total] with no floating-point rounding drift
/// (subtotal + detergentFee + pickupFee − discount == total, always).
class PriceBreakdown {
  /// Service price per kg × weight in kg.
  final double subtotal;

  /// Flat fee for the chosen detergent (0 if none/free).
  final double detergentFee;

  /// Flat fee for Pickup delivery (0 for Drop-off).
  final double pickupFee;

  /// Amount subtracted from the total. Always a positive number (an
  /// amount taken off), never negative, and never larger than what
  /// was actually owed before the discount — see
  /// [PriceCalculator.calculate].
  final double discount;

  /// subtotal + detergentFee + pickupFee − discount.
  final double total;

  const PriceBreakdown({
    required this.subtotal,
    required this.detergentFee,
    required this.pickupFee,
    required this.discount,
    required this.total,
  });

  @override
  String toString() {
    return 'PriceBreakdown(subtotal: $subtotal, detergentFee: $detergentFee, '
        'pickupFee: $pickupFee, discount: $discount, total: $total)';
  }
}

/// Stateless calculator — every method is pure (same inputs always
/// produce the same output), so it never needs to be instantiated.
class PriceCalculator {
  PriceCalculator._();

  /// Rounds to 2 decimal places. Doing this once, in one place, is
  /// what keeps `subtotal + fees - discount` from ever landing a
  /// fraction of a centavo off from [PriceBreakdown.total] due to
  /// binary floating-point representation (money should never be
  /// compared/summed as raw, unrounded doubles).
  static double _round2(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  /// Computes the full [PriceBreakdown] for one order.
  ///
  /// - [servicePricePerKg]: the chosen service's price per kg/piece
  ///   (from `ServiceModel.pricePerKg` — never hard-code this in a
  ///   widget, per PART 08). Ignored when [itemsSubtotal] is passed —
  ///   see below.
  /// - [weightKg]: the weight (or piece count) entered on the PART 10
  ///   order form. Ignored when [itemsSubtotal] is passed.
  /// - [itemsSubtotal]: PART 3 — for an itemized order (Dry
  ///   Cleaning), the already-computed Σ(quantity × item price)
  ///   across every selected garment (see `OrderDraft.itemsSubtotal`
  ///   / `OrderItemModel.subtotalOf`). When this is provided (non-
  ///   null), it is used as-is for the subtotal line instead of
  ///   `servicePricePerKg × weightKg` — a Dry Cleaning draft always
  ///   has `weightKg == 0` (it isn't priced by weight at all), so
  ///   computing the subtotal the weight-based way for an itemized
  ///   order would silently price it at ₱0. Leave `null` for any
  ///   weight/piece-count service (Wash & Ironing, Quick/Standard/
  ///   Premium Wash), which keeps pricing via [servicePricePerKg] ×
  ///   [weightKg] exactly as before.
  /// - [detergentFee]: the chosen detergent's flat additional fee
  ///   (from `DetergentModel.additionalPrice`), or 0 if none
  ///   selected.
  /// - [pickupFee]: flat delivery fee — 0 for Drop-off, some flat
  ///   amount for Pickup.
  /// - [discount]: flat/promo discount to subtract, 0 if none.
  ///
  /// Throws [ArgumentError] if any input is negative — an order can
  /// never have a negative price, weight, fee, or discount, and it's
  /// better to fail loudly here than silently show a nonsensical
  /// total on the summary screen.
  static PriceBreakdown calculate({
    double servicePricePerKg = 0,
    double weightKg = 0,
    double? itemsSubtotal,
    double detergentFee = 0,
    double pickupFee = 0,
    double discount = 0,
  }) {
    if (servicePricePerKg < 0) {
      throw ArgumentError.value(
        servicePricePerKg,
        'servicePricePerKg',
        'Service price per kg cannot be negative.',
      );
    }
    if (weightKg < 0) {
      throw ArgumentError.value(
        weightKg,
        'weightKg',
        'Weight cannot be negative.',
      );
    }
    if (itemsSubtotal != null && itemsSubtotal < 0) {
      throw ArgumentError.value(
        itemsSubtotal,
        'itemsSubtotal',
        'Items subtotal cannot be negative.',
      );
    }
    if (detergentFee < 0) {
      throw ArgumentError.value(
        detergentFee,
        'detergentFee',
        'Detergent fee cannot be negative.',
      );
    }
    if (pickupFee < 0) {
      throw ArgumentError.value(
        pickupFee,
        'pickupFee',
        'Pickup fee cannot be negative.',
      );
    }
    if (discount < 0) {
      throw ArgumentError.value(
        discount,
        'discount',
        'Discount cannot be negative.',
      );
    }

    final subtotal = _round2(itemsSubtotal ?? (servicePricePerKg * weightKg));
    final roundedDetergentFee = _round2(detergentFee);
    final roundedPickupFee = _round2(pickupFee);

    // A discount can never exceed what's actually owed — clamp it so
    // the total never goes negative (e.g. a promo code bigger than a
    // very small/light order). PART 18's promo validation will add
    // its own rules on top of this; this is just the calculator's
    // own safety floor.
    final amountBeforeDiscount = subtotal + roundedDetergentFee + roundedPickupFee;
    final appliedDiscount = _round2(
      discount > amountBeforeDiscount ? amountBeforeDiscount : discount,
    );

    final total = _round2(amountBeforeDiscount - appliedDiscount);

    return PriceBreakdown(
      subtotal: subtotal,
      detergentFee: roundedDetergentFee,
      pickupFee: roundedPickupFee,
      discount: appliedDiscount,
      total: total,
    );
  }

  /// Formats an amount as Philippine Peso, e.g. `410` → `'₱410.00'`,
  /// `1234.5` → `'₱1,234.50'`, `-20` → `'-₱20.00'`.
  ///
  /// Kept here (rather than duplicated across every screen that shows
  /// money) so PART 11.2's Order Summary — and any later screen, like
  /// PART 19's receipts/reports — format currency identically.
  static String formatCurrency(double amount) {
    final rounded = _round2(amount);
    final isNegative = rounded < 0;
    final fixed = rounded.abs().toStringAsFixed(2);
    final dotIndex = fixed.indexOf('.');
    final wholePart = fixed.substring(0, dotIndex);
    final decimalPart = fixed.substring(dotIndex + 1);

    final buffer = StringBuffer();
    for (int i = 0; i < wholePart.length; i++) {
      if (i > 0 && (wholePart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(wholePart[i]);
    }

    return '${isNegative ? '-' : ''}₱$buffer.$decimalPart';
  }
}