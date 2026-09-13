import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Thin access point for Firebase service instances.
///
/// Nothing in here does auth, reads/writes data, or sends
/// notifications yet — those come in Parts 04, 07, 08+, and 14.
/// This just centralizes access so later code doesn't scatter
/// `FirebaseAuth.instance` / `FirebaseFirestore.instance` calls
/// everywhere, which makes testing/mocking easier down the line.
class FirebaseService {
  FirebaseService._();

  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseFirestore get firestore => FirebaseFirestore.instance;
  static FirebaseStorage get storage => FirebaseStorage.instance;
  static FirebaseMessaging get messaging => FirebaseMessaging.instance;
}