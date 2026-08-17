import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/budgets/data/firestore/firestore_budget_repository.dart';
import 'package:spendsense/features/budgets/domain/entities/budget.dart';
import 'package:spendsense/features/budgets/domain/repositories/budget_repository.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';

/// THE swap point for the budgets domain.
final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  return FirestoreBudgetRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
});

final budgetListProvider = StreamProvider.autoDispose<List<Budget>>((ref) {
  return ref.watch(budgetRepositoryProvider).watchAll();
});

/// Spent is computed live from transactions on every read — never stored —
/// so editing a transaction immediately moves the progress bar.
final budgetProgressListProvider = Provider.autoDispose<List<BudgetProgress>>((ref) {
  final budgets = ref.watch(budgetListProvider).valueOrNull ?? const [];
  final transactions = ref.watch(transactionListProvider(null)).valueOrNull ?? const [];

  return budgets.map((budget) {
    var spent = Money.zero;
    for (final t in transactions) {
      if (t.type != TransactionType.expense) continue;
      if (t.categoryId != budget.categoryId) continue;
      if (budget.walletId != null && t.walletId != budget.walletId) continue;
      if (t.date.isBefore(budget.startDate) || t.date.isAfter(budget.endDate)) continue;
      spent = spent + t.amount;
    }
    return BudgetProgress(budget: budget, spent: spent);
  }).toList();
});

/// Fires a system notification the first time a budget crosses 80% and again
/// when it goes over 100%, driven by the same live "spent" figure the budget
/// screen shows — so any new expense (manual, receipt, recurring or AI) can
/// trigger it without each of those paths knowing about alerts.
///
/// Kept alive for the app's lifetime (watched from the dashboard) because the
/// already-alerted set is what stops it re-notifying on every rebuild.
final budgetAlertWatcherProvider = Provider<void>((ref) {
  final alerted = <String>{};

  ref.listen<List<BudgetProgress>>(budgetProgressListProvider, (previous, next) async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile == null || !profile.notificationPrefs.budgetAlerts) return;

    final categories = ref.read(categoryListProvider).valueOrNull ?? const [];
    final currency = profile.currencySymbol;

    for (final progress in next) {
      final threshold = progress.isOverBudget ? 'over' : (progress.fraction >= 0.8 ? 'near' : null);
      if (threshold == null) continue;

      final key = '${progress.budget.id}:$threshold';
      if (!alerted.add(key)) continue;

      final name = categories.firstWhereOrNull((c) => c.id == progress.budget.categoryId)?.name ?? 'this category';
      await ref.read(notificationServiceProvider).show(
            title: progress.isOverBudget ? 'Over budget: $name' : "You're close to your $name budget",
            body: progress.isOverBudget
                ? 'Spent ${progress.spent.format(currency)} of ${progress.budget.limitAmount.format(currency)}.'
                : '${progress.spent.format(currency)} of ${progress.budget.limitAmount.format(currency)} used '
                    '(${(progress.fraction * 100).round()}%).',
          );
    }

    // A budget that drops back below a threshold (transaction edited or
    // deleted, or a new period started) becomes eligible to alert again.
    alerted.removeWhere((key) {
      final id = key.split(':').first;
      final current = next.firstWhereOrNull((p) => p.budget.id == id);
      if (current == null) return true;
      return key.endsWith(':over') ? !current.isOverBudget : current.fraction < 0.8;
    });
  });
});
