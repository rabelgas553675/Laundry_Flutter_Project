// lib/features/user/screens/address_selection_screen.dart
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/services/auth_state.dart';
import '../../../models/user_model.dart';
import 'edit_address_screen.dart';

/// Profile → Address entry point. Reached from [ProfileScreen]'s
/// "Address" row instead of jumping straight into [EditAddressScreen]
/// — this screen lists every address the signed-in customer has saved
/// ([UserModel.effectiveAddresses], which already reads only *this*
/// user's own `users/{uid}` document, so there is no way to see
/// another customer's addresses) and lets them:
///
/// - pick which one is currently active (radio selection —
///   [UserModel.selectedAddressId], persisted via
///   [UserModel.copyWith] so choosing a non-default address here never
///   flips which one is flagged default),
/// - jump into [EditAddressScreen] to edit a specific address, or
/// - jump into [EditAddressScreen] with no [EditAddressScreen.existingAddress]
///   to add a brand-new one.
///
/// There is no second address store here either: every read/write
/// goes through the same [UserModel]/[UserRepository]/[AuthState] the
/// rest of the app already uses.
///
/// Visual design matches [ProfileScreen]: the same soft steel-blue →
/// white diagonal gradient backdrop, with every card, button, and
/// header drawn as a frosted glass panel ([_GlassPanel]) blurring that
/// backdrop instead of using flat, opaque surfaces.
class AddressSelectionScreen extends StatefulWidget {
  const AddressSelectionScreen({
    super.key,
    required this.user,
    this.forOrderSelection = false,
  });

  final UserModel user;

  /// Part 2A — `true` when this screen was opened to pick an address
  /// for a single order (e.g. the Pickup Checkout flow in
  /// `laundry_order_screen.dart`) rather than to manage Profile →
  /// Address itself. This is the same screen either way — there is no
  /// second address-selection implementation — but it behaves
  /// differently in a few small ways while `true`:
  ///
  /// - Tapping a card only highlights it in this screen's own local
  ///   state; it does **not** write `UserModel.selectedAddressId` (or
  ///   anything else) to Firestore/[AuthState]. Browsing addresses for
  ///   one order can therefore never change what Profile shows as
  ///   picked, and — same as the normal Profile flow — can never touch
  ///   which address is flagged [SavedAddress.isDefault] either. See
  ///   [_selectAddress].
  /// - A primary "Use this Address" button appears; confirming a pick
  ///   is the only way to leave with a result, and pops this screen
  ///   with the chosen [SavedAddress] itself (not a [UserModel]) — see
  ///   [_useSelectedAddress].
  /// - Backing out (the app bar arrow, the OS back gesture/button)
  ///   without confirming pops with `null`, which the caller treats as
  ///   "cancelled" and leaves whatever address (if any) it already had
  ///   untouched.
  ///
  /// Adding/editing an address still goes through [EditAddressScreen]
  /// exactly as it does from Profile, and still persists normally —
  /// saving or deleting an address is managing the address book, not
  /// merely picking one for this order, so it's unaffected by this
  /// flag.
  final bool forOrderSelection;

  @override
  State<AddressSelectionScreen> createState() => _AddressSelectionScreenState();
}

