import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/promo_repository.dart';
import '../../../models/promo_model.dart';
import '../widgets/promo_card.dart';
import 'add_promo_screen.dart';
import 'edit_promo_screen.dart';

/// PART 18B — Admin Promotion Management.
///
/// Admin can: view all promotions, create promotions, edit
/// promotions, deactivate promotions, view promotion details (via
/// [AdminPromoCard] itself — there's no separate details screen,
/// since a promo has few enough fields to show fully on its card),
/// search promotions, and filter promotions by status.
///
/// Like [ManageServicesScreen] (PART 17), the promo catalog is small
/// and rarely-changing, so this screen re-fetches once after every
/// add/edit/toggle rather than holding a permanent realtime
/// subscription open, via [PromoRepository.getAllPromos].
///
/// Reachable through the `managePromos` route, which [RoleGuard]
/// (PART 05) restricts to [UserRole.admin] — this screen does no role
/// checking of its own — and also embedded directly as one of
/// [AdminDashboard]'s bottom-nav tabs (see [embedded]).
class ManagePromosScreen extends StatefulWidget {
  const ManagePromosScreen({super.key, this.repository, this.embedded = false});

  /// Injectable for widget tests; defaults to a real
  /// Supabase-backed [PromoRepository].
  final PromoRepository? repository;

  /// When `true`, shown as one tab of [AdminDashboard]'s bottom-nav
  /// `IndexedStack` — no own `Scaffold`/`AppBar` is drawn in that
  /// case, and the status [TabBar] moves into the body instead of
  /// living in `AppBar.bottom` (there's no AppBar to hang it off of).
  final bool embedded;

  @override
  State<ManagePromosScreen> createState() => _ManagePromosScreenState();
}

