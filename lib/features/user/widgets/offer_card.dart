import 'package:flutter/material.dart';

/// Placeholder shape only — real promos arrive in Part 18
/// (models/promo_model.dart, offers_screen.dart).
///
/// Added `imageAsset` and `backgroundColor` so each promo card can show
/// its own photo and pastel tint. Swap the two asset paths below for
/// your real photos — no widget code needs to change to do that.
class PlaceholderOffer {
  const PlaceholderOffer({
    required this.title,
    required this.description,
    required this.badge,
    required this.imageAsset,
    required this.backgroundColor,
  });

  final String title;
  final String description;
  final String badge; // e.g. "20% OFF"

  /// Asset path for this offer's promo photo (see pubspec.yaml assets).
  /// If the file isn't there yet, the card falls back to a simple icon
  /// instead of crashing — see [OfferCard]'s errorBuilder.
  final String imageAsset;

  /// Soft pastel background tint for this card.
  final Color backgroundColor;
}

const List<PlaceholderOffer> kPlaceholderOffers = [
  PlaceholderOffer(
    title: 'First Order Discount',
    description: 'Get 20% off your first laundry order.',
    badge: '20% OFF',
    // TODO: replace with Photo 1 (First Order Discount) and add the
    // matching entry under `flutter: assets:` in pubspec.yaml.
    imageAsset: 'assets/images/offers/first_order_discount.png',
    backgroundColor: Color(0xffFCE4E7), // soft pink
  ),
  PlaceholderOffer(
    title: 'Weekend Bundle',
    description: 'Bundle 2+ services on weekends and save.',
    badge: 'BUNDLE',
    // TODO: replace with Photo 2 (Weekend Bundle) and add the matching
    // entry under `flutter: assets:` in pubspec.yaml.
    imageAsset: 'assets/images/offers/weekend_bundle.png',
    backgroundColor: Color(0xffE3EEFD), // soft blue
  ),
];

/// Sizing bounds for a promo card, per the design spec: ~230–280 wide,
/// ~110–130 tall. Width is derived responsively from the available
/// layout width (see [CurrentOffersSection]) rather than fixed, so the
/// row doesn't overflow on narrow phones.
const double _kOfferCardMinWidth = 230;
const double _kOfferCardMaxWidth = 280;
const double _kOfferCardHeight = 122;
const double _kOfferPhotoWidth = 96;
const double _kOfferCardSpacing = 12;

/// "Current Offers" section: a bold title, a "See all" accent link,
/// and a horizontally-scrolling row of compact promo cards with slide
/// arrows overlaid on the edges. Pulled out as its own widget so the
/// Home tab just drops it in as one line.
class CurrentOffersSection extends StatefulWidget {
  const CurrentOffersSection({
    super.key,
    this.offers = kPlaceholderOffers,
    this.onSeeAll,
  });

  final List<PlaceholderOffer> offers;

  /// Called when "See all" is tapped — typically navigates to (or
  /// switches the bottom nav to) the full Offers screen. The link is
  /// still shown if this is null; it simply won't do anything.
  final VoidCallback? onSeeAll;

  @override
  State<CurrentOffersSection> createState() => _CurrentOffersSectionState();
}

class _CurrentOffersSectionState extends State<CurrentOffersSection> {
  final ScrollController _scrollController = ScrollController();

  // Kept in sync with scroll position so an arrow disables itself once
  // you've hit that end of the list instead of doing nothing silently.
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateArrowState);
    // Check arrow enabled-state once the first frame has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateArrowState();
    });
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

  @override
  Widget build(BuildContext context) {
    if (widget.offers.isEmpty) return const SizedBox.shrink();

    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Current Offers',
              style: textTheme.titleMedium?.copyWith(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            GestureDetector(
              onTap: widget.onSeeAll,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                // Small hit-area padding so "See all" is easy to tap
                // without changing its visual position.
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: Text(
                  'See all',
                  style: textTheme.labelLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            // ~0.66 of the available width shows one full card plus a
            // peek of the next on typical phone widths, while the
            // clamp keeps every card within the 230–280 spec even on
            // very narrow or very wide layouts.
            final cardWidth = (constraints.maxWidth * 0.66).clamp(
              _kOfferCardMinWidth,
              _kOfferCardMaxWidth,
            );
            // One arrow tap scrolls roughly one card + its separator.
            final scrollStep = cardWidth + _kOfferCardSpacing;

            return SizedBox(
              height: _kOfferCardHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  ListView.separated(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.offers.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: _kOfferCardSpacing),
                    itemBuilder: (context, index) {
                      return OfferCard(
                        offer: widget.offers[index],
                        width: cardWidth,
                      );
                    },
                  ),
                  // Left slide arrow
                  if (widget.offers.length > 1)
                    Positioned(
                      left: 0,
                      child: _SlideArrowButton(
                        icon: Icons.chevron_left,
                        enabled: _canScrollLeft,
                        onTap: () => _scrollBy(-scrollStep),
                      ),
                    ),
                  // Right slide arrow
                  if (widget.offers.length > 1)
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
  }
}

/// Small circular arrow button overlaid on the offer list's edges for
/// sliding the row left/right. Dims and ignores taps once that
/// direction has nothing left to scroll to. Solid white + soft shadow
/// to match the pastel promo cards it floats over.
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
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 30,
            height: 30,
            child: Icon(icon, size: 18, color: Colors.black87),
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal promo card: pastel background, text + badge on
/// the left, promo photo bleeding to the rounded edge on the right.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, this.width});

  final PlaceholderOffer offer;

  /// Explicit card width, normally supplied by [CurrentOffersSection]
  /// so every card in the row matches. Falls back to the max spec
  /// width if used standalone (e.g. on the full Offers screen).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cardWidth = (width ?? _kOfferCardMaxWidth).clamp(
      _kOfferCardMinWidth,
      _kOfferCardMaxWidth,
    );

    return Container(
      width: cardWidth,
      height: _kOfferCardHeight,
      decoration: BoxDecoration(
        color: offer.backgroundColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left: title, description, badge.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        offer.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.black54,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  // Compact badge pill.
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      offer.badge,
                      style: textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Right: promo photo, clipped to the card's rounded edge.
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            child: SizedBox(
              width: _kOfferPhotoWidth,
              child: Image.asset(
                offer.imageAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Shown until the real asset is added — keeps the
                  // layout intact instead of throwing.
                  return Container(
                    color: Colors.black.withValues(alpha: 0.06),
                    child: const Center(
                      child: Icon(
                        Icons.local_offer_outlined,
                        size: 26,
                        color: Colors.black45,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}