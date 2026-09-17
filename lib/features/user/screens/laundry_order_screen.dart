import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../app/constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/detergent_selection.dart';
import '../../../core/widgets/dropoff_info_card.dart';
import '../../../core/widgets/laundry_item_selection.dart';
    import '../../../core/widgets/location_selection.dart';
import '../../../models/detergent_model.dart';
import '../../../models/laundry_item_model.dart';
import '../../../models/location_area_model.dart';
import '../../../models/order_draft_model.dart';
import '../../../models/service_model.dart';
import 'order_summary_screen.dart';

/// How the order gets to/from the customer. UI-only for now — PART 12
/// (order creation) will decide how this maps onto the persisted
/// order document, so it's kept local to the order form rather than
/// promoted to a models/ file yet.
enum DeliveryMethod { pickup, dropoff }

/// Brand blue used across the dashboard's glass UI
/// (`user_dashboard.dart`'s `_DashboardBackground`/`_DashboardAppBar`).
/// Pulled out here so the Stepper/step-content override below and the
/// two small shell widgets at the bottom of this file always agree
/// with the rest of the app instead of drifting to a local guess.
const Color _kBrandBlue = Color(0xff0D47A1);
const Color _kBrandBlueLight = Color(0xff8EC5FC);

/// PART 10 — the customer's laundry order form.
///
/// Built incrementally across three sub-parts, all inside this one
/// screen/state object:
///   • 10.1: Select Service, Select Laundry Items, Enter Weight
///   • 10.2: Select Detergent, Select Pickup/Drop-off (Address,
///     Phone, Landmark shipped as plain fields; Location shipped as
///     a placeholder text field)
///   • 10.3: the real Location selection interface, plus a whole-form
///     validation pass gating the final "Proceed" button
///
/// The visual shell (app bar, background, Stepper/step colors) was
/// restyled to match `user_dashboard.dart`'s frosted-glass look — see
/// [_buildShell] at the bottom of [build]. The outer content sheet and
/// the "Select Service" step's own content are both frosted glass
/// (translucent + blurred) rather than solid white, so the background
/// blobs show through. None of the step logic, validation, or state
/// below was touched.
///
/// Everything the customer picks is kept only in this screen's state
/// for now — PART 11 adds price calculation, and PART 12 is the first
/// part that actually saves anything to Firestore.
class LaundryOrderScreen extends StatefulWidget {
  const LaundryOrderScreen({super.key, this.initialService});

  /// Optional pre-selected service — e.g. when the customer tapped a
  /// service directly from the dashboard's Quick Service Selection.
  final ServiceModel? initialService;

  @override
  State<LaundryOrderScreen> createState() => _LaundryOrderScreenState();
}

class _LaundryOrderScreenState extends State<LaundryOrderScreen> {
  /// Index of the last step in [Stepper.steps]. Used by the controls
  /// builder to label the final button "Proceed" instead of
  /// "Continue", and by [_runFullValidation] to know it has reached
  /// the end of the form.
  static const int _finalStepIndex = 4;

  int _currentStep = 0;

  // ---- Step 1: Service ----
  ServiceModel? _selectedService;
  String? _serviceError;

  // ---- Step 2: Laundry Items ----
  final Set<LaundryItemModel> _selectedItems = {};
  String? _itemsError;

  // ---- Step 3: Weight ----
  final _weightController = TextEditingController();
  String? _weightError;

  // ---- Step 4: Detergent ----
  DetergentModel? _selectedDetergent;
  String? _detergentError;

