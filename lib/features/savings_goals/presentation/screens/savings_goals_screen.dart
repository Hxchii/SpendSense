import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/savings_goals/application/savings_goal_providers.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class SavingsGoalsScreen extends ConsumerWidget {
  const SavingsGoalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(savingsGoalListProvider);
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Savings Goals')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/savings-goals/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.piggyBank,
              title: 'No savings goals yet',
              message: 'Set a target and track your progress toward it.',
            );
          }
          final active = list.where((g) => g.status != GoalStatus.completed).toList();
          final completed = list.where((g) => g.status == GoalStatus.completed).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final goal in active) ...[
                _GoalCard(goal: goal, currency: currency, onAddContribution: () => _addContribution(context, ref, goal.id)),
                const SizedBox(height: 12),
              ],
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Completed 🎉', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                for (final goal in completed) ...[
                  _CompletedGoalTile(goal: goal, currency: currency),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  static Future<void> _addContribution(BuildContext context, WidgetRef ref, String goalId) async {
    final wallets = ref.read(walletListProvider).valueOrNull ?? const <Wallet>[];
    if (wallets.isEmpty) {
      showValidationSnackBar(context, 'Add a wallet first — a contribution needs somewhere to deduct from.');
      return;
    }
    final controller = TextEditingController();
    String walletId = wallets.first.id;

    final result = await showDialog<(num amount, String walletId)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add contribution'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Amount'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: walletId,
                decoration: const InputDecoration(labelText: 'From wallet'),
                items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
                onChanged: (v) => setState(() => walletId = v ?? walletId),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final amount = num.tryParse(controller.text.trim());
                if (amount != null && amount > 0) Navigator.pop(context, (amount, walletId));
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      await ref.read(savingsGoalContributionControllerProvider).contributeManually(goalId, Money.fromMajor(result.$1), result.$2);
    }
  }
}

class _GoalCard extends ConsumerStatefulWidget {
  const _GoalCard({required this.goal, required this.currency, required this.onAddContribution});

  final SavingsGoal goal;
  final String currency;
  final Future<void> Function() onAddContribution;

  @override
  ConsumerState<_GoalCard> createState() => _GoalCardState();
}

class _GoalCardState extends ConsumerState<_GoalCard> {
  bool _processing = false;

  Future<void> _runGuarded(Future<void> Function() action) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final currency = widget.currency;
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.push('/savings-goals/edit', extra: goal),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(categoryIcon(goal.iconKey)),
                const SizedBox(width: 8),
                Expanded(child: Text(goal.name, style: Theme.of(context).textTheme.titleMedium)),
                Text('${(goal.fraction * 100).clamp(0, 999).round()}%'),
              ],
            ),
            const SizedBox(height: 12),
            ProgressBar(value: goal.fraction, favorHigh: true),
            const SizedBox(height: 6),
            Text('${goal.currentAmount.format(currency)} of ${goal.targetAmount.format(currency)}'),
            if (goal.isAutoContributing)
              Text(
                'Auto-contributes ${goal.autoContributeAmount!.format(currency)} ${goal.autoContributeFrequency == GoalReminderFrequency.weekly ? 'weekly' : 'monthly'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            const SizedBox(height: 8),
            // Wrap, not Row: both labels together overflow a 360dp screen
            // once the goal has a contribution to undo.
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              children: [
                if (goal.canUndoLastContribution)
                  TextButton(
                    onPressed: _processing
                        ? null
                        : () => _runGuarded(() => ref.read(savingsGoalContributionControllerProvider).undoLastContribution(goal.id)),
                    style: TextButton.styleFrom(foregroundColor: colors.textMuted),
                    child: const Text('Undo last'),
                  ),
                TextButton(
                  onPressed: _processing ? null : () => _runGuarded(widget.onAddContribution),
                  child: const Text('Add contribution'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedGoalTile extends ConsumerStatefulWidget {
  const _CompletedGoalTile({required this.goal, required this.currency});

  final SavingsGoal goal;
  final String currency;

  @override
  ConsumerState<_CompletedGoalTile> createState() => _CompletedGoalTileState();
}

class _CompletedGoalTileState extends ConsumerState<_CompletedGoalTile> {
  bool _processing = false;

  Future<void> _runGuarded(Future<void> Function() action) async {
    if (_processing) return;
    setState(() => _processing = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.goal;
    final currency = widget.currency;
    final colors = context.colors;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: DataPalette.statusGood),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${goal.name} — reached ${goal.targetAmount.format(currency)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          if (goal.canUndoLastContribution)
            TextButton(
              onPressed: _processing
                  ? null
                  : () => _runGuarded(() => ref.read(savingsGoalContributionControllerProvider).undoLastContribution(goal.id)),
              child: const Text('Undo'),
            ),
          IconButton(
            iconSize: 18,
            icon: const Icon(LucideIcons.trash2),
            onPressed: _processing ? null : () => _runGuarded(() => ref.read(savingsGoalRepositoryProvider).delete(goal.id)),
          ),
        ],
      ),
    );
  }
}
