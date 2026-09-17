import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/utils/price_calculator.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';

/// Home-tab "Offers & Promos" section.
///
/// PART 19 — now a larger, horizontally-scrolling strip of
/// photo-based promo cards (the admin-uploaded photo from
/// [PromoModel.imageUrl] is each card's main visual), the whole
/// section wrapped in the same frosted-glass panel recipe as "Our
/// Services" (see [_GlassPanel] below — duplicated rather than
/// imported, since that panel is private to
/// service_selection_card.dart and "Our Services" itself must stay
/// untouched).
///
/// Still reuses [PromoRepository.getVisiblePromos] — the same
/// already-live, already-filtered (active + within date window) data
/// source [OffersScreen] uses — so every promo shown here, for every
/// promotion an admin creates (not just one hardcoded code), comes
/// from the same real promotion data. Fails quietly (no error card)
/// on a dashboard-level load failure, same reasoning as
/// ActiveOrdersSection — the full Offers tab, backed by the same
/// repository, already shows a real error state if the connection is
/// actually down.
class CurrentOffersSection extends StatefulWidget {
  const CurrentOffersSection({
    super.key,
    this.onSeeAll,
    this.promoRepository,
    this.maxCards = 5,
  });

  final VoidCallback? onSeeAll;

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [PromoRepository] — same pattern as
  /// [ActiveOrdersSection]'s `orderRepository`.
  final PromoRepository? promoRepository;

  /// How many promo cards to show in the horizontal strip.
  final int maxCards;

  @override
  State<CurrentOffersSection> createState() => _CurrentOffersSectionState();
}

/// Min/max bounds for the responsive offer-card width — noticeably
/// larger than the old 190px text-only card, in the same spirit as
/// _kMinCardWidth/_kMaxCardWidth in service_selection_card.dart.
const double _kMinCardWidth = 240;
const double _kMaxCardWidth = 320;

/// Fraction of the available width a single card should target
/// before being clamped — mirrors
/// service_selection_card.dart's _kCardWidthFraction, tuned wider
/// since these cards are meant to read as the larger, photo-led
/// layout PART 19 asks for.
const double _kCardWidthFraction = 0.78;

/// Spacing between cards (must match the ListView's separatorBuilder).
const double _kCardSpacing = 14;

/// Height reserved below the photo for [_PromoOfferCard]'s text block:
/// promo code (1 line) + spacing + subtitle (1 line) + spacing +
/// description (up to 2 lines, reserved even when a promo has none,
/// so every card in the row is the same height) + the card's own
/// vertical padding (10 top + 14 bottom), plus a small buffer for
/// line-height/text-scale rounding.
const double _kCardTextBlockHeight = 108;

class _CurrentOffersSectionState extends State<CurrentOffersSection> {
  late final PromoRepository _promoRepository =
      widget.promoRepository ?? PromoRepository();

  // `late final` + assigned once in initState, not called inline in
  // build() — same fix already applied to ActiveOrdersSection /
  // AdminDashboard / MyOrdersScreen / OrderStatusTracker: calling a
  // repository method directly inside build() hands FutureBuilder a
  // brand-new Future every rebuild.
  late Future<List<PromoModel>> _promosFuture;

  final ScrollController _scrollController = ScrollController();

  // Whether the left/right arrows should currently be enabled, kept
  // in sync with scroll position — same pattern as
  // _ServiceSelectionCardState._updateArrowState.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _promosFuture = _promoRepository.getVisiblePromos();
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

  double _cardWidthFor(double availableWidth) {
    return (availableWidth * _kCardWidthFraction).clamp(_kMinCardWidth, _kMaxCardWidth);
  }

  /// Total card height for a given [cardWidth]: the 16:9 photo's
  /// resulting height, plus a fixed budget for the text block below
  /// it (promo code + subtitle + up to a 2-line description +
  /// [_PromoOfferCard]'s own padding), plus a small safety buffer for
  /// text-scale/line-height rounding.
  ///
  /// This used to be a flat `220` regardless of [cardWidth] or
  /// whether a promo has a description, which is exactly why cards
  /// were overflowing: at the card widths this section actually
  /// produces, the photo alone is already close to 180px, leaving too
  /// little room underneath for even a one-line title/subtitle, let
  /// alone a two-line description.
  double _cardHeightFor(double cardWidth) {
    final photoHeight = cardWidth * 9 / 16;
    return photoHeight + _kCardTextBlockHeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // PART 19 — the whole section (header + card strip) now lives
    // inside its own frosted-glass panel, matching "Our Services",
    // instead of sitting directly on the dashboard background.
    return _GlassPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = _cardWidthFor(constraints.maxWidth);
          final scrollStep = cardWidth + _kCardSpacing;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: "Offers & Promos" + "See all" — kept
              // exactly as before.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Offers & Promos',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  GestureDetector(
                    onTap: widget.onSeeAll,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text(
                        'See all',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FutureBuilder<List<PromoModel>>(
                future: _promosFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      height: _cardHeightFor(cardWidth),
                      child: const Center(
                        child: SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    // Dashboard-level section: fail quietly rather
                    // than pushing an error card into the home
                    // screen — the full Offers tab (same
                    // PromoRepository) already surfaces a real error
                    // state if the connection is actually down.
                    return const SizedBox.shrink();
                  }

                  final promos = snapshot.data ?? const <PromoModel>[];
                  if (promos.isEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'No active promotions right now',
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                    );
                  }

                  final visible = promos.take(widget.maxCards).toList();

                  // Check arrow enabled-state once the list has
                  // content and a frame has been laid out.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _updateArrowState();
                  });

