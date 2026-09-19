import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/glass_container.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/service_item_repository.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import '../widgets/admin_service_card.dart';
import '../widgets/service_form_dialog.dart';

/// Fixed content height of the glass app bar (excludes the status-bar
/// inset, which SafeArea adds on top of this) — matches the same
/// constant used across the rest of the Admin section. Only used when
/// [ManageServicesScreen.embedded] is `false`, since the embedded tab
/// inside [AdminDashboard] already has its own app bar + backdrop.
const double _kAppBarContentHeight = 64;

/// PART 17 — Admin Service Management.
///
/// Admin can: view services (active AND inactive, via
/// [ServiceRepository.getAllServices] rather than PART 08's
/// customer-facing [ServiceRepository.getActiveServices]), add a
/// service, edit a service (name/description/price/estimated time),
/// and activate/deactivate it.
///
/// Unlike PART 15/16 (which stream live from Firestore because
/// multiple Admins changing an order's status needs to be seen
/// instantly by a customer watching their tracker), the service
/// catalog is small and rarely-changing, so this screen simply
/// re-fetches once after every add/edit/toggle rather than holding a
/// permanent listener open — the same trade-off already documented on
/// [ServiceRepository]'s cache.
///
/// Reachable only through the `manageServices` route, which
/// [RoleGuard] (PART 05) restricts to [UserRole.admin] — this screen
/// does no role checking of its own.
///
/// REDESIGN — when NOT [embedded] (i.e. opened as its own route
/// rather than as an [AdminDashboard] tab), this now draws the same
/// frosted-glass app bar + blue-blob backdrop as the rest of the
/// Admin section, and every loading/error/empty state renders inside
/// a [GlassContainer] panel. When [embedded] is `true` it stays exactly
/// as before — no own app bar/backdrop, since [AdminDashboard] already
/// supplies both — only the state panels below pick up the glass
/// treatment, since they read fine on either backdrop.
class ManageServicesScreen extends StatefulWidget {
  const ManageServicesScreen({super.key, this.repository, this.embedded = false});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [ServiceRepository].
  final ServiceRepository? repository;

  /// When `true`, shown as one tab of [AdminDashboard]'s bottom-nav
  /// `IndexedStack` — no own `Scaffold`/`AppBar`/background is drawn
  /// in that case.
  final bool embedded;

  @override
  State<ManageServicesScreen> createState() => _ManageServicesScreenState();
}

class _ManageServicesScreenState extends State<ManageServicesScreen> {
  late final ServiceRepository _repository = widget.repository ?? ServiceRepository();

  /// Seeds each itemized service's per-garment catalog (currently
  /// only Dry Cleaning / Wash & Ironing have one — see
  /// [ServiceItemRepository.seedDefaultItemsIfEmpty]). Only ever
  /// written to from here, an admin-only screen, the same way
  /// [ServiceRepository.seedDefaultServicesIfEmpty] is only ever
  /// *reliably* written to from here — every customer-facing
  /// screen's attempt is best-effort and silently fails under
  /// `firestore.rules`.
  final ServiceItemRepository _itemRepository = ServiceItemRepository();

  late Future<List<ServiceModel>> _servicesFuture = _load();

  /// Id of the service whose activate/deactivate switch is mid-flight,
  /// so only that one card shows a spinner rather than the whole list.
  String? _togglingServiceId;

  /// BUG FIX — this screen used to call [ServiceRepository.getAllServices]
  /// directly and nothing else, despite that method's own doc comment
  /// claiming this screen was "the one caller that genuinely can seed
  /// successfully" (because it's admin-only, so the `services` create
  /// actually succeeds instead of being silently swallowed like it is
  /// for every customer-facing caller — see
  /// [ServiceRepository.seedDefaultServicesIfEmpty]'s doc comment).
  /// That call was never actually made, so there was no path in the
  /// app — customer or admin — that could ever create a
  /// [kDefaultServices] entry added after a Firestore project already
  /// had some services in it (e.g. "Dry Cleaning"/"Wash & Ironing" for
  /// an existing project). Customers would see "Dry Cleaning is not
  /// available yet." forever, because nothing ever created that
  /// document.
  ///
  /// Calling it here — before the admin's own list loads — means the
  /// very first time any admin opens Manage Services after a new
  /// default is added to the catalog, it gets created for real, and
  /// every customer-facing screen's own (best-effort, silently-failing)
  /// seed attempt has nothing left to do from then on.
  Future<List<ServiceModel>> _load() async {
    await _repository.seedDefaultServicesIfEmpty();
    final services = await _repository.getAllServices();

    // BUG FIX — seeding the *service* documents above (Dry Cleaning,
    // Wash & Ironing) is only half of what those two services need:
    // each also has its own per-garment/per-load catalog stored at
    // `services/{serviceId}/items`, which nothing was ever seeding.
    // `DryCleaningItemSelection` does call
    // `ServiceItemRepository.seedDefaultItemsIfEmpty` on its own, but
    // only from the *customer* order screen — and per
    // `firestore.rules`, a customer's write to that subcollection is
    // rejected and silently swallowed, same reasoning as
    // `seedDefaultServicesIfEmpty`'s doc comment above. So a Dry
    // Cleaning service created (or seeded) after a project already
    // existed could sit forever with zero item documents, showing
    // "No items available" to every customer, exactly like the
    // parent service document itself used to.
    //
    // Seeding here — an admin-only screen — means the write actually
    // succeeds. `seedDefaultItemsIfEmpty` is itself idempotent (only
    // writes when a service has zero item documents), so it's safe
    // to call for every service on every load, and does nothing at
    // all for service types with no default catalog (Quick/Standard/
    // Premium Wash — see `_defaultCatalogFor`).
    for (final service in services) {
      await _itemRepository.seedDefaultItemsIfEmpty(service.id, service.serviceType);
    }

    return services;
  }

