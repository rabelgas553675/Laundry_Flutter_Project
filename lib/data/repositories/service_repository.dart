import 'package:flutter/foundation.dart';

import '../datasources/service_datasource.dart';
import '../../models/service_model.dart';
import '../../core/utils/service_unit.dart';

/// PART 1 fix — [kDefaultServices] below did not previously pass
/// [ServiceModel.serviceType] / [ServiceModel.pricingType] for any
/// entry, so every seeded service (including "Dry Cleaning" and
/// "Wash & Ironing") would be written to Firestore with the
/// constructor's defaults — [ServiceType.standardWash] and
/// [PricingType.perKg] — baked directly into the document. On *read*,
/// [ServiceTypeParsing.resolve]/[PricingTypeParsing.resolve] mask
/// this by falling back to name/unit-based inference when the stored
/// value is missing, but the stored value here was never missing —
/// it was present and wrong. Each entry below now states its real
/// [ServiceType]/[PricingType] explicitly so the document written to
/// Firestore is correct from the moment it's created, not just
/// "corrected" every time it happens to be re-read.

/// PART 08 default catalog. Only ever used by [seedDefaultServicesIfEmpty]
/// to populate a brand-new Firestore project — the UI never reads this
/// list directly, so prices always come from Firestore, never a widget.
///
/// Per-piece pricing (Part 1): "Dry Cleaning" and "Wash & Ironing" are
/// added here as real, orderable [ServiceModel] entries with
/// `unit: ServiceUnit.piece` — `explore_services_screen.dart`'s
/// "Dry Cleaning" / "Wash & Ironing" grid tiles already look for a
/// service matching the `'dry'` / `'iron'` keyword (see
/// `_matchService`/`_mainCategories` there), but until now no seeded
/// service actually had that name, so those tiles always fell back to
/// their "not available yet" placeholder. The three original kg-based
/// services now carry an explicit `unit: ServiceUnit.kilogram` too,
/// instead of relying on the model's default.
const List<ServiceModel> kDefaultServices = [
  ServiceModel(
    id: '',
    name: 'Quick Wash',
    description: 'Fast turnaround wash for everyday laundry.',
    pricePerKg: 60,
    estimatedTime: '3 hours',
    unit: ServiceUnit.kilogram,
    serviceType: ServiceType.quickWash,
    pricingType: PricingType.perKg,
  ),
  ServiceModel(
    id: '',
    name: 'Standard Wash',
    description: 'Our regular wash, dry, and fold service.',
    pricePerKg: 70,
    estimatedTime: '24 hours',
    unit: ServiceUnit.kilogram,
    serviceType: ServiceType.standardWash,
    pricingType: PricingType.perKg,
  ),
  ServiceModel(
    id: '',
    name: 'Premium Wash',
    description: 'Gentle detergents with fabric care for delicate items.',
    pricePerKg: 100,
    estimatedTime: '48 hours',
    unit: ServiceUnit.kilogram,
    serviceType: ServiceType.premiumWash,
    pricingType: PricingType.perKg,
  ),
  ServiceModel(
    id: '',
    name: 'Dry Cleaning',
    description: 'Professional dry cleaning for delicate and formal wear.',
    // PART 1 — priced per garment (see `ServiceItemModel`/
    // `kDryCleaningDefaultCatalog`), not by this single number. Kept
    // non-zero rather than 0 so any code path that hasn't been
    // updated to read the per-item catalog yet still shows a sane
    // fallback instead of "₱0".
    pricePerKg: 150,
    estimatedTime: '48 hours',
    unit: ServiceUnit.piece,
    serviceType: ServiceType.dryCleaning,
    pricingType: PricingType.perItem,
  ),
  ServiceModel(
    id: '',
    name: 'Wash & Ironing',
    description: 'Wash, dry, and press — ready to wear, per kilo.',
    pricePerKg: 80,
    estimatedTime: '24 hours',
    unit: ServiceUnit.kilogram,
    serviceType: ServiceType.washAndIroning,
    pricingType: PricingType.perKg,
  ),
];

class ServiceRepository {
  ServiceRepository({ServiceDatasource? datasource})
      : _datasource = datasource ?? ServiceDatasource();

  final ServiceDatasource _datasource;

  /// Session cache — cleared via [clearCache]. Avoids re-fetching the
  /// same short, rarely-changing list on every dashboard rebuild.
  List<ServiceModel>? _cachedActive;

  Future<List<ServiceModel>> getActiveServices({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedActive != null) {
      return _cachedActive!;
    }
    final services = await _datasource.getActiveServices();
    _cachedActive = services;
    return services;
  }

  /// Part 17 — Admin service management needs inactive services too.
  Future<List<ServiceModel>> getAllServices() {
    return _datasource.getAllServices();
  }

  /// Seeds whichever entries in [kDefaultServices] don't already exist
  /// yet, matched by name (case-insensitive).
  ///
  /// This used to only run when the whole collection was empty, which
  /// meant that once *any* services existed — even just 2 out of 3,
  /// from an earlier version of this list or a manual console edit —
  /// it would never seed the rest. That's why Premium Wash could go
  /// missing forever even after being added to [kDefaultServices].
  /// Checking by name makes this self-healing: safe to call on every
  /// app start, and it naturally catches up if you add a 4th default
  /// later too.
  ///
  /// PRODUCTION FIX — this is called from every customer-facing
  /// screen that browses services (`ServiceSelectionCard`,
  /// `ExploreServicesScreen`, `ServiceBundleScreen`, `ServiceSelection`)
  /// as a "catch the catalog up if a default is missing" convenience.
  /// But `firestore.rules` only allows *admins* to create documents
  /// in `services` — a regular customer's write here is expected to
  /// fail with `permission-denied`. Before this fix, that exception
  /// propagated straight out of this method, so `_loadServices()` in
  /// every calling screen would show a raw "Error:
  /// [cloud_firestore/permission-denied] Missing or insufficient
  /// permissions." instead of the services that actually exist —
  /// this became visible in practice the moment Part 1 of the
  /// per-piece pricing feature added two new entries ("Dry Cleaning",
  /// "Wash & Ironing") to [kDefaultServices] that hadn't been created
  /// in Firestore yet, since every customer's next app load would
  /// detect them as missing and try (and fail) to seed them.
  ///
  /// Seeding is now best-effort: if the write is rejected (or fails
  /// for any other reason — network, etc.), this silently continues
  /// rather than failing the whole catalog load. The one caller that
  /// genuinely can seed successfully is [ManageServicesScreen], which
  /// is reachable only by an admin (enforced by `RoleGuard`) and also
  /// calls this method — that's the actual place new defaults get
  /// created for real.
  Future<void> seedDefaultServicesIfEmpty() async {
    final existingNames = await _datasource.getExistingServiceNames();
    final missing = kDefaultServices
        .where((service) => !existingNames.contains(service.name.toLowerCase().trim()))
        .toList();

    if (missing.isEmpty) return;

    try {
      await _datasource.seedDefaults(missing);
      _cachedActive = null; // force a fresh read next call
    } catch (e, stackTrace) {
      debugPrint('ServiceRepository: seeding default services skipped: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Part 17 — Add service.
  Future<void> createService(ServiceModel service) async {
    await _datasource.createService(service);
    _cachedActive = null;
  }

  /// Part 17 — Edit price/description/estimated time, or
  /// activate/deactivate.
  Future<void> updateService(ServiceModel updated) async {
    await _datasource.updateServiceFields(updated.id, updated.toEditableMap());
    _cachedActive = null;
  }

  void clearCache() {
    _cachedActive = null;
  }
}