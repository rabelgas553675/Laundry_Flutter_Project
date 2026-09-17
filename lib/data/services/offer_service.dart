import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/offer_model.dart';

/// Streams real promotional offers from Firestore, replacing the old
/// hardcoded `kPlaceholderOffers` list. Mirrors the shape of
/// `NotificationService.streamUserNotifications` elsewhere in the app
/// (a thin service around a single collection's `.snapshots()`).
///
/// Expects a `offers` collection where each document has:
///   title: string
///   description: string
///   badge: string
///   imageUrl: string
///   backgroundColorHex: string   (e.g. "#FCE4E7")
///   isActive: bool
///   priority: number             (higher shows first)
///
/// Adjust `_collectionPath` and the field names in
/// [OfferModel.fromMap] if your schema differs.
class OfferService {
  OfferService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const String _collectionPath = 'offers';

  /// Streams every currently-active offer, sorted client-side by
  /// `priority` (descending) then `title` as a stable tiebreaker.
  ///
  /// Deliberately does NOT add `.orderBy('priority')` on the query
  /// itself: combined with `.where('isActive', ...)` on a different
  /// field, Firestore requires a composite index for that, and until
  /// it exists the stream fails with FAILED_PRECONDITION — which is
  /// almost always why this silently "can't load" the first time.
  /// Sorting client-side avoids that requirement entirely.
  Stream<List<OfferModel>> streamActiveOffers() {
    return _firestore
        .collection(_collectionPath)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final offers = snapshot.docs
          .map((doc) => OfferModel.fromMap(doc.id, doc.data()))
          .toList();
      offers.sort((a, b) {
        final byPriority = b.priority.compareTo(a.priority);
        if (byPriority != 0) return byPriority;
        return a.title.compareTo(b.title);
      });
      return offers;
    });
  }
}