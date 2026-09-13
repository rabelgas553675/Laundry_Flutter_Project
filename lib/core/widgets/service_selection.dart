import 'package:flutter/material.dart';

import '../../data/repositories/service_repository.dart';
import '../../models/service_model.dart';

/// Same icon heuristic used by [ServiceSelectionCard] on the dashboard,
/// kept in sync here so a service looks the same wherever it appears.
IconData _iconForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return Icons.flash_on_outlined;
  if (name.contains('premium')) return Icons.auto_awesome_outlined;
  return Icons.local_laundry_service_outlined;
}

/// PART 10.1 — "Select Service" step of [LaundryOrderScreen].
///
/// Unlike [ServiceSelectionCard] (dashboard, tap-through only), this
/// widget tracks which service is *currently chosen* so the Stepper
/// can validate against it — hence the [selected] / [onChanged] pair
/// instead of a single [onServiceTap] callback.
///
/// Loads from the same [ServiceRepository] as the dashboard card,
/// including the PART 08 seed-if-empty call, so this screen works
/// correctly even if it's the very first screen touched on a fresh
/// Firestore project.
class ServiceSelection extends StatefulWidget {
  const ServiceSelection({
    super.key,
    required this.selected,
    required this.onChanged,
    ServiceRepository? repository,
    // ignore: prefer_initializing_formals
  }) : _repository = repository;

  final ServiceModel? selected;
  final ValueChanged<ServiceModel?> onChanged;
  final ServiceRepository? _repository;

  @override
  State<ServiceSelection> createState() => _ServiceSelectionState();
}

class _ServiceSelectionState extends State<ServiceSelection> {
  late final ServiceRepository _repository =
      widget._repository ?? ServiceRepository();
  late final Future<List<ServiceModel>> _servicesFuture = _loadServices();

  Future<List<ServiceModel>> _loadServices() async {
    await _repository.seedDefaultServicesIfEmpty();
    return _repository.getActiveServices();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<List<ServiceModel>>(
      future: _servicesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Could not load services. Pull to refresh or try again later.',
              style: textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          );
        }

        final services = snapshot.data ?? const [];
        if (services.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No services available right now.',
              style: textTheme.bodySmall,
            ),
          );
        }

        return Column(
          children: [
            for (final service in services) ...[
              _ServiceOptionTile(
                service: service,
                isSelected: widget.selected?.id == service.id,
                onTap: () => widget.onChanged(service),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _ServiceOptionTile extends StatelessWidget {
  const _ServiceOptionTile({
    required this.service,
    required this.isSelected,
    required this.onTap,
  });

  final ServiceModel service;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.primary.withValues(alpha: 0.08)
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(_iconForService(service), color: colors.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    service.description,
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${service.pricePerKg.toStringAsFixed(0)}/kg · ${service.estimatedTime}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Non-deprecated stand-in for a Radio button: we don't need
            // Radio's built-in group semantics since `isSelected` is
            // already driven externally by the parent's selection state.
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected ? colors.primary : colors.outline,
            ),
          ],
        ),
      ),
    );
  }
}