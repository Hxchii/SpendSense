import 'package:flutter/material.dart';

/// Shown when a form's Save button is pressed with invalid/missing input,
/// so the no-op isn't silent — the user sees why nothing happened.
void showValidationSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}
