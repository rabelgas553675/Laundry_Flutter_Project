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

import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../core/widgets/service_grid_card.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import '../../user/screens/laundry_order_screen.dart';

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
    return Scaffold(
      // Back arrow is automatic here since this screen is always
      // reached via Navigator.push — no extra wiring needed.
      appBar: AppBar(title: const Text('Explore Services')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            slivers: [
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
    );
  }
}