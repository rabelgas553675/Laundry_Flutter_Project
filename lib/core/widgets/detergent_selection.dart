import 'package:flutter/material.dart';

import '../../data/repositories/detergent_repository.dart';
import '../../models/detergent_model.dart';
import 'app_card.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'loading_widget.dart';

/// Loads active detergents from Firestore (via [DetergentRepository])
/// and renders them as a single-select radio list, each row showing
/// its [DetergentModel.additionalPrice]. Reusable wherever a customer
/// picks a detergent — the PART 10 order form, and potentially
/// elsewhere later.
///
/// Controlled widget: selection lives in the parent via [selected] /
/// [onChanged], so PART 11's price calculator can read the chosen
/// detergent's fee directly from the order form's state.
class DetergentSelection extends StatefulWidget {
  const DetergentSelection({
    super.key,
    required this.selected,
    required this.onChanged,
    DetergentRepository? repository,
    // ignore: prefer_initializing_formals
  }) : _repository = repository;

  /// Currently selected detergent, or null if none chosen yet.
  final DetergentModel? selected;

  /// Called with the newly chosen detergent whenever the user taps a
  /// row.
  final ValueChanged<DetergentModel> onChanged;

  final DetergentRepository? _repository;

  @override
  State<DetergentSelection> createState() => _DetergentSelectionState();
}

class _DetergentSelectionState extends State<DetergentSelection> {
  late final DetergentRepository _repository =
      widget._repository ?? DetergentRepository();
  late Future<List<DetergentModel>> _detergentsFuture = _loadDetergents();

  Future<List<DetergentModel>> _loadDetergents() async {
    // First run on a fresh Firestore project: nothing to show yet, so
    // seed the three PART 09 defaults, then read them straight back.
    await _repository.seedDefaultDetergentsIfEmpty();
    return _repository.getActiveDetergents();
  }

  void _retry() {
    setState(() => _detergentsFuture = _loadDetergents());
  }

  String _priceLabel(double price) {
    if (price <= 0) return 'No extra charge';
    return '+ ₱${price.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Detergent', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Choose one detergent for this load.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<DetergentModel>>(
            future: _detergentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LoadingWidget(message: 'Loading detergents...'),
                );
              }

              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Could not load detergents.',
                  onRetry: _retry,
                );
              }

              final detergents = snapshot.data ?? const [];
              if (detergents.isEmpty) {
                return const EmptyState(
                  icon: Icons.local_laundry_service_outlined,
                  title: 'No detergents available',
                  message: 'Check back later or contact support.',
                );
              }

              return RadioGroup<String>(
                groupValue: widget.selected?.id,
                onChanged: (id) {
                  if (id == null) return;
                  final detergent = detergents.firstWhere(
                    (d) => d.id == id,
                    orElse: () => detergents.first,
                  );
                  widget.onChanged(detergent);
                },
                child: Column(
                  children: detergents.map((detergent) {
                    final isSelected = widget.selected == detergent;
                    return RadioListTile<String>(
                      value: detergent.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(detergent.name),
                      subtitle: detergent.description.isNotEmpty
                          ? Text(detergent.description, style: textTheme.bodySmall)
                          : null,
                      secondary: Text(
                        _priceLabel(detergent.additionalPrice),
                        style: textTheme.bodyMedium?.copyWith(
                          color: isSelected ? colors.primary : colors.onSurfaceVariant,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}