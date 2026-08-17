import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/firebase/firestore_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/recurring_bills/domain/repositories/recurring_bill_repository.dart';

class FirestoreRecurringBillRepository implements RecurringBillRepository {
  FirestoreRecurringBillRepository({required FirebaseFirestore firestore, required String uid})
      : _c = FirestoreCollection<RecurringBill>(
          firestore: firestore,
          uid: uid,
          name: 'recurring_bills',
          toJson: _toJson,
          fromJson: _fromJson,
        );

  final FirestoreCollection<RecurringBill> _c;

  static Map<String, dynamic> _toJson(RecurringBill b) => {
        'name': b.name,
        'categoryId': b.categoryId,
        'walletId': b.walletId,
        'amountMinor': b.amount.minorUnits,
        'frequency': b.frequency.name,
        'nextDueDate': Timestamp.fromDate(b.nextDueDate),
        'reminderDaysBefore': b.reminderDaysBefore,
        'autoLogTransaction': b.autoLogTransaction,
        'status': b.status.name,
        'totalOccurrences': b.totalOccurrences,
        'occurrencesPaid': b.occurrencesPaid,
        'lastPaymentTransactionId': b.lastPaymentTransactionId,
        'previousDueDate': b.previousDueDate == null ? null : Timestamp.fromDate(b.previousDueDate!),
      };

  static RecurringBill _fromJson(String id, Map<String, dynamic> json) => RecurringBill(
        id: id,
        name: json['name'] as String? ?? '',
        categoryId: json['categoryId'] as String? ?? '',
        walletId: json['walletId'] as String?,
        amount: Money((json['amountMinor'] as num?)?.toInt() ?? 0),
        frequency: BillFrequency.values.firstWhere(
          (f) => f.name == json['frequency'],
          orElse: () => BillFrequency.monthly,
        ),
        nextDueDate: _dateFrom(json['nextDueDate']),
        reminderDaysBefore: (json['reminderDaysBefore'] as num?)?.toInt() ?? 3,
        autoLogTransaction: json['autoLogTransaction'] as bool? ?? false,
        status: BillStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => BillStatus.active,
        ),
        totalOccurrences: (json['totalOccurrences'] as num?)?.toInt(),
        occurrencesPaid: (json['occurrencesPaid'] as num?)?.toInt() ?? 0,
        lastPaymentTransactionId: json['lastPaymentTransactionId'] as String?,
        previousDueDate: _dateOrNull(json['previousDueDate']),
      );

  static DateTime _dateFrom(Object? v) => _dateOrNull(v) ?? DateTime.now();

  /// Pending local writes surface the value we just wrote (a [DateTime]), and
  /// older/hand-edited documents can hold an ISO string, so accept all three.
  static DateTime? _dateOrNull(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Stream<List<RecurringBill>> watchAll() {
    return _c.watch().map((bills) {
      // Firestore returns documents in document-id order, which for random
      // UUIDs is arbitrary — sort so the list stays stable between rebuilds.
      final sorted = [...bills]..sort((a, b) {
          final byDue = a.nextDueDate.compareTo(b.nextDueDate);
          return byDue != 0 ? byDue : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return sorted;
    });
  }

  @override
  Future<RecurringBill> create(RecurringBillDraft draft) async {
    final bill = RecurringBill(
      id: newId(),
      name: draft.name,
      categoryId: draft.categoryId,
      walletId: draft.walletId,
      amount: draft.amount,
      frequency: draft.frequency,
      nextDueDate: draft.nextDueDate,
      reminderDaysBefore: draft.reminderDaysBefore,
      autoLogTransaction: draft.autoLogTransaction,
      totalOccurrences: draft.totalOccurrences,
    );
    await _c.put(bill.id, bill);
    return bill;
  }

  @override
  Future<RecurringBill> update(RecurringBill bill) async {
    await _c.put(bill.id, bill);
    return bill;
  }

  @override
  Future<RecurringBill> markPaidNow(String id) async {
    final bill = await _c.getById(id);
    if (bill == null) throw StateError('Recurring bill $id not found');

    final paidCount = bill.occurrencesPaid + 1;
    final justFinished = bill.totalOccurrences != null && paidCount >= bill.totalOccurrences!;
    final updated = bill.copyWith(
      // A finished installment plan stops recurring — no point advancing
      // to a due date that will never actually come due again.
      nextDueDate: justFinished ? bill.nextDueDate : bill.advancedDueDate(),
      occurrencesPaid: paidCount,
      status: justFinished ? BillStatus.completed : bill.status,
    );
    await _c.put(id, updated);
    return updated;
  }

  @override
  Future<void> delete(String id) => _c.delete(id);
}
