import '../features/user/screens/laundry_order_screen.dart' show DeliveryMethod;
import 'detergent_model.dart';
import 'laundry_item_model.dart';
import 'location_area_model.dart';
import 'service_model.dart';

/// PART 11.2 — a snapshot of everything the customer chose on the
/// PART 10 order form, handed to [OrderSummaryScreen] so it has
/// something concrete to display and price.
///
/// This is intentionally NOT the PART 12 `OrderModel` — it has no
/// `id`, no `orderNumber`, no `status`, no Firestore
/// `toMapForCreate()`/`fromFirestore()`. It only exists to carry data
/// from one screen to another in memory; PART 12 is the first part
/// that turns a confirmed order into something persisted.
///
/// [DeliveryMethod] is reused from `laundry_order_screen.dart` rather
/// than redeclared here, so the order form and the summary screen can
/// never drift out of sync on what "Pickup" vs "Drop-off" means.
class OrderDraft {
  final ServiceModel service;
  final Set<LaundryItemModel> items;
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

  /// Flat/promo discount to feed into [PriceCalculator]. Always 0 for
  /// now — PART 18 is what actually introduces promo codes.
  final double discount;

  const OrderDraft({
    required this.service,
    required this.items,
    required this.weightKg,
    required this.detergent,
    required this.deliveryMethod,
    this.pickupAddress,
    this.pickupPhone,
    this.pickupLandmark,
    this.pickupLocation,
    this.pickupFee = 0,
    this.discount = 0,
  });

  bool get isPickup => deliveryMethod == DeliveryMethod.pickup;
}