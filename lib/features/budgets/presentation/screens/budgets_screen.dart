import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/features/budgets/application/budget_providers.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressList = ref.watch(budgetProgressListProvider);
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(onPressed: () => context.push('/savings-goals'), icon: const Icon(LucideIcons.piggyBank)),
          IconButton(onPressed: () => context.push('/recurring-bills'), icon: const Icon(LucideIcons.repeat)),
          IconButton(onPressed: () => context.push('/reports'), icon: const Icon(LucideIcons.trendingUp)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/budgets/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: progressList.isEmpty
          ? const EmptyState(
              icon: LucideIcons.pieChart,
              title: 'No budgets yet',
              message: 'Set a monthly limit for a category to start tracking your progress.',
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: progressList.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final progress = progressList[i];
                final category = categories.where((c) => c.id == progress.budget.categoryId).firstOrNull;
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => context.push('/budgets/edit', extra: progress.budget),
                  child: SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(categoryIcon(category?.iconKey ?? 'other')),
                            const SizedBox(width: 8),
                            Expanded(child: Text(category?.name ?? 'Category', style: Theme.of(context).textTheme.titleMedium)),
                            Text(
                              '${progress.spent.format(currency)} / ${progress.budget.limitAmount.format(currency)}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ProgressBar(value: progress.fraction),
                        const SizedBox(height: 6),
                        Text(
                          progress.isOverBudget
                              ? 'Over by ${(progress.spent - progress.budget.limitAmount).format(currency)}'
                              : '${progress.remaining.format(currency)} remaining',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: progress.isOverBudget ? Theme.of(context).colorScheme.error : null,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
