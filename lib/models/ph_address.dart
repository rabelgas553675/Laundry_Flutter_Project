/// Philippine Standard Geographic Code (PSGC) address hierarchy —
/// Region -> Province -> City/Municipality -> Barangay.
///
/// These four classes are pure data: a code (the PSGC identifier used
/// to look up children/parents) and a display name. They're loaded
/// from the bundled nationwide dataset in `assets/data/ph_*.json` by
/// [PhAddressDatasource] and rendered by `AddressHierarchyPicker`
/// (see lib/core/widgets/address_hierarchy_picker.dart).
///
/// This is a **general, nationwide** hierarchy — it is not scoped to
/// Digos City, Davao del Sur, or any other single place. It exists to
/// represent *the customer's own address*, wherever in the
/// Philippines that is.
///
/// This is deliberately separate from `LocationAreaModel`
/// (lib/models/location_area_model.dart), which is a short,
/// hand-maintained list of the *shop's own pickup service zones*
/// used by the order flow (`LocationSelection` /
/// `laundry_order_screen.dart`). Whether a given address falls inside
/// the shop's supported pickup area is a separate question from what
/// the customer's address actually is — see the class doc on
/// `LocationAreaModel` for why that stays a small, separate list
/// rather than being derived from this dataset.
library;

class PhRegion {
  final String code;
  final String name;

  const PhRegion({required this.code, required this.name});

  factory PhRegion.fromJson(Map<String, dynamic> json) => PhRegion(
        code: json['code'] as String,
        name: json['name'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PhRegion && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

class PhProvince {
  final String code;
  final String name;
  final String regionCode;

  const PhProvince({
    required this.code,
    required this.name,
    required this.regionCode,
  });

  factory PhProvince.fromJson(Map<String, dynamic> json) => PhProvince(
        code: json['code'] as String,
        name: json['name'] as String,
        regionCode: json['region_code'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PhProvince && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

/// Covers both cities and municipalities — PSGC (and the dataset this
/// app bundles) treats them as one level between Province and
/// Barangay, distinguished only by [name] (e.g. "City Of Digos
/// (Capital)" vs "Adams"). Not renamed to something narrower like
/// `PhCity` alone so it's clear at every call site that municipalities
/// are included too, not just chartered cities.
class PhCity {
  final String code;
  final String name;
  final String provinceCode;

  const PhCity({
    required this.code,
    required this.name,
    required this.provinceCode,
  });

  factory PhCity.fromJson(Map<String, dynamic> json) => PhCity(
        code: json['code'] as String,
        name: json['name'] as String,
        provinceCode: json['province_code'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PhCity && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

class PhBarangay {
  final String code;
  final String name;
  final String cityCode;

  const PhBarangay({
    required this.code,
    required this.name,
    required this.cityCode,
  });

  factory PhBarangay.fromJson(Map<String, dynamic> json) => PhBarangay(
        code: json['code'] as String,
        name: json['name'] as String,
        cityCode: json['city_code'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PhBarangay && other.code == code);

  @override
  int get hashCode => code.hashCode;
}

/// One fully-resolved Region -> Province -> City -> Barangay pick,
/// bundled together so callers (EditAddressScreen, UserModel) don't
/// have to juggle four separate nullable objects and can never end up
/// with e.g. a barangay saved without its parent city.
class PhAddressSelection {
  final PhRegion region;
  final PhProvince province;
  final PhCity city;
  final PhBarangay barangay;

  const PhAddressSelection({
    required this.region,
    required this.province,
    required this.city,
    required this.barangay,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhAddressSelection &&
          other.region == region &&
          other.province == province &&
          other.city == city &&
          other.barangay == barangay);

  @override
  int get hashCode => Object.hash(region, province, city, barangay);
}