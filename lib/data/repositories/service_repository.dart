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

  /// Idempotent: only writes the default catalog the very first time
  /// there are zero service documents, so re-running the app never
  /// duplicates services. Safe to call from a widget's initState/build
  /// path since it's a no-op on every call after the first.
  Future<void> seedDefaultServicesIfEmpty() async {
    final existing = await _datasource.countAll();
    if (existing > 0) return;
    await _datasource.seedDefaults(kDefaultServices);
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