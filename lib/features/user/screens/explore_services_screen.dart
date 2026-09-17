// TARGET PATH IN YOUR PROJECT:
// lib/features/user/screens/explore_services_screen.dart
// (replaces the existing file at that path)

import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/service_grid_card.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import 'laundry_order_screen.dart';
import '../../services/screens/service_bundle_screen.dart';

/// Fixed content height of the frosted app bar — same value as
/// `UserDashboard`'s `_kAppBarContentHeight`, kept as its own local
/// constant so this screen doesn't need to import anything from
/// `user_dashboard.dart` just for one number.
const double _kAppBarContentHeight = 64;

/// PART 1 — the full catalog behind "See all" on the dashboard's
/// "Our Services" section.
///
/// Per the latest spec this is now a fixed 2x2 grid of four top-level
/// categories — Regular Wash, Dry Cleaning, Wash & Ironing, Service
/// Bundle — instead of a searchable list of every active service.
/// Tapping "Service Bundle" no longer opens the order screen directly:
/// it opens ServiceBundleScreen, which is where Quick Wash / Standard
/// Wash / Premium Wash now live.
///
/// REDESIGN — this screen now uses the same blurred-blob background
/// and frosted glass app bar as `UserDashboard`, so navigating here
/// from "See all" on the dashboard feels like a continuation of the
/// same surface rather than a visually unrelated screen. The service
/// cards themselves (`ServiceGridCard`/`_PlaceholderCategoryCard`)
/// are left as solid white cards, unchanged — that mirrors how the
/// dashboard's own content (`ActiveOrderCard`, `ServiceSelectionCard`)
/// is solid on top of its blurred backdrop; only the chrome (app bar,
/// background) is glass.
class ExploreServicesScreen extends StatefulWidget {
  const ExploreServicesScreen({super.key});

  @override
  State<ExploreServicesScreen> createState() => _ExploreServicesScreenState();
}

/// One tile on the main Explore Services grid.
///
/// `keywords` are checked in order against each active service's name
/// (case-insensitive `contains`) to find the real ServiceModel to show —
/// same matching heuristic the card helpers already use for photos and
/// icons. ADJUST THESE if your Firestore service names differ — e.g. if
/// there's no service literally named "Regular Wash", either rename it
/// in Firestore or add its real name/keyword here.
///
/// `assetPath` / `fallbackIcon` are used only when no matching
/// ServiceModel exists yet (see `_PlaceholderCategoryCard`) — they let
/// the placeholder tile show the *real* category photo instead of a
/// plain gray box with an icon.
class _CategoryTile {
  const _CategoryTile({
    required this.label,
    required this.keywords,
    required this.assetPath,
    required this.fallbackIcon,
    this.isBundle = false,
  });

  final String label;
  final List<String> keywords;
  final String assetPath;
  final IconData fallbackIcon;

  /// The bundle tile never opens the order screen directly — tapping it
  /// always pushes ServiceBundleScreen instead, whether or not a
  /// matching ServiceModel exists yet.
  final bool isBundle;
}

const List<_CategoryTile> _mainCategories = [
  _CategoryTile(
    label: 'Regular Wash',
    keywords: ['regular', 'standard'],
    assetPath: 'assets/images/regular_wash.png',
    fallbackIcon: Icons.local_laundry_service_outlined,
  ),
  _CategoryTile(
    label: 'Dry Cleaning',
    keywords: ['dry'],
    assetPath: 'assets/images/dry_cleaning.jpg',
    fallbackIcon: Icons.checkroom_outlined,
  ),
  _CategoryTile(
    label: 'Wash & Ironing',
    keywords: ['iron'],
    assetPath: 'assets/images/wash_and_ironing.jpg',
    fallbackIcon: Icons.iron_outlined,
  ),
  _CategoryTile(
    label: 'Service Bundle',
    keywords: ['bundle', 'pick'],
    assetPath: 'assets/images/service_bundle.jpg',
    fallbackIcon: Icons.shopping_basket_outlined,
    isBundle: true,
  ),
];

class _ExploreServicesScreenState extends State<ExploreServicesScreen> {
  final ServiceRepository _repository = ServiceRepository();

