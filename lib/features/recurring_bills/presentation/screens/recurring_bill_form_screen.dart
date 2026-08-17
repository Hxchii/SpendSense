import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/recurring_bills/application/recurring_bill_providers.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class RecurringBillFormScreen extends ConsumerStatefulWidget {
  const RecurringBillFormScreen({super.key, this.bill});

  final RecurringBill? bill;

  @override
  ConsumerState<RecurringBillFormScreen> createState() => _RecurringBillFormScreenState();
}

class _RecurringBillFormScreenState extends ConsumerState<RecurringBillFormScreen> {
  late final _nameController = TextEditingController(text: widget.bill?.name ?? '');
  late final _amountController = TextEditingController(text: widget.bill == null ? '' : widget.bill!.amount.major.toStringAsFixed(2));
  late final _occurrencesController = TextEditingController(text: widget.bill?.totalOccurrences?.toString() ?? '');
  late String? _categoryId = widget.bill?.categoryId;
  late String? _walletId = widget.bill?.walletId;
  late BillFrequency _frequency = widget.bill?.frequency ?? BillFrequency.monthly;
  late DateTime _nextDueDate = widget.bill?.nextDueDate ?? DateTime.now().add(const Duration(days: 7));
  late bool _autoLog = widget.bill?.autoLogTransaction ?? false;
  late bool _isInstallment = widget.bill?.isInstallmentPlan ?? false;

  bool get _editing => widget.bill != null;

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _occurrencesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _nextDueDate, firstDate: DateTime.now(), lastDate: DateTime(2100));
    if (picked != null) setState(() => _nextDueDate = picked);
  }

  Future<void> _save() async {
    final amount = Money.fromMajor(num.tryParse(_amountController.text.trim()) ?? 0);
    if (_nameController.text.trim().isEmpty || _categoryId == null || amount.minorUnits <= 0) {
      showValidationSnackBar(context, 'Enter a bill name, category, and a valid amount.');
      return;
    }
    final totalOccurrences = _isInstallment ? int.tryParse(_occurrencesController.text.trim()) : null;
    if (_isInstallment && (totalOccurrences == null || totalOccurrences <= 0)) {
      showValidationSnackBar(context, 'Enter a valid number of payments for the installment plan.');
      return;
    }

    final repo = ref.read(recurringBillRepositoryProvider);
    if (_editing) {
      await repo.update(widget.bill!.copyWith(
        name: _nameController.text.trim(),
        categoryId: _categoryId,
        walletId: _walletId,
        amount: amount,
        frequency: _frequency,
        nextDueDate: _nextDueDate,
        autoLogTransaction: _autoLog,
        totalOccurrences: totalOccurrences,
        clearTotalOccurrences: !_isInstallment,
      ));
    } else {
      await repo.create(RecurringBillDraft(
        name: _nameController.text.trim(),
        categoryId: _categoryId!,
        walletId: _walletId,
        amount: amount,
        frequency: _frequency,
        nextDueDate: _nextDueDate,
        autoLogTransaction: _autoLog,
        totalOccurrences: totalOccurrences,
      ));
    }
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    await ref.read(recurringBillRepositoryProvider).delete(widget.bill!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoryListProvider).valueOrNull ?? const [];
    // Active wallets, plus this bill's own wallet even if it's since been
    // archived (so editing it doesn't crash) — but never any OTHER archived
    // wallet, so a new/different bill can't be assigned to a closed account.
    final allWallets = ref.watch(walletListIncludingArchivedProvider).valueOrNull ?? const <Wallet>[];
    final wallets = allWallets.where((w) => !w.archived || w.id == widget.bill?.walletId).toList();
    _categoryId ??= categories.isNotEmpty ? categories.first.id : null;
    _walletId ??= wallets.firstWhereOrNull((w) => !w.archived)?.id ?? (wallets.isNotEmpty ? wallets.first.id : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Recurring Bill' : 'New Recurring Bill'),
        actions: [
          if (_editing) IconButton(onPressed: _delete, icon: const Icon(LucideIcons.trash2)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Bill name')),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Amount per payment'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _walletId,
            decoration: const InputDecoration(labelText: 'Wallet'),
            items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.archived ? '${w.name} (Archived)' : w.name))).toList(),
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<BillFrequency>(
            initialValue: _frequency,
            decoration: const InputDecoration(labelText: 'Frequency'),
            items: BillFrequency.values.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
            onChanged: (v) => setState(() => _frequency = v ?? _frequency),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Next due date'),
            subtitle: Text('${_nextDueDate.year}-${_nextDueDate.month.toString().padLeft(2, '0')}-${_nextDueDate.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(LucideIcons.calendar),
            onTap: _pickDate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-deduct on the due date'),
            subtitle: const Text('Automatically logs an expense and deducts the wallet when this bill comes due — good for bills you know will hit no matter what (utilities, subscriptions). You can always undo the latest payment afterward, e.g. if you\'ll be late this cycle.'),
            value: _autoLog,
            onChanged: (v) => setState(() => _autoLog = v),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fixed number of payments'),
            subtitle: const Text('For installment plans (e.g. a 3-month downpayment) — stops automatically once paid off, instead of repeating forever.'),
            value: _isInstallment,
            onChanged: (v) => setState(() => _isInstallment = v),
          ),
          if (_isInstallment) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _occurrencesController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Total number of payments'),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
