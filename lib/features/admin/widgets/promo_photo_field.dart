import 'dart:typed_data';

import 'package:flutter/material.dart';

/// PART 19 — "Add Offer Photo" upload area shown on both
/// [AddPromoScreen] and [EditPromoScreen].
///
/// Purely presentational: it shows whichever photo is currently
/// picked (local [pendingImageBytes] takes priority — a freshly
/// picked photo the admin hasn't saved yet — falling back to
/// [existingImageUrl], the promo's already-uploaded photo when
/// editing), plus a "Change Photo" affordance. It never generates or
/// assumes a default image — with nothing picked and nothing
/// existing, it shows a plain upload placeholder instead.
class PromoPhotoField extends StatelessWidget {
  const PromoPhotoField({
    super.key,
    required this.onTap,
    this.pendingImageBytes,
    this.existingImageUrl,
    this.isBusy = false,
  });

  /// Opens the photo-source bottom sheet (camera/gallery/remove).
  final VoidCallback onTap;

  /// Bytes of a photo the admin just picked in this session, still
  /// unsaved. Takes priority over [existingImageUrl] so replacing a
  /// photo previews immediately instead of showing the old one until
  /// the promo is actually saved.
  final Uint8List? pendingImageBytes;

  /// The promo's already-uploaded photo (edit flow only). Ignored
  /// once [pendingImageBytes] is set.
  final String? existingImageUrl;

  /// True while a freshly picked photo is being read into memory —
  /// shows a small inline spinner over the preview instead of the
  /// tap area doing nothing visibly.
  final bool isBusy;

  bool get _hasAnyPhoto =>
      pendingImageBytes != null || (existingImageUrl ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: _buildPreview(colors),
              ),
            ),
            if (isBusy)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.25),
                    child: const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_hasAnyPhoto)
              Positioned(
                right: 10,
                bottom: 10,
                child: _ChangePhotoChip(colors: colors),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(ColorScheme colors) {
    if (pendingImageBytes != null) {
      return Image.memory(pendingImageBytes!, fit: BoxFit.cover);
    }
    final url = existingImageUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _PlaceholderContent(colors: colors),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: progress.expectedTotalBytes != null
                    ? (progress.cumulativeBytesLoaded / progress.expectedTotalBytes!)
                    : null,
              ),
            ),
          );
        },
      );
    }
    return _PlaceholderContent(colors: colors);
  }
}

class _PlaceholderContent extends StatelessWidget {
  const _PlaceholderContent({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_photo_alternate_outlined, size: 34, color: colors.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'Add Offer Photo',
            style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Tap to upload from your device',
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ChangePhotoChip extends StatelessWidget {
  const _ChangePhotoChip({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(100),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_outlined, size: 14, color: Colors.white),
          SizedBox(width: 4),
          Text(
            'Change Photo',
            style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// One row in [PromoPhotoField]'s photo-source bottom sheet (Take
/// Photo / Choose From Gallery / Remove Selected Photo).
class PromoPhotoSheetOption extends StatelessWidget {
  const PromoPhotoSheetOption({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label),
      onTap: onTap,
    );
  }
}