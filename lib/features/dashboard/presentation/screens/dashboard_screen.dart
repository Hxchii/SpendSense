import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/core/widgets/money_text.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/features/budgets/application/budget_providers.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/recurring_bills/application/recurring_bill_providers.dart';
import 'package:spendsense/features/reminders/application/reminder_providers.dart';
import 'package:spendsense/features/reminders/domain/entities/reminder.dart';
import 'package:spendsense/features/savings_goals/application/savings_goal_providers.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/transactions/presentation/widgets/transaction_tile.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Cached (non-autoDispose) provider — this only actually runs once per
    // app session, the closest a mock-data app gets to a due-date cron.
    ref.watch(dueRecurringBillsSweepProvider);
    ref.watch(dueGoalRemindersSweepProvider);
    ref.watch(dueGoalAutoContributionsSweepProvider);
    ref.watch(budgetAlertWatcherProvider);
    final colors = context.colors;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final wallets =
        ref.watch(walletListProvider).valueOrNull ?? const <Wallet>[];
    final totalBalance = ref.watch(totalBalanceProvider);
    final transactions =
        ref.watch(transactionListProvider(null)).valueOrNull ??
        const <Transaction>[];
    final budgetProgress = ref.watch(budgetProgressListProvider);
    final bills = ref.watch(recurringBillListProvider).valueOrNull ?? const [];
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final currency = profile?.currencySymbol ?? '₱';
    final dueSoonBill = bills
        .where((b) => b.daysUntilDue <= b.reminderDaysBefore)
        .sorted((a, b) => a.daysUntilDue.compareTo(b.daysUntilDue))
        .firstOrNull;
    final reminders = ref.watch(reminderListProvider).valueOrNull ?? const <Reminder>[];
    final goals = ref.watch(savingsGoalListProvider).valueOrNull ?? const <SavingsGoal>[];
    final goalReminder = reminders
        .where((r) => r.type == ReminderType.goalReminder && !r.read)
        // The reminder's text ("50% saved so far") is baked in at creation
        // time — if the goal it's about has since been completed (or
        // deleted), that text is stale, so drop it rather than show old news.
        .where((r) => r.relatedId == null || goals.any((g) => g.id == r.relatedId && g.status == GoalStatus.active))
        .sorted((a, b) => b.scheduledFor.compareTo(a.scheduledFor))
        .firstOrNull;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    var monthIncome = Money.zero;
    var monthExpense = Money.zero;
    for (final t in transactions) {
      if (t.date.isBefore(monthStart)) continue;
      if (t.type == TransactionType.income) {
        monthIncome = monthIncome + t.amount;
      } else {
        monthExpense = monthExpense + t.amount;
      }
    }

    return Scaffold(
      // AppShell's own SafeArea already clears the floating nav bar.
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      Text(
                        profile == null || profile.displayName.isEmpty
                            ? 'SpendSense'
                            : profile.displayName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _BalanceHero(
              totalBalance: totalBalance,
              currency: currency,
              monthIncome: monthIncome,
              monthExpense: monthExpense,
              walletCount: wallets.length,
            ),
            const SizedBox(height: 20),
            _QuickActions(),
            if (dueSoonBill != null) ...[
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () => context.push('/recurring-bills'),
                child: SectionCard(
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.bellRing,
                        color: dueSoonBill.daysUntilDue <= 0
                            ? DataPalette.statusCritical
                            : DataPalette.statusWarning,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${dueSoonBill.name} is due in ${dueSoonBill.daysUntilDue} day${dueSoonBill.daysUntilDue == 1 ? '' : 's'}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      Icon(LucideIcons.chevronRight, size: 18, color: colors.textMuted),
                    ],
                  ),
                ),
              ),
            ],
            if (goalReminder != null) ...[
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: () {
                  ref.read(reminderRepositoryProvider).markRead(goalReminder.id);
                  context.push('/savings-goals');
                },
                child: SectionCard(
                  child: Row(
                    children: [
                      const Icon(LucideIcons.piggyBank, color: DataPalette.statusWarning),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(goalReminder.title, style: Theme.of(context).textTheme.bodyMedium),
                            Text(goalReminder.body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted)),
                          ],
                        ),
                      ),
                      IconButton(
                        iconSize: 18,
                        icon: const Icon(LucideIcons.x),
                        onPressed: () => ref.read(reminderRepositoryProvider).markRead(goalReminder.id),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Wallets',
              onSeeAll: () => context.push('/wallets'),
            ),
            const SizedBox(height: 12),
            if (wallets.isEmpty)
              _InlineHint(text: 'No wallets yet — add one to start tracking.')
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: wallets.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final w = wallets[i];
                    return _WalletMiniCard(
                      wallet: w,
                      onTap: () => context.push('/wallets/edit', extra: w),
                    );
                  },
                ),
              ),
            const SizedBox(height: 28),
            _SectionHeader(
              title: 'Budgets',
              onSeeAll: () => context.go('/budgets'),
            ),
            const SizedBox(height: 12),
            if (budgetProgress.isEmpty)
              _InlineHint(
                text: 'No budgets set — create one to track spending limits.',
              )
            else
              for (final bp in budgetProgress.take(2)) ...[
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            categoryIcon(
                              categories
                                      .where(
                                        (c) => c.id == bp.budget.categoryId,
                                      )
                                      .firstOrNull
                                      ?.iconKey ??
                                  'other',
                            ),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            categories
                                    .where((c) => c.id == bp.budget.categoryId)
                                    .firstOrNull
                                    ?.name ??
                                'Category',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ProgressBar(value: bp.fraction),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 20),
            _SectionHeader(
              title: 'Recent Activity',
              onSeeAll: () => context.go('/transactions'),
            ),
            const SizedBox(height: 12),
            if (transactions.isEmpty)
              const EmptyState(
                icon: LucideIcons.receipt,
                title: 'No activity yet',
                message: 'Add your first transaction to see it here.',
              )
            else
              SectionCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (final t in transactions.take(5))
                      TransactionTile(
                        transaction: t,
                        onTap: () =>
                            context.push('/transactions/edit', extra: t),
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

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.totalBalance,
    required this.currency,
    required this.monthIncome,
    required this.monthExpense,
    required this.walletCount,
  });

  final Money totalBalance;
  final String currency;
  final Money monthIncome;
  final Money monthExpense;
  final int walletCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total balance',
            style: TextStyle(
              color: colors.paper.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          MoneyText(
            amount: totalBalance,
            currencySymbol: currency,
            style: Theme.of(context).textTheme.displaySmall,
            color: colors.paper,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _HeroStat(
                icon: LucideIcons.arrowDown,
                label: 'Income',
                amount: monthIncome,
                currency: currency,
                colors: colors,
                positive: true,
              ),
              const SizedBox(width: 24),
              _HeroStat(
                icon: LucideIcons.arrowUp,
                label: 'Expenses',
                amount: monthExpense,
                currency: currency,
                colors: colors,
                positive: false,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.paper.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '$walletCount wallet${walletCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: colors.paper.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.amount,
    required this.currency,
    required this.colors,
    required this.positive,
  });

  final IconData icon;
  final String label;
  final Money amount;
  final String currency;
  final AppColors colors;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final tint = positive
        ? DataPalette.statusGood
        : colors.paper.withValues(alpha: 0.85);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 12, color: tint),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: colors.paper.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          amount.format(currency),
          style: TextStyle(
            color: colors.paper,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// Every major destination gets a clear, labeled home here — no more tiny
// unlabeled corner icons. Some (Budgets, Goals, Bills, Reports) are also
// still reachable from other screens on purpose — multiple entry points are
// fine, a destination with NO obvious entry point is the actual problem.
class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _QuickAction(icon: LucideIcons.plus, label: 'Add', onTap: () => context.push('/transactions/new'))),
            Expanded(child: _QuickAction(icon: LucideIcons.camera, label: 'Scan', onTap: () => context.push('/receipts/scan'))),
            Expanded(child: _QuickAction(icon: LucideIcons.wallet, label: 'Wallets', onTap: () => context.push('/wallets'))),
            Expanded(child: _QuickAction(icon: LucideIcons.piggyBank, label: 'Goals', onTap: () => context.push('/savings-goals'))),
          ],
        ),
        Row(
          children: [
            Expanded(child: _QuickAction(icon: LucideIcons.repeat, label: 'Bills', onTap: () => context.push('/recurring-bills'))),
            Expanded(child: _QuickAction(icon: LucideIcons.receipt, label: 'Receipts', onTap: () => context.push('/receipts'))),
            Expanded(child: _QuickAction(icon: LucideIcons.lineChart, label: 'Reports', onTap: () => context.push('/reports'))),
            Expanded(child: _QuickAction(icon: LucideIcons.pieChart, label: 'Budgets', onTap: () => context.go('/budgets'))),
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 22, color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletMiniCard extends ConsumerWidget {
  const _WalletMiniCard({required this.wallet, required this.onTap});

  final Wallet wallet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final balance = ref.watch(walletBalanceProvider(wallet.id));
    final currency =
        ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: onTap,
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              walletTypeIcon(wallet.type.name),
              size: 18,
              color: colors.textSecondary,
            ),
            const Spacer(),
            Text(
              wallet.name,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              balance.format(currency),
              style: Theme.of(context).textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        TextButton(onPressed: onSeeAll, child: const Text('See all')),
      ],
    );
  }
}

class _InlineHint extends StatelessWidget {
  const _InlineHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: context.colors.textSecondary),
    );
  }
}

extension _SortedList<T> on Iterable<T> {
  List<T> sorted(int Function(T a, T b) compare) => toList()..sort(compare);
}
