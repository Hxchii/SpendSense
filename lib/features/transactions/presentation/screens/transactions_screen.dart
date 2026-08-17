import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/transactions/presentation/widgets/transaction_tile.dart';

final _transactionTypeFilterProvider = StateProvider.autoDispose<TransactionType?>((ref) => null);
final _transactionCategoryFilterProvider = StateProvider.autoDispose<String?>((ref) => null);

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeFilter = ref.watch(_transactionTypeFilterProvider);
    final categoryFilter = ref.watch(_transactionCategoryFilterProvider);
    final filter = (typeFilter == null && categoryFilter == null)
        ? null
        : TransactionFilter(type: typeFilter, categoryId: categoryFilter);
    final transactions = ref.watch(transactionListProvider(filter));
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/transactions/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: typeFilter == null,
                  onSelected: () => ref.read(_transactionTypeFilterProvider.notifier).state = null,
                ),
                _FilterChip(
                  label: 'Income',
                  selected: typeFilter == TransactionType.income,
                  onSelected: () => ref.read(_transactionTypeFilterProvider.notifier).state = TransactionType.income,
                ),
                _FilterChip(
                  label: 'Expense',
                  selected: typeFilter == TransactionType.expense,
                  onSelected: () => ref.read(_transactionTypeFilterProvider.notifier).state = TransactionType.expense,
                ),
                for (final category in categories)
                  _FilterChip(
                    label: category.name,
                    selected: categoryFilter == category.id,
                    onSelected: () => ref.read(_transactionCategoryFilterProvider.notifier).state =
                        categoryFilter == category.id ? null : category.id,
                  ),
              ],
            ),
          ),
          Expanded(
            child: transactions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Something went wrong: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: LucideIcons.receipt,
                    title: 'No transactions found',
                    message: 'Try a different filter, or add your first transaction.',
                  );
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final t = list[i];
                    return TransactionTile(transaction: t, onTap: () => context.push('/transactions/edit', extra: t));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onSelected()),
    );
  }
}
