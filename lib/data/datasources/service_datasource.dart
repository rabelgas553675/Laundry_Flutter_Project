import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/service_model.dart';

/// Raw Firestore access for the `services` collection.
/// No business rules here — just reads/writes, same split as
/// UserDatasource/UserRepository.
class ServiceDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _servicesRef =>
      FirebaseService.firestore.collection('services');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  /// NOTE: This intentionally does NOT combine `where()` + `orderBy()`
  /// on different fields. That combination requires a Firestore
  /// composite index, and until that index exists the query throws
  /// `failed-precondition` — which is what was causing "Could not
  /// load services." Sorting client-side avoids needing that index.
  Future<List<ServiceModel>> getActiveServices() async {
    final snapshot = await _servicesRef
        .where('status', isEqualTo: ServiceStatus.active.value)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading services'));

    final services = snapshot.docs.map(ServiceModel.fromFirestore).toList();
    services.sort(_byCreatedAt);
    return services;
  }

  /// Part 17 — Admin service management needs inactive services too (to
  /// reactivate them), so this reads everything, unfiltered.
  Future<List<ServiceModel>> getAllServices() async {
    final snapshot = await _servicesRef
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading services'));

    final services = snapshot.docs.map(ServiceModel.fromFirestore).toList();
    services.sort(_byCreatedAt);
    return services;
  }

  int _byCreatedAt(ServiceModel a, ServiceModel b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  }

  Future<int> countAll() async {
    final agg = await _servicesRef
        .count()
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking services'));
    return agg.count ?? 0;
  }

  /// Names of every existing service document, lowercased for a
  /// case-insensitive comparison against `kDefaultServices`.
  ///
  /// Used to seed only the defaults that are actually missing, instead
  /// of an all-or-nothing "collection is empty" check — that's what
  /// let Premium Wash silently never get created once Quick Wash and
  /// Standard Wash already existed.
  Future<Set<String>> getExistingServiceNames() async {
    final snapshot = await _servicesRef
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking services'));
    return snapshot.docs
        .map((doc) => (doc.data()['name'] as String? ?? '').toLowerCase().trim())
        .toSet();
  }

  Future<void> createService(ServiceModel service) {
    return _servicesRef
        .doc(service.id.isEmpty ? null : service.id)
        .set(service.toMapForCreate())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the service'));
  }

  /// Batch-writes whichever default services are passed in (already
  /// filtered down to the missing ones by the repository).
  Future<void> seedDefaults(List<ServiceModel> defaults) async {
    if (defaults.isEmpty) return;
    final batch = FirebaseService.firestore.batch();
    for (final service in defaults) {
      batch.set(_servicesRef.doc(), service.toMapForCreate());
    }
    await batch
        .commit()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('seeding default services'));
  }

  /// Part 17 — Admin edits (price, description, estimated time,
  /// activate/deactivate).
  Future<void> updateServiceFields(String id, Map<String, dynamic> fields) {
    return _servicesRef
        .doc(id)
        .update(fields)
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the service'));
  }
}