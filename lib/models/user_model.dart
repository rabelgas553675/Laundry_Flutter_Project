import 'package:cloud_firestore/cloud_firestore.dart';

import 'ph_address.dart';

/// The two roles supported by the app.
enum UserRole { admin, user }

extension UserRoleX on UserRole {
  String get value => name; // 'admin' or 'user'

  static UserRole fromValue(String? value) {
    switch (value) {
      case 'admin':
        return UserRole.admin;
      case 'user':
      default:
        return UserRole.user;
    }
  }
}

/// One entry in a user's saved address book (Profile → Address
/// Selection). Introduced alongside [AddressSelectionScreen] so a
/// customer can keep more than one delivery address (e.g. Home,
/// Office) instead of the single free-text/structured address the
/// app used to store directly on [UserModel].
///
/// This deliberately lives inside `user_model.dart` and is persisted
/// as a plain array field (`savedAddresses`) on the *same*
/// `users/{uid}` document — there is no second Firestore collection,
/// no second repository, and no second datasource. It is read and
/// written entirely through [UserModel]/[UserRepository], the same
/// classes the rest of the app already uses for the user's profile.
///
/// [id] is a client-generated identifier (see
/// `EditAddressScreen._generateId`) used only to find/replace/delete
/// one entry inside the list — it is never a separate document id.
class SavedAddress {
  final String id;
  final String fullName;
  final String phone;
  final String streetAddress;
  final String regionCode;
  final String regionName;
  final String provinceCode;
  final String provinceName;
  final String cityCode;
  final String cityName;
  final String barangayCode;
  final String barangayName;
  final String postalCode;

  /// Whether this is the customer's default address. Exactly one
  /// entry in a given [UserModel.savedAddresses] list should have
  /// this set to `true` — enforced when the list is saved (see
  /// `EditAddressScreen._submit`), not by this class itself.
  final bool isDefault;

  const SavedAddress({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.streetAddress,
    required this.regionCode,
    required this.regionName,
    required this.provinceCode,
    required this.provinceName,
    required this.cityCode,
    required this.cityName,
    required this.barangayCode,
    required this.barangayName,
    required this.postalCode,
    this.isDefault = false,
  });

  /// Reconstructs the [PhAddressSelection] for this address, or
  /// `null` if it somehow has no region/province/city/barangay yet
  /// (shouldn't happen for anything saved through
  /// [EditAddressScreen], which requires the full hierarchy).
  PhAddressSelection? get phAddress {
    if (regionCode.isEmpty ||
        provinceCode.isEmpty ||
        cityCode.isEmpty ||
        barangayCode.isEmpty) {
      return null;
    }
    return PhAddressSelection(
      region: PhRegion(code: regionCode, name: regionName),
      province: PhProvince(
        code: provinceCode,
        name: provinceName,
        regionCode: regionCode,
      ),
      city: PhCity(code: cityCode, name: cityName, provinceCode: provinceCode),
      barangay: PhBarangay(
        code: barangayCode,
        name: barangayName,
        cityCode: cityCode,
      ),
    );
  }

  /// "Street / Building / House No." line — the reference design's
  /// first address line.
  String get streetLine => streetAddress;

  /// "Barangay, City/Municipality, Province, Region, Postal Code"
  /// line — the reference design's second address line.
  String get localityLine {
    final parts = <String>[
      if (barangayName.isNotEmpty) barangayName,
      if (cityName.isNotEmpty) cityName,
      if (provinceName.isNotEmpty) provinceName,
      if (regionName.isNotEmpty) regionName,
      if (postalCode.isNotEmpty) postalCode,
    ];
    return parts.where((p) => p.trim().isNotEmpty).join(', ');
  }

  /// Single composed line — what [UserModel.address] (the legacy
  /// free-text field every other screen already reads: profile
  /// header, admin views, order summaries) is kept in sync with.
  String get composedLine {
    final parts = <String>[streetLine, localityLine];
    return parts.where((p) => p.trim().isNotEmpty).join(', ');
  }