class _AddressSelectionScreenState extends State<AddressSelectionScreen> {
  late UserModel _user;
  late String? _selectedId;
  bool _isSelecting = false;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    // Auto-select the default address (or whatever was last explicitly
    // picked) the moment the screen opens — [UserModel.selectedAddress]
    // already encodes exactly that fallback, so no separate lookup or
    // write is needed just to show the right radio checked.
    _selectedId = _user.selectedAddress?.id;
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError ? colorScheme.error : colorScheme.inverseSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          margin: const EdgeInsets.all(16),
          content: Text(
            message,
            style: TextStyle(
              color: isError ? colorScheme.onError : colorScheme.onInverseSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
  }

  /// Selecting a card only changes [UserModel.selectedAddressId] — it
  /// never touches `isDefault` on any [SavedAddress], so it can never
  /// change which address is the customer's default.
  ///
  /// In [AddressSelectionScreen.forOrderSelection] mode this doesn't
  /// even reach [UserModel.selectedAddressId]: the pick stays purely
  /// local (just highlighting the tapped card) until the customer
  /// taps "Use this Address" ([_useSelectedAddress]), which returns it
  /// to the caller without ever writing to Firestore/[AuthState]. That
  /// keeps "which address I'm using for this one order" completely
  /// separate from "which address Profile shows as picked".
  Future<void> _selectAddress(SavedAddress address) async {
    if (address.id == _selectedId || _isSelecting) return;

    if (widget.forOrderSelection) {
      setState(() => _selectedId = address.id);
      return;
    }

    final previousId = _selectedId;
    setState(() {
      _selectedId = address.id;
      _isSelecting = true;
    });

    try {
      final updated = _user.copyWith(selectedAddressId: address.id);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      setState(() => _user = updated);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _selectedId = previousId);
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _selectedId = previousId);
      _showMessage('Could not select this address. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  /// [forOrderSelection] only — confirms whichever card is currently
  /// highlighted and returns it to the caller (e.g. the Pickup
  /// Checkout flow). Deliberately never touches Firestore: which
  /// address is being used for one order is not persisted anywhere on
  /// [UserModel] — only adding/editing/deleting an address is.
  void _useSelectedAddress() {
    final id = _selectedId;
    if (id == null) return;
    final addresses = _user.effectiveAddresses;
    final address = addresses.firstWhere(
      (a) => a.id == id,
      orElse: () => addresses.first,
    );
    Navigator.pop(context, address);
  }

  Future<void> _openAddAddress() async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(builder: (_) => EditAddressScreen(user: _user)),
    );
    if (updated != null && mounted) {
      setState(() {
        _user = updated;
        _selectedId = updated.selectedAddress?.id;
      });
    }
  }

