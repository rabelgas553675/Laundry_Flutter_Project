import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/widgets/detergent_selection.dart';
import 'package:laundry_flutter/data/datasources/detergent_datasource.dart';
import 'package:laundry_flutter/data/repositories/detergent_repository.dart';
import 'package:laundry_flutter/models/detergent_model.dart';

class _FakeDatasource implements DetergentDatasource {
  _FakeDatasource({this.detergents = const [], this.throwOnRead = false});
  List<DetergentModel> detergents;
  bool throwOnRead;

  @override
  Future<List<DetergentModel>> getActiveDetergents() async {
    if (throwOnRead) throw Exception('network error');
    return detergents;
  }

  @override
  Future<List<DetergentModel>> getAllDetergents() async => detergents;
  @override
  Future<int> countAll() async => detergents.length;
  @override
  Future<void> createDetergent(DetergentModel detergent) async {}
  @override
  Future<void> seedDefaults(List<DetergentModel> defaults) async {}
  @override
  Future<void> updateDetergentFields(String id, Map<String, dynamic> fields) async {}
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const regular = DetergentModel(id: '1', name: 'Regular', additionalPrice: 0);
  const premium = DetergentModel(id: '2', name: 'Premium', additionalPrice: 30);

  testWidgets('renders each detergent with its additional price label', (tester) async {
    final repo = DetergentRepository(datasource: _FakeDatasource(detergents: [regular, premium]));
    await tester.pumpWidget(_wrap(DetergentSelection(
      selected: null,
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('No extra charge'), findsOneWidget);
    expect(find.text('Premium'), findsOneWidget);
    expect(find.text('+ ₱30'), findsOneWidget);
  });

  testWidgets('selecting a detergent calls onChanged with that detergent', (tester) async {
    final repo = DetergentRepository(datasource: _FakeDatasource(detergents: [regular, premium]));
    DetergentModel? chosen;

    await tester.pumpWidget(_wrap(DetergentSelection(
      selected: null,
      onChanged: (d) => chosen = d,
      repository: repo,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Premium'));
    await tester.pump();

    expect(chosen, equals(premium));
  });

  testWidgets('shows an empty state when no detergents are returned', (tester) async {
    final repo = DetergentRepository(datasource: _FakeDatasource(detergents: []));
    await tester.pumpWidget(_wrap(DetergentSelection(
      selected: null,
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('No detergents available'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when Firestore read fails', (tester) async {
    final repo = DetergentRepository(datasource: _FakeDatasource(throwOnRead: true));
    await tester.pumpWidget(_wrap(DetergentSelection(
      selected: null,
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Could not load detergents.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}