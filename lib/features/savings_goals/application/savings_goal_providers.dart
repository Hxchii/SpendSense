import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/seed/seed_ids.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/reminders/application/reminder_providers.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/savings_goals/data/api/api_savings_goal_repository.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/savings_goals/domain/repositories/savings_goal_repository.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

/// THE swap point for the savings goals domain.
final savingsGoalRepositoryProvider = Provider<SavingsGoalRepository>((ref) {
  return ApiSavingsGoalRepository(client: ref.watch(apiClientProvider));
});

final savingsGoalListProvider = StreamProvider.autoDispose<List<SavingsGoal>>((ref) {
  return ref.watch(savingsGoalRepositoryProvider).watchAll();
});

DateTime _advanceReminderDate(DateTime from, GoalReminderFrequency frequency) {
  return frequency == GoalReminderFrequency.weekly
      ? from.add(const Duration(days: 7))
      : _sameDayNextMonth(from);
}

/// Clamps to the last day of the target month — DateTime(y, 2, 31) rolls
/// into March, which would walk a monthly schedule off its date permanently.
DateTime _sameDayNextMonth(DateTime from) {
  final year = from.month == 12 ? from.year + 1 : from.year;
  final month = from.month == 12 ? 1 : from.month + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, from.day.clamp(1, lastDay));
}

