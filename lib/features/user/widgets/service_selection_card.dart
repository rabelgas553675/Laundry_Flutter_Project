import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';

// NOTE: ServiceModel (see models/service_model.dart) has:
//   id, name, description, pricePerKg, estimatedTime, status, createdAt
// It does NOT have assetPath / priceFormatted / etaText / etaColorCode —
// those were from an earlier draft of the model. The helpers below
// derive the same display values from the real fields instead.

/// Min/max bounds for the responsive card width. The actual width is
/// derived from the available layout width in `_ServiceSelectionCardState`
/// so the carousel adapts across phone/tablet sizes instead of using a
/// single fixed value.
const double _kMinCardWidth = 150;
const double _kMaxCardWidth = 210;

/// Fraction of the available width a single card should target before
/// being clamped to [_kMinCardWidth, _kMaxCardWidth]. Roughly shows
/// 2-2.5 cards on a typical phone width with the next card peeking in.
const double _kCardWidthFraction = 0.42;

/// Spacing between cards (must match the ListView's separatorBuilder).
const double _kCardSpacing = 16;

/// Maps a service to its bundled asset image (see pubspec.yaml assets).
/// Falls back to the standard-wash image if the name doesn't match a
/// known default service — Image.asset's errorBuilder still covers any
/// path that fails to load.
String _assetPathForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return 'assets/images/quick_wash.png';
  if (name.contains('premium')) return 'assets/images/premium_wash.png';
  return 'assets/images/standard_wash.png';
}

/// Small fallback lookup for icons if an image asset fails to load.
IconData _iconForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return Icons.flash_on_outlined;
  if (name.contains('premium')) return Icons.auto_awesome_outlined;
  return Icons.local_laundry_service_outlined;
}

/// The bold, colored leading part of the price string, e.g. "$0.80".
/// Split out from [_priceSuffix] so the card can render "Per Kg" in a
/// lighter weight, matching the reference design's two-tone price.
String _priceAmount(ServiceModel service) {
  return '\$${service.pricePerKg.toStringAsFixed(2)}';
}

/// The plain-weight trailing part of the price string, e.g. "Per Kg".
/// Per PART 08, prices always come from Firestore (ServiceModel.pricePerKg)
/// — never hard-coded in the UI. Swap the unit text here if you need a
/// different locale.
const String _priceSuffix = ' Per Kg';

/// Compact ETA badge text, e.g. "ETA 2hrs" or "ETA 3days". Empty when
/// estimatedTime is unset, so the badge simply won't render (see
/// _ServiceListItem below). Firestore stores the friendly form
/// ("3 hours", "2 days") — this just tightens it for the small pill.
String _formatEta(ServiceModel service) {
  final raw = service.estimatedTime.trim();
  if (raw.isEmpty) return '';
  final match = RegExp(r'\d+').firstMatch(raw);
  if (match == null) return 'ETA $raw';
  final number = match.group(0);
  final unit = raw.toLowerCase().contains('day') ? 'days' : 'hrs';
  return 'ETA $number$unit';
}

/// Derives a rough urgency color from the estimated-time string, since
/// ServiceModel has no dedicated color field. Falls back to grey if no
/// number of hours can be parsed out of estimatedTime.
Color _colorForEta(ServiceModel service) {
  final match = RegExp(r'\d+').firstMatch(service.estimatedTime);
  final hours = match != null ? int.tryParse(match.group(0)!) : null;
  if (hours == null) return Colors.grey;
  if (hours <= 6) return const Color(0xffa1ffc8); // green: fast
  if (hours <= 24) return const Color(0xfffff0a3); // yellow: standard
  return const Color(0xffffb4a8); // salmon/red: slower / premium
}

class ServiceSelectionCard extends StatefulWidget {
  const ServiceSelectionCard({
    super.key,
    this.onServiceTap,
    this._repository,
  });

  final ValueChanged<ServiceModel>? onServiceTap;
  final ServiceRepository? _repository;

  @override
  State<ServiceSelectionCard> createState() => _ServiceSelectionCardState();
}

class _ServiceSelectionCardState extends State<ServiceSelectionCard> {
  late final ServiceRepository _repository =
      widget._repository ?? ServiceRepository();
  late Future<List<ServiceModel>> _servicesFuture = _loadServices();

  final ScrollController _scrollController = ScrollController();

