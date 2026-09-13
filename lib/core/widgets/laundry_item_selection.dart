import 'package:flutter/material.dart';

import '../../data/repositories/laundry_item_repository.dart';
import '../../models/laundry_item_model.dart';
import 'app_card.dart';
import 'empty_state.dart';
import 'error_state.dart';
import 'loading_widget.dart';

/// Maps a laundry item's stored icon name to a concrete [IconData].
/// Keeps Firestore holding a plain string (portable, no Flutter
/// dependency baked into the data) while the widget layer decides
/// how to render it. Unknown/future icon names fall back gracefully.
IconData _iconFor(String iconName) {
  switch (iconName) {
    case 'bed':
      return Icons.bed_outlined;
    case 'bedroom_child':
      return Icons.bedroom_child_outlined;
    case 'dry_cleaning':
      return Icons.dry_cleaning_outlined;
    case 'checkroom':
    default:
      return Icons.checkroom_outlined;
  }
}

/// Loads active laundry items from Firestore (via
/// [LaundryItemRepository]) and renders them as a multi-select chip
/// grid. Reusable anywhere a customer needs to flag what's being
/// washed — the PART 10 order form, and potentially elsewhere later.
///
/// Selection state is owned by the parent through [selected] /
/// [onChanged] (a controlled widget), so the order form can read the
/// chosen items directly without reaching into this widget's state.
class LaundryItemSelection extends StatefulWidget {
  const LaundryItemSelection({
    super.key,
    required this.selected,
    required this.onChanged,
    LaundryItemRepository? repository,
    // ignore: prefer_initializing_formals
  }) : _repository = repository;

  /// Currently selected items, keyed by [LaundryItemModel]'s id-based
  /// equality — the parent screen owns this set.
  final Set<LaundryItemModel> selected;

  /// Called with the full updated selection whenever the user taps a
  /// chip to select/deselect it.
  final ValueChanged<Set<LaundryItemModel>> onChanged;

  final LaundryItemRepository? _repository;

  @override
  State<LaundryItemSelection> createState() => _LaundryItemSelectionState();
}

class _LaundryItemSelectionState extends State<LaundryItemSelection> {
  late final LaundryItemRepository _repository =
      widget._repository ?? LaundryItemRepository();
  late Future<List<LaundryItemModel>> _itemsFuture = _loadItems();

  Future<List<LaundryItemModel>> _loadItems() async {
    // First run on a fresh Firestore project: nothing to show yet, so
    // seed the four PART 09 defaults, then read them straight back.
    await _repository.seedDefaultItemsIfEmpty();
    return _repository.getActiveItems();
  }

  void _retry() {
    setState(() => _itemsFuture = _loadItems());
  }

  void _toggle(LaundryItemModel item) {
    final next = Set<LaundryItemModel>.of(widget.selected);
    if (!next.remove(item)) {
      next.add(item);
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
          Text('Laundry Items', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Select everything included in this load.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<LaundryItemModel>>(
            future: _itemsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: LoadingWidget(message: 'Loading laundry items...'),
                );
              }

              if (snapshot.hasError) {
                return ErrorState(
                  message: 'Could not load laundry items.',
                  onRetry: _retry,
                );
              }

              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.checkroom_outlined,
                  title: 'No laundry items available',
                  message: 'Check back later or contact support.',
                );
              }

              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: items.map((item) {
                  final isSelected = widget.selected.contains(item);
                  return FilterChip(
                    selected: isSelected,
                    onSelected: (_) => _toggle(item),
                    avatar: Icon(
                      _iconFor(item.icon),
                      size: 18,
                      color: isSelected
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    label: Text(item.name),
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