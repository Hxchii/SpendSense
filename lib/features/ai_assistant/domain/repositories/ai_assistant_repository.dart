import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/financial_snapshot.dart';

abstract class AiAssistantRepository {
  Future<AiChatResponse> ask({
    required String message,
    required List<AiChatMessage> history,
    required FinancialSnapshot snapshot,
  });
}
