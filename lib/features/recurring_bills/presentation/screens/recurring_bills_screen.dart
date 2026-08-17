import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/recurring_bills/application/recurring_bill_providers.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';

class RecurringBillsScreen extends ConsumerWidget {
  const RecurringBillsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(recurringBillListProvider);
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring Bills')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/recurring-bills/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.repeat,
              title: 'No recurring bills yet',
              message: 'Track subscriptions and bills so you never miss a due date.',
            );
          }
          final active = list.where((b) => b.status != BillStatus.completed).toList();
          final completed = list.where((b) => b.status == BillStatus.completed).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final bill in active) ...[
                _BillCard(bill: bill, category: categories.where((c) => c.id == bill.categoryId).firstOrNull, currency: currency),
                const SizedBox(height: 12),
              ],
              if (completed.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Paid off', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                for (final bill in completed) ...[
                  _CompletedBillTile(bill: bill),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BillCard extends ConsumerStatefulWidget {
  const _BillCard({required this.bill, required this.category, required this.currency});

  final RecurringBill bill;
  final Category? category;
  final String currency;

  @override
  ConsumerState<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends ConsumerState<_BillCard> {
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
    final bill = widget.bill;
    final category = widget.category;
    final currency = widget.currency;
    final dueSoon = bill.daysUntilDue <= bill.reminderDaysBefore;
    final urgencyColor = bill.daysUntilDue <= 0
        ? DataPalette.statusCritical
        : dueSoon
            ? DataPalette.statusWarning
            : null;
    final colors = context.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      onTap: () => context.push('/recurring-bills/edit', extra: bill),
      child: SectionCard(
        child: Row(
          children: [
            CircleAvatar(child: Icon(categoryIcon(category?.iconKey ?? 'bills'))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.name, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    'Due in ${bill.daysUntilDue} day${bill.daysUntilDue == 1 ? '' : 's'} · ${bill.frequency.name}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: urgencyColor),
                  ),
                  if (bill.isInstallmentPlan)
                    Text(
                      'Payment ${bill.occurrencesPaid + 1} of ${bill.totalOccurrences}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(bill.amount.format(currency), style: Theme.of(context).textTheme.titleSmall),
                TextButton(
                  onPressed: _processing ? null : () => _runGuarded(() => ref.read(recurringBillPaymentControllerProvider).payBill(bill.id)),
                  child: const Text('Mark paid'),
                ),
                if (bill.canUndoLastPayment)
                  TextButton(
                    onPressed: _processing ? null : () => _runGuarded(() => ref.read(recurringBillPaymentControllerProvider).undoLastPayment(bill.id)),
                    style: TextButton.styleFrom(foregroundColor: colors.textMuted),
                    child: const Text('Undo last payment'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompletedBillTile extends ConsumerStatefulWidget {
  const _CompletedBillTile({required this.bill});
  final RecurringBill bill;

  @override
  ConsumerState<_CompletedBillTile> createState() => _CompletedBillTileState();
}

class _CompletedBillTileState extends ConsumerState<_CompletedBillTile> {
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
    final bill = widget.bill;
    final colors = context.colors;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 18, color: DataPalette.statusGood),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${bill.name} — all ${bill.totalOccurrences} payments complete',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ),
          if (bill.canUndoLastPayment)
            TextButton(
              onPressed:
                  _processing ? null : () => _runGuarded(() => ref.read(recurringBillPaymentControllerProvider).undoLastPayment(bill.id)),
              child: const Text('Undo'),
            ),
          IconButton(
            iconSize: 18,
            icon: const Icon(LucideIcons.trash2),
            onPressed: _processing ? null : () => _runGuarded(() => ref.read(recurringBillRepositoryProvider).delete(bill.id)),
          ),
        ],
      ),
    );
  }
}
