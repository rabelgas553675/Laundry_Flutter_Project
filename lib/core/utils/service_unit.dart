/// PART 1 (per-piece pricing) — the single source of truth for how a
/// service's quantity is measured and priced.
///
/// Before this file existed, whether a service was priced "per kg" or
/// "per item" was guessed independently in a few different widgets by
/// checking `service.name` for substrings like `'dry'` or `'iron'`
/// (see the old `priceUnitForService` in `service_grid_card.dart`).
/// That's fragile — it breaks the moment a service is renamed, and it
/// duplicates the same guess in every screen that needs it.
///
/// From Part 1 onward:
/// - [ServiceModel] stores its unit explicitly (see `service_model.dart`).
/// - Every screen/widget reads `service.unit` (or, for a historical
///   order, the unit stored on the order — Part 2/3) instead of
///   re-deriving it from a name.
/// - Formatting a quantity or a price/unit label always goes through
///   [ServiceUnitFormat] below, so `"3 pcs"` vs `"3 kg"` is rendered
///   identically everywhere.
library;

/// How a service's price is measured.
enum ServiceUnit {
  /// Priced by weight — `pricePerKg` × weight in kilograms. Supports
  /// fractional quantities (e.g. `2.5` kg).
  kilogram,

  /// Priced per individual item — `pricePerKg` (the field is not
  /// renamed; see the doc comment on `ServiceModel.pricePerKg`) ×
  /// item count. Quantities must be whole numbers.
  piece,
}

extension ServiceUnitX on ServiceUnit {
  bool get isPiece => this == ServiceUnit.piece;

  bool get isKilogram => this == ServiceUnit.kilogram;

  /// Whether a quantity for this unit must be a whole number. Piece
  /// quantities can't be fractional (you can't order half a shirt);
  /// kilogram quantities keep supporting decimals, same as before
  /// this feature existed.
  bool get requiresWholeNumberQuantity => isPiece;

  /// Label for the quantity field itself — "Weight" for kg-based
  /// services (matches the existing order-form field), "Quantity"
  /// for piece-based ones. Used by Part 2's order form.
  String get quantityFieldLabel => isPiece ? 'Quantity' : 'Weight';

  /// Firestore-safe string written by [ServiceModel.toMapForCreate]/
  /// [ServiceModel.toEditableMap], e.g. `'kilogram'` or `'piece'`.
  String get value => name;
}

/// Parses the `unit` field persisted on a service document, with a
/// migration-safe fallback for documents written before this feature
/// existed.
class ServiceUnitParsing {
  ServiceUnitParsing._();

  /// Strict parse of a stored `unit` value. Returns `null` (rather
  /// than defaulting to [ServiceUnit.kilogram]) when the value is
  /// missing or unrecognized, so callers can decide how to fall back
  /// — see [resolve], which is what [ServiceModel.fromFirestore]
  /// actually uses.
  static ServiceUnit? fromValue(String? value) {
    switch (value) {
      case 'piece':
        return ServiceUnit.piece;
      case 'kilogram':
        return ServiceUnit.kilogram;
      default:
        return null;
    }
  }

  /// Migration-only fallback for services persisted before the
  /// `unit` field existed. Matched case-insensitively by name — the
  /// same heuristic the old per-widget detection used, kept here as
  /// the *one* place it's allowed to live.
  ///
  /// This must never be used to decide the unit of a *new or edited*
  /// service (those always carry an explicit `unit`), and it must
  /// never be reintroduced in a screen/widget — see [resolve].
  static ServiceUnit fromServiceName(String name) {
    final normalized = name.toLowerCase();
    const pieceServiceKeywords = [
      'dry clean',
      'wash & iron',
      'wash and iron',
      'ironing',
    ];
    if (pieceServiceKeywords.any(normalized.contains)) {
      return ServiceUnit.piece;
    }
    return ServiceUnit.kilogram;
  }

  /// What [ServiceModel.fromFirestore] actually calls: use the stored
  /// `unit` when present, otherwise infer it from the service's name
  /// so historical documents (saved before this feature shipped)
  /// still deserialize into the correct unit instead of silently
  /// defaulting to kilogram.
  static ServiceUnit resolve(String? storedValue, String serviceName) {
    return fromValue(storedValue) ?? fromServiceName(serviceName);
  }
}

/// Formatting helpers for quantities and price/unit labels. No
/// widget should format these strings itself — always go through
/// here so "3 pcs" vs "3 kg" (and "₱150/pc" vs "₱80/kg") look
/// identical everywhere in the app.
class ServiceUnitFormat {
  ServiceUnitFormat._();

  /// `'kg'` (always) / `'pc'` (quantity == 1) / `'pcs'` (otherwise).
  static String shortUnitLabel(ServiceUnit unit, num quantity) {
    if (unit.isKilogram) return 'kg';
    return quantity == 1 ? 'pc' : 'pcs';
  }

