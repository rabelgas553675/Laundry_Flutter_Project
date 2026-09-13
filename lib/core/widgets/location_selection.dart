import 'package:flutter/material.dart';

import '../../models/location_area_model.dart';
import 'app_card.dart';

/// PART 10.3 — lets the customer pick which service area their
/// pickup address falls in. This replaces the plain "Location" text
/// field that PART 10.2 shipped as a placeholder.
///
/// Controlled widget: selection lives in the parent (laundry_order_
/// screen.dart) via [selected] / [onChanged], same pattern as
/// [ServiceSelection] / [DetergentSelection]. Unlike those two, the
/// list here ([LocationAreaModel.pickupAreas]) is a local constant
/// rather than something loaded from Firestore — PART 10 doesn't add
/// any database/Firebase functionality, and there's nothing to fetch.
///
/// A later part can swap this for a real map-based picker (e.g.
/// google_maps_flutter + a geocoded pin) without changing the
/// contract the order form depends on — it just needs *a* selected
/// [LocationAreaModel].
class LocationSelection extends StatelessWidget {
  const LocationSelection({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  /// Currently selected pickup area, or null if none chosen yet.
  final LocationAreaModel? selected;

  /// Called with the newly chosen area whenever the customer taps a
  /// row.
  final ValueChanged<LocationAreaModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Location', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Choose the zone your pickup address is in.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: selected?.id,
            onChanged: (id) {
              if (id == null) return;
              final area = LocationAreaModel.pickupAreas.firstWhere(
                (a) => a.id == id,
                orElse: () => LocationAreaModel.pickupAreas.first,
              );
              onChanged(area);
            },
            child: Column(
              children: LocationAreaModel.pickupAreas.map((area) {
                final isSelected = selected == area;
                return RadioListTile<String>(
                  value: area.id,
                  contentPadding: EdgeInsets.zero,
                  title: Text(area.label),
                  subtitle: area.note.isNotEmpty
                      ? Text(
                          area.note,
                          style: textTheme.bodySmall?.copyWith(
                            color: isSelected
                                ? colors.primary
                                : colors.onSurfaceVariant,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                        )
                      : null,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}