  Future<void> _refresh() async {
    setState(() => _servicesFuture = _load());
    await _servicesFuture;
  }

  Future<void> _openAddDialog() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ServiceFormDialog(repository: _repository),
    );
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Service added.')));
      await _refresh();
    }
  }

  Future<void> _openEditDialog(ServiceModel service) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => ServiceFormDialog(existing: service, repository: _repository),
    );
    if (saved == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Service updated.')));
      await _refresh();
    }
  }

  Future<void> _toggleStatus(ServiceModel service) async {
    setState(() => _togglingServiceId = service.id);
    try {
      final newStatus =
          service.status == ServiceStatus.active ? ServiceStatus.inactive : ServiceStatus.active;
      await _repository.updateService(service.copyWith(status: newStatus));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == ServiceStatus.active
                ? '${service.name} is now active.'
                : '${service.name} is now inactive.',
          ),
        ),
      );
      await _refresh();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Unable to update this service.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _togglingServiceId = null);
    }
  }

  Widget _buildBody(BuildContext context, {required EdgeInsets listPadding}) {
    return FutureBuilder<List<ServiceModel>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _GlassStatePanel(
            child: LoadingWidget(message: 'Loading services...'),
          );
        }
        if (snapshot.hasError) {
          return _GlassStatePanel(
            child: ErrorState(
              message: 'Unable to load services. Please try again.',
              onRetry: _refresh,
            ),
          );
        }

        final services = snapshot.data ?? const <ServiceModel>[];
        if (services.isEmpty) {
          return _GlassStatePanel(
            child: EmptyState(
              title: 'No services yet',
              message: 'Add your first laundry service to get started.',
              icon: Icons.local_laundry_service_outlined,
              actionLabel: 'Add Service',
              onAction: _openAddDialog,
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.separated(
            padding: listPadding,
            itemCount: services.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final service = services[index];
              return AdminServiceCard(
                service: service,
                isUpdating: _togglingServiceId == service.id,
                onEdit: () => _openEditDialog(service),
                onToggleStatus: () => _toggleStatus(service),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Embedded (a tab inside AdminDashboard): AdminDashboard already
    // supplies the glass app bar and blue-blob background, so this
    // just returns the content — a bare list/state-panel, with its
    // own FAB anchored via a Stack since there's no Scaffold here to
    // host a floatingActionButton.
    if (widget.embedded) {
      return Stack(
        children: [
          _buildBody(context, listPadding: const EdgeInsets.only(bottom: 96)),
          Positioned(
            right: 0,
            bottom: 12,
            child: _GlassFab(onPressed: _openAddDialog),
          ),
        ],
      );
    }

    // Standalone route: draw the full glass shell (background + app
    // bar), same as the other Admin screens.
    final statusBarInset = MediaQuery.paddingOf(context).top;
    final appBarTotalHeight = statusBarInset + _kAppBarContentHeight;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(appBarTotalHeight),
        child: _ReportAppBar(title: 'Manage Services', onBack: () => Navigator.maybePop(context)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _ReportBackground()),
          SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, appBarTotalHeight + 14, 16, 0),
                  child: _buildBody(context, listPadding: const EdgeInsets.only(bottom: 96)),
                ),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: 20,
            child: _GlassFab(onPressed: _openAddDialog),
          ),
        ],
      ),
    );
  }
}

/// Frosted "Add Service" FAB — a light glass pill (matches the
/// "Add Promo" button style used elsewhere in the Admin section):
/// translucent white background with primary-colored icon/text,
/// rather than a solid dark pill with white text.
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
                    'Add Service',
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

/// Wraps a loading/error/empty state widget in a glass panel so it
/// still reads as belonging to this screen's frosted-glass
/// background instead of floating as a bare opaque block.
class _GlassStatePanel extends StatelessWidget {
  const _GlassStatePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        borderRadius: 24,
        child: child,
      ),
    );
  }
}

/// -----------------------------------------------------------------
/// Shared glass shell pieces (background blobs, app bar) — only used
/// when this screen is NOT embedded. Same look as
/// [AdminDashboard]/[AdminNotificationsScreen]/the report screens,
/// duplicated here (private to this file) so this screen doesn't
/// depend on those files directly.
/// -----------------------------------------------------------------

class _ReportBackground extends StatelessWidget {
  const _ReportBackground();

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

/// Minimal glass app bar: back button + title, same blur/border
/// treatment as the Admin section's other app bars.
class _ReportAppBar extends StatelessWidget {
  const _ReportAppBar({required this.title, required this.onBack});

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
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
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
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: onBack,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 18,
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

/// Small circular glass button — same treatment used across the rest
/// of the Admin section's app bars.
class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
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
            icon: Icon(icon, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}