  Future<void> _openEditAddress(SavedAddress address) async {
    final updated = await Navigator.push<UserModel>(
      context,
      MaterialPageRoute(
        builder: (_) => EditAddressScreen(user: _user, existingAddress: address),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _user = updated;
        _selectedId = updated.selectedAddress?.id;
      });
    }
  }

  /// Deletes one saved address straight from this screen, mirroring
  /// [EditAddressScreen]'s own "Delete Address" flow — same
  /// confirmation copy, same [UserModel.withSavedAddressRemoved] call
  /// (which already keeps exactly one address flagged default, or
  /// clears everything cleanly if this was the last one left), same
  /// [UserRepository.updateProfile]/[AuthState.updateUserModel] pair.
  /// Having it here too means the customer doesn't have to open Edit
  /// just to remove an address they don't want anymore.
  Future<void> _deleteAddress(SavedAddress address) async {
    if (_isSelecting) return;

    final colorScheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete address?'),
        content: Text(
          'This removes "${address.fullName}" from your saved addresses. '
          'You can add a new one any time.',
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
    if (confirmed != true || !mounted) return;

    setState(() => _isSelecting = true);
    try {
      final updated = _user.withSavedAddressRemoved(address.id);
      await AuthState.sharedUserRepository.updateProfile(updated);
      AuthState.instance.updateUserModel(updated);
      if (!mounted) return;
      setState(() {
        _user = updated;
        _selectedId = updated.selectedAddress?.id;
      });
      _showMessage('Address deleted.');
    } on AppException catch (e) {
      if (!mounted) return;
      _showMessage(e.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      _showMessage('Could not delete this address. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _isSelecting = false);
    }
  }

  // ---------------------------------------------------------------------
  // Layout — matches ProfileScreen's glass/gradient design language.
  // ---------------------------------------------------------------------

  /// Same corner radius used across every glass panel on the Profile
  /// screen, kept identical here so the two screens read as one system.
  static const double _kRadius = 28.0;

  /// Same cool near-white frost tint used for Profile's glass panels.
  static const Color _kGlassTint = Color(0xFFF7F9FC);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final addresses = _user.effectiveAddresses;

    return PopScope(
      // Intercept every way off this screen — the AppBar's back
      // arrow, the OS back gesture/button, all of it — so whichever
      // one the customer uses, ProfileScreen still gets back the
      // latest [_user] (picked address / added / edited) instead of
      // the `null` a bare default pop would return. Without this,
      // selecting an address here would persist fine (it's already
      // written straight to Firestore in [_selectAddress]), but
      // ProfileScreen's own in-memory `_user` would stay stale until
      // the next full reload.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Profile → Address (the default) still returns the latest
        // [UserModel] on every way off this screen — see the class
        // doc comment. `forOrderSelection` mode never persisted a
        // pick just from browsing, so backing out without tapping
        // "Use this Address" has nothing to return but `null`
        // ("cancelled"), leaving whatever the caller already had
        // untouched.
        Navigator.pop(context, widget.forOrderSelection ? null : _user);
      },
      child: Scaffold(
        // The gradient backdrop below fills the whole screen, so the
        // Scaffold's own background is just a fallback behind it.
        backgroundColor: colorScheme.surface,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          title: Text(widget.forOrderSelection ? 'Select Address' : 'Address Selection'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () =>
                Navigator.pop(context, widget.forOrderSelection ? null : _user),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ---- Same soft blue-grey diagonal gradient backdrop as
            // ProfileScreen — steel blue at the top-left fading to
            // near-white/white toward the bottom-right. Fixed palette,
            // not derived from the theme, to match that screen exactly. ----
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
              child: Column(
                children: [
                  Expanded(
                    child: addresses.isEmpty
                        ? const _EmptyAddressState()
                        // `Radio.groupValue`/`Radio.onChanged` are deprecated in
                        // favor of a `RadioGroup` ancestor managing the shared
                        // value — wrapping the whole list here is what lets
                        // every `_AddressCard`'s `Radio<String>` below drop
                        // those two params and just declare its own `value`.
                        // `onChanged` fires with whichever address's radio was
                        // tapped directly; tapping anywhere else on a card
                        // still goes through `_AddressCard.onSelect` exactly as
                        // before, and both paths end up at the same
                        // `_selectAddress` call.
                        : RadioGroup<String>(
                            groupValue: _selectedId,
                            onChanged: (id) {
                              if (id == null) return;
                              final address = addresses.firstWhere(
                                (a) => a.id == id,
                                orElse: () => addresses.first,
                              );
                              _selectAddress(address);
                            },
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 8, bottom: 10),
                                  child: Text(
                                    'Address',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                for (final address in addresses) ...[
                                  _AddressCard(
                                    address: address,
                                    selected: address.id == _selectedId,
                                    onSelect: () => _selectAddress(address),
                                    onEdit: () => _openEditAddress(address),
                                    onDelete: () => _deleteAddress(address),
                                    borderRadius: BorderRadius.circular(_kRadius - 8),
                                    tintColor: _kGlassTint,
                                  ),
                                  const SizedBox(height: 12),
                                ],
                              ],
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      children: [
                        if (widget.forOrderSelection) ...[
                          _UseAddressButton(
                            enabled: _selectedId != null && addresses.isNotEmpty,
                            onTap: _useSelectedAddress,
                            borderRadius: BorderRadius.circular(_kRadius - 8),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _AddAddressButton(
                          onTap: _openAddAddress,
                          borderRadius: BorderRadius.circular(_kRadius - 8),
                          tintColor: _kGlassTint,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A frosted-glass panel: blurs whatever sits behind it (the gradient
/// backdrop) and overlays a translucent, theme-neutral tint so content
/// stays readable while the color beneath still shows through. Copied
/// from [ProfileScreen]'s own `_GlassPanel` so every card and button on
/// this screen shares the exact same glass treatment.
class _GlassPanel extends StatelessWidget {
  const _GlassPanel({
    required this.child,
    required this.borderRadius,
    this.padding = const EdgeInsets.all(16),
    this.tintColor,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Overrides the neutral `colorScheme.surface` tint with a fixed color
  /// — used here to match Profile's cool near-white frost.
  final Color? tintColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseTint = tintColor ?? colorScheme.surface;

    return ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: baseTint.withValues(alpha: 0.55),
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
  }
}

/// Shown when the customer has no saved addresses yet — a friendly
/// prompt centered above the "+ Add a new address" button, drawn as
/// its own glass panel so it matches the rest of the screen instead of
/// sitting directly on the gradient.
class _EmptyAddressState extends StatelessWidget {
  const _EmptyAddressState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _GlassPanel(
          borderRadius: BorderRadius.circular(24),
          tintColor: const Color(0xFFF7F9FC),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.location_off_outlined,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No saved addresses yet',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Add an address so we know where to pick up and drop off your laundry.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One saved address, drawn as a translucent glass card. Selection is
/// still shown with the primary-colored border/tint on top of the
/// glass, so the highlighted state stays clearly visible even though
/// the base card is now transparent instead of a flat opaque surface.
class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.selected,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
    required this.borderRadius,
    required this.tintColor,
  });

  final SavedAddress address;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final BorderRadius borderRadius;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: tintColor.withValues(alpha: selected ? 0.62 : 0.5),
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onSelect,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 12),
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: selected
                      ? colorScheme.primary
                      : Colors.white.withValues(alpha: 0.5),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `groupValue`/`onChanged` now come from the `RadioGroup<String>`
                  // wrapping the whole address list in the parent screen (see
                  // its build method) rather than being set per-radio here —
                  // the old per-card `groupValue: selected ? address.id : null`
                  // trick is exactly what `RadioGroup` replaces. Tapping this
                  // radio directly still selects this address via that
                  // ancestor's `onChanged`; tapping anywhere else on the card
                  // still goes through [onSelect] below via the `InkWell`.
                  Radio<String>(value: address.id),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                address.fullName,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Text(
                                '|',
                                style: TextStyle(color: colorScheme.onSurfaceVariant),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                address.phone,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (address.streetLine.isNotEmpty)
                          Text(
                            address.streetLine,
                            style: textTheme.bodyMedium,
                          ),
                        if (address.localityLine.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              address.localityLine,
                              style: textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (address.isDefault)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer.withValues(
                                    alpha: 0.8,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Default',
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            const Spacer(),
                            TextButton(
                              onPressed: onEdit,
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.primary,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                // The app's global TextButtonTheme sets
                                // `minimumSize: Size.fromHeight(48)`, which is
                                // `Size(double.infinity, 48)` — intended for
                                // full-width primary buttons. Left unset here,
                                // this small inline "Edit" action (sitting next
                                // to a Spacer in a Row, not wrapped by
                                // Expanded/SizedBox) inherits that infinite
                                // minimum width and can throw "BoxConstraints
                                // forces an infinite width" during layout.
                                // Overriding both minimumSize and tapTargetSize
                                // here keeps this one button intrinsically
                                // sized instead of inheriting the app-wide
                                // full-width default.
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Edit',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              onPressed: onDelete,
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                // Same reasoning as the "Edit" button above —
                                // don't inherit the app-wide
                                // Size.fromHeight(48) (infinite minimum width)
                                // TextButtonTheme default on a small inline
                                // action sitting in this Row.
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Delete',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Part 2A — "Use this Address", the primary confirm action shown
/// only in [AddressSelectionScreen.forOrderSelection] mode. Now a
/// frosted glass button (primary-tinted, blurred) instead of a flat
/// filled button, so it matches the rest of the screen while staying
/// visually primary. Disabled until a card is highlighted (or when
/// there are no saved addresses yet) so the customer can't confirm an
/// empty pick.
class _UseAddressButton extends StatelessWidget {
  const _UseAddressButton({
    required this.enabled,
    required this.onTap,
    required this.borderRadius,
  });

  final bool enabled;
  final VoidCallback onTap;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: colorScheme.primary.withValues(alpha: enabled ? 0.55 : 0.25),
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: enabled ? onTap : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Text(
                'Use this Address',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "+ Add a new address" — now a translucent glass button (blurred,
/// dashed outline) instead of a plain dashed outline on flat
/// background, matching every other card/button on this screen.
class _AddAddressButton extends StatelessWidget {
  const _AddAddressButton({
    required this.onTap,
    required this.borderRadius,
    required this.tintColor,
  });

  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final Color tintColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: tintColor.withValues(alpha: 0.4),
          borderRadius: borderRadius,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onTap,
            child: CustomPaint(
              painter: _DashedRRectPainter(
                color: colorScheme.primary.withValues(alpha: 0.6),
                radius: borderRadius.topLeft.x,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, color: colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Add a new address',
                      style: TextStyle(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    const dashWidth = 6.0;
    const dashGap = 4.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}