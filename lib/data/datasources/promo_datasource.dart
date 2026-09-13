import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/services/firebase_service.dart';
import '../../models/promo_model.dart';

/// Raw Firestore access for the `promos` collection. No business
/// rules here (no "is this promo currently valid" logic) — that
/// belongs in [PromoRepository], same split as
/// ServiceDatasource/ServiceRepository.
///
/// PART 18A only needs read access (browse + look-up-by-code); PART
/// 18B is what adds admin create/update methods on top of this.
class PromoDatasource {
  static const _timeout = Duration(seconds: 10);

  CollectionReference<Map<String, dynamic>> get _promosRef =>
      FirebaseService.firestore.collection('promos');

  FirebaseException _timeoutException(String action) => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'deadline-exceeded',
        message: 'Timed out $action — check your network connection.',
      );

  /// All promos with `status == active` (the admin on/off switch —
  /// see [PromoStatus]). Whether each one is also within its
  /// start/end date window is a PART 18A concern for
  /// [PromoRepository], not this raw read.
  Future<List<PromoModel>> getActiveStatusPromos() async {
    final snapshot = await _promosRef
        .where('status', isEqualTo: PromoStatus.active.value)
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading promotions'));

    return snapshot.docs.map(PromoModel.fromFirestore).toList();
  }

  /// Looks up a single promo by its exact (already-uppercased) code.
  /// Returns `null` if no promo document has that code.
  Future<PromoModel?> getByCode(String code) async {
    final snapshot = await _promosRef
        .where('code', isEqualTo: code)
        .limit(1)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking that promo code'));

    if (snapshot.docs.isEmpty) return null;
    return PromoModel.fromFirestore(snapshot.docs.first);
  }

  /// PART 18B — Admin promo management needs every promo regardless of
  /// [PromoStatus] (active AND inactive), unlike PART 18A's
  /// [getActiveStatusPromos], so admins can find and reactivate an
  /// inactive/expired promo too. Same "read everything, unfiltered"
  /// shape as ServiceDatasource.getAllServices.
  Future<List<PromoModel>> getAllPromos() async {
    final snapshot = await _promosRef
        .orderBy('createdAt', descending: true)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('loading promotions'));

    return snapshot.docs.map(PromoModel.fromFirestore).toList();
  }

  /// PART 18B — "Promo code must be unique." All promo codes are
  /// stored upper-cased (see [PromoModel.code]'s doc comment), so
  /// [code] is expected to already be upper-cased by the caller.
  /// [excludeId], when given, excludes that document from the check —
  /// used by [EditPromoScreen] so saving a promo without changing its
  /// own code never falsely reports a collision with itself.
  Future<bool> isCodeTaken(String code, {String? excludeId}) async {
    final snapshot = await _promosRef
        .where('code', isEqualTo: code)
        .limit(5)
        .get()
        .timeout(_timeout, onTimeout: () => throw _timeoutException('checking that promo code'));

    if (excludeId == null) return snapshot.docs.isNotEmpty;
    return snapshot.docs.any((doc) => doc.id != excludeId);
  }

  /// PART 18B — "Create promotions."
  Future<void> createPromo(PromoModel promo) {
    return _promosRef
        .add(promo.toMapForCreate())
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the promotion'));
  }

  /// PART 18B — Admin edits (code, discount type/value, minimum
  /// order, valid dates, description, active/inactive).
  Future<void> updatePromoFields(String id, Map<String, dynamic> fields) {
    return _promosRef
        .doc(id)
        .update(fields)
        .timeout(_timeout, onTimeout: () => throw _timeoutException('saving the promotion'));
  }
}