  /// Part 2A — the label used when this address is handed to an order
  /// (e.g. `OrderDraft.pickupAddress` / `OrderModel.address` on the
  /// Pickup Checkout flow): the recipient's name on its own line,
  /// followed by [composedLine]. This is deliberately just a
  /// formatted getter on the existing model, not a new
  /// `OrderModel`/`OrderDraft` field — `order.address` already exists
  /// and is a single free-text string, so folding the name in here is
  /// how the address's [fullName] reaches the order without adding a
  /// duplicate "recipient name" field elsewhere.
  String get orderAddressLine {
    final parts = <String>[fullName, composedLine];
    return parts.where((p) => p.trim().isNotEmpty).join('\n');
  }

  SavedAddress copyWith({
    String? fullName,
    String? phone,
    String? streetAddress,
    String? regionCode,
    String? regionName,
    String? provinceCode,
    String? provinceName,
    String? cityCode,
    String? cityName,
    String? barangayCode,
    String? barangayName,
    String? postalCode,
    bool? isDefault,
  }) {
    return SavedAddress(
      id: id,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      streetAddress: streetAddress ?? this.streetAddress,
      regionCode: regionCode ?? this.regionCode,
      regionName: regionName ?? this.regionName,
      provinceCode: provinceCode ?? this.provinceCode,
      provinceName: provinceName ?? this.provinceName,
      cityCode: cityCode ?? this.cityCode,
      cityName: cityName ?? this.cityName,
      barangayCode: barangayCode ?? this.barangayCode,
      barangayName: barangayName ?? this.barangayName,
      postalCode: postalCode ?? this.postalCode,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fullName': fullName,
      'phone': phone,
      'streetAddress': streetAddress,
      'regionCode': regionCode,
      'regionName': regionName,
      'provinceCode': provinceCode,
      'provinceName': provinceName,
      'cityCode': cityCode,
      'cityName': cityName,
      'barangayCode': barangayCode,
      'barangayName': barangayName,
      'postalCode': postalCode,
      'isDefault': isDefault,
    };
  }