/// One-shot per app session, same pattern as [dueRecurringBillsSweepProvider]
/// — on first read (dashboard load), posts a contribution-nudge Reminder for
/// every active goal whose reminder schedule has come due, then advances it.
final dueGoalRemindersSweepProvider = FutureProvider<void>((ref) async {
  // Runs AFTER the contribution sweep, never alongside it. Both write whole
  // goal documents with set(), so overlapping them let the reminder's write
  // clobber a contribution that had just been applied — reverting the goal's
  // balance while leaving the expense transaction behind, and re-charging on
  // the next launch because nextContributionDate went back too.
  await ref.watch(dueGoalAutoContributionsSweepProvider.future);

  final goalRepo = ref.read(savingsGoalRepositoryProvider);
  final reminderRepo = ref.read(reminderRepositoryProvider);
  final currency = ref.read(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
  final goals = await goalRepo.watchAll().first;
  final today = DateTime.now();
  final dueToday = DateTime(today.year, today.month, today.day);

  for (final goal in goals) {
    if (goal.reminderFrequency == null || goal.nextReminderDate == null) continue;
    if (goal.status != GoalStatus.active) continue;
    final reminderDate = goal.nextReminderDate!;
    final dueDate = DateTime(reminderDate.year, reminderDate.month, reminderDate.day);
    if (dueDate.isAfter(dueToday)) continue;

    final title = 'Add to "${goal.name}"';
    final body = '${(goal.fraction * 100).clamp(0, 100).round()}% of ${goal.targetAmount.format(currency)} saved so far — keep it going!';
    await reminderRepo.create(
      Reminder(id: newId(), type: ReminderType.goalReminder, title: title, body: body, scheduledFor: today, relatedId: goal.id),
    );
    if (ref.read(userProfileProvider).valueOrNull?.notificationPrefs.savingsGoalReminders ?? false) {
      await ref.read(notificationServiceProvider).show(title: title, body: body);
    }
    await goalRepo.update(goal.copyWith(nextReminderDate: _advanceReminderDate(reminderDate, goal.reminderFrequency!)));
  }
});

final savingsGoalContributionControllerProvider = Provider((ref) => SavingsGoalContributionController(ref));

/// One-shot per app session, same pattern as [dueRecurringBillsSweepProvider]
/// — on first read (dashboard load), auto-contributes to every active goal
/// whose auto-contribute schedule has come due.
final dueGoalAutoContributionsSweepProvider = FutureProvider<void>((ref) {
  return ref.read(savingsGoalContributionControllerProvider).runDueSweep();
});

/// Handles the money-moving side of auto-contribute — creating the linked
/// expense transaction when a scheduled contribution fires (manually or via
/// the due-date sweep), and reversing that single most recent contribution
/// on request. Mirrors [RecurringBillPaymentController] in
/// recurring_bill_providers.dart — same shape, applied to goals.
class SavingsGoalContributionController {
  SavingsGoalContributionController(this._ref);
  final Ref _ref;

  Future<SavingsGoal?> _goalById(String id) async {
    final goals = await _ref.read(savingsGoalRepositoryProvider).watchAll().first;
    return goals.firstWhereOrNull((g) => g.id == id);
  }

  Future<void> contributeNow(String id) async {
    final goal = await _goalById(id);
    if (goal == null || goal.autoContributeAmount == null) return;

    final wallets = await _ref.read(walletRepositoryProvider).watchAll().first;
    final walletId = goal.walletId ?? wallets.firstWhereOrNull((w) => !w.archived)?.id;
    if (walletId == null) return;

    await _applyContribution(
      goal,
      amount: goal.autoContributeAmount!,
      walletId: walletId,
      note: 'Auto-contribute: ${goal.name}',
      source: TransactionSource.recurring,
      nextContributionDate:
          _advanceReminderDate(goal.nextContributionDate ?? DateTime.now(), goal.autoContributeFrequency ?? GoalReminderFrequency.monthly),
    );
  }

  /// A manually-entered "Add contribution" — same money-moving mechanics as
  /// an auto-contribution (real linked transaction, undoable), just
  /// user-triggered with a user-chosen amount/wallet instead of the
  /// configured auto-contribute schedule.
  Future<void> contributeManually(String id, Money amount, String walletId) async {
    final goal = await _goalById(id);
    if (goal == null) return;
    await _applyContribution(
      goal,
      amount: amount,
      walletId: walletId,
      note: 'Contribution: ${goal.name}',
      source: TransactionSource.manual,
      nextContributionDate: goal.nextContributionDate,
    );
  }

  Future<void> _applyContribution(
    SavingsGoal goal, {
    required Money amount,
    required String walletId,
    required String note,
    required TransactionSource source,
    required DateTime? nextContributionDate,
  }) async {
    final goalRepo = _ref.read(savingsGoalRepositoryProvider);
    final categories =
        await _ref.read(categoryRepositoryProvider).watchAll(type: CategoryType.expense, includeArchived: true).first;
    // Falls back by id first, then by name, so an account created before the
    // Savings category existed still resolves something sensible.
    final categoryId = categories.firstWhereOrNull((c) => c.id == SeedIds.catSavings)?.id ??
        categories.firstWhereOrNull((c) => c.name.toLowerCase() == 'savings')?.id ??
        categories.firstWhereOrNull((c) => c.id == SeedIds.catOther)?.id ??
        categories.firstOrNull?.id;
    if (categoryId == null) return;
    final transaction = await _ref.read(transactionRepositoryProvider).create(TransactionDraft(
          walletId: walletId,
          categoryId: categoryId,
          type: TransactionType.expense,
          amount: amount,
          date: DateTime.now(),
          note: note,
          source: source,
        ));

    final previousCurrentAmount = goal.currentAmount;
    final previousNextContributionDate = goal.nextContributionDate;
    final newAmount = goal.currentAmount + amount;
    await goalRepo.update(goal.copyWith(
      currentAmount: newAmount,
      status: newAmount >= goal.targetAmount ? GoalStatus.completed : goal.status,
      nextContributionDate: nextContributionDate,
      lastContributionTransactionId: transaction.id,
      previousCurrentAmount: previousCurrentAmount,
      previousNextContributionDate: previousNextContributionDate,
    ));
  }

  Future<void> undoLastContribution(String id) async {
    final goalRepo = _ref.read(savingsGoalRepositoryProvider);
    final goal = await _goalById(id);
    if (goal == null || goal.lastContributionTransactionId == null) return;

    await _ref.read(transactionRepositoryProvider).delete(goal.lastContributionTransactionId!);
    final restoredAmount = goal.previousCurrentAmount ?? goal.currentAmount;
    await goalRepo.update(goal.copyWith(
      currentAmount: restoredAmount,
      // Derive from the restored amount rather than assuming active — if
      // the goal had already legitimately hit its target before this
      // contribution (e.g. an AI-added extra contribution on top of an
      // already-complete goal), undoing it must not un-complete it.
      status: restoredAmount >= goal.targetAmount ? GoalStatus.completed : GoalStatus.active,
      nextContributionDate: goal.previousNextContributionDate ?? goal.nextContributionDate,
      clearLastContribution: true,
    ));
  }

  Future<void> runDueSweep() async {
    final goals = await _ref.read(savingsGoalRepositoryProvider).watchAll().first;
    final today = DateTime.now();
    final dueToday = DateTime(today.year, today.month, today.day);
    final currency = _ref.read(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final notificationsOn = _ref.read(userProfileProvider).valueOrNull?.notificationPrefs.savingsGoalReminders ?? false;
    for (final goal in goals) {
      if (goal.autoContributeAmount == null) continue;
      if (goal.status != GoalStatus.active) continue;
      final contributionDate = goal.nextContributionDate;
      if (contributionDate == null) continue;
      final dueDate = DateTime(contributionDate.year, contributionDate.month, contributionDate.day);
      if (dueDate.isAfter(dueToday)) continue;
      await contributeNow(goal.id);
      if (notificationsOn) {
        await _ref.read(notificationServiceProvider).show(
              title: 'Auto-contributed to "${goal.name}"',
              body: '${goal.autoContributeAmount!.format(currency)} was added automatically.',
            );
      }
    }
  }
}
