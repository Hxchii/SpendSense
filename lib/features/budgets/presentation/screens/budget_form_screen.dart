import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/budgets/application/budget_providers.dart';
import 'package:spendsense/features/budgets/domain/entities/budget.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';

class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.budget});

  final Budget? budget;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  late final _limitController = TextEditingController(text: widget.budget == null ? '' : widget.budget!.limitAmount.major.toStringAsFixed(2));
  late String? _categoryId = widget.budget?.categoryId;
  late BudgetPeriod _period = widget.budget?.period ?? BudgetPeriod.monthly;

  bool get _editing => widget.budget != null;

  @override
  void dispose() {
    _limitController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limit = Money.fromMajor(num.tryParse(_limitController.text.trim()) ?? 0);
    if (_categoryId == null || limit.minorUnits <= 0) {
      showValidationSnackBar(context, 'Choose a category and enter a valid limit.');
      return;
    }

    final repo = ref.read(budgetRepositoryProvider);
    if (_editing) {
      await repo.update(widget.budget!.copyWith(categoryId: _categoryId, period: _period, limitAmount: limit));
    } else {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      await repo.create(BudgetDraft(categoryId: _categoryId!, period: _period, limitAmount: limit, startDate: start, endDate: end));
    }
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    await ref.read(budgetRepositoryProvider).delete(widget.budget!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoryListProvider).valueOrNull ?? const [];
    _categoryId ??= categories.isNotEmpty ? categories.first.id : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Budget' : 'New Budget'),
        actions: [
          if (_editing) IconButton(onPressed: _delete, icon: const Icon(LucideIcons.trash2)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _limitController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Monthly limit'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<BudgetPeriod>(
            initialValue: _period,
            decoration: const InputDecoration(labelText: 'Period'),
            items: BudgetPeriod.values.map((p) => DropdownMenuItem(value: p, child: Text(p.name))).toList(),
            onChanged: (v) => setState(() => _period = v ?? _period),
          ),
          const SizedBox(height: 32),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
