// TARGET PATH IN YOUR PROJECT: lib/core/widgets/service_grid_card.dart
//
// Shared "photo card" for a single laundry service — big service photo +
// ETA badge on top, price/name/arrow row below. Used by
// ExploreServicesScreen and ServiceBundleScreen so every service tile in
// the app looks identical.
//
// FIXES IN THIS VERSION
//  1. "BOTTOM OVERFLOWED BY 4.1 PIXELS": the price ("$70.00 Per Kg") used
//     to wrap onto two lines in narrow grid cells, making the card taller
//     than the grid cell. It is now forced onto ONE line and scales down
//     slightly if the cell is too narrow (FittedBox + scaleDown).
//  2. ETA badge is now a solid white pill with coloured text, so it stays
//     readable on top of any photo.
//  3. BUG FIX: `useUploadedImage` now defaults to `true` instead of
//     `false`. Previously every call site that didn't explicitly pass
//     `useUploadedImage: true` silently ignored the admin's uploaded
//     photo (ServiceModel.imageUrl) and fell back to the bundled
//     category asset picked by matching keywords in the service name
//     (assetPathForService) — meaning services with a custom name (e.g.
//     "SSFDGF") always showed the generic standard_wash.png regardless
//     of what photo the admin uploaded for them, and even services
//     whose name happened to match a keyword (e.g. "Dry Cleaning")
//     showed the bundled stock photo instead of the admin's own upload.
//     Defaulting to `true` makes "show the admin's real photo when one
//     exists" the behavior everywhere, with the bundled asset only used
//     as a fallback when `imageUrl` is null/empty (see
//     uploadedImageUrlForService) or fails to load (see errorBuilder
//     in _ServicePhoto).
//
// NOTE: ServiceModel exposes a real `unit` field
// (`core/utils/service_unit.dart`), so the kg-vs-piece question is always
// answered from `service.unit` — never re-derived from the service name.

import 'package:flutter/material.dart';

import '../../models/service_model.dart';
import '../utils/service_unit.dart';
import 'app_card.dart';

/// Whether a service's price is picked manually at checkout (the
/// "Service Bundle" tile) rather than shown directly on the card.
bool isBundleService(ServiceModel service) {
  final name = service.name.toLowerCase();
  return name.contains('bundle') || name.contains('pick');
}

const List<Color> _etaPalette = [
  Color(0xff36b37e), // green
  Color(0xfff59f00), // orange
  Color(0xffe8567a), // pink/red
];

Color etaBadgeColorForService(ServiceModel service, {required bool isBundle}) {
  if (isBundle) return const Color(0xff3d8bff);
  final index = service.estimatedTime.hashCode.abs() % _etaPalette.length;
  return _etaPalette[index];
}

/// Maps a service to its bundled asset image (see pubspec.yaml assets).
///
/// Dry Cleaning, Wash & Ironing, and Service Bundle use .jpg — the other
/// services use .png.
String assetPathForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return 'assets/images/quick_wash.png';
  if (name.contains('premium')) return 'assets/images/premium_wash.png';
  if (name.contains('dry')) return 'assets/images/dry_cleaning.jpg';
  if (name.contains('iron')) return 'assets/images/wash_and_ironing.jpg';
  if (name.contains('bundle') || name.contains('pick')) {
    return 'assets/images/service_bundle.jpg';
  }
  if (name.contains('regular')) return 'assets/images/regular_wash.png';
  return 'assets/images/standard_wash.png';
}

/// Fallback icon shown (via errorBuilder) only if the asset above fails
/// to load.
IconData iconForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return Icons.flash_on_outlined;
  if (name.contains('premium')) return Icons.auto_awesome_outlined;
  if (name.contains('dry')) return Icons.checkroom_outlined;
  if (name.contains('iron')) return Icons.iron_outlined;
  if (name.contains('bundle') || name.contains('pick')) {
    return Icons.shopping_basket_outlined;
  }
  return Icons.local_laundry_service_outlined;
}

/// The admin-uploaded photo URL for [service] (Manage Services → Add /
/// Edit Service → Service Photo), trimmed — or null when the admin
/// hasn't uploaded one.
String? uploadedImageUrlForService(ServiceModel service) {
  final url = service.imageUrl?.trim();
  return (url == null || url.isEmpty) ? null : url;
}