                  return SizedBox(
                    height: _cardHeightFor(cardWidth),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ListView.separated(
                          controller: _scrollController,
                          scrollDirection: Axis.horizontal,
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(width: _kCardSpacing),
                          itemBuilder: (context, index) {
                            return _PromoOfferCard(
                              promo: visible[index],
                              width: cardWidth,
                              onTap: widget.onSeeAll,
                            );
                          },
                        ),
                        if (visible.length > 1)
                          Positioned(
                            left: 0,
                            child: _SlideArrowButton(
                              icon: Icons.chevron_left,
                              enabled: _canScrollLeft,
                              onTap: () => _scrollBy(-scrollStep),
                            ),
                          ),
                        if (visible.length > 1)
                          Positioned(
                            right: 0,
                            child: _SlideArrowButton(
                              icon: Icons.chevron_right,
                              enabled: _canScrollRight,
                              onTap: () => _scrollBy(scrollStep),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Frosted-glass container for the whole "Offers & Promos" section.
///
/// Deliberately the exact same recipe as
/// service_selection_card.dart's private `_GlassPanel` (blur + low-alpha
/// white gradient fill + soft white border + floating shadow) so both
/// dashboard sections read as one consistent glass material — "Our
/// Services" itself is left completely untouched, this is a separate
/// copy scoped to this file only.
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

/// Small circular arrow button overlaid on the list edges — same
/// frosted-glass disc recipe as
/// service_selection_card.dart's private `_SlideArrowButton`,
/// duplicated here for the same reason as [_GlassPanel] above. Dims
/// and ignores taps once that direction has nothing left to scroll to.
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

/// One large, photo-led promo card in the home tab's horizontal
/// strip.
///
/// PART 19 — [promo.imageUrl] (the photo the admin uploaded when
/// creating/editing this exact promotion — see AddPromoScreen /
/// EditPromoScreen) is the card's main visual, `BoxFit.cover`'d
/// inside a fixed aspect ratio so it's always cleanly cropped and
/// never stretched or distorted. With no photo uploaded yet, this
/// shows a plain tinted icon tile — never a placeholder/stock photo —
/// so PromoModel.imageUrl being unset always stays visibly obvious
/// rather than silently faked.
///
/// Purely presentational — tapping it just opens the full Offers tab
/// (via [onTap], typically [CurrentOffersSection.onSeeAll]) rather
/// than redeeming the code itself; redemption stays on OffersScreen.
class _PromoOfferCard extends StatelessWidget {
  const _PromoOfferCard({
    required this.promo,
    required this.width,
    this.onTap,
  });

  final PromoModel promo;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            width: width,
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
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Photo section — the admin-provided image is the
                // main visual here, cropped (never stretched) to a
                // fixed aspect ratio.
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _PromoPhoto(promo: promo),
                      // Discount badge, floated on top of the photo.
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _GlassBadge(text: promo.discountLabel),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        promo.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.black87,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        promo.minimumOrder > 0
                            ? 'Min. order ${PriceCalculator.formatCurrency(promo.minimumOrder)}'
                            : 'No minimum order',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                      ),
                      if (promo.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          promo.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ],
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

/// The promo's photo, or a graceful (non-fake) fallback tile when
/// [PromoModel.imageUrl] hasn't been set yet, or fails to load.
class _PromoPhoto extends StatelessWidget {
  const _PromoPhoto({required this.promo});

  final PromoModel promo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (!promo.hasImage) {
      return _fallback(colors);
    }

    return Image.network(
      promo.imageUrl!,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _fallback(colors),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: colors.primaryContainer.withValues(alpha: 0.4),
          child: const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      },
    );
  }

  Widget _fallback(ColorScheme colors) {
    // Deliberately just a tinted tile + icon — never a stock/placeholder
    // photo — so a promo with no uploaded photo stays visibly distinct
    // from one that has a real photo behind it.
    return Container(
      color: colors.primaryContainer.withValues(alpha: 0.55),
      alignment: Alignment.center,
      child: Icon(
        Icons.local_offer_outlined,
        size: 36,
        color: colors.onPrimaryContainer.withValues(alpha: 0.7),
      ),
    );
  }
}

class _GlassBadge extends StatelessWidget {
  const _GlassBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}