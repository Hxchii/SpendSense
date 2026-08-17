// cloud_firestore also exports a `Transaction` (its write-batch handle), so it
// is hidden here to keep the domain entity unambiguous.
import 'package:cloud_firestore/cloud_firestore.dart' hide Transaction;
import 'package:spendsense/core/firebase/firestore_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/transactions/domain/repositories/transaction_repository.dart';

class FirestoreTransactionRepository implements TransactionRepository {
  FirestoreTransactionRepository({required FirebaseFirestore firestore, required String uid})
      : _c = FirestoreCollection<Transaction>(
          firestore: firestore,
          uid: uid,
          name: 'transactions',
          toJson: _toJson,
          fromJson: _fromJson,
        );

  final FirestoreCollection<Transaction> _c;

  static Map<String, dynamic> _toJson(Transaction t) => {
        'walletId': t.walletId,
        'categoryId': t.categoryId,
        'type': t.type.name,
        'amountMinor': t.amount.minorUnits,
        'date': Timestamp.fromDate(t.date),
        'createdAt': Timestamp.fromDate(t.createdAt),
        'note': t.note,
        'source': t.source.name,
        'receiptId': t.receiptId,
      };

  static Transaction _fromJson(String id, Map<String, dynamic> json) {
    final createdAt = _dateFrom(json['createdAt']) ?? DateTime.now();
    return Transaction(
      id: id,
      walletId: json['walletId'] as String? ?? '',
      categoryId: json['categoryId'] as String? ?? '',
      type: TransactionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => TransactionType.expense,
      ),
      amount: Money((json['amountMinor'] as num?)?.toInt() ?? 0),
      date: _dateFrom(json['date']) ?? createdAt,
      createdAt: createdAt,
      note: json['note'] as String? ?? '',
      source: TransactionSource.values.firstWhere(
        (s) => s.name == json['source'],
        orElse: () => TransactionSource.manual,
      ),
      receiptId: json['receiptId'] as String?,
    );
  }

  /// Firestore returns a [Timestamp], but a locally cached or still-pending
  /// write can surface the value as it was written client-side.
  static DateTime? _dateFrom(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  @override
  Stream<List<Transaction>> watchAll({TransactionFilter? filter}) {
    // Filtering and sorting run in Dart so the DESC date / DESC createdAt
    // contract holds for every filter combination without a composite index.
    return _c.watch().map((transactions) {
      final visible = filter == null ? transactions : transactions.where(filter.matches).toList();
      visible.sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        return b.createdAt.compareTo(a.createdAt);
      });
      return visible;
    });
  }

  @override
  Future<Transaction?> getById(String id) => _c.getById(id);

  @override
  Future<Transaction> create(TransactionDraft draft) async {
    final transaction = draft.toEntity(id: newId(), createdAt: DateTime.now());
    await _c.put(transaction.id, transaction);
    return transaction;
  }

  @override
  Future<Transaction> update(Transaction transaction) async {
    await _c.put(transaction.id, transaction);
    return transaction;
  }

  @override
  Future<void> delete(String id) => _c.delete(id);
}
