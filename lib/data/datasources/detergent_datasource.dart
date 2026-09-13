import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/detergent_model.dart';

/// Raw Firestore access for the `detergents` collection.
/// No business rules here — just reads/writes, same split as
/// ServiceDatasource/ServiceRepository.
class DetergentDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _detergentsRef =>
      FirebaseService.firestore.collection('detergents');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  /// NOTE: Sorts client-side rather than via `.orderBy('createdAt')`
  /// chained onto `.where('status', ...)` — see LaundryItemDatasource
  /// / ServiceDatasource for the same fix and why it's needed.
  Future<List<DetergentModel>> getActiveDetergents() async {
    final snapshot = await _detergentsRef
        .where('status', isEqualTo: DetergentStatus.active.value)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading detergents'));

    final detergents = snapshot.docs.map(DetergentModel.fromFirestore).toList();
    detergents.sort(_byCreatedAt);
    return detergents;
  }

  /// Reserved for future Admin detergent management (inactive
  /// detergents included, so they can be reactivated).
  Future<List<DetergentModel>> getAllDetergents() async {
    final snapshot = await _detergentsRef
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading detergents'));

    final detergents = snapshot.docs.map(DetergentModel.fromFirestore).toList();
    detergents.sort(_byCreatedAt);
    return detergents;
  }

  int _byCreatedAt(DetergentModel a, DetergentModel b) {
    final aTime = a.createdAt;
    final bTime = b.createdAt;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  }

  Future<int> countAll() async {
    final agg = await _detergentsRef
        .count()
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking detergents'));
    return agg.count ?? 0;
  }

  Future<void> createDetergent(DetergentModel detergent) {
    return _detergentsRef
        .doc(detergent.id.isEmpty ? null : detergent.id)
        .set(detergent.toMapForCreate())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the detergent'));
  }

  /// Batch-writes the PART 09 default catalog (Regular, Premium,
  /// Hypoallergenic) in one round trip.
  Future<void> seedDefaults(List<DetergentModel> defaults) async {
    final batch = FirebaseService.firestore.batch();
    for (final detergent in defaults) {
      batch.set(_detergentsRef.doc(), detergent.toMapForCreate());
    }
    await batch
        .commit()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('seeding default detergents'));
  }

  Future<void> updateDetergentFields(String id, Map<String, dynamic> fields) {
    return _detergentsRef
        .doc(id)
        .update(fields)
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the detergent'));
  }
}