  factory SavedAddress.fromMap(Map<dynamic, dynamic> map) {
    return SavedAddress(
      id: map['id'] as String? ?? '',
      fullName: map['fullName'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      streetAddress: map['streetAddress'] as String? ?? '',
      regionCode: map['regionCode'] as String? ?? '',
      regionName: map['regionName'] as String? ?? '',
      provinceCode: map['provinceCode'] as String? ?? '',
      provinceName: map['provinceName'] as String? ?? '',
      cityCode: map['cityCode'] as String? ?? '',
      cityName: map['cityName'] as String? ?? '',
      barangayCode: map['barangayCode'] as String? ?? '',
      barangayName: map['barangayName'] as String? ?? '',
      postalCode: map['postalCode'] as String? ?? '',
      isDefault: map['isDefault'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SavedAddress && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

/// Mirrors the Firestore document at `users/{userId}`.
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String address;
  final UserRole role;
  final DateTime? createdAt;

  /// Added in Part 07. Never contains raw bytes — only the Firebase
  /// Storage download URL for `users/{uid}/profile/profile.jpg`.
  final String? profileImageUrl;

  /// Added in Part 17. Whether this account may sign in / place
  /// orders — an Admin toggles this via "Activate/deactivate
  /// accounts" instead of deleting the user document, so their order
  /// history stays intact and their `userId` still resolves on any
  /// past order. Defaults to `true`: every account created through
  /// PART 04/05 registration is active from the moment it exists.
  final bool isActive;

  /// Structured address fields backing the full-page "Edit Address"
  /// screen (Profile → Address). These are additive/optional — every
  /// pre-existing document keeps working with just [address] (a
  /// single free-text line) and simply reads these back as ''.
  ///
  /// Region/Province/City/Barangay are a real, general Philippine
  /// address hierarchy (PSGC — see lib/models/ph_address.dart), not a
  /// list hand-restricted to Digos City: a customer can live anywhere
  /// in the Philippines. Both the PSGC code *and* the display name are
  /// stored for each level so the saved address can be shown
  /// immediately (in the profile header, admin views, order
  /// summaries — anywhere that just reads [address]) without an extra
  /// lookup against the address dataset, while the codes remain
  /// available for anything that needs to resolve the hierarchy again
  /// (e.g. reopening the picker already scoped to the right
  /// region/province/city). See [phAddress].
  ///
  /// [address] itself remains the single composed line every other
  /// screen already reads — EditAddressScreen keeps it in sync
  /// whenever these structured fields are saved, so nothing else in
  /// the app needs to change.
  final String regionCode;
  final String regionName;
  final String provinceCode;
  final String provinceName;
  final String cityCode;
  final String cityName;
  final String barangayCode;
  final String barangayName;
  final String postalCode;
  final String streetAddress;

  /// The customer's saved address book (Profile → Address Selection).
  /// Additive, same as the structured fields above — any document
  /// written before this existed simply has an empty list here, and
  /// [effectiveAddresses] falls back to synthesizing a single entry
  /// out of the legacy fields above so nothing already saved is ever
  /// lost. Persisted on this same `users/{uid}` document (no second
  /// collection/repository) via [toEditableMap] / [fromFirestore].
  final List<SavedAddress> savedAddresses;

  /// Which address in [effectiveAddresses] the customer last picked
  /// on the Address Selection screen. Empty means "no explicit pick
  /// yet" — [selectedAddress] then falls back to the default address.
  /// Picking a non-default address here never changes which address
  /// is flagged `isDefault`.
  final String selectedAddressId;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.role,
    this.createdAt,
    this.profileImageUrl,
    this.isActive = true,
    this.regionCode = '',
    this.regionName = '',
    this.provinceCode = '',
    this.provinceName = '',
    this.cityCode = '',
    this.cityName = '',
    this.barangayCode = '',
    this.barangayName = '',
    this.postalCode = '',
    this.streetAddress = '',
    this.savedAddresses = const [],
    this.selectedAddressId = '',
  });

  /// Reconstructs the full [PhAddressSelection] from the stored
  /// codes/names, or `null` if no structured address has been saved
  /// yet (e.g. a pre-existing account that only ever had the free-text
  /// [address] line, or one whose address was cleared). Doesn't need
  /// [PhAddressDatasource] — every level's name is already stored
  /// alongside its code.
  PhAddressSelection? get phAddress {
    if (regionCode.isEmpty ||
        provinceCode.isEmpty ||
        cityCode.isEmpty ||
        barangayCode.isEmpty) {
      return null;
    }
    return PhAddressSelection(
      region: PhRegion(code: regionCode, name: regionName),
      province: PhProvince(
        code: provinceCode,
        name: provinceName,
        regionCode: regionCode,
      ),
      city: PhCity(code: cityCode, name: cityName, provinceCode: provinceCode),
      barangay: PhBarangay(
        code: barangayCode,
        name: barangayName,
        cityCode: cityCode,
      ),
    );
  }

  /// [savedAddresses] if the customer has ever saved through the new
  /// Address Selection / Edit Address flow, otherwise a single
  /// synthesized entry built from the legacy flat fields above (for
  /// an account that only ever had the old one-address form) — or an
  /// empty list if neither exists. Every screen that lists, selects,
  /// or edits addresses reads *this*, never [savedAddresses] or the
  /// legacy fields directly, so both generations of data display the
  /// same way.
  List<SavedAddress> get effectiveAddresses {
    if (savedAddresses.isNotEmpty) return savedAddresses;
    final legacy = phAddress;
    if (legacy == null && address.trim().isEmpty) return const [];
    return [
      SavedAddress(
        id: 'legacy',
        fullName: name,
        phone: phone,
        streetAddress: streetAddress,
        regionCode: regionCode,
        regionName: regionName,
        provinceCode: provinceCode,
        provinceName: provinceName,
        cityCode: cityCode,
        cityName: cityName,
        barangayCode: barangayCode,
        barangayName: barangayName,
        postalCode: postalCode,
        isDefault: true,
      ),
    ];
  }

  /// The address flagged as default, or the first saved address if
  /// (unexpectedly) none is flagged, or `null` if there are none yet.
  SavedAddress? get defaultAddress {
    final all = effectiveAddresses;
    if (all.isEmpty) return null;
    for (final a in all) {
      if (a.isDefault) return a;
    }
    return all.first;
  }

  /// The address that should be pre-selected on the Address Selection
  /// screen: whichever the customer last explicitly picked
  /// ([selectedAddressId]), falling back to the default address.
  SavedAddress? get selectedAddress {
    if (selectedAddressId.isNotEmpty) {
      for (final a in effectiveAddresses) {
        if (a.id == selectedAddressId) return a;
      }
    }
    return defaultAddress;
  }

  /// Inserts [address] (brand-new — [address.id] not yet present in
  /// [effectiveAddresses]) or replaces the existing entry with the
  /// same id (editing), used by [EditAddressScreen._submit] for both
  /// **Add Address** and **Edit Address**. There is no second address
  /// store: this only ever rewrites the `savedAddresses` array on
  /// this same [UserModel].
  ///
  /// Starts from [effectiveAddresses] rather than [savedAddresses] so
  /// an account that still only has the legacy single-address fields
  /// (no `savedAddresses` entries yet) gets folded into the array on
  /// its very first Add/Edit instead of that legacy address silently
  /// disappearing.
  ///
  /// Exactly one entry ends up `isDefault: true` afterwards:
  /// - The very first address a customer ever saves is always the
  ///   default (there is nothing else for it to be).
  /// - Otherwise [address.isDefault] is honored as the customer set it
  ///   on the form — including leaving it unchanged from whatever the
  ///   screen preloaded, per the "preserve unless intentionally
  ///   changed" rule — and every other entry is demoted so only one
  ///   default ever exists.
  ///
  /// Also keeps the legacy top-level address fields ([address] itself,
  /// [regionCode]..[streetAddress]) mirroring whichever address ends
  /// up default, so every other screen that still reads those directly
  /// (profile header, admin views, order summaries) keeps working
  /// unchanged. [selectedAddressId] is set to the saved address's id,
  /// since saving/editing an address is itself an implicit pick of it.
  UserModel withSavedAddressUpserted(SavedAddress address) {
    final current = List<SavedAddress>.from(effectiveAddresses);
    final existingIndex = current.indexWhere((a) => a.id == address.id);

    final isFirstEverAddress = current.isEmpty;
    final toSave = isFirstEverAddress
        ? address.copyWith(isDefault: true)
        : address;

    if (existingIndex == -1) {
      current.add(toSave);
    } else {
      current[existingIndex] = toSave;
    }

    final normalized = _withSingleDefault(
      current,
      preferId: toSave.isDefault ? toSave.id : null,
    );
    final defaultAddress = normalized.firstWhere(
      (a) => a.isDefault,
      orElse: () => normalized.first,
    );

    return copyWith(
      savedAddresses: normalized,
      selectedAddressId: toSave.id,
      address: defaultAddress.composedLine,
      regionCode: defaultAddress.regionCode,
      regionName: defaultAddress.regionName,
      provinceCode: defaultAddress.provinceCode,
      provinceName: defaultAddress.provinceName,
      cityCode: defaultAddress.cityCode,
      cityName: defaultAddress.cityName,
      barangayCode: defaultAddress.barangayCode,
      barangayName: defaultAddress.barangayName,
      postalCode: defaultAddress.postalCode,
      streetAddress: defaultAddress.streetAddress,
    );
  }

  /// Removes the entry with [addressId] from [effectiveAddresses],
  /// used by [EditAddressScreen._confirmDelete]. Only ever touches
  /// this [UserModel]'s own `savedAddresses` array — the caller is
  /// always the signed-in customer's own document (see [AuthState]),
  /// so this can never reach another user's addresses.
  ///
  /// If the removed address was the default, the first remaining
  /// address is promoted to default automatically — never leaving the
  /// list with zero (or more than one) default. If the removed address
  /// was also [selectedAddressId], the selection moves to the new
  /// default so [selectedAddress] never points at a deleted entry.
  /// Removing the last remaining address clears the legacy fields back
  /// to empty, matching a customer with no saved address at all.
  UserModel withSavedAddressRemoved(String addressId) {
    final current = List<SavedAddress>.from(effectiveAddresses)
      ..removeWhere((a) => a.id == addressId);

    final newSelectedId =
        selectedAddressId == addressId ? '' : selectedAddressId;

    if (current.isEmpty) {
      return copyWith(
        savedAddresses: const [],
        selectedAddressId: '',
        address: '',
        regionCode: '',
        regionName: '',
        provinceCode: '',
        provinceName: '',
        cityCode: '',
        cityName: '',
        barangayCode: '',
        barangayName: '',
        postalCode: '',
        streetAddress: '',
      );
    }

    final normalized = _withSingleDefault(current);
    final defaultAddress = normalized.firstWhere(
      (a) => a.isDefault,
      orElse: () => normalized.first,
    );

    return copyWith(
      savedAddresses: normalized,
      selectedAddressId: newSelectedId.isEmpty ? defaultAddress.id : newSelectedId,
      address: defaultAddress.composedLine,
      regionCode: defaultAddress.regionCode,
      regionName: defaultAddress.regionName,
      provinceCode: defaultAddress.provinceCode,
      provinceName: defaultAddress.provinceName,
      cityCode: defaultAddress.cityCode,
      cityName: defaultAddress.cityName,
      barangayCode: defaultAddress.barangayCode,
      barangayName: defaultAddress.barangayName,
      postalCode: defaultAddress.postalCode,
      streetAddress: defaultAddress.streetAddress,
    );
  }

  /// Returns a copy of [addresses] where exactly one entry has
  /// `isDefault: true`. Prefers [preferId] (the entry the customer
  /// just explicitly flagged default); otherwise keeps whichever entry
  /// was already default; otherwise falls back to the first entry.
  /// Shared by [withSavedAddressUpserted] and
  /// [withSavedAddressRemoved] so "exactly one default, never zero,
  /// never duplicated" is enforced in exactly one place.
  static List<SavedAddress> _withSingleDefault(
    List<SavedAddress> addresses, {
    String? preferId,
  }) {
    if (addresses.isEmpty) return addresses;

    final String winnerId;
    if (preferId != null && addresses.any((a) => a.id == preferId)) {
      winnerId = preferId;
    } else {
      final alreadyDefault = addresses.where((a) => a.isDefault);
      winnerId =
          alreadyDefault.isNotEmpty ? alreadyDefault.first.id : addresses.first.id;
    }

    return addresses
        .map((a) => a.copyWith(isDefault: a.id == winnerId))
        .toList();
  }

  /// Used only when writing a brand-new user document.
  /// createdAt is left to Firestore's server timestamp so client
  /// clock skew can never affect it.
  Map<String, dynamic> toMapForCreate() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'address': address,
      'regionCode': regionCode,
      'regionName': regionName,
      'provinceCode': provinceCode,
      'provinceName': provinceName,
      'cityCode': cityCode,
      'cityName': cityName,
      'barangayCode': barangayCode,
      'barangayName': barangayName,
      'postalCode': postalCode,
      'streetAddress': streetAddress,
      'savedAddresses': const [],
      'selectedAddressId': '',
      'role': role.value,
      'profileImageUrl': null,
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Used by ProfileScreen (Part 07) to persist edits. Deliberately
  /// excludes role/email/createdAt — those aren't editable from the
  /// profile screen (role changes go through Admin in Part 17; email
  /// changes require Firebase Auth re-verification, out of scope here).
  Map<String, dynamic> toEditableMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'regionCode': regionCode,
      'regionName': regionName,
      'provinceCode': provinceCode,
      'provinceName': provinceName,
      'cityCode': cityCode,
      'cityName': cityName,
      'barangayCode': barangayCode,
      'barangayName': barangayName,
      'postalCode': postalCode,
      'streetAddress': streetAddress,
      'savedAddresses': savedAddresses.map((a) => a.toMap()).toList(),
      'selectedAddressId': selectedAddressId,
      'profileImageUrl': profileImageUrl,
    };
  }

