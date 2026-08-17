import 'package:spendsense/features/budgets/domain/entities/budget.dart';

abstract class BudgetRepository {
  Stream<List<Budget>> watchAll();
  Future<Budget> create(BudgetDraft draft);
  Future<Budget> update(Budget budget);
  Future<void> delete(String id);
}
