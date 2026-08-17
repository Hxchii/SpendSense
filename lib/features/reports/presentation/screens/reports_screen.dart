import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionListProvider(null)).valueOrNull ?? const [];
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final categoryById = {for (final c in categories) c.id: c};

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    final thisMonth = transactions.where((t) => !t.date.isBefore(monthStart) && !t.date.isAfter(monthEnd));

    final byCategory = <String, double>{};
    var totalIncome = 0.0;
    var totalExpense = 0.0;
    for (final t in thisMonth) {
      if (t.type == TransactionType.expense) {
        byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + t.amount.major;
        totalExpense += t.amount.major;
      } else {
        totalIncome += t.amount.major;
      }
    }

    final sortedEntries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('This Month', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _StatColumn(label: 'Income', value: totalIncome, currency: currency, color: AppTheme.income(Theme.of(context).brightness))),
                    Expanded(child: _StatColumn(label: 'Expenses', value: totalExpense, currency: currency, color: AppTheme.expense(Theme.of(context).brightness))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (sortedEntries.isEmpty)
            const SectionCard(child: Text('No expenses recorded yet this month.'))
          else ...[
            SectionCard(
              child: SizedBox(
                height: 220,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                    sections: [
                      for (final entry in sortedEntries)
                        PieChartSectionData(
                          value: entry.value,
                          color: DataPalette.adaptive(categoryById[entry.key]?.colorHex ?? '#e34948', Theme.of(context).brightness),
                          title: '',
                          radius: 60,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('By Category', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final entry in sortedEntries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: DataPalette.adaptive(categoryById[entry.key]?.colorHex ?? '#e34948', Theme.of(context).brightness), shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(categoryById[entry.key]?.name ?? 'Other')),
                          Text('$currency${entry.value.toStringAsFixed(2)}'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.label, required this.value, required this.currency, required this.color});

  final String label;
  final double value;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text('$currency${value.toStringAsFixed(2)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
      ],
    );
  }
}
