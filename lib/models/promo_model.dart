import 'package:cloud_firestore/cloud_firestore.dart';

/// How a promo's [PromoModel.discountValue] is applied to an order's
/// subtotal.
///
/// Per PART 18B: exactly two types are supported —
/// [percentage] (e.g. 20 → 20% off) and [fixedAmount] (e.g. 50 → ₱50
/// off), never anything else.
enum PromoDiscountType { percentage, fixedAmount }

extension PromoDiscountTypeX on PromoDiscountType {
  String get value => name; // 'percentage' or 'fixedAmount'

  String get label {
    switch (this) {
      case PromoDiscountType.percentage:
        return 'Percentage';
      case PromoDiscountType.fixedAmount:
        return 'Fixed Amount';
    }
  }

  static PromoDiscountType fromValue(String? value) {
    switch (value) {
      case 'fixedAmount':
        return PromoDiscountType.fixedAmount;
      case 'percentage':
      default:
        return PromoDiscountType.percentage;
    }
  }
}

/// The admin-controlled on/off switch for a promo (PART 18B's
/// "Deactivate promotions"/"Inactive promotions cannot be applied by
/// users"). This is deliberately separate from [PromoDisplayStatus]
/// below — a promo can be `status == active` and still be Expired or
/// Scheduled from the user's point of view, purely based on today's
/// date vs. [PromoModel.startDate]/[PromoModel.endDate].
enum PromoStatus { active, inactive }

extension PromoStatusX on PromoStatus {
  String get value => name; // 'active' or 'inactive'

  static PromoStatus fromValue(String? value) {
    switch (value) {
      case 'inactive':
        return PromoStatus.inactive;
      case 'active':
      default:
        return PromoStatus.active;
    }
  }
}

/// The four states PART 18B's admin promo list displays, derived from
/// [PromoStatus] + today's date vs. the promo's validity window —
/// never stored in Firestore directly, since it changes on its own as
/// time passes (an "Active" promo automatically becomes "Expired" the
/// day after its [PromoModel.endDate], with no admin action needed).
enum PromoDisplayStatus { active, inactive, expired, scheduled }

extension PromoDisplayStatusX on PromoDisplayStatus {
  String get label {
    switch (this) {
      case PromoDisplayStatus.active:
        return 'Active';
      case PromoDisplayStatus.inactive:
        return 'Inactive';
      case PromoDisplayStatus.expired:
        return 'Expired';
      case PromoDisplayStatus.scheduled:
        return 'Scheduled';
    }
  }
}

/// Mirrors the Firestore document at `promos/{promoId}`.
///
/// Per PART 18A/18B's field list: [code], [discountType],
/// [discountValue], [minimumOrder], [startDate], [endDate], [status].
/// [description] is a small addition on top of that list purely for
/// display (so a promo card/list has something readable to show
/// besides the raw code) — it carries no pricing logic of its own.
class PromoModel {
  final String id;

  /// Always stored/compared in upper case so "welcome10" and
  /// "WELCOME10" are treated as the exact same code, both when
  /// enforcing PART 18B's "code must be unique" rule and when a user
  /// types it in on PART 18A's redeem field.
  final String code;

  final PromoDiscountType discountType;

  /// Percentage points (e.g. `20` → 20%) when [discountType] is
  /// [PromoDiscountType.percentage], or a flat peso amount (e.g. `50`
  /// → ₱50) when it's [PromoDiscountType.fixedAmount].
  final double discountValue;

  /// The order subtotal must be at least this amount for the promo to
  /// be applicable. `0` means no minimum.
  final double minimumOrder;

  final DateTime startDate;
  final DateTime endDate;

  /// Admin on/off switch — see [PromoStatus] doc comment above.
  final PromoStatus status;

  /// Optional short blurb shown on promo cards (e.g. "20% off orders
  /// over ₱300"). Not part of PART 18's required field list, but
  /// harmless to carry — never used for any pricing/validation logic.
  final String description;

  final DateTime? createdAt;

  /// PART 19 — public URL of the admin-uploaded offer photo (Supabase
  /// Storage, `promo-images` bucket — see [FileService.uploadPromoImage]).
  /// `null`/empty means no photo has been uploaded for this promo yet;
  /// the app never fabricates a placeholder image in its place — the
  /// user dashboard's offer card shows a plain tinted icon tile
  /// instead when this is unset.
  final String? imageUrl;

  const PromoModel({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minimumOrder,
    required this.startDate,
    required this.endDate,
    this.status = PromoStatus.active,
    this.description = '',
    this.createdAt,
    this.imageUrl,
  });

