import 'package:spendsense/core/utils/money.dart';

enum GoalStatus { active, completed, archived }

enum GoalReminderFrequency { weekly, monthly }

class SavingsGoal {
  const SavingsGoal({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.iconKey,
    this.targetDate,
    this.status = GoalStatus.active,
    this.reminderFrequency,
    this.nextReminderDate,
    this.walletId,
    this.autoContributeAmount,
    this.autoContributeFrequency,
    this.nextContributionDate,
    this.lastContributionTransactionId,
    this.previousCurrentAmount,
    this.previousNextContributionDate,
  });

  final String id;
  final String name;
  final Money targetAmount;
  final Money currentAmount;
  final DateTime? targetDate;
  final String iconKey;
  final GoalStatus status;

  // Null means no contribution reminders are set up for this goal.
  final GoalReminderFrequency? reminderFrequency;
  final DateTime? nextReminderDate;

  // Wallet auto-contributions are pulled from — only meaningful alongside
  // autoContributeAmount. Null autoContributeAmount means auto-contribute is
  // off entirely for this goal.
  final String? walletId;
  final Money? autoContributeAmount;
  final GoalReminderFrequency? autoContributeFrequency;
  final DateTime? nextContributionDate;

  // Set together, only for the most recent auto-contribution — lets that one
  // be undone (delete the linked transaction, restore the amount/schedule),
  // same mechanism as a recurring bill's last-payment undo.
  final String? lastContributionTransactionId;
  final Money? previousCurrentAmount;
  final DateTime? previousNextContributionDate;

  double get fraction =>
      targetAmount.minorUnits == 0 ? 0 : (currentAmount.minorUnits / targetAmount.minorUnits).clamp(0, 1.5);

  bool get isAutoContributing => autoContributeAmount != null;
  bool get canUndoLastContribution => lastContributionTransactionId != null;

  SavingsGoal copyWith({
    String? name,
    Money? targetAmount,
    Money? currentAmount,
    DateTime? targetDate,
    GoalStatus? status,
    String? iconKey,
    GoalReminderFrequency? reminderFrequency,
    DateTime? nextReminderDate,
    bool clearReminder = false,
    String? walletId,
    Money? autoContributeAmount,
    GoalReminderFrequency? autoContributeFrequency,
    DateTime? nextContributionDate,
    bool clearAutoContribute = false,
    String? lastContributionTransactionId,
    Money? previousCurrentAmount,
    DateTime? previousNextContributionDate,
    bool clearLastContribution = false,
  }) {
    return SavingsGoal(
      id: id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      targetDate: targetDate ?? this.targetDate,
      iconKey: iconKey ?? this.iconKey,
      status: status ?? this.status,
      reminderFrequency: clearReminder ? null : (reminderFrequency ?? this.reminderFrequency),
      nextReminderDate: clearReminder ? null : (nextReminderDate ?? this.nextReminderDate),
      walletId: clearAutoContribute ? null : (walletId ?? this.walletId),
      autoContributeAmount: clearAutoContribute ? null : (autoContributeAmount ?? this.autoContributeAmount),
      autoContributeFrequency: clearAutoContribute ? null : (autoContributeFrequency ?? this.autoContributeFrequency),
      nextContributionDate: clearAutoContribute ? null : (nextContributionDate ?? this.nextContributionDate),
      lastContributionTransactionId:
          clearLastContribution ? null : (lastContributionTransactionId ?? this.lastContributionTransactionId),
      previousCurrentAmount: clearLastContribution ? null : (previousCurrentAmount ?? this.previousCurrentAmount),
      previousNextContributionDate:
          clearLastContribution ? null : (previousNextContributionDate ?? this.previousNextContributionDate),
    );
  }
}

class SavingsGoalDraft {
  const SavingsGoalDraft({
    required this.name,
    required this.targetAmount,
    required this.iconKey,
    this.currentAmount = Money.zero,
    this.targetDate,
    this.reminderFrequency,
    this.nextReminderDate,
    this.walletId,
    this.autoContributeAmount,
    this.autoContributeFrequency,
    this.nextContributionDate,
  });

  final String name;
  final Money targetAmount;
  final Money currentAmount;
  final DateTime? targetDate;
  final String iconKey;
  final GoalReminderFrequency? reminderFrequency;
  final DateTime? nextReminderDate;
  final String? walletId;
  final Money? autoContributeAmount;
  final GoalReminderFrequency? autoContributeFrequency;
  final DateTime? nextContributionDate;
}
