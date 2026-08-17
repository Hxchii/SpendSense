import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/financial_snapshot.dart';
import 'package:spendsense/features/budgets/application/budget_providers.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/savings_goals/application/savings_goal_providers.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

/// Builds an aggregated-only snapshot of the user's finances for the AI
/// assistant to read — never raw transaction line items.
///
/// Reads every repository directly with `await ...watchAll().first` rather
/// than `ref.watch()`-ing the app's `.autoDispose` list providers. Those get
/// disposed the moment nothing else is watching them (e.g. the moment you
/// navigate away from the screen that was showing them), so a `ref.watch()`
/// from here could cold-resubscribe and observe the stream's not-yet-emitted
/// initial state — an empty list — on the very same synchronous pass. That
/// was a real, reproduced bug: the assistant told the user it didn't see a
/// savings goal that was sitting right there, because the snapshot it was
/// actually handed was built before the goal list had arrived. Awaiting the
/// repository directly guarantees the real current data every time.
final financialSnapshotProvider = FutureProvider.autoDispose<FinancialSnapshot>((ref) async {
  // userProfileProvider is a plain (non-autoDispose) StreamProvider kept
  // alive for the app's whole lifetime, so watching it here doesn't have
  // the cold-resubscribe problem the other domains below do.
  final profile = await ref.read(userProfileRepositoryProvider).get();
  final categories = await ref.read(categoryRepositoryProvider).watchAll().first;
  final transactions = await ref.read(transactionRepositoryProvider).watchAll().first;
  final budgets = await ref.read(budgetRepositoryProvider).watchAll().first;
  final goals = await ref.read(savingsGoalRepositoryProvider).watchAll().first;
  final wallets = await ref.read(walletRepositoryProvider).watchAll().first;

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
  final categoryNameById = {for (final c in categories) c.id: c.name};

  var totalIncome = Money.zero;
  var totalExpense = Money.zero;
  final spendingByCategory = <String, Money>{};

  for (final t in transactions) {
    if (t.date.isBefore(monthStart) || t.date.isAfter(monthEnd)) continue;
    if (t.type == TransactionType.income) {
      totalIncome = totalIncome + t.amount;
    } else {
      totalExpense = totalExpense + t.amount;
      final name = categoryNameById[t.categoryId] ?? 'Other';
      spendingByCategory[name] = (spendingByCategory[name] ?? Money.zero) + t.amount;
    }
  }

  final currency = profile.currencySymbol;
  final budgetSummaries = budgets.map((budget) {
    var spent = Money.zero;
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.categoryId != budget.categoryId) continue;
      if (budget.walletId != null && t.walletId != budget.walletId) continue;
      if (t.date.isBefore(budget.startDate) || t.date.isAfter(budget.endDate)) continue;
      spent = spent + t.amount;
    }
    final categoryName = categoryNameById[budget.categoryId] ?? 'Category';
    if (spent > budget.limitAmount) {
      return '$categoryName: over by ${(spent - budget.limitAmount).format(currency)}';
    }
    return '$categoryName: ${spent.format(currency)} of ${budget.limitAmount.format(currency)}';
  }).toList();

  final goalSummaries = goals.map((g) {
    final remaining = g.targetAmount - g.currentAmount;
    return '${g.name}: ${g.currentAmount.format(currency)} of ${g.targetAmount.format(currency)} '
        '(${remaining.minorUnits <= 0 ? 'reached' : '${remaining.format(currency)} remaining'})';
  }).toList();

  return FinancialSnapshot(
    currencySymbol: currency,
    periodLabel: 'this month',
    totalIncome: totalIncome,
    totalExpense: totalExpense,
    spendingByCategory: spendingByCategory,
    budgetSummaries: budgetSummaries,
    goalSummaries: goalSummaries,
    expenseCategoryNames: categories.where((c) => c.type == CategoryType.expense).map((c) => c.name).toList(),
    incomeCategoryNames: categories.where((c) => c.type == CategoryType.income).map((c) => c.name).toList(),
    walletNames: wallets.map((w) => w.name).toList(),
    goalNames: goals.map((g) => g.name).toList(),
  );
});
