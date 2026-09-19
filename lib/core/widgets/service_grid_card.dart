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

/// Photo + ETA badge + price/name/arrow card for a single service.
class ServiceGridCard extends StatelessWidget {
  const ServiceGridCard({
    super.key,
    required this.service,
    required this.onTap,
  });

  final ServiceModel service;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
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
                  child: Image.asset(
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