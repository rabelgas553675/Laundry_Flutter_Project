import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../errors/app_exception.dart';

/// Picking, validating, and uploading the user's profile photo.
/// Firestore (via UserRepository) only ever stores the resulting
/// public URL — this class is the only place raw image bytes touch
/// the network.
///
/// Storage backend: Supabase Storage (bucket "profile-images"), not
/// Firebase Storage — Firebase Storage requires the paid Blaze plan
/// even at $0 usage (policy change, Feb 2026), so this app uses
/// Supabase's free tier instead. Firebase Auth/Firestore are
/// untouched; only file storage moved.
class FileService {
  FileService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  static const _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const _allowedExtensions = {'jpg', 'jpeg', 'png'};
  static const _bucket = 'profile-images';

  /// PART 19 — separate bucket for admin-uploaded promo photos, kept
  /// apart from [_bucket] the same way the two features are otherwise
  /// unrelated (different owner — admin vs. the signed-in user —
  /// different lifetime, different access pattern). Must exist in the
  /// Supabase project (public bucket, same setup as "profile-images")
  /// before this is used.
  static const _promoBucket = 'promo-images';

  /// Separate bucket for admin-uploaded service photos (Manage Services
  /// → Add/Edit Service), kept apart from [_promoBucket] for the same
  /// reason promo photos are kept apart from profile photos. Must exist
  /// in the Supabase project (public bucket, same setup and policies as
  /// "promo-images") before this is used.
  static const _serviceBucket = 'service-images';

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  Future<XFile?> pickFromCamera() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  }

  Future<XFile?> pickFromGallery() {
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  }

  /// Public entry point to the same checks [uploadServiceImage] /
  /// [uploadPromoImage] run at upload time (JPG/PNG only, not empty,
  /// under 5 MB) so a form can reject a bad file the moment it's
  /// picked, instead of only after the admin taps Save. Throws
  /// [AppException] with a user-facing message.
  Future<void> validateImage(XFile file) => _validate(file);

  /// Throws [AppException] (never a raw platform exception) so callers
  /// can show `e.message` straight in a SnackBar.
  ///
  /// IMPORTANT: uses [XFile.name], not [XFile.path], for the extension
  /// check. On Flutter web, `path` is a blob URL (e.g.
  /// `blob:http://localhost:64064/3f2a1c-...`) with no real file
  /// extension, so checking it here rejected every valid PNG/JPG picked
  /// in the browser. `name` is the original filename on every platform.
  Future<void> _validate(XFile file) async {
    final extension = file.name.split('.').last.toLowerCase();
    if (!_allowedExtensions.contains(extension)) {
      throw const AppException('Only JPG and PNG images are supported.');
    }

    final sizeBytes = await file.length();
    if (sizeBytes == 0) {
      throw const AppException('That image looks empty — try another one.');
    }
    if (sizeBytes > _maxFileSizeBytes) {
      throw const AppException('Image must be smaller than 5 MB.');
    }
  }

  /// Fixed filename per user — a re-upload simply overwrites the old
  /// object instead of leaving orphaned files behind in Storage.
  String _profilePath(String uid) => 'users/$uid/profile.jpg';

  /// Validates, uploads to `profile-images/users/{uid}/profile.jpg`,
  /// and returns the public URL to save on the Firestore document.
  ///
  /// Uses `uploadBinary` with raw bytes (via `XFile.readAsBytes()`)
  /// instead of `upload` + `dart:io.File`, because `dart:io.File` has
  /// no working implementation on Flutter web — this keeps the upload
  /// path identical across web, Android, and iOS.
  Future<String> uploadProfileImage({
    required String uid,
    required XFile file,
  }) async {
    await _validate(file);

    try {
      final path = _profilePath(uid);
      final bytes = await file.readAsBytes();
      await _client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const sb.FileOptions(
              contentType: 'image/jpeg',
              upsert: true, // overwrite the previous photo at this path
            ),
          );
      // Cache-bust so a re-uploaded photo shows immediately instead of
      // a cached copy of the old one at the same URL.
      final publicUrl = _client.storage.from(_bucket).getPublicUrl(path);
      return '$publicUrl?updated=${DateTime.now().millisecondsSinceEpoch}';
    } on sb.StorageException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Upload failed. Please try again.');
    }
  }

  /// Deletes the stored profile image. A missing object (nothing was
  /// ever uploaded) is treated as success, not an error.
  Future<void> removeProfileImage(String uid) async {
    try {
      await _client.storage.from(_bucket).remove([_profilePath(uid)]);
    } on sb.StorageException catch (e) {
      // Supabase returns a 400 with this message when the object
      // doesn't exist — treat it the same as "nothing to delete".
      if (e.message.toLowerCase().contains('not found')) return;
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not remove the photo. Please try again.');
    }
  }

  /// PART 19 — fixed filename per promo, same reasoning as
  /// [_profilePath]: replacing a promo's photo overwrites the same
  /// Storage object instead of leaving orphaned files behind.
  String _promoPath(String promoId) => 'promos/$promoId/photo.jpg';

  /// Validates, uploads to `promo-images/promos/{promoId}/photo.jpg`,
  /// and returns the public URL to save as [PromoModel.imageUrl].
  ///
  /// [promoId] is generated up front by the caller (see
  /// `PromoRepository.newPromoId`) so this can run — and the resulting
  /// URL can be saved together with the rest of the promotion's
  /// fields on its very first write — before the Firestore document
  /// itself exists.
  Future<String> uploadPromoImage({
    required String promoId,
    required XFile file,
  }) async {
    await _validate(file);

    try {
      final path = _promoPath(promoId);
      final bytes = await file.readAsBytes();
      await _client.storage.from(_promoBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const sb.FileOptions(
              contentType: 'image/jpeg',
              upsert: true, // overwrite the previous photo at this path
            ),
          );
      // Cache-bust so a replaced photo shows immediately instead of a
      // cached copy of the old one at the same URL.
      final publicUrl = _client.storage.from(_promoBucket).getPublicUrl(path);
      return '$publicUrl?updated=${DateTime.now().millisecondsSinceEpoch}';
    } on sb.StorageException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Upload failed. Please try again.');
    }
  }

  /// Deletes a promo's stored photo. A missing object is treated as
  /// success, same as [removeProfileImage].
  Future<void> removePromoImage(String promoId) async {
    try {
      await _client.storage.from(_promoBucket).remove([_promoPath(promoId)]);
    } on sb.StorageException catch (e) {
      if (e.message.toLowerCase().contains('not found')) return;
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not remove the photo. Please try again.');
    }
  }

  /// Fixed filename per service, same reasoning as [_promoPath]:
  /// replacing a service's photo overwrites the same Storage object
  /// instead of leaving orphaned files behind.
  String _servicePath(String serviceId) => 'services/$serviceId/photo.jpg';

  /// Validates, uploads to `service-images/services/{serviceId}/photo.jpg`,
  /// and returns the public URL to save as [ServiceModel.imageUrl].
  ///
  /// [serviceId] is known before the Firestore document exists (see
  /// `ServiceRepository.newServiceId`), so a brand-new service's photo
  /// can be uploaded first and its URL written together with the rest
  /// of the fields in the service's very first write.
  Future<String> uploadServiceImage({
    required String serviceId,
    required XFile file,
  }) async {
    await _validate(file);

    try {
      final path = _servicePath(serviceId);
      final bytes = await file.readAsBytes();
      await _client.storage.from(_serviceBucket).uploadBinary(
            path,
            bytes,
            fileOptions: const sb.FileOptions(
              contentType: 'image/jpeg',
              upsert: true, // overwrite the previous photo at this path
            ),
          );
      // Cache-bust so a replaced photo shows immediately instead of a
      // cached copy of the old one at the same URL.
      final publicUrl = _client.storage.from(_serviceBucket).getPublicUrl(path);
      return '$publicUrl?updated=${DateTime.now().millisecondsSinceEpoch}';
    } on sb.StorageException catch (e) {
      throw AppException(e.message.isNotEmpty ? e.message : 'Upload failed. Please try again.');
    }
  }

  /// Deletes a service's stored photo. A missing object is treated as
  /// success, same as [removePromoImage].
  Future<void> removeServiceImage(String serviceId) async {
    try {
      await _client.storage.from(_serviceBucket).remove([_servicePath(serviceId)]);
    } on sb.StorageException catch (e) {
      if (e.message.toLowerCase().contains('not found')) return;
      throw AppException(e.message.isNotEmpty ? e.message : 'Could not remove the photo. Please try again.');
    }
  }
}