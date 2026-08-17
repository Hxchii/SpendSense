import 'package:spendsense/core/utils/money.dart';

/// Aggregated-only snapshot of the user's finances, built fresh for each AI
/// request. Never includes raw transaction line items — aggregates only —
/// so the payload sent to the (future) cloud AI backend stays privacy-light.
class FinancialSnapshot {
  const FinancialSnapshot({
    required this.currencySymbol,
    required this.periodLabel,
    required this.totalIncome,
    required this.totalExpense,
    required this.spendingByCategory,
    required this.budgetSummaries,
    required this.goalSummaries,
    required this.expenseCategoryNames,
    required this.incomeCategoryNames,
    required this.walletNames,
    required this.goalNames,
  });

  final String currencySymbol;
  final String periodLabel;
  final Money totalIncome;
  final Money totalExpense;
  final Map<String, Money> spendingByCategory; // category name -> spent
  final List<String> budgetSummaries; // e.g. "Food: 320/500"
  final List<String> goalSummaries; // e.g. "Emergency Fund: 60% funded"

  /// Every category/wallet name that actually exists right now — not just
  /// ones with activity this period — so the assistant (real or fake) can
  /// only ever propose a transaction against something real.
  final List<String> expenseCategoryNames;
  final List<String> incomeCategoryNames;
  final List<String> walletNames;
  final List<String> goalNames;
}
