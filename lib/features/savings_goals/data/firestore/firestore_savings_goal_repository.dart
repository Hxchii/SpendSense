import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/firebase/firestore_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/savings_goals/domain/repositories/savings_goal_repository.dart';

class FirestoreSavingsGoalRepository implements SavingsGoalRepository {
  FirestoreSavingsGoalRepository({required FirebaseFirestore firestore, required String uid})
      : _c = FirestoreCollection<SavingsGoal>(
          firestore: firestore,
          uid: uid,
          name: 'savings_goals',
          toJson: _toJson,
          fromJson: _fromJson,
        );

  final FirestoreCollection<SavingsGoal> _c;

  /// Every optional field is written explicitly, nulls included — the undo and
  /// auto-contribute flows read "field is null" as real state, so a cleared
  /// field must come back null rather than fall back to a stale value.
  static Map<String, dynamic> _toJson(SavingsGoal g) => {
        'name': g.name,
        'targetAmountMinor': g.targetAmount.minorUnits,
        'currentAmountMinor': g.currentAmount.minorUnits,
        'targetDate': _timestampOrNull(g.targetDate),
        'iconKey': g.iconKey,
        'status': g.status.name,
        'reminderFrequency': g.reminderFrequency?.name,
        'nextReminderDate': _timestampOrNull(g.nextReminderDate),
        'walletId': g.walletId,
        'autoContributeAmountMinor': g.autoContributeAmount?.minorUnits,
        'autoContributeFrequency': g.autoContributeFrequency?.name,
        'nextContributionDate': _timestampOrNull(g.nextContributionDate),
        'lastContributionTransactionId': g.lastContributionTransactionId,
        'previousCurrentAmountMinor': g.previousCurrentAmount?.minorUnits,
        'previousNextContributionDate': _timestampOrNull(g.previousNextContributionDate),
      };

  static SavingsGoal _fromJson(String id, Map<String, dynamic> json) => SavingsGoal(
        id: id,
        name: json['name'] as String? ?? '',
        targetAmount: Money((json['targetAmountMinor'] as num?)?.toInt() ?? 0),
        currentAmount: Money((json['currentAmountMinor'] as num?)?.toInt() ?? 0),
        targetDate: _dateOrNull(json['targetDate']),
        iconKey: json['iconKey'] as String? ?? 'shield',
        status: GoalStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => GoalStatus.active,
        ),
        reminderFrequency: _frequencyOrNull(json['reminderFrequency']),
        nextReminderDate: _dateOrNull(json['nextReminderDate']),
        walletId: json['walletId'] as String?,
        autoContributeAmount: _moneyOrNull(json['autoContributeAmountMinor']),
        autoContributeFrequency: _frequencyOrNull(json['autoContributeFrequency']),
        nextContributionDate: _dateOrNull(json['nextContributionDate']),
        lastContributionTransactionId: json['lastContributionTransactionId'] as String?,
        previousCurrentAmount: _moneyOrNull(json['previousCurrentAmountMinor']),
        previousNextContributionDate: _dateOrNull(json['previousNextContributionDate']),
      );

  static Timestamp? _timestampOrNull(DateTime? date) => date == null ? null : Timestamp.fromDate(date);

  /// Pending local writes surface the value we just wrote (a [DateTime]), and
  /// older/hand-edited documents can hold an ISO string, so accept all three.
  static DateTime? _dateOrNull(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static Money? _moneyOrNull(Object? v) => v is num ? Money(v.toInt()) : null;

  static GoalReminderFrequency? _frequencyOrNull(Object? v) {
    if (v == null) return null;
    return GoalReminderFrequency.values.firstWhere(
      (f) => f.name == v,
      orElse: () => GoalReminderFrequency.monthly,
    );
  }

  @override
  Stream<List<SavingsGoal>> watchAll() {
    return _c.watch().map((goals) {
      // Firestore returns documents in document-id order, which for random
      // UUIDs is arbitrary — sort so the list stays stable between rebuilds.
      final sorted = [...goals]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return sorted;
    });
  }

  @override
  Future<SavingsGoal> create(SavingsGoalDraft draft) async {
    final goal = SavingsGoal(
      id: newId(),
      name: draft.name,
      targetAmount: draft.targetAmount,
      currentAmount: draft.currentAmount,
      targetDate: draft.targetDate,
      iconKey: draft.iconKey,
      reminderFrequency: draft.reminderFrequency,
      nextReminderDate: draft.nextReminderDate,
      walletId: draft.walletId,
      autoContributeAmount: draft.autoContributeAmount,
      autoContributeFrequency: draft.autoContributeFrequency,
      nextContributionDate: draft.nextContributionDate,
    );
    await _c.put(goal.id, goal);
    return goal;
  }

  @override
  Future<SavingsGoal> update(SavingsGoal goal) async {
    await _c.put(goal.id, goal);
    return goal;
  }

  @override
  Future<void> delete(String id) => _c.delete(id);
}
