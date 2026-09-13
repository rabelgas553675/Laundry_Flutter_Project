/// PART 10.3 — the customer's pickup "service area" / zone.
///
/// This is intentionally NOT Firestore-backed. PART 10 keeps the
/// whole order form local to screen state — no database/Firebase
/// functionality is added until PART 12 — so the list of zones the
/// shop currently picks up from is just a small, hand-maintained
/// constant list rather than a `location_areas` collection.
///
/// If/when the shop's real coverage area needs to be managed by an
/// admin, this can be migrated to Firestore the same way
/// ServiceModel / DetergentModel / LaundryItemModel already are —
/// [LocationSelection] (the widget that renders this list) only
/// depends on getting *a* list of [LocationAreaModel]s, not on where
/// they come from.
class LocationAreaModel {
  final String id;
  final String label;

  /// Short, purely informational note shown next to the option (e.g.
  /// a rough pickup-time estimate). Not used in any price/time
  /// calculation yet — that's PART 11+.
  final String note;

  const LocationAreaModel({
    required this.id,
    required this.label,
    this.note = '',
  });

  /// Zones the shop currently offers pickup for, closest-to-shop
  /// first (see [AppConstants.shopAddress] — Rizal Street, Digos
  /// City), plus a catch-all so a customer outside these named zones
  /// is never blocked from selecting Pickup entirely.
  static const List<LocationAreaModel> pickupAreas = [
    LocationAreaModel(
      id: 'poblacion',
      label: 'Zone 1 – Poblacion (City Proper)',
      note: 'Closest to the shop · ~15–20 min pickup',
    ),
    LocationAreaModel(
      id: 'aplaya',
      label: 'Aplaya',
      note: '~20–30 min pickup',
    ),
    LocationAreaModel(
      id: 'igpit',
      label: 'Igpit',
      note: '~20–30 min pickup',
    ),
    LocationAreaModel(
      id: 'tres_de_mayo',
      label: 'Tres de Mayo',
      note: '~25–35 min pickup',
    ),
    LocationAreaModel(
      id: 'balabag',
      label: 'Balabag',
      note: '~30–40 min pickup',
    ),
    LocationAreaModel(
      id: 'colorado',
      label: 'Colorado',
      note: '~30–40 min pickup',
    ),
    LocationAreaModel(
      id: 'other',
      label: 'Other area within Digos City',
      note: 'Add details in the Landmark field below',
    ),
  ];

  /// Value equality by id — matches ServiceModel / DetergentModel /
  /// LaundryItemModel, so `selected == area` works safely in a
  /// RadioListTile without relying on identity equality.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is LocationAreaModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}