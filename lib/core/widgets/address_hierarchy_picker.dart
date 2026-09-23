import 'package:flutter/material.dart';

import '../../data/datasources/ph_address_datasource.dart';
import '../../models/ph_address.dart';

/// Region -> Province -> City/Municipality -> Barangay picker for the
/// customer's own delivery/pickup address.
///
/// Nationwide: every step is populated from [PhAddressDatasource] (the
/// full bundled PSGC dataset) — the customer can pick literally any
/// Philippine region, province, city/municipality and barangay
/// combination. Nothing here is restricted to Digos City or assumes
/// the customer lives near the shop.
///
/// This is what backs the "Region, Province, City, Barangay" field on
/// EditAddressScreen. It is unrelated to `LocationSelection`
/// (lib/core/widgets/location_selection.dart), which remains the
/// shop's own separate pickup-service-area selector used in the order
/// flow — see the class doc on `LocationAreaModel` for that
/// distinction.
class AddressHierarchyPicker {
  AddressHierarchyPicker._();

  /// Opens the picker as a tall modal bottom sheet. Resolves with the
  /// customer's chosen [PhAddressSelection] once they complete all
  /// four steps, or `null` if they dismiss the sheet without
  /// finishing — callers should leave any existing selection
  /// untouched in that case.
  ///
  /// [initial], when given, seeds the sheet with an existing
  /// selection (e.g. re-opening this from a saved address) so the
  /// customer starts at the Barangay step with Region/Province/City
  /// already resolved, instead of picking all four again from
  /// scratch.
  static Future<PhAddressSelection?> show(
    BuildContext context, {
    PhAddressSelection? initial,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return showModalBottomSheet<PhAddressSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => _AddressHierarchySheet(initial: initial),
    );
  }
}

enum _Step { region, province, city, barangay }

class _AddressHierarchySheet extends StatefulWidget {
  const _AddressHierarchySheet({this.initial});

  final PhAddressSelection? initial;

  @override
  State<_AddressHierarchySheet> createState() =>
      _AddressHierarchySheetState();
}

class _AddressHierarchySheetState extends State<_AddressHierarchySheet> {
  final _datasource = PhAddressDatasource.instance;
  final _searchController = TextEditingController();

  _Step _step = _Step.region;
  bool _loading = true;

  PhRegion? _region;
  PhProvince? _province;
  PhCity? _city;

  List<PhRegion> _regions = const [];
  List<PhProvince> _provinces = const [];
  List<PhCity> _cities = const [];
  List<PhBarangay> _barangays = const [];

  @override
  void initState() {
    super.initState();
    _region = widget.initial?.region;
    _province = widget.initial?.province;
    _city = widget.initial?.city;
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _regions = await _datasource.getRegions();
    if (_region != null) {
      _provinces = await _datasource.getProvinces(_region!.code);
    }
    if (_province != null) {
      _cities = await _datasource.getCities(_province!.code);
    }
    if (_city != null) {
      _barangays = await _datasource.getBarangays(_city!.code);
    }
    if (!mounted) return;
    setState(() {
      if (_city != null) {
        _step = _Step.barangay;
      } else if (_province != null) {
        _step = _Step.city;
      } else if (_region != null) {
        _step = _Step.province;
      } else {
        _step = _Step.region;
      }
      _loading = false;
    });
  }

  String get _stepTitle {
    switch (_step) {
      case _Step.region:
        return 'Select Region';
      case _Step.province:
        return 'Select Province';
      case _Step.city:
        return 'Select City / Municipality';
      case _Step.barangay:
        return 'Select Barangay';
    }
  }

  List<Object> get _currentItems {
    switch (_step) {
      case _Step.region:
        return _regions;
      case _Step.province:
        return _provinces;
      case _Step.city:
        return _cities;
      case _Step.barangay:
        return _barangays;
    }
  }

  String _labelOf(Object item) {
    if (item is PhRegion) return item.name;
    if (item is PhProvince) return item.name;
    if (item is PhCity) return item.name;
    if (item is PhBarangay) return item.name;
    return '';
  }

  Future<void> _selectRegion(PhRegion region) async {
    setState(() {
      _region = region;
      _province = null;
      _city = null;
      _provinces = const [];
      _cities = const [];
      _barangays = const [];
      _loading = true;
    });
    _searchController.clear();
    final provinces = await _datasource.getProvinces(region.code);
    if (!mounted) return;
    setState(() {
      _provinces = provinces;
      _step = _Step.province;
      _loading = false;
    });
  }

  Future<void> _selectProvince(PhProvince province) async {
    setState(() {
      _province = province;
      _city = null;
      _cities = const [];
      _barangays = const [];
      _loading = true;
    });
    _searchController.clear();
    final cities = await _datasource.getCities(province.code);
    if (!mounted) return;
    setState(() {
      _cities = cities;
      _step = _Step.city;
      _loading = false;
    });
  }

  Future<void> _selectCity(PhCity city) async {
    setState(() {
      _city = city;
      _barangays = const [];
      _loading = true;
    });
    _searchController.clear();
    final barangays = await _datasource.getBarangays(city.code);
    if (!mounted) return;
    setState(() {
      _barangays = barangays;
      _step = _Step.barangay;
      _loading = false;
    });
  }

  void _selectBarangay(PhBarangay barangay) {
    Navigator.pop(
      context,
      PhAddressSelection(
        region: _region!,
        province: _province!,
        city: _city!,
        barangay: barangay,
      ),
    );
  }

  void _selectItem(Object item) {
    if (item is PhRegion) {
      _selectRegion(item);
    } else if (item is PhProvince) {
      _selectProvince(item);
    } else if (item is PhCity) {
      _selectCity(item);
    } else if (item is PhBarangay) {
      _selectBarangay(item);
    }
  }

  void _goBack() {
    if (_loading) return;
    setState(() {
      _searchController.clear();
      switch (_step) {
        case _Step.region:
          break;
        case _Step.province:
          _step = _Step.region;
          break;
        case _Step.city:
          _step = _Step.province;
          break;
        case _Step.barangay:
          _step = _Step.city;
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final query = _searchController.text.trim().toLowerCase();
    final items = query.isEmpty
        ? _currentItems
        : _currentItems
            .where((item) => _labelOf(item).toLowerCase().contains(query))
            .toList();

    final breadcrumb = [_region?.name, _province?.name, _city?.name]
        .whereType<String>()
        .join(' \u203a ');

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(
              children: [
                SizedBox(
                  width: 40,
                  child: _step == _Step.region
                      ? null
                      : IconButton(
                          padding: EdgeInsets.zero,
                          onPressed: _goBack,
                          icon: const Icon(Icons.arrow_back_rounded),
                          tooltip: 'Back',
                        ),
                ),
                Expanded(
                  child: Text(
                    _stepTitle,
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 40),
              ],
            ),
          ),
          if (breadcrumb.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  breadcrumb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search ${_stepTitle.replaceFirst('Select ', '')}',
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
                filled: true,
                fillColor: colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : items.isEmpty
                    ? Center(
                        child: Text(
                          'No matches found.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: Text(_labelOf(item)),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _selectItem(item),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}