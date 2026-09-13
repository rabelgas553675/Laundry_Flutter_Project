import 'package:flutter/material.dart';

import '../../../app/constants.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/detergent_selection.dart';
import '../../../core/widgets/dropoff_info_card.dart';
import '../../../core/widgets/laundry_item_selection.dart';
import '../../../core/widgets/location_selection.dart';
import '../../../core/widgets/service_selection.dart';
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

/// PART 10 — the customer's laundry order form.
///
/// Built incrementally across three sub-parts, all inside this one
/// screen/state object:
///   • 10.1: Select Service, Select Laundry Items, Enter Weight
///   • 10.2: Select Detergent, Select Pickup/Drop-off (Address,
///     Phone, Landmark shipped as plain fields; Location shipped as
///     a placeholder text field)
///   • 10.3 (this part): the real Location selection interface, plus
///     a whole-form validation pass gating the final "Proceed"
///     button
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('New Laundry Order')),
      body: SafeArea(
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
            Step(
              title: const Text('Select Service'),
              subtitle: _selectedService != null ? Text(_selectedService!.name) : null,
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: Column(
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
                    Text(_serviceError!, style: TextStyle(color: colors.error)),
                  ],
                ],
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    prefixIcon: Icons.scale_outlined,
                    onChanged: (_) {
                      // Always rebuild so the step subtitle stays in
                      // sync as the customer types, clearing any
                      // previous validation error along the way.
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
              subtitle:
                  _selectedDetergent != null ? Text(_selectedDetergent!.name) : null,
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
                  ? Text(_deliveryMethod == DeliveryMethod.pickup ? 'Pickup' : 'Drop-off')
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
                    selected: _deliveryMethod == null ? const {} : {_deliveryMethod!},
                    emptySelectionAllowed: true,
                    onSelectionChanged: (selection) {
                      setState(() {
                        _deliveryMethod = selection.isEmpty ? null : selection.first;
                        _deliveryMethodError = null;
                      });
                    },
                  ),
                  if (_deliveryMethodError != null) ...[
                    const SizedBox(height: 8),
                    Text(_deliveryMethodError!, style: TextStyle(color: colors.error)),
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
                      onChanged: (_) => setState(() => _pickupAddressError = null),
                    ),
                    if (_pickupAddressError != null) ...[
                      const SizedBox(height: 4),
                      Text(_pickupAddressError!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Phone',
                      hint: 'e.g. 0917 123 4567',
                      controller: _pickupPhoneController,
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      onChanged: (_) => setState(() => _pickupPhoneError = null),
                    ),
                    if (_pickupPhoneError != null) ...[
                      const SizedBox(height: 4),
                      Text(_pickupPhoneError!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 12),
                    AppTextField(
                      label: 'Landmark',
                      hint: 'e.g. Near the barangay hall',
                      controller: _pickupLandmarkController,
                      prefixIcon: Icons.signpost_outlined,
                      onChanged: (_) => setState(() => _pickupLandmarkError = null),
                    ),
                    if (_pickupLandmarkError != null) ...[
                      const SizedBox(height: 4),
                      Text(_pickupLandmarkError!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 12),

                    // PART 10.3 — real location-selection interface,
                    // replacing the PART 10.2 plain text field.
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
                      Text(_pickupLocationError!, style: TextStyle(color: colors.error)),
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
    );
  }
}