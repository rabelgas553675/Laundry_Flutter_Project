import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';

/// Placeholder shape only — real promos arrive in Part 18
/// (models/promo_model.dart, offers_screen.dart).
class PlaceholderOffer {
  const PlaceholderOffer({
    required this.title,
    required this.description,
    required this.badge,
  });

  final String title;
  final String description;
  final String badge; // e.g. "20% OFF"
}

const List<PlaceholderOffer> kPlaceholderOffers = [
  PlaceholderOffer(
    title: 'First Order Discount',
    description: 'Get 20% off your first laundry order.',
    badge: '20% OFF',
  ),
  PlaceholderOffer(
    title: 'Weekend Bundle',
    description: 'Bundle 2+ services on weekends and save.',
    badge: 'BUNDLE',
  ),
];

class OfferCard extends StatefulWidget {
  const OfferCard({super.key, required this.offer});

  final PlaceholderOffer offer;

  @override
  State<OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<OfferCard> {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.offer.title, style: textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(widget.offer.description, style: textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              widget.offer.badge,
              style: textTheme.labelLarge?.copyWith(color: colors.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}