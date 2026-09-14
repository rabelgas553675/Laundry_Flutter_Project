import '../datasources/service_datasource.dart';
import '../../models/service_model.dart';

/// PART 08 default catalog. Only ever used by [seedDefaultServicesIfEmpty]
/// to populate a brand-new Firestore project — the UI never reads this
/// list directly, so prices always come from Firestore, never a widget.
const List<ServiceModel> kDefaultServices = [
  ServiceModel(
    id: '',
    name: 'Quick Wash',
    description: 'Fast turnaround wash for everyday laundry.',
    pricePerKg: 60,
    estimatedTime: '3 hours',
  ),
  ServiceModel(
    id: '',
    name: 'Standard Wash',
    description: 'Our regular wash, dry, and fold service.',
    pricePerKg: 70,
    estimatedTime: '24 hours',
  ),
  ServiceModel(
    id: '',
    name: 'Premium Wash',
    description: 'Gentle detergents with fabric care for delicate items.',
    pricePerKg: 100,
    estimatedTime: '48 hours',
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
  Future<void> seedDefaultServicesIfEmpty() async {
    final existingNames = await _datasource.getExistingServiceNames();
    final missing = kDefaultServices
        .where((service) => !existingNames.contains(service.name.toLowerCase().trim()))
        .toList();

    if (missing.isEmpty) return;

    await _datasource.seedDefaults(missing);
    _cachedActive = null; // force a fresh read next call
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