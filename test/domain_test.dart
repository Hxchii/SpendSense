import 'package:flutter_test/flutter_test.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';

RecurringBill _billDue(DateTime date, BillFrequency frequency) => RecurringBill(
      id: 'bill-1',
      name: 'Rent',
      categoryId: 'cat-bills',
      amount: Money.fromMajor(1000),
      frequency: frequency,
      nextDueDate: date,
    );

void main() {
  group('Money', () {
    test('stores minor units without floating-point drift', () {
      expect(Money.fromMajor(150.50).minorUnits, 15050);
      expect(Money.fromMajor(0.1).minorUnits + Money.fromMajor(0.2).minorUnits, 30);
    });

    test('arithmetic keeps expenses and income distinct', () {
      expect((Money.fromMajor(100) - Money.fromMajor(30)).minorUnits, 7000);
      expect((Money.fromMajor(10) - Money.fromMajor(25)).isNegative, isTrue);
    });
  });

  group('TransactionFilter equality', () {
    // Regression: without value equality this is the key of a .family stream
    // provider, so every rebuild minted a new provider and a new Firestore
    // listener — the Activity screen span in an infinite loading loop.
    test('equal field values compare equal', () {
      const a = TransactionFilter(type: TransactionType.expense, categoryId: 'cat-food');
      const b = TransactionFilter(type: TransactionType.expense, categoryId: 'cat-food');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing field values compare unequal', () {
      const a = TransactionFilter(type: TransactionType.expense);
      const b = TransactionFilter(type: TransactionType.income);
      expect(a, isNot(equals(b)));
    });
  });

  group('TransactionFilter.matches', () {
    Transaction txnOn(DateTime date) => Transaction(
          id: 't1',
          walletId: 'w1',
          categoryId: 'c1',
          type: TransactionType.expense,
          amount: Money.fromMajor(100),
          date: date,
          createdAt: date,
        );

    test('date range is inclusive on both ends', () {
      final filter = TransactionFilter(from: DateTime(2026, 3, 10), to: DateTime(2026, 3, 20));
      expect(filter.matches(txnOn(DateTime(2026, 3, 10))), isTrue);
      expect(filter.matches(txnOn(DateTime(2026, 3, 20, 18))), isTrue);
      expect(filter.matches(txnOn(DateTime(2026, 3, 9, 23, 59))), isFalse);
      expect(filter.matches(txnOn(DateTime(2026, 3, 21))), isFalse);
    });
  });

  group('RecurringBill.advancedDueDate', () {
    // Regression: DateTime(y, 2, 31) silently rolls into March, which walked a
    // bill due on the 31st permanently off its date (Jan 31 -> Mar 3 -> Apr 3).
    test('clamps to the last day of a shorter month', () {
      final jan31 = _billDue(DateTime(2026, 1, 31), BillFrequency.monthly);
      expect(jan31.advancedDueDate(), DateTime(2026, 2, 28));
    });

    test('keeps the day of month when it exists', () {
      final mar15 = _billDue(DateTime(2026, 3, 15), BillFrequency.monthly);
      expect(mar15.advancedDueDate(), DateTime(2026, 4, 15));
    });

    test('rolls the year over in December', () {
      final dec10 = _billDue(DateTime(2026, 12, 10), BillFrequency.monthly);
      expect(dec10.advancedDueDate(), DateTime(2027, 1, 10));
    });

    test('handles leap years', () {
      final jan31 = _billDue(DateTime(2028, 1, 31), BillFrequency.monthly);
      expect(jan31.advancedDueDate(), DateTime(2028, 2, 29));
    });

    test('weekly and yearly advance as expected', () {
      expect(
        _billDue(DateTime(2026, 3, 10), BillFrequency.weekly).advancedDueDate(),
        DateTime(2026, 3, 17),
      );
      expect(
        _billDue(DateTime(2026, 3, 10), BillFrequency.yearly).advancedDueDate(),
        DateTime(2027, 3, 10),
      );
    });
  });
}
