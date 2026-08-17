import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';

abstract class RecurringBillRepository {
  Stream<List<RecurringBill>> watchAll();
  Future<RecurringBill> create(RecurringBillDraft draft);
  Future<RecurringBill> update(RecurringBill bill);
  Future<RecurringBill> markPaidNow(String id);
  Future<void> delete(String id);
}
