import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../data/repositories/service_repository.dart';
import '../../../models/service_model.dart';

/// Small, presentation-only lookup — services don't store an icon in
/// Firestore, so this just picks something sensible by name. Falls
/// back to a generic laundry icon for any service an admin adds later
/// (Part 17) that isn't one of the three defaults.
IconData _iconForService(ServiceModel service) {
  final name = service.name.toLowerCase();
  if (name.contains('quick')) return Icons.flash_on_outlined;
  if (name.contains('premium')) return Icons.auto_awesome_outlined;
  return Icons.local_laundry_service_outlined;
}

/// Loads active services from Firestore (via [ServiceRepository]) and
/// shows them as a horizontal quick-selection strip. Prices/turnaround
/// live in Firestore only — nothing here hard-codes a price, per the
/// PART 08 requirement.
class ServiceSelectionCard extends StatefulWidget {
  const ServiceSelectionCard({
    super.key,
    this.onServiceTap,
    ServiceRepository? repository,
    // ignore: prefer_initializing_formals
  }) : _repository = repository;

  final ValueChanged<ServiceModel>? onServiceTap;
  final ServiceRepository? _repository;

  @override
  State<ServiceSelectionCard> createState() => _ServiceSelectionCardState();
}

class _ServiceSelectionCardState extends State<ServiceSelectionCard> {
  late final ServiceRepository _repository =
      widget._repository ?? ServiceRepository();
  late Future<List<ServiceModel>> _servicesFuture = _loadServices();

  Future<List<ServiceModel>> _loadServices() async {
    try {
      // First run on a fresh Firestore project: nothing to show yet, so
      // seed the three PART 08 defaults, then read them straight back.
      await _repository.seedDefaultServicesIfEmpty();
      return await _repository.getActiveServices();
    } catch (e, stackTrace) {
      // Surface the real Firebase error (permission-denied,
      // failed-precondition, etc.) instead of swallowing it — this is
      // what was hiding the actual cause behind "Could not load
      // services." Check the browser/DevTools console for this line.
      debugPrint('ServiceSelectionCard failed to load services: $e');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  void _retry() {
    setState(() {
      _servicesFuture = _loadServices();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Quick Service Selection', style: textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 92,
            child: FutureBuilder<List<ServiceModel>>(
              future: _servicesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          kDebugMode
                              ? 'Error: ${snapshot.error}'
                              : 'Could not load services.',
                          style: textTheme.bodySmall,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                final services = snapshot.data ?? const [];
                if (services.isEmpty) {
                  return Center(
                    child: Text(
                      'No services available right now.',
                      style: textTheme.bodySmall,
                    ),
                  );
                }

                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: services.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final service = services[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => widget.onServiceTap?.call(service),
                      child: Container(
                        width: 96,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_iconForService(service), color: colors.primary),
                            const SizedBox(height: 8),
                            Text(
                              service.name,
                              textAlign: TextAlign.center,
                              style: textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}