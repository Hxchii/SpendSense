import 'package:spendsense/features/transactions/domain/entities/transaction.dart';

/// Contract: [watchAll] emits sorted DESC by date, then by createdAt DESC
/// for same-day transactions. Date-range filters in [TransactionFilter] are
/// inclusive on both ends.
abstract class TransactionRepository {
  Stream<List<Transaction>> watchAll({TransactionFilter? filter});
  Future<Transaction?> getById(String id);
  Future<Transaction> create(TransactionDraft draft);
  Future<Transaction> update(Transaction transaction);
  Future<void> delete(String id);
}
