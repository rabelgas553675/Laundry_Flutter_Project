import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/service_item_repository.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';
import '../widgets/admin_service_card.dart';
import '../widgets/service_form_dialog.dart';

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
class ManageServicesScreen extends StatefulWidget {
  const ManageServicesScreen({super.key, this.repository});

  /// Injectable for widget tests; defaults to a real
  /// Firestore-backed [ServiceRepository].
  final ServiceRepository? repository;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
      body: SafeArea(
        child: FutureBuilder<List<ServiceModel>>(
          future: _servicesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Loading services...');
            }
            if (snapshot.hasError) {
              return ErrorState(
                message: 'Unable to load services. Please try again.',
                onRetry: _refresh,
              );
            }

            final services = snapshot.data ?? const <ServiceModel>[];
            if (services.isEmpty) {
              return EmptyState(
                title: 'No services yet',
                message: 'Add your first laundry service to get started.',
                icon: Icons.local_laundry_service_outlined,
                actionLabel: 'Add Service',
                onAction: _openAddDialog,
              );
            }

            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
        ),
      ),
    );
  }
}