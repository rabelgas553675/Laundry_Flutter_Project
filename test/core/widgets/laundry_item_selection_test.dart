import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_flutter/core/widgets/laundry_item_selection.dart';
import 'package:laundry_flutter/data/datasources/laundry_item_datasource.dart';
import 'package:laundry_flutter/data/repositories/laundry_item_repository.dart';
import 'package:laundry_flutter/models/laundry_item_model.dart';

class _FakeDatasource implements LaundryItemDatasource {
  _FakeDatasource({this.items = const [], this.throwOnRead = false});
  List<LaundryItemModel> items;
  bool throwOnRead;

  @override
  Future<List<LaundryItemModel>> getActiveItems() async {
    if (throwOnRead) throw Exception('network error');
    return items;
  }

  @override
  Future<List<LaundryItemModel>> getAllItems() async => items;
  @override
  Future<int> countAll() async => items.length;
  @override
  Future<void> createItem(LaundryItemModel item) async {}
  @override
  Future<void> seedDefaults(List<LaundryItemModel> defaults) async {}
  @override
  Future<void> updateItemFields(String id, Map<String, dynamic> fields) async {}
}

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  const clothes = LaundryItemModel(id: '1', name: 'Clothes');
  const bedsheets = LaundryItemModel(id: '2', name: 'Bedsheets');

  testWidgets('shows a loading indicator while fetching', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(items: [clothes]));
    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: const {},
      onChanged: (_) {},
      repository: repo,
    )));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders each active item as a chip once loaded', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(items: [clothes, bedsheets]));
    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: const {},
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Clothes'), findsOneWidget);
    expect(find.text('Bedsheets'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(2));
  });

  testWidgets('tapping a chip adds it to the selection via onChanged', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(items: [clothes, bedsheets]));
    Set<LaundryItemModel> lastSelection = {};

    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: const {},
      onChanged: (s) => lastSelection = s,
      repository: repo,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clothes'));
    await tester.pump();

    expect(lastSelection, contains(clothes));
    expect(lastSelection.length, 1);
  });

  testWidgets('tapping an already-selected chip removes it (toggle off)', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(items: [clothes]));
    Set<LaundryItemModel> lastSelection = {clothes};

    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: {clothes},
      onChanged: (s) => lastSelection = s,
      repository: repo,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clothes'));
    await tester.pump();

    expect(lastSelection, isEmpty);
  });

  testWidgets('shows an empty state when no items are returned', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(items: []));
    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: const {},
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('No laundry items available'), findsOneWidget);
  });

  testWidgets('shows an error state with retry when Firestore read fails', (tester) async {
    final repo = LaundryItemRepository(datasource: _FakeDatasource(throwOnRead: true));
    await tester.pumpWidget(_wrap(LaundryItemSelection(
      selected: const {},
      onChanged: (_) {},
      repository: repo,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Could not load laundry items.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}