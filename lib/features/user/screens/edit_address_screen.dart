import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/auth_state.dart';
import '../../../core/widgets/address_hierarchy_picker.dart';
import '../../../core/widgets/app_button.dart';
import '../../../models/ph_address.dart';
import '../../../models/user_model.dart';

/// Full-page "Add Address" / "Edit Address" screen — reached either as
/// **Add Address** (pushed from [AddressSelectionScreen]'s
/// "+ Add a new address" button, [existingAddress] left `null`) or as
/// **Edit** on one specific card on that screen ([existingAddress]
/// passed in). The app bar title switches between the two automatically.
///
/// Visual design now matches [ProfileScreen] and [AddressSelectionScreen]:
/// the same soft steel-blue → white diagonal gradient backdrop fills
/// the whole screen, with the "Paste and Quick-Fill" card, the
/// "Address" form card, and the pinned bottom action bar all drawn as
/// frosted glass panels blurring that backdrop instead of flat, opaque
/// white surfaces.
///
/// Data model note: this reuses [UserModel]/[UserRepository]/
/// [AuthState] exactly as before — there is no separate address
/// model, table, or repository. One saved address is a
/// [SavedAddress]; the full list lives in [UserModel.savedAddresses]
/// on the same `users/{uid}` document. Saving here goes through
/// [UserModel.withSavedAddressUpserted] and deleting through
/// [UserModel.withSavedAddressRemoved] — both of those keep exactly
/// one address flagged default and keep the legacy top-level address
/// fields ([UserModel.address] etc., which every other screen still
/// reads directly — profile header, admin views, order summaries) in
/// sync with whichever address ends up default. This screen never
/// writes to those legacy fields itself.
///
/// "Full Name" / "Phone Number" here are per-address (a delivery
/// contact can differ address to address), separate from the
/// account-level name/phone edited from the "Profile Setting" sheet.
///
/// "Region, Province, City, Barangay" is a real, general Philippine
/// address hierarchy (PSGC — see lib/models/ph_address.dart and
/// [AddressHierarchyPicker]), not fixed to the shop's own city: the
/// customer's address can be anywhere in the Philippines and is never
/// rewritten to match [AppConstants.shopAddress]. Whether that address
/// happens to fall inside the shop's supported pickup area is a
/// separate question handled entirely by [LocationAreaModel] /
/// [LocationSelection] in the order flow — this screen doesn't touch
/// that logic at all.
///
/// No map: this project has no maps package/API key wired up (no
/// `google_maps_flutter` in pubspec.yaml), and the reference design's
/// map preview has been removed entirely per spec — this screen ends
/// at the address form.
class EditAddressScreen extends StatefulWidget {
  const EditAddressScreen({super.key, required this.user, this.existingAddress});

  final UserModel user;

  /// The address being edited, or `null` when this screen was opened
  /// via "+ Add a new address" to create a brand-new entry.
  final SavedAddress? existingAddress;

  @override
  State<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends State<EditAddressScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _quickFillController;
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _postalController;
  late final TextEditingController _streetController;

  /// The customer's actual Region/Province/City/Barangay selection —
  /// anywhere in the Philippines, never hardcoded to the shop's own
  /// city. Null until the customer has picked one (a brand-new
  /// address, or a pre-existing account saved before this hierarchy
  /// existed — see [UserModel.phAddress]).
  PhAddressSelection? _addressSelection;

  /// Whether this address should be flagged default when saved. Starts
  /// from the existing entry's flag when editing, or `false` for a
  /// brand-new address — unless it will be the customer's *only*
  /// address, in which case it is forced on (see [_forceDefault]):
  /// [UserModel.withSavedAddressUpserted] makes the very first saved
  /// address default no matter what this is set to, so the toggle is
  /// locked to reflect that truthfully instead of offering a choice
  /// that has no effect.
  late bool _setAsDefault;

  bool _isSaving = false;
  bool _isDeleting = false;

  bool get _isEditing => widget.existingAddress != null;