  // Whether the left/right arrows should currently be enabled, kept in
  // sync with scroll position so an arrow disables itself once you've
  // hit that end of the list instead of doing nothing silently.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateArrowState);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateArrowState);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateArrowState() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > position.minScrollExtent + 1;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  Future<List<ServiceModel>> _loadServices() async {
    try {
      await _repository.seedDefaultServicesIfEmpty();
      return await _repository.getActiveServices();
    } catch (e, stackTrace) {
      debugPrint('ServiceSelectionCard failed to load services: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _servicesFuture = _loadServices();
    });
  }

  void _scrollBy(double delta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Derives a responsive card width from the available layout width so
  /// the carousel scales sensibly on phones and tablets alike, instead
  /// of using a single fixed value.
  double _cardWidthFor(double availableWidth) {
    return (availableWidth * _kCardWidthFraction).clamp(
      _kMinCardWidth,
      _kMaxCardWidth,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // The whole "Our Services" panel is its own frosted-glass surface now
    // (previously the opaque AppCard) so it sits on the dashboard's blob
    // background the same way the app bar / bottom nav do, instead of
    // reading as a flat white box on top of it.
    return _GlassPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = _cardWidthFor(constraints.maxWidth);
          // One arrow tap scrolls roughly one card + its separator.
          final scrollStep = cardWidth + _kCardSpacing;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Our Services',
                style: textTheme.titleMedium?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 220,
                child: FutureBuilder<List<ServiceModel>>(
                  future: _servicesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              kDebugMode
                                  ? 'Error: ${snapshot.error}'
                                  : 'Could not load services.',
                              style: textTheme.bodySmall,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: _retry,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      );
                    }

                    final services = snapshot.data ?? const [];
                    if (services.isEmpty) {
                      return Center(
                        child: Text(
                          'No services available right now.',
                          style: textTheme.bodySmall,
                        ),
                      );
                    }

                    // Check arrow enabled-state once the list has content
                    // and a frame has been laid out.
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _updateArrowState();
                    });

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        ListView.separated(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: services.length,
                          separatorBuilder: (context, index) =>
                              SizedBox(width: _kCardSpacing),
                          itemBuilder: (context, index) {
                            final service = services[index];
                            return _ServiceListItem(
                              service: service,
                              width: cardWidth,
                              onTap: () =>
                                  widget.onServiceTap?.call(service),
                              colors: colors,
                              textTheme: textTheme,
                            );
                          },
                        ),
                        // Left slide arrow
                        if (services.length > 1)
                          Positioned(
                            left: 0,
                            child: _SlideArrowButton(
                              icon: Icons.chevron_left,
                              enabled: _canScrollLeft,
                              onTap: () => _scrollBy(-scrollStep),
                            ),
                          ),
                        // Right slide arrow
                        if (services.length > 1)
                          Positioned(
                            right: 0,
                            child: _SlideArrowButton(
                              icon: Icons.chevron_right,
                              enabled: _canScrollRight,
                              onTap: () => _scrollBy(scrollStep),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Frosted-glass container for the whole "Our Services" section — same
/// recipe as the dashboard's app bar and bottom nav (blur + low-alpha
/// white fill + soft white border + floating shadow) so every glass
/// surface in the app reads as one consistent material.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.12),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 26,
                spreadRadius: -6,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small circular arrow button overlaid on the list edges for sliding
/// the card carousel left/right. Now a frosted-glass disc (matching the
/// panel and cards) instead of a solid white Material button. Dims and
/// ignores taps once that direction has nothing left to scroll to.
class _SlideArrowButton extends StatelessWidget {
  const _SlideArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.35),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? onTap : null,
                child: Icon(icon, size: 20, color: Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceListItem extends StatelessWidget {
  final ServiceModel service;
  final double width;
  final VoidCallback onTap;
  final ColorScheme colors;
  final TextTheme textTheme;

  const _ServiceListItem({
    required this.service,
    required this.width,
    required this.onTap,
    required this.colors,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    const priceColor = Color(0xff9e1e77);
    final etaText = _formatEta(service);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: width,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.30),
                  Colors.white.withValues(alpha: 0.10),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.55),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 30,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                // Top Section: Large service photo & ETA Tag.
                Expanded(
                  flex: 5,
                  child: AspectRatio(
                    aspectRatio: 1.05,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(
                              _assetPathForService(service),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: colors.primary.withValues(alpha: 0.08),
                                  child: Center(
                                    child: Icon(
                                      _iconForService(service),
                                      size: 40,
                                      color: colors.primary,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        // ETA Tag — also glassy: tinted + soft border, no
                        // solid fill so it reads as frosted rather than flat.
                        if (etaText.isNotEmpty)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _colorForEta(service)
                                        .withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    etaText,
                                    style: textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Bottom Section: Price, Action Icon & Title
                Expanded(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: RichText(
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  style: textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: priceColor,
                                  ),
                                  children: [
                                    TextSpan(text: _priceAmount(service)),
                                    TextSpan(
                                      text: _priceSuffix,
                                      style: textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.22),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  width: 0.8,
                                ),
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.arrow_outward_rounded,
                                  size: 14,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          service.name,
                          textAlign: TextAlign.left,
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}