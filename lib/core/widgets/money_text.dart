import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spendsense/core/utils/money.dart';

/// Large, tabular-figure money display — the display typeface (Space
/// Grotesk), used for hero balances and stat figures so numbers read with
/// more character than the body font. Never used for small inline amounts.
class MoneyText extends StatelessWidget {
  const MoneyText({
    super.key,
    required this.amount,
    required this.currencySymbol,
    this.style,
    this.color,
  });

  final Money amount;
  final String currencySymbol;
  final TextStyle? style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final base = style ?? Theme.of(context).textTheme.displaySmall;
    return Text(
      amount.format(currencySymbol),
      style: GoogleFonts.spaceGrotesk(
        textStyle: base,
        color: color ?? base?.color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
