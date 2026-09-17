import '../core/utils/service_unit.dart';
import '../features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'detergent_model.dart';
import 'laundry_item_model.dart';
import 'location_area_model.dart';
import 'order_item_model.dart';
import 'promo_model.dart';
import 'service_model.dart';

/// PART 11.2 / PART 1 — a snapshot of everything the customer chose
/// on the order form, handed to `OrderSummaryScreen` so it has
/// something concrete to display and price.
///
/// This is intentionally NOT the PART 12 `OrderModel` — it has no
/// `id`, no `orderNumber`, no `status`, no Firestore
/// `toMapForCreate()`/`fromFirestore()`. It only exists to carry data
/// from one screen to another in memory; PART 12 is the first part
/// that turns a confirmed order into something persisted. This must
/// never be written to Firestore directly — only the `OrderModel`
/// built from it (PART 4) is.
///
/// [DeliveryMethod] is reused from `laundry_order_screen.dart` rather
/// than redeclared here, so the order form and the summary screen can
/// never drift out of sync on what "Pickup" vs "Drop-off" means.
///
/// PART 1 note on `subtotal`/`detergentFee`/`total`: the spec lists
/// these as things the draft "should contain", but they are not
/// stored here as separate fields. Everything needed to compute them
/// — [service], [selectedItems], [weightKg], [detergent], [pickupFee],
/// [discount] — already lives on this draft, and `PriceCalculator`
/// (PART 3) is the single place that turns those inputs into a
/// `PriceBreakdown`. Storing the computed numbers a second time here
/// would mean two places a subtotal could live and drift apart; a
/// draft field that's a getter deriving from the others, kept exactly
/// where the PART 3 calculator already lives.
class OrderDraft {
  final ServiceModel service;

  /// Wash & Ironing's "what's in the load" checklist (Clothes,
  /// Bedsheets, Blankets, Towels, ...) — unpriced category tags. Empty
  /// for Dry Cleaning, which uses [selectedItems] instead.
  final Set<LaundryItemModel> items;

  /// PART 1 — Dry Cleaning's itemized line list: one [OrderItemModel]
  /// per garment the customer picked, each carrying its own
  /// `quantity` and `unitPrice` from the Dry Cleaning catalog (see
  /// `ServiceItemModel`). Empty for Wash & Ironing and every other
  /// service, which use [weightKg] (or a plain piece count) instead
  /// of a per-garment breakdown.
  ///
  /// Kept as a separate field from [items] rather than folding Dry
  /// Cleaning garments into that `Set<LaundryItemModel>`, because
  /// [LaundryItemModel] has no price/quantity of its own — see its
  /// doc comment — while a Dry Cleaning line always needs both.
  final List<OrderItemModel> selectedItems;

  /// Weight in kilograms, entered on the order form's quantity step.
  ///
  /// Kept as `weightKg` (not renamed) for the same reason
  /// `OrderModel.weight` wasn't renamed — every existing call site
  /// (`PriceCalculator`, `OrderRepository.createOrder`, ...) keeps
  /// reading this field unchanged. For a per-piece service priced as
  /// a single count (not itemized — see [selectedItems] for the case
  /// that is) this holds the piece count instead of a weight; what it
  /// actually means is given by [unit], never by re-deriving it from
  /// [service.name].
  final double weightKg;

  final DetergentModel detergent;
  final DeliveryMethod deliveryMethod;

  // Only meaningful when deliveryMethod == DeliveryMethod.pickup —
  // null/unused for Drop-off.
  final String? pickupAddress;
  final String? pickupPhone;
  final String? pickupLandmark;
  final LocationAreaModel? pickupLocation;

  /// Flat delivery fee to feed into [PriceCalculator]. 0 for
  /// Drop-off, [AppConstants.pickupFee] for Pickup — decided by
  /// whoever constructs this draft (PART 11.3), not by this class.
  final double pickupFee;

  /// Flat discount amount to feed into [PriceCalculator] when no
  /// [appliedPromo] is attached. Kept for backward compatibility with
  /// callers/tests that build a draft with a plain numeric discount
  /// and no promo at all. Once [appliedPromo] is set, [resolvedDiscount]
  /// — not this field — is what pricing actually uses.
  final double discount;