  /// `'kilogram(s)'` / `'piece(s)'` — used in longer copy (validation
  /// messages, field hints) where `'kg'`/`'pc'` would read as too
  /// terse. See Part 2's quantity validation.
  static String longUnitLabel(ServiceUnit unit, num quantity) {
    if (unit.isKilogram) return quantity == 1 ? 'kilogram' : 'kilograms';
    return quantity == 1 ? 'piece' : 'pieces';
  }

  /// `'Per Kg'` / `'Per Piece'` — the capitalized unit phrase used by
  /// `ServiceGridCard`'s price label (e.g. `"₱150.00 Per Piece"`).
  static String perUnitPhrase(ServiceUnit unit) =>
      unit.isPiece ? 'Per Piece' : 'Per Kg';

  /// The admin service form's price-field label, e.g.
  /// `'Price per piece (₱)'` / `'Price per kg (₱)'`.
  static String priceFieldLabel(ServiceUnit unit) =>
      unit.isPiece ? 'Price per piece (₱)' : 'Price per kg (₱)';

  /// Formats a quantity with its short unit label, e.g. `'3 pcs'`,
  /// `'1 pc'`, `'3 kg'`, `'2.5 kg'`.
  ///
  /// Piece quantities always render as whole numbers (no trailing
  /// `.0`); kilogram quantities keep up to one decimal place but drop
  /// a trailing `.0` too — matching this app's existing weight
  /// formatting convention (see `active_order_card.dart`'s
  /// `_weightLabel`), so a piece-based order can never accidentally
  /// display something like `'3.0 kg'`.
  static String formatQuantity(ServiceUnit unit, num quantity) {
    final numberPart = unit.isPiece
        ? quantity.round().toString()
        : _formatDecimalDroppingTrailingZero(quantity.toDouble());
    return '$numberPart ${shortUnitLabel(unit, quantity)}';
  }

  /// Appends the correct `/unit` suffix to an already-formatted price
  /// string, e.g. `formatPricePerUnit(ServiceUnit.piece, '₱150')` →
  /// `'₱150/pc'`. Deliberately takes the price pre-formatted (rather
  /// than a raw number) so this stays decoupled from currency
  /// symbol/decimal-place/locale concerns — see
  /// `PriceCalculator.formatCurrency`, which already owns that.
  static String formatPricePerUnit(ServiceUnit unit, String formattedPrice) {
    return '$formattedPrice/${shortUnitLabel(unit, 1)}';
  }

  static String _formatDecimalDroppingTrailingZero(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(1);
  }
}

/// Part 2 (customer ordering) — the single place that decides whether
/// a quantity is valid for a given [ServiceUnit].
///
/// Both `laundry_order_screen.dart`'s order form (validating the raw
/// text the customer typed) and `order_summary_screen.dart` (re
/// validating the already-parsed [OrderDraft.weightKg] before
/// submitting) go through here, so a piece service can never end up
/// with a fractional quantity by one screen enforcing the whole
/// number rule and the other forgetting to.
class ServiceUnitValidation {
  ServiceUnitValidation._();

  /// Validates raw text input from the order form's quantity/weight
  /// field for [unit]. Returns a human-readable error message, or
  /// `null` if [rawText] is a valid quantity for that unit.
  ///
  /// Piece services reject anything that isn't a whole number > 0
  /// (`'1.5'`, `'0'`, `'-1'`, `'abc'`, `''` are all invalid) with the
  /// message `'Please enter a whole number of pieces.'` — never a
  /// kg-specific message. Kilogram services keep the existing
  /// decimal-friendly rule (any parsable number > 0).
  static String? validateQuantityInput(ServiceUnit unit, String rawText) {
    final raw = rawText.trim();
    final parsed = raw.isEmpty ? null : double.tryParse(raw);
    if (parsed == null) {
      return unit.isPiece
          ? 'Please enter a whole number of pieces.'
          : 'Enter a valid weight in kg (greater than 0).';
    }
    return validateQuantityValue(unit, parsed);
  }

  /// Same rule as [validateQuantityInput], for a quantity that's
  /// already been parsed to a number — e.g. [OrderSummaryScreen]
  /// re-validating `OrderDraft.weightKg` independently of whatever
  /// the order form already checked.
  static String? validateQuantityValue(ServiceUnit unit, num quantity) {
    if (quantity <= 0) {
      return unit.isPiece
          ? 'Please enter a whole number of pieces.'
          : 'Enter a valid weight in kg (greater than 0).';
    }
    if (unit.requiresWholeNumberQuantity && quantity != quantity.roundToDouble()) {
      return 'Please enter a whole number of pieces.';
    }
    return null;
  }
}