class _ManagePromosScreenState extends State<ManagePromosScreen>
    with SingleTickerProviderStateMixin {
  late final PromoRepository _repository = widget.repository ?? PromoRepository();

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  late Future<List<PromoModel>> _promosFuture = _load();

  /// Id of the promo whose activate/deactivate switch is mid-flight,
  /// so only that one card shows a spinner rather than the whole list.
  String? _togglingPromoId;

  /// One tab per [PromoDisplayStatus], "All" first — matches this
  /// part's "Filter promotions by status" / "Display status: Active,
  /// Inactive, Expired, Scheduled" requirements exactly. Index 0 is
  /// "All"; index `i` (i >= 1) maps to `PromoDisplayStatus.values[i - 1]`.
  static const _tabs = ['All', 'Active', 'Inactive', 'Expired', 'Scheduled'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _searchController.addListener(() {
      setState(() => _query = _searchController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<List<PromoModel>> _load() => _repository.getAllPromos(forceRefresh: true);

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _promosFuture = future);
    await future;
  }

  /// Tab filter — client-side over the single fetched list, same
  /// reasoning [ManageOrdersScreen] (PART 16) gives for doing this
  /// instead of four/five separate Firestore queries. Uses each
  /// promo's *computed* [PromoModel.displayStatus] (Active/Inactive/
  /// Expired/Scheduled), not the raw admin [PromoStatus] on/off flag.
  List<PromoModel> _filterByTab(List<PromoModel> promos, int tabIndex) {
    if (tabIndex == 0) return promos;
    final target = PromoDisplayStatus.values[tabIndex - 1];
    return promos.where((p) => p.displayStatus() == target).toList();
  }

  /// Search filter — matches on promo code and description, so an
  /// admin can find a promotion by whichever detail they remember
  /// about it.
  List<PromoModel> _filterBySearch(List<PromoModel> promos, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return promos;
    return promos.where((p) {
      return p.code.toLowerCase().contains(q) || p.description.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openAddScreen() async {
    final createdPromo = await Navigator.push<PromoModel>(
      context,
      MaterialPageRoute(builder: (_) => AddPromoScreen(repository: _repository)),
    );
    if (createdPromo == null) return;
    if (!mounted) return;

    // Splice the new promo straight into the list already backing
    // the screen, rather than re-fetching from Supabase, so it shows
    // up immediately — in whichever tab/search results it belongs to,
    // since [_filterByTab]/[_filterBySearch] both recompute from
    // [_promosFuture] on every build. No manual reload needed.
    await _addPromoToList(createdPromo);

    // The screen may have been disposed while the await above ran, so
    // re-check before touching `context` again (this is the guard that
    // satisfies `use_build_context_synchronously`).
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Promotion created.')));
  }

  /// Inserts a freshly created promo at the front of the current list
  /// and pushes that updated list back into [_promosFuture], so
  /// [FutureBuilder] rebuilds with it on the next frame. The current
  /// list is awaited first (it's already resolved and on-screen by
  /// the time this runs, so this returns immediately) rather than
  /// assumed, since [setState] must only ever assign a value
  /// synchronously — never perform the async work itself.
  Future<void> _addPromoToList(PromoModel promo) async {
    final currentPromos = await _promosFuture;
    final updatedPromos = [promo, ...currentPromos];
    if (!mounted) return;
    setState(() {
      _promosFuture = Future.value(updatedPromos);
    });
  }

  Future<void> _openEditScreen(PromoModel promo) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditPromoScreen(existing: promo, repository: _repository),
      ),
    );
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Promotion updated.')));
      await _refresh();
    }
  }

  /// "Deactivate promotions" (and reactivate them again) — flips the
  /// raw admin [PromoStatus] on/off flag. A promo already computed as
  /// Expired can still be toggled here (e.g. an admin reactivating and
  /// then editing its dates), since [PromoStatus] and
  /// [PromoDisplayStatus] are deliberately independent — see
  /// [PromoModel.displayStatus]'s doc comment.
  Future<void> _toggleStatus(PromoModel promo) async {
    setState(() => _togglingPromoId = promo.id);
    try {
      final newStatus =
          promo.status == PromoStatus.active ? PromoStatus.inactive : PromoStatus.active;
      await _repository.updatePromo(promo.copyWith(status: newStatus));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == PromoStatus.active
                ? '${promo.code} is now active.'
                : '${promo.code} has been deactivated.',
          ),
        ),
      );
      await _refresh();
    } on sb.PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.isNotEmpty ? e.message : 'Unable to update this promotion.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _togglingPromoId = null);
    }
  }

  /// "Delete promotions" — a permanent, hard delete, distinct from
  /// [_toggleStatus]'s deactivate. Confirms first since this can't be
  /// undone (a deactivated promo can be reactivated; a deleted one
  /// can't be recovered).
  Future<void> _deletePromo(PromoModel promo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete promotion?'),
        content: Text(
          'This will permanently delete "${promo.code}". This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _togglingPromoId = promo.id);
    try {
      await _repository.deletePromo(promo.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${promo.code} has been deleted.')));
      await _refresh();
    } on sb.PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.isNotEmpty ? e.message : 'Unable to delete this promotion.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _togglingPromoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Built once per build() and placed in exactly one of the two
    // spots below (AppBar.bottom when standalone, inline in the body
    // when embedded) — never both at once, so there's no duplicate
    // widget-in-tree issue despite the single shared instance.
    final tabBar = TabBar(
      controller: _tabController,
      isScrollable: true,
      tabs: _tabs.map((label) => Tab(text: label)).toList(),
    );

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Manage Promotions'),
              bottom: tabBar,
            ),
      floatingActionButton: _GlassFab(onPressed: _openAddScreen),
      body: SafeArea(
        top: !widget.embedded,
        child: Column(
          children: [
            // No AppBar to hang the TabBar off of when embedded, so
            // it renders here instead, above the search field — same
            // visual position it occupies via AppBar.bottom when
            // standalone, just moved into the body.
            if (widget.embedded)
              Material(
                color: Colors.transparent,
                child: tabBar,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search by promo code or description',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => _searchController.clear(),
                        ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<PromoModel>>(
                future: _promosFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const LoadingWidget(message: 'Loading promotions...');
                  }
                  if (snapshot.hasError) {
                    return ErrorState(
                      message: 'Unable to load promotions. Please try again.',
                      onRetry: _refresh,
                    );
                  }

                  final promos = snapshot.data ?? const <PromoModel>[];
                  if (promos.isEmpty) {
                    return EmptyState(
                      title: 'No promotions yet',
                      message: 'Create your first promo code to get started.',
                      icon: Icons.local_offer_outlined,
                      actionLabel: 'Add Promo',
                      onAction: _openAddScreen,
                    );
                  }

                  return TabBarView(
                    controller: _tabController,
                    children: List.generate(_tabs.length, (tabIndex) {
                      final byTab = _filterByTab(promos, tabIndex);
                      final filtered = _filterBySearch(byTab, _query);

                      if (filtered.isEmpty) {
                        return EmptyState(
                          title: _query.isEmpty
                              ? 'No promotions in this category yet.'
                              : 'No promotions match your search.',
                          icon: Icons.filter_list_off,
                        );
                      }

                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final promo = filtered[index];
                            return AdminPromoCard(
                              promo: promo,
                              isUpdating: _togglingPromoId == promo.id,
                              onEdit: () => _openEditScreen(promo),
                              onToggleStatus: () => _toggleStatus(promo),
                              onDelete: () => _deletePromo(promo),
                            );
                          },
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Frosted "Add Promo" FAB — a light glass pill (translucent white
/// background with primary-colored icon/text) matching the same
/// [_GlassFab] used on [ManageServicesScreen]'s "Add Service" button,
/// in place of the default solid [FloatingActionButton.extended].
class _GlassFab extends StatelessWidget {
  const _GlassFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.white.withValues(alpha: 0.55),
          child: InkWell(
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                boxShadow: [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.15),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, color: colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Add Promo',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}