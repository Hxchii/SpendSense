import 'package:spendsense/core/utils/money.dart';

enum BillFrequency { weekly, monthly, yearly }

enum BillStatus { active, paused, completed }

class RecurringBill {
  const RecurringBill({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
    this.reminderDaysBefore = 3,
    this.autoLogTransaction = false,
    this.status = BillStatus.active,
    this.walletId,
    this.totalOccurrences,
    this.occurrencesPaid = 0,
    this.lastPaymentTransactionId,
    this.previousDueDate,
  });

  final String id;
  final String name;
  final String categoryId;
  final String? walletId;
  final Money amount;
  final BillFrequency frequency;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool autoLogTransaction;
  final BillStatus status;

  /// Null means "ongoing" (a subscription with no fixed end). Set for
  /// installment-style bills (e.g. a 3-month downpayment plan) so the bill
  /// knows when to stop instead of recurring forever.
  final int? totalOccurrences;
  final int occurrencesPaid;

  /// Set together, only for the most recent payment — lets that one payment
  /// be undone (e.g. an auto-deduction that turns out to be premature) by
  /// deleting the linked transaction and restoring [previousDueDate]. A new
  /// payment overwrites both, so only the latest payment is ever revertible.
  final String? lastPaymentTransactionId;
  final DateTime? previousDueDate;

  bool get isInstallmentPlan => totalOccurrences != null;
  int? get remainingOccurrences => totalOccurrences == null ? null : (totalOccurrences! - occurrencesPaid).clamp(0, totalOccurrences!);
  int get daysUntilDue => nextDueDate.difference(DateTime.now()).inDays;
  bool get canUndoLastPayment => lastPaymentTransactionId != null;

  DateTime advancedDueDate() {
    switch (frequency) {
      case BillFrequency.weekly:
        return nextDueDate.add(const Duration(days: 7));
      case BillFrequency.monthly:
        return DateTime(nextDueDate.year, nextDueDate.month + 1, nextDueDate.day);
      case BillFrequency.yearly:
        return DateTime(nextDueDate.year + 1, nextDueDate.month, nextDueDate.day);
    }
  }

  RecurringBill copyWith({
    String? name,
    String? categoryId,
    String? walletId,
    Money? amount,
    BillFrequency? frequency,
    DateTime? nextDueDate,
    int? reminderDaysBefore,
    bool? autoLogTransaction,
    BillStatus? status,
    int? totalOccurrences,
    bool clearTotalOccurrences = false,
    int? occurrencesPaid,
    String? lastPaymentTransactionId,
    DateTime? previousDueDate,
    bool clearLastPayment = false,
  }) {
    return RecurringBill(
      id: id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      walletId: walletId ?? this.walletId,
      amount: amount ?? this.amount,
      frequency: frequency ?? this.frequency,
      nextDueDate: nextDueDate ?? this.nextDueDate,
      reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
      autoLogTransaction: autoLogTransaction ?? this.autoLogTransaction,
      status: status ?? this.status,
      totalOccurrences: clearTotalOccurrences ? null : (totalOccurrences ?? this.totalOccurrences),
      occurrencesPaid: occurrencesPaid ?? this.occurrencesPaid,
      lastPaymentTransactionId: clearLastPayment ? null : (lastPaymentTransactionId ?? this.lastPaymentTransactionId),
      previousDueDate: clearLastPayment ? null : (previousDueDate ?? this.previousDueDate),
    );
  }
}

class RecurringBillDraft {
  const RecurringBillDraft({
    required this.name,
    required this.categoryId,
    required this.amount,
    required this.frequency,
    required this.nextDueDate,
    this.reminderDaysBefore = 3,
    this.autoLogTransaction = false,
    this.walletId,
    this.totalOccurrences,
  });

  final String name;
  final String categoryId;
  final String? walletId;
  final Money amount;
  final BillFrequency frequency;
  final DateTime nextDueDate;
  final int reminderDaysBefore;
  final bool autoLogTransaction;
  final int? totalOccurrences;
}