/// Photo + ETA badge + price/name/arrow card for a single service.
class ServiceGridCard extends StatelessWidget {
  const ServiceGridCard({
    super.key,
    required this.service,
    required this.onTap,
    this.useUploadedImage = true,
  });

  final ServiceModel service;
  final VoidCallback onTap;

  /// When true, the photo the admin uploaded for this service
  /// ([ServiceModel.imageUrl]) is shown instead of the bundled
  /// category image. Image priority is then:
  ///   1. admin-uploaded photo
  ///   2. bundled default/category image ([assetPathForService])
  ///   3. fallback icon ([iconForService])
  /// (2 and 3 are also what's shown if the uploaded photo fails to
  /// load, so a broken URL never leaves a blank card.)
  ///
  /// Defaults to `true` so every call site shows the admin's real
  /// photo whenever one exists; pass `false` only for a call site
  /// that must always show the bundled category image regardless of
  /// what the admin uploaded.
  final bool useUploadedImage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isBundle = isBundleService(service);
    final badgeColor = etaBadgeColorForService(service, isBundle: isBundle);

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---- Service photo -------------------------------------------------
          AspectRatio(
            aspectRatio: 1.2,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _ServicePhoto(
                    service: service,
                    useUploadedImage: useUploadedImage,
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      // Solid-ish white so the coloured text is readable
                      // on top of any photo.
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isBundle
                          ? 'Up-to You'
                          : (service.estimatedTime.isEmpty
                              ? 'ETA —'
                              : 'ETA ${service.estimatedTime}'),
                      style: textTheme.labelSmall?.copyWith(
                        color: badgeColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // ---- Price / name / arrow -----------------------------------------
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isBundle)
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Pick Manually',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: Color(0xff9e1e77),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Color(0xff9e1e77),
                            ),
                          ],
                        ),
                      )
                    else
                      // Forced onto ONE line; scales down if the cell is
                      // too narrow. This is what removes the 4.1px
                      // bottom overflow.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: RichText(
                          maxLines: 1,
                          softWrap: false,
                          text: TextSpan(
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: const Color(0xff9e1e77),
                            ),
                            children: [
                              TextSpan(
                                text:
                                    '\$${service.pricePerKg.toStringAsFixed(2)}',
                              ),
                              TextSpan(
                                text:
                                    ' ${ServiceUnitFormat.perUnitPhrase(service.unit)}',
                                style: textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.normal,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      service.name,
                      style: textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              _ArrowButton(onTap: onTap),
            ],
          ),
        ],
      ),
    );
  }
}

/// The card's photo, following the image priority documented on
/// [ServiceGridCard.useUploadedImage]. The default (bundled image →
/// icon) branch is the card's original, unchanged image code.
class _ServicePhoto extends StatelessWidget {
  const _ServicePhoto({
    required this.service,
    required this.useUploadedImage,
  });

  final ServiceModel service;
  final bool useUploadedImage;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Priority 2 → 3: bundled category image, then the icon.
    Widget defaultPhoto() {
      return Image.asset(
        assetPathForService(service),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: colors.primary.withValues(alpha: 0.08),
            child: Center(
              child: Icon(
                iconForService(service),
                size: 32,
                color: colors.primary,
              ),
            ),
          );
        },
      );
    }

    final uploadedUrl =
        useUploadedImage ? uploadedImageUrlForService(service) : null;
    if (uploadedUrl == null) return defaultPhoto();

    // Priority 1: the admin's real photo. The saved URL carries a
    // cache-busting `?updated=` stamp (see FileService), so a replaced
    // photo is a new URL and loads immediately instead of a cached
    // copy of the old one.
    return Image.network(
      uploadedUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => defaultPhoto(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        // Neutral tint (the same one the icon fallback uses) rather
        // than the bundled image, so the wrong photo never flashes
        // before the real one arrives.
        return Container(
          color: colors.primary.withValues(alpha: 0.08),
          child: const Center(
            child: SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xfff3e6ef),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.north_east_rounded,
            size: 16,
            color: Color(0xff9e1e77),
          ),
        ),
      ),
    );
  }
}