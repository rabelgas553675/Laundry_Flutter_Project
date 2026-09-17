import 'package:flutter/material.dart';

import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/service_item_repository.dart';
import '../../../models/service_item_model.dart';
import '../../../models/service_model.dart';
import 'order_item_card.dart';

/// PART 2 — loads an itemized service's per-garment catalog from
/// Firestore (via [ServiceItemRepository]) and renders it as a list
/// of [OrderItemCard] rows with `[-] N [+]` quantity steppers, one
/// per catalog item (Suit, Coat, Blazer, ...).
///
/// Reusable for any [ServiceType.isItemized] service, not hard-coded
/// to Dry Cleaning specifically — which catalog this renders is
/// entirely decided by [serviceId]/[serviceType].
///
/// Selection state (which item -> how many) is owned by the parent
/// through [selected]/[onChanged] (a controlled widget, same pattern
/// as `LaundryItemSelection`), so `LaundryOrderScreen` can read the
/// chosen quantities directly and turn them into priced
/// `OrderItemModel`s via `OrderItemModel.priced(catalogItem: ...,
/// quantity: ...)` without reaching into this widget's own state.
class DryCleaningItemSelection extends StatefulWidget {
  const DryCleaningItemSelection({
    super.key,
    required this.serviceId,
    required this.serviceType,
    required this.selected,
    required this.onChanged,
    ServiceItemRepository? repository,
    // ignore: prefer_initializing_formals
  }) : _repository = repository;

  final String serviceId;
  final ServiceType serviceType;

  /// Currently chosen quantities, keyed by [ServiceItemModel]'s
  /// id-based equality. An item that isn't a key (or maps to `0`) is
  /// treated as not selected.
  final Map<ServiceItemModel, int> selected;

  /// Called with the full updated quantity map whenever `+`/`-` is
  /// tapped on any item.
  final ValueChanged<Map<ServiceItemModel, int>> onChanged;

  final ServiceItemRepository? _repository;

  @override
  State<DryCleaningItemSelection> createState() => _DryCleaningItemSelectionState();
}

class _DryCleaningItemSelectionState extends State<DryCleaningItemSelection> {
  late final ServiceItemRepository _repository = widget._repository ?? ServiceItemRepository();
  late Future<List<ServiceItemModel>> _itemsFuture = _loadItems();

  @override
  void didUpdateWidget(covariant DryCleaningItemSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different service was picked (e.g. the customer went back to
    // Step 1 and chose a different itemized service) — reload that
    // service's own catalog instead of showing a stale one.
    if (oldWidget.serviceId != widget.serviceId) {
      setState(() => _itemsFuture = _loadItems());
    }
  }

  Future<List<ServiceItemModel>> _loadItems() async {
    // First run for a service with no catalog documents yet: seed the
    // PART 1 defaults for its serviceType, then read them straight back.
    await _repository.seedDefaultItemsIfEmpty(widget.serviceId, widget.serviceType);
    return _repository.getActiveItems(widget.serviceId);
  }

  void _retry() {
    setState(() => _itemsFuture = _loadItems());
  }

  void _setQuantity(ServiceItemModel item, int quantity) {
    final next = Map<ServiceItemModel, int>.of(widget.selected);
    if (quantity <= 0) {
      next.remove(item);
    } else {
      next[item] = quantity;
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select Items', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Choose each garment and how many.', style: textTheme.bodySmall),
          const SizedBox(height: 12),
          FutureBuilder<List<ServiceItemModel>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LoadingWidget(message: 'Loading items...'),
                );
              }

              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Could not load items for this service.',
                  onRetry: _retry,
                );
              }

              final catalog = snapshot.data ?? const [];
              if (catalog.isEmpty) {
                return const EmptyState(
                  icon: Icons.dry_cleaning_outlined,
                  title: 'No items available',
                  message: 'Check back later or contact support.',
                );
              }

              return Column(
                children: catalog.map((item) {
                  final quantity = widget.selected[item] ?? 0;
                  return OrderItemCard(
                    item: item,
                    quantity: quantity,
                    onChanged: (newQuantity) => _setQuantity(item, newQuantity),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}