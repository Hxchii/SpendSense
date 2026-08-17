import 'package:spendsense/core/utils/money.dart';

enum TransactionType { income, expense }

enum TransactionSource { manual, receipt, recurring }

class Transaction {
  const Transaction({
    required this.id,
    required this.walletId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.date,
    required this.createdAt,
    this.note = '',
    this.source = TransactionSource.manual,
    this.receiptId,
  });

  final String id;
  final String walletId;
  final String categoryId;
  final TransactionType type;
  final Money amount;
  final DateTime date;
  final DateTime createdAt;
  final String note;
  final TransactionSource source;
  final String? receiptId;

  /// Signed amount: positive for income, negative for expense — useful for
  /// summing straight into a running balance.
  Money get signedAmount => type == TransactionType.income ? amount : Money(-amount.minorUnits);

  Transaction copyWith({
    String? walletId,
    String? categoryId,
    TransactionType? type,
    Money? amount,
    DateTime? date,
    String? note,
  }) {
    return Transaction(
      id: id,
      walletId: walletId ?? this.walletId,
      categoryId: categoryId ?? this.categoryId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      createdAt: createdAt,
      note: note ?? this.note,
      source: source,
      receiptId: receiptId,
    );
  }
}

class TransactionDraft {
  const TransactionDraft({
    required this.walletId,
    required this.categoryId,
    required this.type,
    required this.amount,
    required this.date,
    this.note = '',
    this.source = TransactionSource.manual,
    this.receiptId,
  });

  final String walletId;
  final String categoryId;
  final TransactionType type;
  final Money amount;
  final DateTime date;
  final String note;
  final TransactionSource source;
  final String? receiptId;

  Transaction toEntity({required String id, required DateTime createdAt}) {
    return Transaction(
      id: id,
      walletId: walletId,
      categoryId: categoryId,
      type: type,
      amount: amount,
      date: date,
      createdAt: createdAt,
      note: note,
      source: source,
      receiptId: receiptId,
    );
  }
}

class TransactionFilter {
  const TransactionFilter({this.walletId, this.categoryId, this.type, this.from, this.to, this.searchText});

  final String? walletId;
  final String? categoryId;
  final TransactionType? type;
  final DateTime? from;
  final DateTime? to;
  final String? searchText;

  /// Contract: [from]/[to] are inclusive on both ends, compared by date only.
  bool matches(Transaction t) {
    if (walletId != null && t.walletId != walletId) return false;
    if (categoryId != null && t.categoryId != categoryId) return false;
    if (type != null && t.type != type) return false;
    if (from != null && t.date.isBefore(DateTime(from!.year, from!.month, from!.day))) return false;
    if (to != null && t.date.isAfter(DateTime(to!.year, to!.month, to!.day, 23, 59, 59))) return false;
    if (searchText != null && searchText!.isNotEmpty && !t.note.toLowerCase().contains(searchText!.toLowerCase())) {
      return false;
    }
    return true;
  }
}
