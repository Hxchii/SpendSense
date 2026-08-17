import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

enum AiActionStatus { proposed, confirmed, dismissed }

/// Anything the assistant can draft on the user's behalf, covering the same
/// ground as manual entry — a transaction, a new wallet/budget/goal, a
/// contribution toward a goal, or a recurring bill. Names (not IDs) are used
/// throughout since the AI reasons in terms of names — resolved to real IDs
/// only at confirm time, against whatever actually exists then.
sealed class AiProposal {
  const AiProposal();

  String summary(String currency);
}

class AiTransactionProposal extends AiProposal {
  const AiTransactionProposal({
    required this.type,
    required this.amount,
    required this.categoryName,
    required this.date,
    this.walletName,
    this.note = '',
  });

  final TransactionType type;
  final Money amount;
  final String categoryName;
  final String? walletName;
  final DateTime date;
  final String note;

  @override
  String summary(String currency) {
    final kind = type == TransactionType.income ? 'Income' : 'Expense';
    return '$kind · ${amount.format(currency)} · $categoryName${walletName != null ? ' · $walletName' : ''}';
  }
}

class AiWalletProposal extends AiProposal {
  const AiWalletProposal({required this.name, required this.type, required this.startingBalance});

  final String name;
  final WalletType type;
  final Money startingBalance;

  @override
  String summary(String currency) => 'New wallet · $name · starting balance ${startingBalance.format(currency)}';
}

class AiBudgetProposal extends AiProposal {
  const AiBudgetProposal({required this.categoryName, required this.limitAmount});

  final String categoryName;
  final Money limitAmount;

  @override
  String summary(String currency) => 'Monthly budget · $categoryName · limit ${limitAmount.format(currency)}';
}

class AiSavingsGoalProposal extends AiProposal {
  const AiSavingsGoalProposal({required this.name, required this.targetAmount, this.targetDate});

  final String name;
  final Money targetAmount;
  final DateTime? targetDate;

  @override
  String summary(String currency) => 'Savings goal · $name · target ${targetAmount.format(currency)}';
}

class AiGoalContributionProposal extends AiProposal {
  const AiGoalContributionProposal({required this.goalName, required this.amount});

  final String goalName;
  final Money amount;

  @override
  String summary(String currency) => 'Add ${amount.format(currency)} to $goalName';
}

class AiRecurringBillProposal extends AiProposal {
  const AiRecurringBillProposal({
    required this.name,
    required this.categoryName,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
    this.totalOccurrences,
    this.autoDeduct = false,
    this.walletName,
  });

  final String name;
  final String categoryName;
  final Money amount;
  final BillFrequency frequency;
  final DateTime nextDueDate;
  final String? walletName;
  // Set for a fixed-length installment plan (e.g. a 3-month downpayment) — the
  // bill stops recurring once this many payments are made, instead of forever.
  final int? totalOccurrences;
  // Auto-pays itself (creates the expense transaction, deducts the wallet) on
  // its due date instead of waiting for the user to mark it paid manually.
  final bool autoDeduct;

  @override
  String summary(String currency) {
    final base = 'Recurring bill · $name · ${amount.format(currency)} ${frequency.name}';
    final withOccurrences = totalOccurrences == null ? base : '$base · $totalOccurrences payments then stops';
    final withWallet = walletName == null ? withOccurrences : '$withOccurrences · $walletName';
    return autoDeduct ? '$withWallet · auto-deducts on due date' : withWallet;
  }
}
