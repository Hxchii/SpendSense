import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';

abstract class SavingsGoalRepository {
  Stream<List<SavingsGoal>> watchAll();
  Future<SavingsGoal> create(SavingsGoalDraft draft);
  Future<SavingsGoal> update(SavingsGoal goal);
  Future<void> delete(String id);
}
