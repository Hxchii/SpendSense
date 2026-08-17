import 'package:intl/intl.dart';

/// Represents a monetary amount as integer minor units (e.g. centavos)
/// to avoid floating-point rounding errors in financial calculations.
class Money {
  const Money(this.minorUnits);

  factory Money.fromMajor(num major) => Money((major * 100).round());

  final int minorUnits;

  double get major => minorUnits / 100;

  Money operator +(Money other) => Money(minorUnits + other.minorUnits);
  Money operator -(Money other) => Money(minorUnits - other.minorUnits);
  bool operator >(Money other) => minorUnits > other.minorUnits;
  bool operator >=(Money other) => minorUnits >= other.minorUnits;
  bool operator <(Money other) => minorUnits < other.minorUnits;
  bool operator <=(Money other) => minorUnits <= other.minorUnits;

  bool get isNegative => minorUnits < 0;

  static const zero = Money(0);

  String format(String currencySymbol) {
    final formatter = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2);
    return formatter.format(major);
  }

  @override
  bool operator ==(Object other) => other is Money && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;
}
