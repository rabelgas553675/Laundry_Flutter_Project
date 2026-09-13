import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
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

  late Future<List<ServiceModel>> _servicesFuture = _load();

  /// Id of the service whose activate/deactivate switch is mid-flight,
  /// so only that one card shows a spinner rather than the whole list.
  String? _togglingServiceId;

  Future<List<ServiceModel>> _load() {
    return _repository.getAllServices();
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