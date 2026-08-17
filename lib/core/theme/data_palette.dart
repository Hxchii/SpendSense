import 'package:flutter/material.dart';
import 'package:spendsense/core/utils/color_utils.dart';

/// Validated categorical/status palette (see the dataviz skill's
/// references/palette.md — used verbatim, not re-derived). Categorical hue
/// ORDER is the CVD-safety mechanism: assign slots in this fixed sequence,
/// never re-cycle or reorder per-entity.
class DataPalette {
  DataPalette._();

  static const List<(String light, String dark)> categoricalSlots = [
    ('#2a78d6', '#3987e5'), // 1 blue
    ('#eb6834', '#d95926'), // 2 orange
    ('#1baf7a', '#199e70'), // 3 aqua
    ('#eda100', '#c98500'), // 4 yellow
    ('#e87ba4', '#d55181'), // 5 magenta
    ('#008300', '#008300'), // 6 green
    ('#4a3aa7', '#9085e9'), // 7 violet
    ('#e34948', '#e66767'), // 8 red
  ];

  static const statusGood = Color(0xFF0CA30C);
  static const statusWarning = Color(0xFFFAB219);
  static const statusSerious = Color(0xFFEC835A);
  static const statusCritical = Color(0xFFD03B3B);

  /// Success/positive delta text (income) — distinct from statusGood, tuned
  /// for text contrast rather than fill contrast.
  static Color deltaGood(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF0CA30C) : const Color(0xFF006300);

  static Color categorical(int slot, Brightness brightness) {
    final (light, dark) = categoricalSlots[slot % categoricalSlots.length];
    return hexToColor(brightness == Brightness.dark ? dark : light);
  }

  /// Resolves a stored light-mode hex (as saved on a Category/Wallet entity)
  /// to its validated dark-mode step when the app is in dark mode, falling
  /// back to a literal parse for any hex outside the categorical table.
  static Color adaptive(String lightHex, Brightness brightness) {
    if (brightness == Brightness.light) return hexToColor(lightHex);
    for (final (light, dark) in categoricalSlots) {
      if (light.toUpperCase() == lightHex.toUpperCase()) return hexToColor(dark);
    }
    return hexToColor(lightHex);
  }
}
