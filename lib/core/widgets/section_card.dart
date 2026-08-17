import 'package:flutter/material.dart';
import 'package:spendsense/core/theme/data_palette.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// Progress toward a limit (budget) or target (savings goal). Color follows
/// the reserved status palette — never a bespoke hue. The two use cases have
/// OPPOSITE meanings at 100%+, so which one applies is explicit per caller:
/// - Budget (default, [favorHigh] false): over the limit is bad — good below
///   80%, warning 80-99% (always paired with a visible amount/percentage
///   label by the caller, per the palette's relief rule), critical at/over
///   100%.
/// - Savings goal ([favorHigh] true): reaching the target is the whole
///   point — warning (still saving) below 100%, good at/over 100%.
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.favorHigh = false});

  /// 0.0 - 1.0+ (values above 1.0 are clamped visually but color signals overage)
  final double value;
  final bool favorHigh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = favorHigh
        ? (value >= 1.0 ? DataPalette.statusGood : DataPalette.statusWarning)
        : (value >= 1.0
            ? DataPalette.statusCritical
            : value >= 0.8
                ? DataPalette.statusWarning
                : DataPalette.statusGood);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(
        value: value.clamp(0.0, 1.0),
        minHeight: 8,
        backgroundColor: scheme.surfaceContainerHighest,
        color: color,
      ),
    );
  }
}