  /// Part 17 — persists an Admin's edit from Manage Users (name,
  /// phone, address, role, active/inactive). Deliberately excludes
  /// [email] and [createdAt], for the same reasons [toEditableMap]
  /// already excludes them from a self-service profile edit: email
  /// changes require Firebase Auth re-verification (out of scope
  /// here), and [createdAt] never changes once set. Unlike
  /// [toEditableMap], this one *does* include [role] and [isActive] —
  /// those two fields are Admin-only levers, never exposed on the
  /// customer-facing Profile screen.
  Map<String, dynamic> toAdminEditableMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'role': role.value,
      'isActive': isActive,
    };
  }

  /// [clearProfileImage] exists because `profileImageUrl: null` as an
  /// argument is indistinguishable from "not provided" in a normal
  /// copyWith — this makes "remove the photo" an explicit, unambiguous
  /// call site (see ProfileScreen._removePhoto).
  UserModel copyWith({
    String? name,
    String? phone,
    String? address,
    String? profileImageUrl,
    bool clearProfileImage = false,
    UserRole? role,
    bool? isActive,
    String? regionCode,
    String? regionName,
    String? provinceCode,
    String? provinceName,
    String? cityCode,
    String? cityName,
    String? barangayCode,
    String? barangayName,
    String? postalCode,
    String? streetAddress,
    List<SavedAddress>? savedAddresses,
    String? selectedAddressId,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      role: role ?? this.role,
      createdAt: createdAt,
      profileImageUrl:
          clearProfileImage ? null : (profileImageUrl ?? this.profileImageUrl),
      isActive: isActive ?? this.isActive,
      regionCode: regionCode ?? this.regionCode,
      regionName: regionName ?? this.regionName,
      provinceCode: provinceCode ?? this.provinceCode,
      provinceName: provinceName ?? this.provinceName,
      cityCode: cityCode ?? this.cityCode,
      cityName: cityName ?? this.cityName,
      barangayCode: barangayCode ?? this.barangayCode,
      barangayName: barangayName ?? this.barangayName,
      postalCode: postalCode ?? this.postalCode,
      streetAddress: streetAddress ?? this.streetAddress,
      savedAddresses: savedAddresses ?? this.savedAddresses,
      selectedAddressId: selectedAddressId ?? this.selectedAddressId,
    );
  }

  factory UserModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['createdAt'];
    return UserModel(
      uid: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      address: data['address'] ?? '',
      role: UserRoleX.fromValue(data['role']),
      createdAt: ts is Timestamp ? ts.toDate() : null,
      profileImageUrl: data['profileImageUrl'] as String?,
      // Defaults to true for any document written before PART 17
      // introduced this field, so a pre-existing account is never
      // silently treated as deactivated just because the field is
      // missing.
      isActive: data['isActive'] as bool? ?? true,
      // Structured address fields are additive — any document written
      // before the full-page Edit Address screen existed (or before
      // it moved to the general Region/Province/City/Barangay
      // hierarchy) simply has none of these keys, so they default to
      // ''. [address] itself is unaffected either way, so a
      // pre-existing account's saved address still displays correctly
      // everywhere it's read — only the structured hierarchy needs to
      // be re-picked once, next time the customer opens Edit Address.
      regionCode: data['regionCode'] as String? ?? '',
      regionName: data['regionName'] as String? ?? '',
      provinceCode: data['provinceCode'] as String? ?? '',
      provinceName: data['provinceName'] as String? ?? '',
      cityCode: data['cityCode'] as String? ?? '',
      cityName: data['cityName'] as String? ?? '',
      barangayCode: data['barangayCode'] as String? ?? '',
      barangayName: data['barangayName'] as String? ?? '',
      postalCode: data['postalCode'] as String? ?? '',
      streetAddress: data['streetAddress'] as String? ?? '',
      // Additive, same reasoning as the structured fields above: a
      // document written before the address book existed simply has
      // no 'savedAddresses' key, so this defaults to an empty list
      // and [effectiveAddresses] synthesizes one entry from the
      // legacy fields instead.
      savedAddresses: (data['savedAddresses'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(SavedAddress.fromMap)
          .toList(),
      selectedAddressId: data['selectedAddressId'] as String? ?? '',
    );
  }
}