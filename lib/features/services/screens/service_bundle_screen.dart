// TARGET PATH IN YOUR PROJECT:
// lib/features/services/screens/service_bundle_screen.dart
//
// The "Service Bundle" destination. ExploreServicesScreen's Service
// Bundle tile pushes this screen instead of expanding inline — this is
// where Quick Wash / Standard Wash / Premium Wash live, as a 2-column
// grid of the exact same ServiceGridCard used everywhere else (real
// photo, ETA badge, price, name, arrow button all come from Firestore
// via ServiceModel — nothing here is faked or hard-coded).
//
// Matching heuristic: a service belongs on this screen if its name
// contains "quick", "premium", or "standard" AND does NOT contain
// "dry", "iron", "bundle"/"pick", or "regular" (those belong to the
// other three top-level category tiles on ExploreServicesScreen).
// Adjust _kBundleKeywords / _isExcluded below if your Firestore names
// differ.
//
// REDESIGN — matches ExploreServicesScreen's glass treatment: same
// blurred-blob background (`_BundleBackground`) and frosted app bar
// (`_BundleGlassAppBar`) as UserDashboard/ExploreServicesScreen, so
// the whole "Explore Services -> Service Bundle" navigation chain
// reads as one continuous surface. Also fixes a leftover bug where
// this screen's AppBar title said "Explore Services" (copy-pasted
// from that screen) instead of "Service Bundle".

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/service_grid_card.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import '../../user/screens/laundry_order_screen.dart';

/// Same fixed app-bar content height as ExploreServicesScreen/
/// UserDashboard — kept as its own local constant so this file stays
/// self-contained rather than importing a private value from another
/// screen.
const double _kAppBarContentHeight = 64;

/// Keywords (checked in this order) that identify a bundle service and
/// also control the display order of the grid: Quick Wash, then
/// Standard Wash, then Premium Wash — matching the reference layout
/// (third card wraps to the next row, aligned left).
const List<String> _kBundleKeywordOrder = ['quick', 'standard', 'premium'];

/// Keywords that mean a service belongs to a DIFFERENT top-level tile
/// (Regular Wash, Dry Cleaning, Wash & Ironing, Service Bundle nav-only
/// entry) and must never show up here, even if it also happens to
/// contain one of the words above.
const List<String> _kExcludedKeywords = ['dry', 'iron', 'bundle', 'pick', 'regular'];

bool _isBundleService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (_kExcludedKeywords.any(name.contains)) return false;
  return _kBundleKeywordOrder.any(name.contains) ||
      // A service with none of the known keywords falls back to
      // "standard" in the shared asset/price heuristics (see
      // service_grid_card.dart's assetPathForService), so treat it as
      // a Standard Wash-equivalent here too rather than dropping it.
      true;
}

/// Sort key so Quick Wash / Standard Wash / Premium Wash always render
/// in that fixed order regardless of Firestore's natural ordering.
int _bundleSortIndex(ServiceModel service) {
  final name = service.name.toLowerCase();
  for (var i = 0; i < _kBundleKeywordOrder.length; i++) {
    if (name.contains(_kBundleKeywordOrder[i])) return i;
  }
  return _kBundleKeywordOrder.length; // unrecognized name goes last
}

class ServiceBundleScreen extends StatefulWidget {
  const ServiceBundleScreen({super.key});

  @override
  State<ServiceBundleScreen> createState() => _ServiceBundleScreenState();
}

class _ServiceBundleScreenState extends State<ServiceBundleScreen> {
  final ServiceRepository _repository = ServiceRepository();

  bool _isLoading = true;
  Object? _error;
  List<ServiceModel> _bundleServices = const <ServiceModel>[];

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  Future<void> _loadServices({bool forceRefresh = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _repository.seedDefaultServicesIfEmpty();
      final all = await _repository.getActiveServices(forceRefresh: forceRefresh);
      final filtered = all.where(_isBundleService).toList()
        ..sort((a, b) => _bundleSortIndex(a).compareTo(_bundleSortIndex(b)));
      if (!mounted) return;
      setState(() {
        _bundleServices = filtered;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() => _loadServices(forceRefresh: true);

  void _openService(ServiceModel service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LaundryOrderScreen(initialService: service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _BundleGlassAppBar(
          // BUG FIX — was hardcoded 'Explore Services', a copy-paste
          // leftover from that screen. This one is Service Bundle.
          title: 'Service Bundle',
          onBack: () => Navigator.maybePop(context),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _BundleBackground()),
          SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: appBarTotalHeight + 8),
                  ),
                  if (_isLoading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: LoadingWidget(message: 'Loading services...'),
                    )
                  else if (_error != null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: ErrorState(
                          message: 'We couldn\'t load our services. Please try again.',
                          onRetry: _refresh,
                        ),
                      ),
                    )
                  else if (_bundleServices.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: EmptyState(
                          icon: Icons.local_laundry_service_outlined,
                          title: 'No services available right now',
                          message: 'Check back soon for our laundry services.',
                        ),
                      ),
                    )
                  else
                    // 2-column grid. With exactly 3 items, GridView leaves
                    // the 3rd card alone on row 2, aligned to the left —
                    // matching the reference image with no extra code needed.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final service = _bundleServices[index];
                            return ServiceGridCard(
                              service: service,
                              onTap: () => _openService(service),
                            );
                          },
                          childCount: _bundleServices.length,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same three-blob blurred backdrop as ExploreServicesScreen's
/// `_ExploreBackground` / UserDashboard's `_DashboardBackground`.
class _BundleBackground extends StatelessWidget {
  const _BundleBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 280,
                height: 280,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0D47A1), Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 260,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff0D47A1).withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -50,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff8EC5FC).withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same frosted-glass app bar recipe as ExploreServicesScreen's
/// `_ExploreGlassAppBar` — back arrow leading, blurred semi-
/// transparent fill, rounded bottom corners.
class _BundleGlassAppBar extends StatelessWidget {
  const _BundleGlassAppBar({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _kAppBarContentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 18, 0),
                child: Row(
                  children: [
                    _BundleGlassIconButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Same frosted circular icon button recipe as
/// ExploreServicesScreen's `_ExploreGlassIconButton`.
class _BundleGlassIconButton extends StatelessWidget {
  const _BundleGlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.black87, size: 17),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}