  bool _isLoading = true;
  Object? _error;
  List<ServiceModel> _services = const <ServiceModel>[];

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
      final services =
          await _repository.getActiveServices(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _services = services;
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

  /// First active service whose name contains one of `keywords`, or null
  /// if none matches yet.
  ServiceModel? _matchService(List<String> keywords) {
    for (final keyword in keywords) {
      for (final service in _services) {
        if (service.name.toLowerCase().contains(keyword)) return service;
      }
    }
    return null;
  }

  void _openService(ServiceModel service) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LaundryOrderScreen(initialService: service),
      ),
    );
  }

  void _openServiceBundle() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ServiceBundleScreen()),
    );
  }

  void _handleTileTap(_CategoryTile tile, ServiceModel? matched) {
    if (tile.isBundle) {
      _openServiceBundle();
      return;
    }
    if (matched == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${tile.label} is not available yet.')),
      );
      return;
    }
    _openService(matched);
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
        child: _ExploreGlassAppBar(
          title: 'Explore Services',
          onBack: () => Navigator.maybePop(context),
        ),
      ),
      body: Stack(
        children: [
          // Same blurred color blobs on a light base wash as
          // UserDashboard's `_DashboardBackground` — kept as its own
          // local copy (rather than importing a private widget from
          // another screen) so this file stays self-contained.
          const Positioned.fill(child: _ExploreBackground()),
          SafeArea(
            top: false,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: appBarTotalHeight + 8),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Text(
                        'Our Services',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
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
                          message:
                              'We couldn\'t load our services. Please try again.',
                          onRetry: _refresh,
                        ),
                      ),
                    )
                  else if (_services.isEmpty)
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
                    // Fixed 2x2 grid of the four category tiles — always
                    // exactly 4 cells, in the order defined by
                    // `_mainCategories`, regardless of how many services
                    // Firestore actually returns.
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: 0.72,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final tile = _mainCategories[index];
                            final matched = _matchService(tile.keywords);
                            // Prefer the real ServiceModel (real photo, real
                            // price/ETA from Firestore) whenever one was
                            // found. Only the "Service Bundle" tile is meant
                            // to ever render without a match, since it's a
                            // pure navigation entry point rather than an
                            // orderable service.
                            if (matched != null) {
                              return ServiceGridCard(
                                service: matched,
                                onTap: () => _handleTileTap(tile, matched),
                              );
                            }
                            return _PlaceholderCategoryCard(
                              label: tile.label,
                              assetPath: tile.assetPath,
                              fallbackIcon: tile.fallbackIcon,
                              isBundle: tile.isBundle,
                              onTap: () => _handleTileTap(tile, null),
                            );
                          },
                          childCount: _mainCategories.length,
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

/// Ambient backdrop for this screen — a light base wash with three
/// large, heavily-blurred color blobs pinned near the corners. Pixel-
/// for-pixel the same treatment as `UserDashboard`'s own
/// `_DashboardBackground`, so pushing this screen from "See all"
/// reads as a continuation of the same surface rather than a jump to
/// a visually different screen.
class _ExploreBackground extends StatelessWidget {
  const _ExploreBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Top-right dark-blue-to-light-blue blob
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
          // Left-side dark-blue blob, roughly mid-height
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
          // Bottom-right light-blue blob, sits behind the last grid row
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

/// Frosted-glass app bar matching `UserDashboard`'s `_DashboardAppBar`
/// treatment: a blurred, semi-transparent bar with a rounded bottom
/// edge and a subtle border/shadow, instead of a solid opaque
/// Material AppBar. Unlike the dashboard's bar (which is a bottom-nav
/// root tab and shows a logout action), this one is reached via
/// `Navigator.push`, so its leading glass button is a back arrow
/// instead.
class _ExploreGlassAppBar extends StatelessWidget {
  const _ExploreGlassAppBar({required this.title, required this.onBack});

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
                    _ExploreGlassIconButton(
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

/// Small frosted circular icon button — same visual recipe as
/// UserDashboard's private `_GlassIconButton`, generalized with an
/// `icon`/`tooltip` so this file doesn't need to reach into another
/// screen's private widget.
class _ExploreGlassIconButton extends StatelessWidget {
  const _ExploreGlassIconButton({
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

/// Shown for a category tile when no matching ServiceModel exists in
/// Firestore yet. Same card language as ServiceGridCard (photo area,
/// name, arrow button) — including the real bundled photo for that
/// category, cropped with BoxFit.cover and rounded corners, at whatever
/// size the grid cell gives it. The icon is only an errorBuilder
/// fallback for a missing/broken asset, never shown once the photo
/// loads.
class _PlaceholderCategoryCard extends StatelessWidget {
  const _PlaceholderCategoryCard({
    required this.label,
    required this.assetPath,
    required this.fallbackIcon,
    required this.isBundle,
    required this.onTap,
  });

  final String label;
  final String assetPath;
  final IconData fallbackIcon;
  final bool isBundle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                assetPath,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // Only reached if the asset is missing/broken — keeps
                  // the grid from ever showing a blank cell.
                  return Container(
                    color: colors.primary.withValues(alpha: 0.08),
                    child: Center(
                      child: Icon(
                        fallbackIcon,
                        size: 32,
                        color: colors.primary,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Material(
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
              ),
            ],
          ),
        ],
      ),
    );
  }
}