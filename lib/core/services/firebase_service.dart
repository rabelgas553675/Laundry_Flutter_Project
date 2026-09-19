import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Thin access point for Firebase service instances.
///
/// Nothing in here does auth, reads/writes data, or sends
/// notifications yet — those come in Parts 04, 07, 08+, and 14.
/// This just centralizes access so later code doesn't scatter
/// `FirebaseAuth.instance` / `FirebaseFirestore.instance` calls
/// everywhere, which makes testing/mocking easier down the line.
///
/// File storage is NOT here — profile/promo/service photos all go
/// through Supabase Storage (see `core/services/file_service.dart`),
/// not Firebase Storage, so there is no `storage` getter on this
/// class.
class FirebaseService {
  FirebaseService._();

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseMessaging get messaging => FirebaseMessaging.instance;
}