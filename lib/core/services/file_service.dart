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

  sb.SupabaseClient get _client => sb.Supabase.instance.client;

  Future<XFile?> pickFromCamera() {
    return _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
  }

  Future<XFile?> pickFromGallery() {
    return _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
  }

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
}