  /// Whether this promo actually has a photo an admin uploaded — used
  /// instead of a raw null/empty check wherever a promo card decides
  /// between the photo layout and the icon fallback.
  bool get hasImage => (imageUrl ?? '').trim().isNotEmpty;

  /// PART 18B — the four-state status shown on the admin promo list.
  /// [now] is injectable so this stays pure/testable rather than
  /// silently depending on the wall clock; defaults to `DateTime.now()`
  /// for normal call sites.
  PromoDisplayStatus displayStatus({DateTime? now}) {
    if (status == PromoStatus.inactive) return PromoDisplayStatus.inactive;
    final n = now ?? DateTime.now();
    if (n.isBefore(startDate)) return PromoDisplayStatus.scheduled;
    if (n.isAfter(endDate)) return PromoDisplayStatus.expired;
    return PromoDisplayStatus.active;
  }

  /// PART 18A — "Only show promotions that are currently active and
  /// within their valid start and end dates."
  bool isCurrentlyActive({DateTime? now}) =>
      displayStatus(now: now) == PromoDisplayStatus.active;

  /// Raw discount this promo would take off [orderSubtotal], with NO
  /// validity/minimum-order checks applied — those live in
  /// `PromoRepository.validateCode`, which is the only place that
  /// should decide whether a promo is actually usable. This is purely
  /// "if it were applied, how much would it take off," clamped so a
  /// percentage/fixed discount can never exceed the subtotal itself
  /// (matches PriceCalculator.calculate's own discount clamp).
  double discountFor(double orderSubtotal) {
    if (orderSubtotal <= 0) return 0;
    final raw = discountType == PromoDiscountType.percentage
        ? orderSubtotal * (discountValue / 100)
        : discountValue;
    return raw > orderSubtotal ? orderSubtotal : raw;
  }

  /// Human-readable discount summary, e.g. "20% off" or "₱50 off".
  String get discountLabel {
    return discountType == PromoDiscountType.percentage
        ? '${_trimZeros(discountValue)}% off'
        : '₱${_trimZeros(discountValue)} off';
  }

  static String _trimZeros(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  /// Used when creating a new promo document (PART 18B). createdAt is
  /// left to Firestore's server timestamp, same pattern as
  /// ServiceModel/DetergentModel.
  Map<String, dynamic> toMapForCreate() {
    return {
      'code': code.toUpperCase(),
      'discountType': discountType.value,
      'discountValue': discountValue,
      'minimumOrder': minimumOrder,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status.value,
      'description': description,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// PART 18B — admin edits (discount, dates, minimum order,
  /// activate/deactivate). Excludes createdAt, which never changes.
  Map<String, dynamic> toEditableMap() {
    return {
      'code': code.toUpperCase(),
      'discountType': discountType.value,
      'discountValue': discountValue,
      'minimumOrder': minimumOrder,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status.value,
      'description': description,
      'imageUrl': imageUrl,
    };
  }

  /// [imageUrl] uses a sentinel default (rather than `imageUrl ??
  /// this.imageUrl`) so callers can explicitly clear a photo by
  /// passing an empty string — plain omission still keeps the
  /// existing photo, same as every other field here.
  PromoModel copyWith({
    String? code,
    PromoDiscountType? discountType,
    double? discountValue,
    double? minimumOrder,
    DateTime? startDate,
    DateTime? endDate,
    PromoStatus? status,
    String? description,
    Object? imageUrl = _unset,
  }) {
    return PromoModel(
      id: id,
      code: code ?? this.code,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      minimumOrder: minimumOrder ?? this.minimumOrder,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      status: status ?? this.status,
      description: description ?? this.description,
      createdAt: createdAt,
      imageUrl: identical(imageUrl, _unset) ? this.imageUrl : imageUrl as String?,
    );
  }

  static const Object _unset = Object();

  factory PromoModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final createdTs = data['createdAt'];
    final startTs = data['startDate'];
    final endTs = data['endDate'];
    return PromoModel(
      id: doc.id,
      code: (data['code'] ?? '').toString().toUpperCase(),
      discountType: PromoDiscountTypeX.fromValue(data['discountType']),
      discountValue: (data['discountValue'] as num?)?.toDouble() ?? 0,
      minimumOrder: (data['minimumOrder'] as num?)?.toDouble() ?? 0,
      startDate: startTs is Timestamp ? startTs.toDate() : DateTime.now(),
      endDate: endTs is Timestamp ? endTs.toDate() : DateTime.now(),
      status: PromoStatusX.fromValue(data['status']),
      description: data['description'] ?? '',
      createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
      imageUrl: (data['imageUrl'] as String?)?.trim(),
    );
  }

  /// Value equality by id — matches ServiceModel/DetergentModel, so
  /// promo cards/lists can compare instances safely.
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PromoModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}