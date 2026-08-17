import 'package:spendsense/features/ai_assistant/domain/entities/ai_action.dart';

enum ChatRole { user, assistant }

class AiChatMessage {
  const AiChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.suggestions = const [],
    this.proposal,
    this.proposalStatus = AiActionStatus.proposed,
  });

  final String id;
  final ChatRole role;
  final String content;
  final DateTime createdAt;
  final List<String> suggestions;
  final AiProposal? proposal;
  final AiActionStatus proposalStatus;

  AiChatMessage copyWith({AiActionStatus? proposalStatus}) {
    return AiChatMessage(
      id: id,
      role: role,
      content: content,
      createdAt: createdAt,
      suggestions: suggestions,
      proposal: proposal,
      proposalStatus: proposalStatus ?? this.proposalStatus,
    );
  }
}

class AiChatResponse {
  const AiChatResponse({required this.reply, this.suggestions = const [], this.proposal});

  final String reply;
  final List<String> suggestions;
  final AiProposal? proposal;
}
