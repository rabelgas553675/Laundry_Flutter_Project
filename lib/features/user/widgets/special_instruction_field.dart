import 'package:flutter/material.dart';

import '../../../core/widgets/app_text_field.dart';

/// PART 2 — optional free-text note wrapping the shared [AppTextField]
/// with the multiline/hint/icon defaults this one field always needs,
/// so `LaundryOrderScreen` doesn't repeat them. Maps directly onto
/// `OrderDraft.specialInstructions` (PART 1) — never required, so
/// there is no validation here.
class SpecialInstructionField extends StatelessWidget {
  const SpecialInstructionField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: 'Special Instructions (optional)',
      hint: 'e.g. Handle carefully, separate the whites',
      controller: controller,
      prefixIcon: Icons.notes_outlined,
      maxLines: 3,
      textInputAction: TextInputAction.done,
    );
  }
}