import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../../models/ph_address.dart';

/// Loads the bundled Philippine Standard Geographic Code (PSGC)
/// dataset — `assets/data/ph_regions.json`, `ph_provinces.json`,
/// `ph_cities.json`, `ph_barangays.json` — and serves the full
/// Region -> Province -> City/Municipality -> Barangay hierarchy used
/// by `AddressHierarchyPicker`.
///
/// This is a general, nationwide reference dataset — every region,
/// province, city/municipality and barangay in the Philippines, not
/// just Digos City. It intentionally replaces the old approach of
/// hardcoding a handful of Digos City barangays directly into a
/// widget; see the class doc on `LocationAreaModel`
/// (lib/models/location_area_model.dart) for the one list that *is*
/// still deliberately hand-maintained and Digos-specific — the shop's
/// own pickup service zones, a separate concern from a customer's
/// address.
///
/// Bundled as an asset (not fetched from a PSGC API at runtime) so
/// address entry keeps working with no network connection and never
/// depends on a third-party API's uptime. Parsed once per app run and
/// cached in memory — a few MB of JSON and ~42k barangay rows, which
/// is small enough to hold entirely in memory and much simpler than
/// paging a bounded, mostly-static reference dataset.
class PhAddressDatasource {
  PhAddressDatasource._();

  static final PhAddressDatasource instance = PhAddressDatasource._();

  List<PhRegion>? _regions;
  List<PhProvince>? _provinces;
  List<PhCity>? _cities;
  List<PhBarangay>? _barangays;

  Future<void>? _loading;

  /// Loads and parses all four JSON assets exactly once, no matter how
  /// many times/from how many places it's called concurrently.
  Future<void> _ensureLoaded() {
    if (_regions != null) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    final raw = await Future.wait([
      rootBundle.loadString('assets/data/ph_regions.json'),
      rootBundle.loadString('assets/data/ph_provinces.json'),
      rootBundle.loadString('assets/data/ph_cities.json'),
      rootBundle.loadString('assets/data/ph_barangays.json'),
    ]);

    final regions = (jsonDecode(raw[0]) as List)
        .map((e) => PhRegion.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final provinces = (jsonDecode(raw[1]) as List)
        .map((e) => PhProvince.fromJson(e as Map<String, dynamic>))
        .toList();
    final cities = (jsonDecode(raw[2]) as List)
        .map((e) => PhCity.fromJson(e as Map<String, dynamic>))
        .toList();
    final barangays = (jsonDecode(raw[3]) as List)
        .map((e) => PhBarangay.fromJson(e as Map<String, dynamic>))
        .toList();

    _regions = regions;
    _provinces = provinces;
    _cities = cities;
    _barangays = barangays;
  }

  /// Every region in the Philippines, alphabetically.
  Future<List<PhRegion>> getRegions() async {
    await _ensureLoaded();
    return _regions!;
  }

  /// Provinces belonging to [regionCode], alphabetically. Some
  /// regions (NCR, and a few chartered-city-only cases) have no
  /// provinces — callers should be ready for an empty list and treat
  /// the region's cities as directly selectable, if this dataset ever
  /// needs to support that; the current PSGC snapshot bundled here
  /// gives every region at least one province.
  Future<List<PhProvince>> getProvinces(String regionCode) async {
    await _ensureLoaded();
    final list = _provinces!.where((p) => p.regionCode == regionCode).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Cities/municipalities belonging to [provinceCode], alphabetically.
  Future<List<PhCity>> getCities(String provinceCode) async {
    await _ensureLoaded();
    final list = _cities!.where((c) => c.provinceCode == provinceCode).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Barangays belonging to [cityCode], alphabetically.
  Future<List<PhBarangay>> getBarangays(String cityCode) async {
    await _ensureLoaded();
    final list = _barangays!.where((b) => b.cityCode == cityCode).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // -------------------------------------------------------------------
  // Lookups by code — resolve a previously-saved selection (e.g. from
  // Firestore) back into display objects without re-running the whole
  // cascading pick flow. UserModel stores both the code and the name
  // for each level, so in practice these aren't needed just to *show*
  // a saved address, only for flows that only have a code on hand.
  // -------------------------------------------------------------------

  Future<PhRegion?> findRegionByCode(String code) async {
    await _ensureLoaded();
    for (final r in _regions!) {
      if (r.code == code) return r;
    }
    return null;
  }

  Future<PhProvince?> findProvinceByCode(String code) async {
    await _ensureLoaded();
    for (final p in _provinces!) {
      if (p.code == code) return p;
    }
    return null;
  }

  Future<PhCity?> findCityByCode(String code) async {
    await _ensureLoaded();
    for (final c in _cities!) {
      if (c.code == code) return c;
    }
    return null;
  }

  Future<PhBarangay?> findBarangayByCode(String code) async {
    await _ensureLoaded();
    for (final b in _barangays!) {
      if (b.code == code) return b;
    }
    return null;
  }
}