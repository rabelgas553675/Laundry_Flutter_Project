import '../datasources/detergent_datasource.dart';
import '../../models/detergent_model.dart';

/// PART 09 default catalog. Only ever used by
/// [seedDefaultDetergentsIfEmpty] to populate a brand-new Firestore
/// project — prices always come from Firestore, never a widget.
const List<DetergentModel> kDefaultDetergents = [
  DetergentModel(
    id: '',
    name: 'Regular',
    description: 'Our standard detergent, included at no extra cost.',
    additionalPrice: 0,
  ),
  DetergentModel(
    id: '',
    name: 'Premium',
    description: 'Extra-strength detergent with fabric softener.',
    additionalPrice: 30,
  ),
  DetergentModel(
    id: '',
    name: 'Hypoallergenic',
    description: 'Gentle, fragrance-free formula for sensitive skin.',
    additionalPrice: 50,
  ),
];

class DetergentRepository {
  DetergentRepository({DetergentDatasource? datasource})
      : _datasource = datasource ?? DetergentDatasource();

  final DetergentDatasource _datasource;

  /// Session cache — cleared via [clearCache].
  List<DetergentModel>? _cachedActive;

  Future<List<DetergentModel>> getActiveDetergents({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedActive != null) {
      return _cachedActive!;
    }
    final detergents = await _datasource.getActiveDetergents();
    _cachedActive = detergents;
    return detergents;
  }

  Future<List<DetergentModel>> getAllDetergents() {
    return _datasource.getAllDetergents();
  }

  /// Idempotent: only writes the default catalog the very first time
  /// there are zero detergent documents.
  Future<void> seedDefaultDetergentsIfEmpty() async {
    final existing = await _datasource.countAll();
    if (existing > 0) return;
    await _datasource.seedDefaults(kDefaultDetergents);
    _cachedActive = null;
  }

  Future<void> createDetergent(DetergentModel detergent) async {
    await _datasource.createDetergent(detergent);
    _cachedActive = null;
  }

  Future<void> updateDetergent(DetergentModel updated) async {
    await _datasource.updateDetergentFields(updated.id, updated.toEditableMap());
    _cachedActive = null;
  }

  void clearCache() {
    _cachedActive = null;
  }
}