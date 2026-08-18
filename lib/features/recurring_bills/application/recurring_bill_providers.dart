import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/recurring_bills/data/api/api_recurring_bill_repository.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/recurring_bills/domain/repositories/recurring_bill_repository.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

/// THE swap point for the recurring bills domain.
final recurringBillRepositoryProvider = Provider<RecurringBillRepository>((ref) {
  return ApiRecurringBillRepository(client: ref.watch(apiClientProvider));
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

  static bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<RecurringBill?> _billById(String id) async {
    final bills = await _ref.read(recurringBillRepositoryProvider).watchAll().first;
    return bills.firstWhereOrNull((b) => b.id == id);
  }

  /// [onlyIfDueOn] guards the sweep against paying a bill the user already
  /// paid manually in the window between the sweep reading the bill list and
  /// getting here — without it, both paths charge and the bill jumps two
  /// periods ahead.
  Future<void> payBill(String id, {DateTime? onlyIfDueOn}) async {
    final billRepo = _ref.read(recurringBillRepositoryProvider);
    final bill = await _billById(id);
    if (bill == null) return;
    if (onlyIfDueOn != null && !_isSameDay(bill.nextDueDate, onlyIfDueOn)) return;

    // Resolve the wallet BEFORE marking paid: marking first meant a bill with
    // no usable wallet still advanced its due date and occurrence count while
    // moving no money, and cleared its own undo state.
    String? walletId;
    if (bill.autoLogTransaction) {
      final wallets = await _ref.read(walletRepositoryProvider).watchAll().first;
      final explicit = wallets.firstWhereOrNull((w) => w.id == bill.walletId && !w.archived);
      walletId = explicit?.id ?? wallets.firstWhereOrNull((w) => !w.archived)?.id;
      if (walletId == null) return;
    }

    final previousDueDate = bill.nextDueDate;
    final updated = await billRepo.markPaidNow(id);

    String? transactionId;
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
      await payBill(bill.id, onlyIfDueOn: bill.nextDueDate);
      if (notificationsOn) {
        await _ref.read(notificationServiceProvider).show(
              title: '"${bill.name}" auto-paid',
              body: '${bill.amount.format(currency)} was deducted automatically.',
            );
      }
    }
  }
}