  /// PART 3 — the offer/promo the customer selected on the Offers
  /// screen before starting this order (see `OffersScreen`'s "Order
  /// with this Promo" action), carried through every step of the
  /// order form so it's still attached by the time this draft reaches
  /// [OrderSummaryScreen] and, ultimately,
  /// `OrderRepository.createOrder`. `null` for an order placed
  /// without ever selecting an offer — the normal case before this
  /// part existed, and still perfectly valid afterward.
  ///
  /// This is only ever a snapshot of *which* promo was picked — it is
  /// never trusted blindly for pricing without being re-validated
  /// (still active, not expired, minimum order met) against the
  /// draft's current [baseSubtotal] first. See [resolvedDiscount] for
  /// the pure/synchronous half of that, and
  /// `PromoRepository.validateCode` for the authoritative check
  /// re-run at each step of checkout.
  final PromoModel? appliedPromo;

  /// PART 1 — optional free-text note from the customer (e.g. "Handle
  /// carefully", "Separate the whites"). `null`/empty when not set;
  /// never required.
  final String? specialInstructions;

  const OrderDraft({
    required this.service,
    this.items = const {},
    this.selectedItems = const [],
    required this.weightKg,
    required this.detergent,
    required this.deliveryMethod,
    this.pickupAddress,
    this.pickupPhone,
    this.pickupLandmark,
    this.pickupLocation,
    this.pickupFee = 0,
    this.discount = 0,
    this.appliedPromo,
    this.specialInstructions,
  });

  bool get isPickup => deliveryMethod == DeliveryMethod.pickup;

  /// Part 2 — the unit [weightKg] is measured in, always read from
  /// the selected [service] (Part 1's single source of truth) rather
  /// than re-derived here. `order_summary_screen.dart` uses this for
  /// every unit-aware label, validation message, and calculation.
  ServiceUnit get unit => service.unit;

  /// PART 1 — whether this draft is for an itemized Dry Cleaning
  /// order (priced from [selectedItems]) rather than a weight/count
  /// based one. Screens branch on this instead of comparing
  /// `service.name` against a literal string.
  bool get isItemized => service.serviceType.isItemized;

  /// PART 1 — Σ(quantity × unitPrice) across [selectedItems]. `0` for
  /// a non-itemized draft. See the class doc comment for why this is
  /// a getter rather than a stored field.
  double get itemsSubtotal => OrderItemModel.subtotalOf(selectedItems);

  /// PART 3 — the order's base pricing subtotal *before* detergent
  /// fee, pickup fee, or any discount: [itemsSubtotal] for an
  /// itemized (Dry Cleaning) draft, or `service.pricePerKg × weightKg`
  /// for every other service. This is what [appliedPromo]'s discount
  /// is computed against — the same "order subtotal" concept
  /// `OffersScreen`'s redeem-code preview and `PromoRepository
  /// .validateCode` already use, so a promo previewed on the Offers
  /// screen and the same promo applied here always agree on how much
  /// it's actually worth.
  double get baseSubtotal => isItemized ? itemsSubtotal : service.pricePerKg * weightKg;

  /// PART 3 — the discount amount this draft should actually be
  /// priced with right now.
  ///
  /// When [appliedPromo] is set, this is always freshly recomputed as
  /// `appliedPromo!.discountFor(baseSubtotal)` — never a stale number
  /// cached at the moment the promo was selected — so it can't drift
  /// out of sync if the customer goes back and changes their weight,
  /// items, or service after picking an offer. Falls back to the
  /// legacy flat [discount] field when no promo is attached, so a
  /// draft built directly with a numeric discount (older code paths,
  /// unit tests) keeps working unchanged.
  ///
  /// This does NOT, by itself, confirm the promo is still valid
  /// (active / not expired / minimum order met) — `PromoModel
  /// .discountFor` only computes "if it were applied, how much would
  /// it take off." The actual validity check is
  /// `PromoRepository.validateCode`, re-run at each step of checkout
  /// (order form → order summary → order creation) — see those call
  /// sites for where an invalid/expired promo actually gets rejected.
  double get resolvedDiscount =>
      appliedPromo != null ? appliedPromo!.discountFor(baseSubtotal) : discount;

