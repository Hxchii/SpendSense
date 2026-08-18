import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/api/api_collection.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_action.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';
import 'package:spendsense/features/ai_assistant/domain/repositories/ai_chat_repository.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The serialization below is unchanged from the
/// Firestore version — only the collection wrapper differs.
class ApiAiChatRepository implements AiChatRepository {
  ApiAiChatRepository({required ApiClient client})
      : _c = ApiCollection<AiChatMessage>(
          client: client,
          name: 'ai_chat',
          toJson: _toJson,
          fromJson: _fromJson,
          idOf: (m) => m.id,
        );

  final ApiCollection<AiChatMessage> _c;

  static Map<String, dynamic> _toJson(AiChatMessage m) => {
        'role': m.role.name,
        'content': m.content,
        'createdAt': Timestamp.fromDate(m.createdAt),
        'suggestions': m.suggestions,
        'proposal': _proposalToJson(m.proposal),
        'proposalStatus': m.proposalStatus.name,
      };

  static AiChatMessage _fromJson(String id, Map<String, dynamic> json) => AiChatMessage(
        id: id,
        role: ChatRole.values.firstWhere(
          (r) => r.name == json['role'],
          orElse: () => ChatRole.assistant,
        ),
        content: json['content'] as String? ?? '',
        createdAt: _dateFrom(json['createdAt']) ?? DateTime.now(),
        suggestions: (json['suggestions'] as List<dynamic>?)?.cast<String>() ?? const [],
        proposal: _proposalFrom(json['proposal']),
        proposalStatus: AiActionStatus.values.firstWhere(
          (s) => s.name == json['proposalStatus'],
          orElse: () => AiActionStatus.proposed,
        ),
      );

  /// `AiProposal` is sealed, so each variant is stored with an `actionType`
  /// discriminator alongside its own payload and rebuilt from it on read.
  static Map<String, dynamic>? _proposalToJson(AiProposal? proposal) => switch (proposal) {
        null => null,
        final AiTransactionProposal p => {
            'actionType': 'transaction',
            'type': p.type.name,
            'amountMinor': p.amount.minorUnits,
            'categoryName': p.categoryName,
            'walletName': p.walletName,
            'date': Timestamp.fromDate(p.date),
            'note': p.note,
          },
        final AiWalletProposal p => {
            'actionType': 'wallet',
            'name': p.name,
            'type': p.type.name,
            'startingBalanceMinor': p.startingBalance.minorUnits,
          },
        final AiBudgetProposal p => {
            'actionType': 'budget',
            'categoryName': p.categoryName,
            'limitAmountMinor': p.limitAmount.minorUnits,
          },
        final AiSavingsGoalProposal p => {
            'actionType': 'savingsGoal',
            'name': p.name,
            'targetAmountMinor': p.targetAmount.minorUnits,
            'targetDate': p.targetDate == null ? null : Timestamp.fromDate(p.targetDate!),
          },
        final AiGoalContributionProposal p => {
            'actionType': 'goalContribution',
            'goalName': p.goalName,
            'amountMinor': p.amount.minorUnits,
          },
        final AiRecurringBillProposal p => {
            'actionType': 'recurringBill',
            'name': p.name,
            'categoryName': p.categoryName,
            'amountMinor': p.amount.minorUnits,
            'frequency': p.frequency.name,
            'nextDueDate': Timestamp.fromDate(p.nextDueDate),
            'walletName': p.walletName,
            'totalOccurrences': p.totalOccurrences,
            'autoDeduct': p.autoDeduct,
          },
      };

  static AiProposal? _proposalFrom(Object? value) {
    if (value is! Map) return null;
    final json = <String, dynamic>{for (final entry in value.entries) '${entry.key}': entry.value};
    switch (json['actionType']) {
      case 'transaction':
        return AiTransactionProposal(
          type: TransactionType.values.firstWhere(
            (t) => t.name == json['type'],
            orElse: () => TransactionType.expense,
          ),
          amount: Money((json['amountMinor'] as num?)?.toInt() ?? 0),
          categoryName: json['categoryName'] as String? ?? '',
          walletName: json['walletName'] as String?,
          date: _dateFrom(json['date']) ?? DateTime.now(),
          note: json['note'] as String? ?? '',
        );
      case 'wallet':
        return AiWalletProposal(
          name: json['name'] as String? ?? '',
          type: WalletType.values.firstWhere(
            (t) => t.name == json['type'],
            orElse: () => WalletType.cash,
          ),
          startingBalance: Money((json['startingBalanceMinor'] as num?)?.toInt() ?? 0),
        );
      case 'budget':
        return AiBudgetProposal(
          categoryName: json['categoryName'] as String? ?? '',
          limitAmount: Money((json['limitAmountMinor'] as num?)?.toInt() ?? 0),
        );
      case 'savingsGoal':
        return AiSavingsGoalProposal(
          name: json['name'] as String? ?? '',
          targetAmount: Money((json['targetAmountMinor'] as num?)?.toInt() ?? 0),
          targetDate: _dateFrom(json['targetDate']),
        );
      case 'goalContribution':
        return AiGoalContributionProposal(
          goalName: json['goalName'] as String? ?? '',
          amount: Money((json['amountMinor'] as num?)?.toInt() ?? 0),
        );
      case 'recurringBill':
        return AiRecurringBillProposal(
          name: json['name'] as String? ?? '',
          categoryName: json['categoryName'] as String? ?? '',
          amount: Money((json['amountMinor'] as num?)?.toInt() ?? 0),
          frequency: BillFrequency.values.firstWhere(
            (f) => f.name == json['frequency'],
            orElse: () => BillFrequency.monthly,
          ),
          nextDueDate: _dateFrom(json['nextDueDate']) ?? DateTime.now(),
          totalOccurrences: (json['totalOccurrences'] as num?)?.toInt(),
          autoDeduct: json['autoDeduct'] as bool? ?? false,
          walletName: json['walletName'] as String?,
        );
      default:
        return null;
    }
  }

  /// Firestore hands back a `Timestamp`, but a locally-cached write can still
  /// surface the raw `DateTime`, and older documents may hold an ISO string.
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
  Stream<List<AiChatMessage>> watchHistory() {
    return _c.watch().map(
          (messages) => [...messages]..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        );
  }

  @override
  Future<AiChatMessage> addMessage(AiChatMessage message) async {
    await _c.put(message.id, message);
    return message;
  }

  @override
  Future<AiChatMessage> updateMessage(AiChatMessage message) async {
    await _c.put(message.id, message);
    return message;
  }
}
