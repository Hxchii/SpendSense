import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/recurring_bills/data/firestore/firestore_recurring_bill_repository.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/recurring_bills/domain/repositories/recurring_bill_repository.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

/// THE swap point for the recurring bills domain.
final recurringBillRepositoryProvider = Provider<RecurringBillRepository>((ref) {
  return FirestoreRecurringBillRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
});

final recurringBillListProvider = StreamProvider.autoDispose<List<RecurringBill>>((ref) {
  return ref.watch(recurringBillRepositoryProvider).watchAll();
});

final recurringBillPaymentControllerProvider = Provider((ref) => RecurringBillPaymentController(ref));

/// One-shot per app session: on first read (dashboard load), auto-pays every
/// active bill with auto-deduct on whose due date has already arrived. Not
/// `.autoDispose`, so re-navigating to the dashboard never re-runs it —
/// mirrors what a real due-date cron would do, without needing a backend.
final dueRecurringBillsSweepProvider = FutureProvider<void>((ref) {
  return ref.read(recurringBillPaymentControllerProvider).runDueSweep();
});

/// Handles the money-moving side of recurring bills — creating the linked
/// expense transaction when a bill with auto-deduct is paid (manually or via
/// the due-date sweep), and reversing that single most recent payment on
/// request. Lives here rather than inside the repository because it spans
/// three domains (bills, transactions, wallets), matching how budget/goal
/// progress is combined at the application layer rather than inside a repo.
class RecurringBillPaymentController {
  RecurringBillPaymentController(this._ref);
  final Ref _ref;

  Future<RecurringBill?> _billById(String id) async {
    final bills = await _ref.read(recurringBillRepositoryProvider).watchAll().first;
    return bills.firstWhereOrNull((b) => b.id == id);
  }

  Future<void> payBill(String id) async {
    final billRepo = _ref.read(recurringBillRepositoryProvider);
    final bill = await _billById(id);
    if (bill == null) return;

    final previousDueDate = bill.nextDueDate;
    final updated = await billRepo.markPaidNow(id);

    String? transactionId;
    if (bill.autoLogTransaction) {
      final wallets = await _ref.read(walletRepositoryProvider).watchAll().first;
      final walletId = bill.walletId ?? wallets.firstWhereOrNull((w) => !w.archived)?.id;
      if (walletId != null) {
        final transaction = await _ref.read(transactionRepositoryProvider).create(TransactionDraft(
              walletId: walletId,
              categoryId: bill.categoryId,
              type: TransactionType.expense,
              amount: bill.amount,
              date: DateTime.now(),
              note: 'Auto-paid: ${bill.name}',
              source: TransactionSource.recurring,
            ));
        transactionId = transaction.id;
      }
    }

    await billRepo.update(updated.copyWith(
      lastPaymentTransactionId: transactionId,
      previousDueDate: transactionId == null ? null : previousDueDate,
      clearLastPayment: transactionId == null,
    ));
  }

  Future<void> undoLastPayment(String id) async {
    final billRepo = _ref.read(recurringBillRepositoryProvider);
    final bill = await _billById(id);
    if (bill == null || bill.lastPaymentTransactionId == null) return;

    await _ref.read(transactionRepositoryProvider).delete(bill.lastPaymentTransactionId!);
    await billRepo.update(bill.copyWith(
      occurrencesPaid: bill.occurrencesPaid > 0 ? bill.occurrencesPaid - 1 : 0,
      nextDueDate: bill.previousDueDate ?? bill.nextDueDate,
      status: BillStatus.active,
      clearLastPayment: true,
    ));
  }

  Future<void> runDueSweep() async {
    final bills = await _ref.read(recurringBillRepositoryProvider).watchAll().first;
    final today = DateTime.now();
    final dueToday = DateTime(today.year, today.month, today.day);
    final currency = _ref.read(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final notificationsOn = _ref.read(userProfileProvider).valueOrNull?.notificationPrefs.billReminders ?? false;
    for (final bill in bills) {
      if (!bill.autoLogTransaction) continue;
      if (bill.status != BillStatus.active) continue;
      final dueDate = DateTime(bill.nextDueDate.year, bill.nextDueDate.month, bill.nextDueDate.day);
      if (dueDate.isAfter(dueToday)) continue;
      await payBill(bill.id);
      if (notificationsOn) {
        await _ref.read(notificationServiceProvider).show(
              title: '"${bill.name}" auto-paid',
              body: '${bill.amount.format(currency)} was deducted automatically.',
            );
      }
    }
  }
}
