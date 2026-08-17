import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';

/// Local persistence for chat history — distinct from [AiAssistantRepository],
/// which performs the (fake-then-real) AI call.
abstract class AiChatRepository {
  Stream<List<AiChatMessage>> watchHistory();
  Future<AiChatMessage> addMessage(AiChatMessage message);
  Future<AiChatMessage> updateMessage(AiChatMessage message);
}