  // ---- Step 5: Pickup / Drop-off ----
  DeliveryMethod? _deliveryMethod;
  String? _deliveryMethodError;
  final _pickupAddressController = TextEditingController();
  final _pickupPhoneController = TextEditingController();
  final _pickupLandmarkController = TextEditingController();
  // PART 10.3 — replaces the PART 10.2 placeholder text field with a
  // real selection value. See lib/core/widgets/location_selection.dart
  // and lib/models/location_area_model.dart.
  LocationAreaModel? _selectedLocationArea;
  String? _pickupAddressError;
  String? _pickupPhoneError;
  String? _pickupLandmarkError;
  String? _pickupLocationError;

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _pickupAddressController.dispose();
    _pickupPhoneController.dispose();
    _pickupLandmarkController.dispose();
    super.dispose();
  }

  // -------------------- Validation --------------------

  bool _validateService() {
    if (_selectedService == null) {
      setState(() => _serviceError = 'Please select a service to continue.');
      return false;
    }
    setState(() => _serviceError = null);
    return true;
  }

  bool _validateItems() {
    if (_selectedItems.isEmpty) {
      setState(() => _itemsError = 'Select at least one laundry item.');
      return false;
    }
    setState(() => _itemsError = null);
    return true;
  }

  bool _validateWeight() {
    final raw = _weightController.text.trim();
    final parsed = double.tryParse(raw);
    if (raw.isEmpty || parsed == null || parsed <= 0) {
      setState(() => _weightError = 'Enter a valid weight in kg (greater than 0).');
      return false;
    }
    setState(() => _weightError = null);
    return true;
  }

  bool _validateDetergent() {
    if (_selectedDetergent == null) {
      setState(() => _detergentError = 'Please select a detergent.');
      return false;
    }
    setState(() => _detergentError = null);
    return true;
  }

  bool _validateDeliveryMethod() {
    if (_deliveryMethod == null) {
      setState(() => _deliveryMethodError = 'Please choose Pickup or Drop-off.');
      return false;
    }

    // Drop-off only displays shop info — nothing further to validate.
    if (_deliveryMethod == DeliveryMethod.dropoff) {
      setState(() {
        _deliveryMethodError = null;
        _pickupAddressError = null;
        _pickupPhoneError = null;
        _pickupLandmarkError = null;
        _pickupLocationError = null;
      });
      return true;
    }

    // Pickup requires Address, Phone, Landmark, and a selected
    // Location (PART 10.3 — previously just "not empty" on a text
    // field, now a real selection from LocationSelection).
    final addressError =
        _pickupAddressController.text.trim().isEmpty ? 'Address is required.' : null;
    final phoneError =
        _pickupPhoneController.text.trim().isEmpty ? 'Phone number is required.' : null;
    final landmarkError =
        _pickupLandmarkController.text.trim().isEmpty ? 'Landmark is required.' : null;
    final locationError =
        _selectedLocationArea == null ? 'Please select your pickup area.' : null;

    setState(() {
      _deliveryMethodError = null;
      _pickupAddressError = addressError;
      _pickupPhoneError = phoneError;
      _pickupLandmarkError = landmarkError;
      _pickupLocationError = locationError;
    });

    return addressError == null &&
        phoneError == null &&
        landmarkError == null &&
        locationError == null;
  }

  /// PART 10.3 — validates every step in the whole form at once, not
  /// just the current one.
  ///
  /// Without this, a customer could use [_handleStepTapped] to jump
  /// back to an earlier step, leave it invalid, tap forward again,
  /// and still reach the final "Proceed" button — [_handleStepContinue]
  /// on its own only ever re-checks the step you're currently on.
  /// This is what actually gates "Proceed": every field across all
  /// five steps must be valid, and the customer is dropped on the
  /// first one that isn't, with that step's own error messages
  /// populated so it's obvious what to fix.
  bool _runFullValidation() {
    final serviceOk = _validateService();
    final itemsOk = _validateItems();
    final weightOk = _validateWeight();
    final detergentOk = _validateDetergent();
    final deliveryOk = _validateDeliveryMethod();

    if (!serviceOk) {
      setState(() => _currentStep = 0);
      return false;
    }
    if (!itemsOk) {
      setState(() => _currentStep = 1);
      return false;
    }
    if (!weightOk) {
      setState(() => _currentStep = 2);
      return false;
    }
    if (!detergentOk) {
      setState(() => _currentStep = 3);
      return false;
    }
    if (!deliveryOk) {
      setState(() => _currentStep = 4);
      return false;
    }
    return true;
  }

  // -------------------- Stepper callbacks --------------------

  void _handleStepContinue() {
    switch (_currentStep) {
      case 0:
        if (!_validateService()) return;
        setState(() => _currentStep = 1);
        break;
      case 1:
        if (!_validateItems()) return;
        setState(() => _currentStep = 2);
        break;
      case 2:
        if (!_validateWeight()) return;
        setState(() => _currentStep = 3);
        break;
      case 3:
        if (!_validateDetergent()) return;
        setState(() => _currentStep = 4);
        break;
      case _finalStepIndex:
        // PART 10.3 — the form's final validation pass. Everything
        // entered across all five steps is preserved in this screen's
        // state (nothing is cleared here), so if the customer needs
        // to go back and fix something, all their other answers are
        // exactly as they left them.
        if (!_runFullValidation()) return;
        _proceedToOrderSummary();
        break;
    }
  }

  /// PART 11.3 — builds the [OrderDraft] snapshot from everything
  /// collected across the five steps and pushes [OrderSummaryScreen]
  /// on top of this form.
  ///
  /// Only called after [_runFullValidation] passes, so the `!`s below
  /// on the required selections (service/detergent/deliveryMethod)
  /// are safe. [AppConstants.pickupFee] is applied here — the single
  /// place that decides Pickup costs a flat delivery fee and Drop-off
  /// doesn't — matching [OrderDraft.pickupFee]'s doc comment. Nothing
  /// is saved: this is purely in-memory navigation, and "Back" on the
  /// summary screen pops right back here with this form's state
  /// untouched.
  void _proceedToOrderSummary() {
    final isPickup = _deliveryMethod == DeliveryMethod.pickup;

    final order = OrderDraft(
      service: _selectedService!,
      items: _selectedItems,
      weightKg: double.parse(_weightController.text.trim()),
      detergent: _selectedDetergent!,
      deliveryMethod: _deliveryMethod!,
      pickupAddress: isPickup ? _pickupAddressController.text.trim() : null,
      pickupPhone: isPickup ? _pickupPhoneController.text.trim() : null,
      pickupLandmark: isPickup ? _pickupLandmarkController.text.trim() : null,
      pickupLocation: isPickup ? _selectedLocationArea : null,
      pickupFee: isPickup ? AppConstants.pickupFee : 0,
      // PART 18 is what actually introduces promo codes — no discount
      // exists yet on the order form, so this is always 0 for now.
      discount: 0,
    );

    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (context) => OrderSummaryScreen(order: order)),
    );
  }

  void _handleStepCancel() {
    if (_currentStep == 0) return;
    setState(() => _currentStep -= 1);
  }

  void _handleStepTapped(int index) {
    // Only allow jumping to a step that's already been reached —
    // prevents skipping ahead of unvalidated steps.
    if (index <= _currentStep) {
      setState(() => _currentStep = index);
    }
  }

  // -------------------- Build --------------------

  @override
  Widget build(BuildContext context) {
    // Local Theme override: Stepper's active/complete step circles and
    // the selection widgets' Radios both read `colorScheme.primary` by
    // default in Material 3, and AppButton very likely does too — this
    // is what turns the previous plain-black circles/radio/button blue
    // to match the dashboard, without needing to touch theme.dart or
    // any of the selection widgets themselves.
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: baseTheme.colorScheme.copyWith(
          primary: _kBrandBlue,
          secondary: _kBrandBlue,
        ),
      ),
      child: Builder(builder: _buildShell),
    );
  }

  /// The actual screen shell: glass app bar + blurred-blob background
  /// (matching `user_dashboard.dart`), with the Stepper now sitting on
  /// a frosted-glass sheet (translucent + blurred, matching the app
  /// bar's recipe) instead of solid white, so the background blobs
  /// show through. [context] here already carries the blue-primary
  /// [Theme] override from [build].
  Widget _buildShell(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const _GlassOrderAppBar(title: 'New Laundry Order'),
      body: Stack(
        children: [
          const Positioned.fill(child: _OrderScreenBackground()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(28),
                  topRight: Radius.circular(28),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      border: Border(
                        top: BorderSide(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Stepper(
                      type: StepperType.vertical,
                      currentStep: _currentStep,
                      onStepContinue: _handleStepContinue,
                      onStepCancel: _handleStepCancel,
                      onStepTapped: _handleStepTapped,
                      controlsBuilder: (context, details) {
                        final isFinalStep = details.stepIndex == _finalStepIndex;
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  label: isFinalStep ? 'Proceed' : 'Continue',
                                  icon: isFinalStep ? Icons.check_circle_outline : null,
                                  onPressed: details.onStepContinue,
                                ),
                              ),
                              if (details.stepIndex > 0) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: AppButton(
                                    label: 'Back',
                                    variant: AppButtonVariant.outlined,
                                    onPressed: details.onStepCancel,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                      steps: [
                        // ---- Step 1: Service ----
                        // Content wrapped in its own frosted-glass card
                        // (translucent + blurred) rather than sitting
                        // directly on the outer sheet, so it reads as
                        // a distinct glass panel over the background
                        // blobs. See [ServiceSelection] for the actual
                        // service tiles rendered inside.
                        Step(
                          title: const Text('Select Service'),
                          subtitle: _selectedService != null
                              ? Text(_selectedService!.name)
                              : null,
                          isActive: _currentStep >= 0,
                          state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                          content: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.30),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ServiceSelection(
                                      selected: _selectedService,
                                      onChanged: (service) {
                                        setState(() {
                                          _selectedService = service;
                                          _serviceError = null;
                                        });
                                      },
                                    ),
                                    if (_serviceError != null) ...[
                                      const SizedBox(height: 8),
                                      Text(
                                        _serviceError!,
                                        style: TextStyle(color: colors.error),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // ---- Step 2: Laundry Items ----
                        Step(
                          title: const Text('Select Laundry Items'),
                          subtitle: _selectedItems.isNotEmpty
                              ? Text('${_selectedItems.length} item(s) selected')
                              : null,
                          isActive: _currentStep >= 1,
                          state: _currentStep > 1
                              ? StepState.complete
                              : (_currentStep == 1 ? StepState.indexed : StepState.disabled),
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LaundryItemSelection(
                                selected: _selectedItems,
                                onChanged: (items) {
                                  setState(() {
                                    _selectedItems
                                      ..clear()
                                      ..addAll(items);
                                    _itemsError = null;
                                  });
                                },
                              ),
                              if (_itemsError != null) ...[
                                const SizedBox(height: 8),
                                Text(_itemsError!, style: TextStyle(color: colors.error)),
                              ],
                            ],
                          ),
                        ),

                        // ---- Step 3: Weight ----
                        Step(
                          title: const Text('Enter Weight'),
                          subtitle: _weightController.text.trim().isNotEmpty
                              ? Text('${_weightController.text.trim()} kg')
                              : null,
                          isActive: _currentStep >= 2,
                          state: _currentStep > 2
                              ? StepState.complete
                              : (_currentStep == 2 ? StepState.indexed : StepState.disabled),
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppTextField(
                                label: 'Weight (kg)',
                                hint: 'e.g. 5.0',
                                controller: _weightController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(decimal: true),
                                prefixIcon: Icons.scale_outlined,
                                onChanged: (_) {
                                  // Always rebuild so the step subtitle
                                  // stays in sync as the customer types,
                                  // clearing any previous validation
                                  // error along the way.
                                  setState(() => _weightError = null);
                                },
                              ),
                              if (_weightError != null) ...[
                                const SizedBox(height: 8),
                                Text(_weightError!, style: TextStyle(color: colors.error)),
                              ],
                            ],
                          ),
                        ),

                        // ---- Step 4: Detergent ----
                        Step(
                          title: const Text('Select Detergent'),
                          subtitle: _selectedDetergent != null
                              ? Text(_selectedDetergent!.name)
                              : null,
                          isActive: _currentStep >= 3,
                          state: _currentStep > 3
                              ? StepState.complete
                              : (_currentStep == 3 ? StepState.indexed : StepState.disabled),
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DetergentSelection(
                                selected: _selectedDetergent,
                                onChanged: (detergent) {
                                  setState(() {
                                    _selectedDetergent = detergent;
                                    _detergentError = null;
                                  });
                                },
                              ),
                              if (_detergentError != null) ...[
                                const SizedBox(height: 8),
                                Text(_detergentError!, style: TextStyle(color: colors.error)),
                              ],
                            ],
                          ),
                        ),

                        // ---- Step 5: Pickup / Drop-off, Address & Location ----
                        Step(
                          title: const Text('Select Pickup/Drop-off'),
                          subtitle: _deliveryMethod != null
                              ? Text(_deliveryMethod == DeliveryMethod.pickup
                                  ? 'Pickup'
                                  : 'Drop-off')
                              : null,
                          isActive: _currentStep >= 4,
                          state: _currentStep == 4 ? StepState.indexed : StepState.disabled,
                          content: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SegmentedButton<DeliveryMethod>(
                                segments: const [
                                  ButtonSegment(
                                    value: DeliveryMethod.pickup,
                                    label: Text('Pickup'),
                                    icon: Icon(Icons.delivery_dining_outlined),
                                  ),
                                  ButtonSegment(
                                    value: DeliveryMethod.dropoff,
                                    label: Text('Drop-off'),
                                    icon: Icon(Icons.storefront_outlined),
                                  ),
                                ],
                                selected:
                                    _deliveryMethod == null ? const {} : {_deliveryMethod!},
                                emptySelectionAllowed: true,
                                onSelectionChanged: (selection) {
                                  setState(() {
                                    _deliveryMethod =
                                        selection.isEmpty ? null : selection.first;
                                    _deliveryMethodError = null;
                                  });
                                },
                              ),
                              if (_deliveryMethodError != null) ...[
                                const SizedBox(height: 8),
                                Text(_deliveryMethodError!,
                                    style: TextStyle(color: colors.error)),
                              ],
                              const SizedBox(height: 16),

                              // Pickup fields — only shown when Pickup is chosen.
                              if (_deliveryMethod == DeliveryMethod.pickup) ...[
                                AppTextField(
                                  label: 'Address',
                                  hint: 'House/unit no., street, barangay',
                                  controller: _pickupAddressController,
                                  prefixIcon: Icons.home_outlined,
                                  maxLines: 2,
                                  onChanged: (_) =>
                                      setState(() => _pickupAddressError = null),
                                ),
                                if (_pickupAddressError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_pickupAddressError!,
                                      style: TextStyle(color: colors.error)),
                                ],
                                const SizedBox(height: 12),
                                AppTextField(
                                  label: 'Phone',
                                  hint: 'e.g. 0917 123 4567',
                                  controller: _pickupPhoneController,
                                  keyboardType: TextInputType.phone,
                                  prefixIcon: Icons.phone_outlined,
                                  onChanged: (_) =>
                                      setState(() => _pickupPhoneError = null),
                                ),
                                if (_pickupPhoneError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_pickupPhoneError!,
                                      style: TextStyle(color: colors.error)),
                                ],
                                const SizedBox(height: 12),
                                AppTextField(
                                  label: 'Landmark',
                                  hint: 'e.g. Near the barangay hall',
                                  controller: _pickupLandmarkController,
                                  prefixIcon: Icons.signpost_outlined,
                                  onChanged: (_) =>
                                      setState(() => _pickupLandmarkError = null),
                                ),
                                if (_pickupLandmarkError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_pickupLandmarkError!,
                                      style: TextStyle(color: colors.error)),
                                ],
                                const SizedBox(height: 12),

                                // PART 10.3 — real location-selection
                                // interface, replacing the PART 10.2
                                // plain text field.
                                LocationSelection(
                                  selected: _selectedLocationArea,
                                  onChanged: (area) {
                                    setState(() {
                                      _selectedLocationArea = area;
                                      _pickupLocationError = null;
                                    });
                                  },
                                ),
                                if (_pickupLocationError != null) ...[
                                  const SizedBox(height: 4),
                                  Text(_pickupLocationError!,
                                      style: TextStyle(color: colors.error)),
                                ],
                              ],

                              // Drop-off info — only shown when Drop-off is chosen.
                              if (_deliveryMethod == DeliveryMethod.dropoff)
                                const DropoffInfoCard(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted-glass app bar for the order form — same recipe as
/// `_DashboardAppBar` in `user_dashboard.dart` (blurred translucent
/// bar, rounded bottom corners, accent stripe), but with a back arrow
/// in place of the dashboard's logout button, since this screen is
/// pushed on top of the dashboard rather than being a bottom-nav tab.
class _GlassOrderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassOrderAppBar({required this.title});

  final String title;

  static const double _contentHeight = 64;

  @override
  Size get preferredSize => const Size.fromHeight(_contentHeight);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(24),
        bottomRight: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.5), width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: _kBrandBlue.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _contentHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 0, 18, 0),
                child: Row(
                  children: [
                    _GlassBackButton(onPressed: () => Navigator.of(context).maybePop()),
                    const SizedBox(width: 6),
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 10),
                      decoration: BoxDecoration(
                        color: _kBrandBlue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
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

class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.25),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.black87, size: 19),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

/// Same blurred-blob backdrop as `_DashboardBackground` in
/// `user_dashboard.dart`, trimmed to two blobs since this is a
/// secondary screen sitting mostly behind a white content sheet
/// rather than the dashboard's fully transparent tab content.
class _OrderScreenBackground extends StatelessWidget {
  const _OrderScreenBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfff4f6fb),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -90,
            right: -70,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 260,
                height: 260,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_kBrandBlue, Color(0xffB3E5FC)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 220,
            left: -90,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kBrandBlueLight.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}