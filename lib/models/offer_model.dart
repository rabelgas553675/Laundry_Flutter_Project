import 'package:flutter/material.dart';

/// A real promotional offer, loaded from Firestore via [OfferService]
/// (see data/services/offer_service.dart). Replaces the old static
/// `PlaceholderOffer` — same visual fields (title, description, badge,
/// image, background tint), but `imageUrl` now points at a real hosted
/// image instead of a bundled asset, and `backgroundColorHex` comes
/// from the document instead of being hardcoded per-card.
@immutable
class OfferModel {
  const OfferModel({
    required this.id,
    required this.title,
    required this.description,
    required this.badge,
    required this.imageUrl,
    required this.backgroundColorHex,
    this.isActive = true,
    this.priority = 0,
  });

  final String id;
  final String title;
  final String description;
  final String badge; // e.g. "20% OFF"

  /// Hosted image URL (Firebase Storage, CDN, etc). Rendered with
  /// `Image.network`; falls back to a plain icon if it fails to load
  /// or is empty — see [OfferCard]'s errorBuilder.
  final String imageUrl;

  /// Hex color string from Firestore, e.g. "#FCE4E7" or "FCE4E7".
  final String backgroundColorHex;

  /// Whether this offer should currently be shown. Filtered at the
  /// query level in [OfferService], kept here too so the model is
  /// self-describing if reused elsewhere (e.g. an admin offers list).
  final bool isActive;

  /// Higher priority sorts first. Ties break by title for a stable,
  /// predictable order.
  final int priority;

  Color get backgroundColor {
    var hex = backgroundColorHex.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'ff$hex';
    final parsed = int.tryParse(hex, radix: 16);
    return parsed != null ? Color(parsed) : const Color(0xffEAF3FF);
  }

  factory OfferModel.fromMap(String id, Map<String, dynamic> data) {
    return OfferModel(
      id: id,
      title: (data['title'] as String?)?.trim() ?? '',
      description: (data['description'] as String?)?.trim() ?? '',
      badge: (data['badge'] as String?)?.trim() ?? '',
      imageUrl: (data['imageUrl'] as String?)?.trim() ?? '',
      backgroundColorHex:
          (data['backgroundColorHex'] as String?)?.trim() ?? '#EAF3FF',
      isActive: (data['isActive'] as bool?) ?? true,
      priority: (data['priority'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'badge': badge,
      'imageUrl': imageUrl,
      'backgroundColorHex': backgroundColorHex,
      'isActive': isActive,
      'priority': priority,
    };
  }
}