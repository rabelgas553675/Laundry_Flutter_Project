import '../../core/utils/price_calculator.dart';
import '../../models/promo_model.dart';
import '../datasources/promo_datasource.dart';

/// Why a promo-code check did or didn't succeed. Kept as a distinct
/// enum (rather than just a bool) so [OffersScreen] can show a
/// specific, correct message for each PART 18A validation rule
/// (expired vs. inactive vs. below minimum order vs. simply
/// nonexistent) instead of one generic "invalid code" error.
enum PromoValidationStatus {
  valid,
  emptyCode,
  invalidCode,
  inactive,
  notStartedYet,
  expired,
  belowMinimumOrder,
}

/// Result of [PromoRepository.validateCode].
///
/// [discountAmount] and [newTotal] are only meaningful when
/// [orderSubtotal] was provided to `validateCode` — otherwise they're
/// `0`/`null` even for an otherwise-valid code, since there's nothing
/// to discount yet.
class PromoValidationResult {
  final PromoValidationStatus status;
  final PromoModel? promo;
  final double discountAmount;
  final double? newTotal;
  final String message;

  const PromoValidationResult({
    required this.status,
    required this.promo,
    required this.discountAmount,
    required this.newTotal,
    required this.message,
  });

  bool get isValid => status == PromoValidationStatus.valid;
}

class PromoRepository {
  PromoRepository({PromoDatasource? datasource})
      : _datasource = datasource ?? PromoDatasource();

  final PromoDatasource _datasource;

  /// Session cache — cleared via [clearCache]. Same reasoning as
  /// ServiceRepository: avoids re-fetching the same short,
  /// rarely-changing list on every Offers-tab rebuild.
  List<PromoModel>? _cachedVisible;

  /// PART 18B — Admin promo management's cache of every promo
  /// (active AND inactive), separate from [_cachedVisible] since the
  /// two lists are filtered differently and refreshed independently.
  List<PromoModel>? _cachedAll;

  /// PART 18A — "Only show promotions that are currently active and
  /// within their valid start and end dates." Fetches every
  /// `status == active` promo, then filters down to the ones whose
  /// date window actually includes today — a promo can have
  /// `status == active` in Firestore and still be Scheduled or
  /// Expired from the customer's point of view.
  Future<List<PromoModel>> getVisiblePromos({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedVisible != null) {
      return _cachedVisible!;
    }
    final activeStatus = await _datasource.getActiveStatusPromos();
    final visible = activeStatus.where((p) => p.isCurrentlyActive()).toList();
    _cachedVisible = visible;
    return visible;
  }

  /// PART 18A — validates a promo code a user typed in, and (when
  /// [orderSubtotal] is given) computes what it would actually take
  /// off that amount.
  ///
  /// [orderSubtotal] is optional: a user browsing the Offers screen
  /// before starting an order can still check whether a code exists
  /// and see its discount terms, without yet having an order total to
  /// apply it to. The minimum-order check is only enforced once an
  /// [orderSubtotal] is actually supplied.
  Future<PromoValidationResult> validateCode({
    required String code,
    double? orderSubtotal,
  }) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return const PromoValidationResult(
        status: PromoValidationStatus.emptyCode,
        promo: null,
        discountAmount: 0,
        newTotal: null,
        message: 'Please enter a promo code.',
      );
    }

    final promo = await _datasource.getByCode(trimmed.toUpperCase());
    if (promo == null) {
      return const PromoValidationResult(
        status: PromoValidationStatus.invalidCode,
        promo: null,
        discountAmount: 0,
        newTotal: null,
        message: 'This promo code doesn\'t exist. Please check and try again.',
      );
    }

    final displayStatus = promo.displayStatus();

    if (displayStatus == PromoDisplayStatus.inactive) {
      return PromoValidationResult(
        status: PromoValidationStatus.inactive,
        promo: promo,
        discountAmount: 0,
        newTotal: null,
        message: 'This promo code is no longer available.',
      );
    }
    if (displayStatus == PromoDisplayStatus.scheduled) {
      return PromoValidationResult(
        status: PromoValidationStatus.notStartedYet,
        promo: promo,
        discountAmount: 0,
        newTotal: null,
        message: 'This promo code isn\'t active yet.',
      );
    }
    if (displayStatus == PromoDisplayStatus.expired) {
      return PromoValidationResult(
        status: PromoValidationStatus.expired,
        promo: promo,
        discountAmount: 0,
        newTotal: null,
        message: 'This promo code has expired.',
      );
    }

    // displayStatus == active from here on.
    if (orderSubtotal != null && orderSubtotal < promo.minimumOrder) {
      return PromoValidationResult(
        status: PromoValidationStatus.belowMinimumOrder,
        promo: promo,
        discountAmount: 0,
        newTotal: null,
        message: 'This code requires a minimum order of '
            '${PriceCalculator.formatCurrency(promo.minimumOrder)}.',
      );
    }

    final discount = orderSubtotal != null ? promo.discountFor(orderSubtotal) : 0.0;
    final total = orderSubtotal != null ? (orderSubtotal - discount) : null;

    return PromoValidationResult(
      status: PromoValidationStatus.valid,
      promo: promo,
      discountAmount: discount,
      newTotal: total,
      message: orderSubtotal != null
          ? 'Promo applied! You saved ${PriceCalculator.formatCurrency(discount)}.'
          : '${promo.code} is valid — ${promo.discountLabel}'
              '${promo.minimumOrder > 0 ? ' on orders over ${PriceCalculator.formatCurrency(promo.minimumOrder)}' : ''}.',
    );
  }

  /// PART 18B — Admin promo management needs every promo, regardless
  /// of [PromoStatus] (active AND inactive), so admins can find and
  /// reactivate/edit one that's currently off or expired.
  Future<List<PromoModel>> getAllPromos({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAll != null) {
      return _cachedAll!;
    }
    final promos = await _datasource.getAllPromos();
    _cachedAll = promos;
    return promos;
  }

  /// PART 18B — "Promo code must be unique." [code] should already be
  /// upper-cased by the caller (matches how codes are stored). Pass
  /// [excludeId] when editing an existing promo so it never collides
  /// with itself.
  Future<bool> isCodeTaken(String code, {String? excludeId}) {
    return _datasource.isCodeTaken(code.trim().toUpperCase(), excludeId: excludeId);
  }

  /// PART 18B — "Create promotions."
  Future<void> createPromo(PromoModel promo) async {
    await _datasource.createPromo(promo);
    _cachedAll = null;
    _cachedVisible = null;
  }

  /// PART 18B — "Edit promotions" / "Deactivate promotions" (via a
  /// [PromoStatus] change on [updated]).
  Future<void> updatePromo(PromoModel updated) async {
    await _datasource.updatePromoFields(updated.id, updated.toEditableMap());
    _cachedAll = null;
    _cachedVisible = null;
  }

  void clearCache() {
    _cachedVisible = null;
    _cachedAll = null;
  }
}