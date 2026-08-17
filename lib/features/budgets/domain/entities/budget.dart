import 'package:spendsense/core/utils/money.dart';

enum BudgetPeriod { weekly, monthly, custom }

class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.period,
    required this.limitAmount,
    required this.startDate,
    required this.endDate,
    this.walletId,
    this.rollover = false,
  });

  final String id;
  final String categoryId;
  final String? walletId; // null = applies across all wallets
  final BudgetPeriod period;
  final Money limitAmount;
  final DateTime startDate;
  final DateTime endDate;
  final bool rollover;

  Budget copyWith({String? categoryId, BudgetPeriod? period, Money? limitAmount, DateTime? startDate, DateTime? endDate, bool? rollover}) {
    return Budget(
      id: id,
      categoryId: categoryId ?? this.categoryId,
      walletId: walletId,
      period: period ?? this.period,
      limitAmount: limitAmount ?? this.limitAmount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rollover: rollover ?? this.rollover,
    );
  }
}

class BudgetDraft {
  const BudgetDraft({
    required this.categoryId,
    required this.period,
    required this.limitAmount,
    required this.startDate,
    required this.endDate,
    this.walletId,
    this.rollover = false,
  });

  final String categoryId;
  final String? walletId;
  final BudgetPeriod period;
  final Money limitAmount;
  final DateTime startDate;
  final DateTime endDate;
  final bool rollover;
}

/// Spent is always computed live from TransactionRepository — never stored —
/// so it can never go stale relative to the actual transaction history.
class BudgetProgress {
  const BudgetProgress({required this.budget, required this.spent});

  final Budget budget;
  final Money spent;

  Money get remaining => budget.limitAmount - spent;
  double get fraction => budget.limitAmount.minorUnits == 0
      ? 0
      : spent.minorUnits / budget.limitAmount.minorUnits;
  bool get isOverBudget => spent > budget.limitAmount;
}
