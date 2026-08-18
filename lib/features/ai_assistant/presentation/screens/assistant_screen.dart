import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/config/environment.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/ai_assistant/application/ai_chat_providers.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_action.dart';
import 'package:spendsense/features/ai_assistant/domain/entities/ai_chat_message.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';

const _starterQuestions = [
  'How much did I spend on food this month?',
  'Which category has the highest expenses?',
  'How much should I save every month?',
  'Why am I exceeding my budget?',
];

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? text]) async {
    final message = text ?? _inputController.text;
    if (message.trim().isEmpty) return;
    _inputController.clear();
    await ref.read(aiChatControllerProvider).send(message);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final history = ref.watch(aiChatHistoryProvider).valueOrNull ?? const [];
    final sending = ref.watch(aiChatSendingProvider);
    final reversed = history.reversed.toList();
    final suggestions = history.isNotEmpty && history.last.role == ChatRole.assistant ? history.last.suggestions : const <String>[];
    final isLive = Environment.hasGeminiApiKey;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: colors.brandSoft, shape: BoxShape.circle),
                    child: Icon(LucideIcons.sparkles, size: 18, color: colors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Financial Assistant', style: Theme.of(context).textTheme.titleMedium),
                        Text(
                          isLive ? 'Online' : 'Not configured',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? _StarterView(onPick: _send)
                  : ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: reversed.length,
                      itemBuilder: (context, i) => _AnimatedEntrance(
                        // Keyed by message so each bubble animates once, on
                        // arrival, instead of replaying as the list rebuilds.
                        key: ValueKey(reversed[i].id),
                        child: _MessageBubble(message: reversed[i]),
                      ),
                    ),
            ),
            if (sending)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Align(alignment: Alignment.centerLeft, child: _ThinkingIndicator(colors: colors)),
              ),
            if (suggestions.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final s in suggestions)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ActionChip(label: Text(s), onPressed: () => _send(s)),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Ask about your spending…',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    onTap: sending ? null : () => _send(),
                    child: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sending ? colors.textMuted : colors.ink,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(LucideIcons.send, color: colors.paper, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StarterView extends StatelessWidget {
  const _StarterView({required this.onPick});
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      children: [
        Icon(LucideIcons.sparkles, size: 32, color: colors.brand),
        const SizedBox(height: 12),
        Text('Ask me about your money', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'I can see your spending, budgets, and goals — try one of these, or ask your own question.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: 20),
        for (final q in _starterQuestions)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => onPick(q),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(q, style: Theme.of(context).textTheme.bodyMedium)),
                    Icon(LucideIcons.arrowUpRight, size: 16, color: colors.textMuted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThinkingIndicator extends StatefulWidget {
  const _ThinkingIndicator({required this.colors});
  final AppColors colors;

  @override
  State<_ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<_ThinkingIndicator> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 4),
              Builder(builder: (context) {
                final phase = (_controller.value - i * 0.2) % 1.0;
                final scale = 0.6 + 0.4 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                return Opacity(
                  opacity: 0.4 + 0.6 * scale,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: widget.colors.textMuted, shape: BoxShape.circle),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }
}

/// Fades and lifts a chat bubble into place so new messages ease in rather
/// than snapping into existence.
class _AnimatedEntrance extends StatefulWidget {
  const _AnimatedEntrance({super.key, required this.child});
  final Widget child;

  @override
  State<_AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<_AnimatedEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  late final Animation<double> _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.12),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message});

  final AiChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.role == ChatRole.user;
    final colors = context.colors;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isUser ? colors.ink : colors.surfaceMuted,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.lg),
          topRight: const Radius.circular(AppRadius.lg),
          bottomLeft: Radius.circular(isUser ? AppRadius.lg : 4),
          bottomRight: Radius.circular(isUser ? 4 : AppRadius.lg),
        ),
      ),
      child: Text(
        message.content,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: isUser ? colors.paper : colors.textPrimary, height: 1.4),
      ),
    );

    if (isUser) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Align(alignment: Alignment.centerRight, child: bubble));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: colors.brandSoft, shape: BoxShape.circle),
            child: Icon(LucideIcons.sparkles, size: 13, color: colors.brand),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bubble,
                if (message.proposal != null) ...[
                  const SizedBox(height: 6),
                  _ProposalCard(message: message),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

IconData _iconForProposal(AiProposal proposal) => switch (proposal) {
      AiTransactionProposal p => p.type == TransactionType.income ? LucideIcons.arrowDown : LucideIcons.arrowUp,
      AiWalletProposal _ => LucideIcons.wallet,
      AiBudgetProposal _ => LucideIcons.pieChart,
      AiSavingsGoalProposal _ => LucideIcons.piggyBank,
      AiGoalContributionProposal _ => LucideIcons.piggyBank,
      AiRecurringBillProposal _ => LucideIcons.repeat,
    };

class _ProposalCard extends ConsumerStatefulWidget {
  const _ProposalCard({required this.message});
  final AiChatMessage message;

  @override
  ConsumerState<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<_ProposalCard> {
  bool _busy = false;

  Future<void> _confirm() => _run(() => ref.read(aiChatControllerProvider).confirmProposal(widget.message));

  Future<void> _dismiss() => _run(() => ref.read(aiChatControllerProvider).dismissProposal(widget.message));

  /// Both actions write over the network now, so a failure has to reset the
  /// button. Without the finally, one failed write left the card stuck
  /// spinning with no message and no way to retry.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, stackTrace) {
      developer.log('Proposal action failed', error: e, stackTrace: stackTrace, name: 'Assistant');
      if (mounted) showValidationSnackBar(context, "That didn't go through. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final proposal = widget.message.proposal!;
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final status = widget.message.proposalStatus;

    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_iconForProposal(proposal), size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  proposal.summary(currency),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          switch (status) {
            AiActionStatus.confirmed => Row(
                children: [
                  Icon(LucideIcons.circleCheck, size: 16, color: DataPalette.statusGood),
                  const SizedBox(width: 6),
                  Text('Added', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: DataPalette.statusGood)),
                ],
              ),
            AiActionStatus.dismissed => Text('Dismissed', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colors.textMuted)),
            AiActionStatus.proposed => Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _dismiss,
                      child: const Text('Dismiss'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _confirm,
                      child: Text(_busy ? '...' : 'Confirm'),
                    ),
                  ),
                ],
              ),
          },
        ],
      ),
    );
  }
}
