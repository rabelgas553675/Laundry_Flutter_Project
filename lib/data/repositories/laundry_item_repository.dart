import '../datasources/laundry_item_datasource.dart';
import '../../models/laundry_item_model.dart';

/// PART 09 default catalog. Only ever used by
/// [seedDefaultItemsIfEmpty] to populate a brand-new Firestore
/// project — the UI never reads this list directly, so item data
/// always comes from Firestore, never hard-coded in a widget.
const List<LaundryItemModel> kDefaultLaundryItems = [
  LaundryItemModel(
    id: '',
    name: 'Clothes',
    description: 'Everyday shirts, pants, and casual wear.',
    icon: 'checkroom',
  ),
  LaundryItemModel(
    id: '',
    name: 'Bedsheets',
    description: 'Bedsheets, pillowcases, and covers.',
    icon: 'bed',
  ),
  LaundryItemModel(
    id: '',
    name: 'Blankets',
    description: 'Blankets, comforters, and duvets.',
    icon: 'bedroom_child',
  ),
  LaundryItemModel(
    id: '',
    name: 'Towels',
    description: 'Bath towels, hand towels, and washcloths.',
    icon: 'dry_cleaning',
  ),
];

class LaundryItemRepository {
  LaundryItemRepository({LaundryItemDatasource? datasource})
      : _datasource = datasource ?? LaundryItemDatasource();

  final LaundryItemDatasource _datasource;

  /// Session cache — cleared via [clearCache]. Avoids re-fetching the
  /// same short, rarely-changing list on every rebuild of the order
  /// form (PART 10).
  List<LaundryItemModel>? _cachedActive;

  Future<List<LaundryItemModel>> getActiveItems({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedActive != null) {
      return _cachedActive!;
    }
    final items = await _datasource.getActiveItems();
    _cachedActive = items;
    return items;
  }

  Future<List<LaundryItemModel>> getAllItems() {
    return _datasource.getAllItems();
  }

  /// Idempotent: only writes the default catalog the very first time
  /// there are zero laundry item documents, so re-running the app
  /// never duplicates items. Safe to call from a widget's build path.
  Future<void> seedDefaultItemsIfEmpty() async {
    final existing = await _datasource.countAll();
    if (existing > 0) return;
    await _datasource.seedDefaults(kDefaultLaundryItems);
    _cachedActive = null; // force a fresh read next call
  }

  Future<void> createItem(LaundryItemModel item) async {
    await _datasource.createItem(item);
    _cachedActive = null;
  }

  Future<void> updateItem(LaundryItemModel updated) async {
    await _datasource.updateItemFields(updated.id, updated.toEditableMap());
    _cachedActive = null;
  }

  void clearCache() {
    _cachedActive = null;
  }
}