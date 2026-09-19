import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// "Service Photo" upload area shown inside [ServiceFormDialog], between
/// the Service Name and Description fields.
///
/// Purely presentational — it never picks, uploads, or deletes
/// anything itself. The dialog owns that state and hands it in:
///
///  * [pendingImageBytes] — a photo the admin just picked this session
///    and hasn't saved yet. Takes priority over [existingImageUrl] so
///    replacing a photo previews immediately instead of showing the
///    old one until Save.
///  * [existingImageUrl] — the service's already-saved photo (Edit
///    flow). Ignored once [pendingImageBytes] is set.
///
/// It never generates or assumes a default/placeholder photo: with
/// nothing picked and nothing saved it shows a plain upload prompt, so
/// the only image that can ever end up on a service is one the admin
/// uploaded.
///
/// Styling follows the dialog's frosted-glass treatment: the brand
/// blue (`0xff2E75B6`) tint used by the dialog's header icon, the same
/// 16px corner radius and soft shadow as [AppTextField], and the same
/// `black87` / `black54` text colors as the rest of the dialog.
class ServicePhotoField extends StatelessWidget {
  const ServicePhotoField({
    super.key,
    required this.onPick,
    required this.onRemove,
    this.pendingImageBytes,
    this.existingImageUrl,
    this.isBusy = false,
    this.enabled = true,
  });

  /// Opens the device's file/photo picker. Used for both the initial
  /// upload and for replacing an existing photo.
  final VoidCallback onPick;

  /// Clears the currently shown photo (picked or saved).
  final VoidCallback onRemove;

  final Uint8List? pendingImageBytes;
  final String? existingImageUrl;

  /// True while a freshly picked photo is being validated/read —
  /// shows a spinner over the preview instead of the tap doing nothing.
  final bool isBusy;

  /// False while the dialog is saving; the whole field dims and stops
  /// responding to taps.
  final bool enabled;

  static const _brand = Color(0xff2E75B6);
  static const _danger = Color(0xffFF4D67);
  static const _radius = 16.0;

  bool get _hasPhoto =>
      pendingImageBytes != null || (existingImageUrl ?? '').trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: SizedBox(
        width: double.infinity,
        child: AspectRatio(
          aspectRatio: 2,
          child: _hasPhoto ? _buildFilled() : _buildEmpty(),
        ),
      ),
    );
  }

  // ── Empty state: dashed upload zone ─────────────────────────────

  Widget _buildEmpty() {
    // The fill is the Material's own color (not a Container above the
    // InkWell) so the tap splash paints over it instead of behind it —
    // same reason the dialog wraps its switch/buttons in a transparent
    // Material.
    return Material(
      color: _brand.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(_radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled && !isBusy ? onPick : null,
        child: CustomPaint(
          foregroundPainter: _DashedRRectPainter(
            color: _brand.withValues(alpha: 0.45),
            radius: _radius,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const Center(child: _EmptyPrompt()),
              if (isBusy) const _BusyOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filled state: preview + Replace / Remove ────────────────────

  Widget _buildFilled() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: const Color(0xffF1F3F5),
              child: _buildImage(),
            ),
            // Tapping the photo itself also opens the picker (replace).
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(onTap: enabled && !isBusy ? onPick : null),
              ),
            ),
            if (isBusy) const _BusyOverlay(),
            Positioned(
              right: 10,
              bottom: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _OverlayChip(
                    icon: Icons.edit_outlined,
                    label: 'Replace',
                    background: Colors.black.withValues(alpha: 0.55),
                    onTap: enabled && !isBusy ? onPick : null,
                  ),
                  const SizedBox(width: 8),
                  _OverlayChip(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove',
                    background: _danger.withValues(alpha: 0.9),
                    onTap: enabled && !isBusy ? onRemove : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage() {
    final pending = pendingImageBytes;
    if (pending != null) {
      return Image.memory(pending, fit: BoxFit.cover);
    }
    return Image.network(
      existingImageUrl!.trim(),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const _ImageLoadError(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            height: 22,
            width: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Icon + "Add Service Photo" + "Tap to upload from your device".
class _EmptyPrompt extends StatelessWidget {
  const _EmptyPrompt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: ServicePhotoField._brand.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.add_photo_alternate_outlined,
            size: 22,
            color: ServicePhotoField._brand,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Add Service Photo',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Tap to upload from your device',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

/// Shown when a saved photo's URL fails to load (deleted from Storage,
/// offline, ...). Replace/Remove stay available on top of it, so the
/// admin can always fix it.
class _ImageLoadError extends StatelessWidget {
  const _ImageLoadError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, size: 30, color: Colors.black38),
          SizedBox(height: 6),
          Text(
            "Couldn't load this photo",
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.25),
        child: const Center(
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Small pill button laid over the photo (Replace / Remove).
class _OverlayChip extends StatelessWidget {
  const _OverlayChip({
    required this.icon,
    required this.label,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rectangle outline for the empty upload zone.
/// Flutter has no built-in dashed border, and a package isn't worth it
/// for one widget.
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dash = 7.0;
  static const _gap = 5.0;
  static const _stroke = 1.4;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + _dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}