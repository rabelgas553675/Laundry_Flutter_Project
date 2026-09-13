/// App-wide constant values.
///
/// Keep this file free of business logic — just names, sizes,
/// durations, and other fixed values referenced across the app.
class AppConstants {
  AppConstants._();

  static const String appName = 'Laundry Management System';

  // Spacing scale, used by widgets built in later parts.
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 16;
  static const double spacingLg = 24;
  static const double spacingXl = 32;

  // Corner radius scale.
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;

  // PART 10.2 — static drop-off info. The shop has exactly one
  // physical location, so this is a fixed constant rather than a
  // Firestore-backed model; nothing in PART 10 adds
  // database/Firebase functionality for delivery info.
  static const String shopName = 'Laundry Management System';
  static const String shopAddress =
      'Rizal Street, Digos City, Davao del Sur, Philippines';
  static const String shopBusinessHours =
      'Mon–Sat: 8:00 AM – 7:00 PM\nSun: 9:00 AM – 5:00 PM';

  // PART 11.2 — flat Pickup delivery fee fed into
  // PriceCalculator.calculate()'s `pickupFee` parameter. 0 for
  // Drop-off (handled by the caller, not here). Like shopAddress
  // above, this is a fixed constant rather than Firestore-backed —
  // PART 11 doesn't add database/Firebase functionality either. If
  // pickup pricing ever needs to vary (e.g. by [LocationAreaModel]
  // zone), this is the single place to change it.
  static const double pickupFee = 50;
}