  /// True when saving this address will leave the customer with
  /// exactly one address on file — i.e. there are no *other* saved
  /// addresses besides the one being edited (or none at all, when
  /// adding). That one address is always the default, so the toggle
  /// is shown locked on rather than interactive.
  bool get _forceDefault {
    final others = widget.user.effectiveAddresses.where(
      (a) => a.id != widget.existingAddress?.id,
    );
    return others.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existingAddress;
    _quickFillController = TextEditingController();
    _nameController = TextEditingController(text: existing?.fullName ?? widget.user.name);
    _phoneController = TextEditingController(text: existing?.phone ?? widget.user.phone);
    _postalController = TextEditingController(text: existing?.postalCode ?? '');
    _streetController = TextEditingController(text: existing?.streetAddress ?? '');
    _addressSelection = existing?.phAddress;
    _setAsDefault = existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    _quickFillController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _postalController.dispose();
    _streetController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? colorScheme.error
              : colorScheme.inverseSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: isError
                    ? colorScheme.onError
                    : colorScheme.onInverseSurface,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: isError
                        ? colorScheme.onError
                        : colorScheme.onInverseSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  // ---------------------------------------------------------------------
  // Paste and Quick-Fill
  // ---------------------------------------------------------------------

  /// Heuristically splits a pasted block of text (name / phone / street,
  /// one per line or separated by commas — the way a customer would
  /// paste an address someone sent them in chat) into the form fields.
  void _applyQuickFill() {
    final raw = _quickFillController.text.trim();
    if (raw.isEmpty) {
      _showMessage(
        'Paste your name, phone number, and address first.',
        isError: true,
      );
      return;
    }

    final phoneExp = RegExp(r'(\+?\d[\d\s\-()]{6,}\d)');
    final postalExp = RegExp(r'^\d{4,6}$');

    final chunks = raw
        .split(RegExp(r'[\n,]'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList();

    String? name;
    String? phone;
    String? postal;
    final streetParts = <String>[];

    for (final chunk in chunks) {
      final phoneMatch = phoneExp.firstMatch(chunk);
      if (phone == null && phoneMatch != null && phoneMatch.group(0) == chunk) {
        phone = chunk;
        continue;
      }
      if (postal == null && postalExp.hasMatch(chunk)) {
        postal = chunk;
        continue;
      }
      if (name == null && !RegExp(r'\d').hasMatch(chunk)) {
        name = chunk;
        continue;
      }
      streetParts.add(chunk);
    }

    setState(() {
      if (name != null) _nameController.text = name;
      if (phone != null) _phoneController.text = phone;
      if (postal != null) _postalController.text = postal;
      if (streetParts.isNotEmpty) {
        _streetController.text = streetParts.join(', ');
      }
      // Region/Province/City/Barangay is deliberately not guessed from
      // pasted text — with ~42k barangays nationwide a substring match
      // would be unreliable and could silently pick the wrong one.
      // The customer still picks it explicitly via the hierarchy field
      // below.
    });

    _showMessage('Filled in from your pasted text — please double-check it.');
  }

  // ---------------------------------------------------------------------
  // Region / Province / City / Barangay picker — general nationwide
  // Philippine address hierarchy, not restricted to any one city.
  // ---------------------------------------------------------------------

  Future<void> _pickAddressHierarchy() async {
    final selection = await AddressHierarchyPicker.show(
      context,
      initial: _addressSelection,
    );
    if (selection != null) {
      setState(() => _addressSelection = selection);
    }
  }

  // ---------------------------------------------------------------------
  // Save / delete
  // ---------------------------------------------------------------------

  String? _requiredField(String? value, String label) {
    if ((value ?? '').trim().isEmpty) return '$label is required.';
    return null;
  }

  String? _validatePhone(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Phone number is required.';
    final digitsOnly = trimmed.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 7) return 'Enter a valid phone number.';
    return null;
  }

  String? _validatePostal(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return 'Postal code is required.';
    if (!RegExp(r'^\d{4,6}$').hasMatch(trimmed)) {
      return 'Enter a valid postal code.';
    }
    return null;
  }

  /// Client-generated id for a brand-new [SavedAddress] entry — never a
  /// Firestore document id, only used to find/replace/delete this one
  /// entry inside [UserModel.savedAddresses] (see the class doc on
  /// [SavedAddress]). Timestamp-based is enough here: entries are only
  /// ever created by the single signed-in customer editing their own
  /// address book, one at a time.
  String _generateId() =>
      'addr_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final selection = _addressSelection;
    if (selection == null) {
      _showMessage(
        'Please select your Region, Province, City, and Barangay.',
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final existing = widget.existingAddress;
      final toSave = SavedAddress(
        id: existing?.id ?? _generateId(),
        fullName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        streetAddress: _streetController.text.trim(),
        regionCode: selection.region.code,
        regionName: selection.region.name,
        provinceCode: selection.province.code,
        provinceName: selection.province.name,
        cityCode: selection.city.code,
        cityName: selection.city.name,
        barangayCode: selection.barangay.code,
        barangayName: selection.barangay.name,
        postalCode: _postalController.text.trim(),
        // Forced true when this will be the customer's only address —
        // matches what UserModel.withSavedAddressUpserted would do
        // anyway, so the toggle and the stored value never disagree.
        isDefault: _forceDefault ? true : _setAsDefault,
      );

      final updated = widget.user.withSavedAddressUpserted(toSave);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      _showMessage(_isEditing ? 'Address updated.' : 'Address added.');
      Navigator.pop(context, updated);
    } on AppException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(
        'Could not save your address. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existingAddress;
    if (existing == null) return;

    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete address?'),
        content: const Text(
          'This removes this saved address. You can add a new one any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete', style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    try {
      final updated = widget.user.withSavedAddressRemoved(existing.id);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      _showMessage('Address deleted.');
      Navigator.pop(context, updated);
    } on AppException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage(
        'Could not delete your address. Please try again.',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  // ---------------------------------------------------------------------
  // Build — matches ProfileScreen / AddressSelectionScreen's glass and
  // gradient design language.
  // ---------------------------------------------------------------------

  /// Same corner radius used across every glass panel on the other two
  /// screens, kept identical here so all three read as one system.
  static const double _kRadius = 28.0;

  /// Same cool near-white frost tint used everywhere else.
  static const Color _kGlassTint = Color(0xFFF7F9FC);

  @override
  Widget build(BuildContext context) {
    final selection = _addressSelection;
    final isBusy = _isSaving || _isDeleting;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(_isEditing ? 'Edit Address' : 'Add Address'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ---- Same soft blue-grey diagonal gradient backdrop as
          // ProfileScreen / AddressSelectionScreen — steel blue at the
          // top-left fading to near-white/white toward the
          // bottom-right. Fixed palette, not derived from the theme,
          // to match those screens exactly. ----
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF93ACCE),
                  Color(0xFFC7D2E3),
                  Color(0xFFF2F4F8),
                  Colors.white,
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: Form(
                    key: _formKey,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        MediaQuery.of(context).padding.top +
                            kToolbarHeight +
                            12,
                        16,
                        24,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _QuickFillCard(
                            controller: _quickFillController,
                            onFillTap: _applyQuickFill,
                            borderRadius: BorderRadius.circular(_kRadius - 8),
                            tintColor: _kGlassTint,
                          ),
                          const SizedBox(height: 16),
                          _AddressFormCard(
                            nameController: _nameController,
                            phoneController: _phoneController,
                            postalController: _postalController,
                            streetController: _streetController,
                            selection: selection,
                            onTapHierarchy: _pickAddressHierarchy,
                            nameValidator: (v) => _requiredField(v, 'Full name'),
                            phoneValidator: _validatePhone,
                            postalValidator: _validatePostal,
                            streetValidator: (v) => _requiredField(
                              v,
                              'Street name, building, house no.',
                            ),
                            isDefault: _forceDefault ? true : _setAsDefault,
                            isDefaultLocked: _forceDefault,
                            onDefaultChanged: (value) =>
                                setState(() => _setAsDefault = value),
                            borderRadius: BorderRadius.circular(_kRadius),
                            tintColor: _kGlassTint,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _BottomActions(
                  isSaving: _isSaving,
                  isDeleting: _isDeleting,
                  showDelete: _isEditing,
                  onDelete: isBusy ? null : _confirmDelete,
                  onSubmit: isBusy ? null : _submit,
                  tintColor: _kGlassTint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A frosted-glass panel: blurs whatever sits behind it (the gradient
/// backdrop) and overlays a translucent, theme-neutral tint so content
/// stays readable while the color beneath still shows through. Same
/// treatment as `ProfileScreen`/`AddressSelectionScreen`'s own
/// `_GlassPanel`, kept here so every card on this screen matches.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.borderRadius,
    this.padding = const EdgeInsets.all(16),
    this.tintColor,
    this.opacity = 0.6,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? tintColor;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseTint = tintColor ?? colorScheme.surface;

    final panel = ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            color: baseTint.withValues(alpha: opacity),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );

    return panel;
  }
}

/// "Paste and Quick-Fill" card — now a frosted glass panel instead of
/// a flat tinted/bordered card, matching the reference layout (icon +
/// heading + multiline paste field + "Fill" action) but with the same
/// blurred, translucent treatment as every other panel on this screen.
class _QuickFillCard extends StatelessWidget {
  const _QuickFillCard({
    required this.controller,
    required this.onFillTap,
    required this.borderRadius,
    required this.tintColor,
  });

  final TextEditingController controller;
  final VoidCallback onFillTap;
  final BorderRadius borderRadius;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return _GlassPanel(
      borderRadius: borderRadius,
      tintColor: tintColor,
      opacity: 0.5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.content_paste_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paste and Quick-Fill',
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paste or input the information, tap Fill to input the name, '
                      'phone number, and address.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // The paste field itself is a lighter glass layer floating on
          // top of the card's own glass, so it still reads as an
          // input well rather than disappearing into the panel.
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                child: TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        'Paste or input the information, tap Fill to input the name, '
                        'phone number, and address.',
                    hintStyle: textTheme.bodySmall,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onFillTap,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.primary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              child: const Text(
                'Fill',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The large rounded "Address" card — title + the five vertical fields
/// plus the "Set as default" toggle, separated by hairline dividers.
/// Now drawn as a frosted glass panel instead of a flat white bordered
/// card, matching the reference layout otherwise unchanged.
class _AddressFormCard extends StatelessWidget {
  const _AddressFormCard({
    required this.nameController,
    required this.phoneController,
    required this.postalController,
    required this.streetController,
    required this.selection,
    required this.onTapHierarchy,
    required this.nameValidator,
    required this.phoneValidator,
    required this.postalValidator,
    required this.streetValidator,
    required this.isDefault,
    required this.isDefaultLocked,
    required this.onDefaultChanged,
    required this.borderRadius,
    required this.tintColor,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController postalController;
  final TextEditingController streetController;
  final PhAddressSelection? selection;
  final VoidCallback onTapHierarchy;
  final String? Function(String?) nameValidator;
  final String? Function(String?) phoneValidator;
  final String? Function(String?) postalValidator;
  final String? Function(String?) streetValidator;
  final bool isDefault;
  final bool isDefaultLocked;
  final ValueChanged<bool> onDefaultChanged;
  final BorderRadius borderRadius;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return _GlassPanel(
      borderRadius: borderRadius,
      tintColor: tintColor,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              'Address',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _AddressField(
            label: 'Full Name',
            controller: nameController,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            validator: nameValidator,
          ),
          _AddressField(
            label: 'Phone Number',
            controller: phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s+()\-]')),
            ],
            validator: phoneValidator,
          ),
          _HierarchyField(
            label: 'Region, Province, City,  Barangay',
            selection: selection,
            onTap: onTapHierarchy,
          ),
          _AddressField(
            label: 'Postal Code',
            controller: postalController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: postalValidator,
          ),
          _AddressField(
            label: 'Street Name, Building, House No.',
            controller: streetController,
            keyboardType: TextInputType.streetAddress,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 3,
            minLines: 1,
            validator: streetValidator,
          ),
          _DefaultToggleRow(
            value: isDefault,
            locked: isDefaultLocked,
            onChanged: onDefaultChanged,
          ),
        ],
      ),
    );
  }
}

/// "Set as default" row — a labelled switch pinned to the bottom of
/// the address form. Locked on (and disabled) when saving this address
/// will leave the customer with only one address on file, since
/// [UserModel.withSavedAddressUpserted] always makes a customer's sole
/// address the default regardless of this toggle.
class _DefaultToggleRow extends StatelessWidget {
  const _DefaultToggleRow({
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  final bool value;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set as default address',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (locked)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Your only saved address is always the default.',
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: locked ? null : onChanged,
          ),
        ],
      ),
    );
  }
}

/// One editable row: small caption label, then a borderless text
/// field showing/editing the value directly underneath — the
/// "tap-in-place" style used throughout the reference form.
class _AddressField extends StatelessWidget {
  const _AddressField({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.validator,
    this.maxLines = 1,
    this.minLines,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final int maxLines;
  final int? minLines;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 2),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          validator: validator,
          maxLines: maxLines,
          minLines: minLines,
          style: textTheme.bodyLarge?.copyWith(
            fontSize: 15.5,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 10),
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

/// The tappable "Region, Province, City, Barangay" row — not free
/// text; opens [AddressHierarchyPicker] to choose all four levels,
/// matching the chevron-and-multi-line-value treatment from the
/// reference. Shows whatever the customer has actually picked —
/// anywhere in the Philippines — or a placeholder prompt when nothing
/// has been picked yet.
class _HierarchyField extends StatelessWidget {
  const _HierarchyField({
    required this.label,
    required this.selection,
    required this.onTap,
  });

  final String label;
  final PhAddressSelection? selection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sel = selection;

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: sel == null
                    ? Text(
                        'Select Region, Province, City, Barangay',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sel.region.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            sel.province.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            sel.city.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            sel.barangay.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(
            height: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ],
      ),
    );
  }
}

/// Pinned bottom bar with "Delete Address" (outlined) and "Submit"
/// (filled) side by side, matching the reference. "Delete Address" is
/// omitted entirely while adding a brand-new address ([showDelete]
/// false) — there is nothing to delete yet — so Submit takes the full
/// width in that case. Now a frosted glass bar instead of a flat
/// opaque surface, matching the rest of the screen.
class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isSaving,
    required this.isDeleting,
    required this.showDelete,
    required this.onDelete,
    required this.onSubmit,
    required this.tintColor,
  });

  final bool isSaving;
  final bool isDeleting;
  final bool showDelete;
  final VoidCallback? onDelete;
  final VoidCallback? onSubmit;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: tintColor.withValues(alpha: 0.65),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                if (showDelete) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Delete Address',
                      variant: AppButtonVariant.outlined,
                      isLoading: isDeleting,
                      onPressed: onDelete,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: AppButton(
                    label: 'Submit',
                    isLoading: isSaving,
                    onPressed: onSubmit,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}