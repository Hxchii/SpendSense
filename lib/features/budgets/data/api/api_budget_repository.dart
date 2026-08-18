import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/api/api_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/budgets/domain/entities/budget.dart';
import 'package:spendsense/features/budgets/domain/repositories/budget_repository.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The serialization below is unchanged from the
/// Firestore version — only the collection wrapper differs.
class ApiBudgetRepository implements BudgetRepository {
  ApiBudgetRepository({required ApiClient client})
      : _c = ApiCollection<Budget>(
          client: client,
          name: 'budgets',
          toJson: _toJson,
          fromJson: _fromJson,
          idOf: (b) => b.id,
        );

  final ApiCollection<Budget> _c;

  static Map<String, dynamic> _toJson(Budget b) => {
        'categoryId': b.categoryId,
        'walletId': b.walletId,
        'period': b.period.name,
        'limitAmountMinor': b.limitAmount.minorUnits,
        'startDate': Timestamp.fromDate(b.startDate),
        'endDate': Timestamp.fromDate(b.endDate),
        'rollover': b.rollover,
      };

  static Budget _fromJson(String id, Map<String, dynamic> json) {
    final startDate = _dateFrom(json['startDate']) ?? DateTime.now();
    return Budget(
      id: id,
      categoryId: json['categoryId'] as String? ?? '',
      walletId: json['walletId'] as String?,
      period: BudgetPeriod.values.firstWhere(
        (p) => p.name == json['period'],
        orElse: () => BudgetPeriod.monthly,
      ),
      limitAmount: Money((json['limitAmountMinor'] as num?)?.toInt() ?? 0),
      startDate: startDate,
      endDate: _dateFrom(json['endDate']) ?? startDate,
      rollover: json['rollover'] as bool? ?? false,
    );
  }

  /// Firestore returns a [Timestamp], but a locally cached or still-pending
  /// write can surface the value as it was written client-side.
  static DateTime? _dateFrom(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    // toLocal: the API returns UTC ("...Z"), and DateTime.parse keeps it UTC.
    // Firestore used to hand back local times, so without this every date
    // reads a day early for anything before 08:00 in UTC+8.
    if (v is String) return DateTime.tryParse(v)?.toLocal();
    return null;
  }

  @override
  Stream<List<Budget>> watchAll() {
    // Firestore snapshots arrive in document-id order, so a stable order is
    // applied in Dart instead of a query that would need a composite index.
    return _c.watch().map((budgets) {
      budgets.sort((a, b) {
        final byStart = b.startDate.compareTo(a.startDate);
        if (byStart != 0) return byStart;
        return a.categoryId.compareTo(b.categoryId);
      });
      return budgets;
    });
  }

  @override
  Future<Budget> create(BudgetDraft draft) async {
    final budget = Budget(
      id: newId(),
      categoryId: draft.categoryId,
      walletId: draft.walletId,
      period: draft.period,
      limitAmount: draft.limitAmount,
      startDate: draft.startDate,
      endDate: draft.endDate,
      rollover: draft.rollover,
    );
    await _c.put(budget.id, budget);
    return budget;
  }

  @override
  Future<Budget> update(Budget budget) async {
    await _c.put(budget.id, budget);
    return budget;
  }

  @override
  Future<void> delete(String id) => _c.delete(id);
}