  /// PART 6 — the same validation rules `laundry_order_screen.dart`
  /// already enforces step-by-step in its private `_validateItems` /
  /// `_validateWeight` / `_validateDeliveryMethod` methods, re-stated
  /// here as a single pure, Flutter-independent pass over a finished
  /// [OrderDraft].
  ///
  /// This does NOT replace the screen's own step-by-step validation
  /// (that still drives per-step error banners as the customer fills
  /// the form in) — it exists so the *rules themselves* (not the
  /// widget that happens to enforce them) are unit-testable in
  /// isolation, and so any other caller that builds/receives an
  /// [OrderDraft] (e.g. a future admin "create order for customer"
  /// flow) has one place to check "is this draft actually valid"
  /// without re-deriving the rules or spinning up a widget test.
  ///
  /// Returns an empty list when the draft is valid. Otherwise returns
  /// one short, customer-facing message per broken rule (a draft can
  /// fail more than one rule at once, e.g. zero weight AND a missing
  /// phone number on the same pickup order).
  List<String> validate() {
    final errors = <String>[];

    if (isItemized) {
      // Dry Cleaning: at least one garment, each at a quantity > 0.
      // `selectedItems` should never actually contain a zero/negative
      // quantity line (the order screen's stepper can't go below 0
      // and only adds a line once it's > 0), but a defensively
      // constructed draft (e.g. in a test, or a future non-UI caller)
      // is checked for it here rather than trusted blindly.
      if (selectedItems.isEmpty) {
        errors.add('Select at least one item and its quantity.');
      } else if (selectedItems.any((item) => item.quantity <= 0)) {
        errors.add('Quantity must be greater than 0 for every selected item.');
      }
    } else {
      // Weight/piece-count services (Standard Wash, Wash & Ironing,
      // ...): the entered amount must be greater than zero. Negative
      // weight is caught the same way (it can never be entered
      // through the order form's numeric field, but is still an
      // invalid draft if constructed directly).
      if (weightKg <= 0) {
        errors.add(
          unit.isPiece
              ? 'Quantity must be greater than 0.'
              : 'Weight must be greater than 0.',
        );
      }
    }

    if (isPickup) {
      if (pickupAddress == null || pickupAddress!.trim().isEmpty) {
        errors.add('Pickup requires an address.');
      }
      if (pickupPhone == null || pickupPhone!.trim().isEmpty) {
        errors.add('Pickup requires a phone number.');
      }
    }

    // A discount can never exceed 100% of what's actually owed as a
    // *malformed input* (as opposed to `PriceCalculator.calculate`,
    // which clamps an over-large discount rather than rejecting it —
    // this catches the case that should never happen at all: a
    // negative discount amount).
    if (discount < 0) {
      errors.add('Discount cannot be negative.');
    }

    return errors;
  }

  /// `true` when [validate] finds nothing wrong with this draft.
  bool get isValid => validate().isEmpty;

  OrderDraft copyWith({
    ServiceModel? service,
    Set<LaundryItemModel>? items,
    List<OrderItemModel>? selectedItems,
    double? weightKg,
    DetergentModel? detergent,
    DeliveryMethod? deliveryMethod,
    String? pickupAddress,
    String? pickupPhone,
    String? pickupLandmark,
    LocationAreaModel? pickupLocation,
    double? pickupFee,
    double? discount,
    PromoModel? appliedPromo,
    // PART 3 — `copyWith`'s usual `field ?? this.field` pattern can
    // never express "clear this back to null" (only "leave it alone"
    // or "replace it with a new value"). `OffersScreen`/
    // `OrderSummaryScreen` need exactly that when an offer turns out
    // to be no longer valid at some later checkout step, so this one
    // field gets an explicit escape hatch. Defaults to `false`, so
    // every existing call site (which never passes it) keeps the
    // normal `??` behavior unchanged.
    bool clearAppliedPromo = false,
    String? specialInstructions,
  }) {
    return OrderDraft(
      service: service ?? this.service,
      items: items ?? this.items,
      selectedItems: selectedItems ?? this.selectedItems,
      weightKg: weightKg ?? this.weightKg,
      detergent: detergent ?? this.detergent,
      deliveryMethod: deliveryMethod ?? this.deliveryMethod,
      pickupAddress: pickupAddress ?? this.pickupAddress,
      pickupPhone: pickupPhone ?? this.pickupPhone,
      pickupLandmark: pickupLandmark ?? this.pickupLandmark,
      pickupLocation: pickupLocation ?? this.pickupLocation,
      pickupFee: pickupFee ?? this.pickupFee,
      discount: discount ?? this.discount,
      appliedPromo: clearAppliedPromo ? null : (appliedPromo ?? this.appliedPromo),
      specialInstructions: specialInstructions ?? this.specialInstructions,
    );
  }
}