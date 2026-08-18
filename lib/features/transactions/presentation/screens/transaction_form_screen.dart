import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// A write only resolves once the server acknowledges it. There is no local
/// write queue behind this any more, so a timeout means "still in flight",
/// not "safely stored" — sized to cover a suspended host waking up.
const _writeTimeout = Duration(seconds: 75);

class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.transaction});

  final Transaction? transaction;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  late TransactionType _type = widget.transaction?.type ?? TransactionType.expense;
  late final _amountController = TextEditingController(
    text: widget.transaction == null ? '' : widget.transaction!.amount.major.toStringAsFixed(2),
  );
  late final _noteController = TextEditingController(text: widget.transaction?.note ?? '');
  late DateTime _date = widget.transaction?.date ?? DateTime.now();
  late String? _walletId = widget.transaction?.walletId;
  late String? _categoryId = widget.transaction?.categoryId;
  bool _busy = false;

  bool get _editing => widget.transaction != null;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final amount = Money.fromMajor(num.tryParse(_amountController.text.trim()) ?? 0);
    if (amount.minorUnits <= 0 || _walletId == null || _categoryId == null) {
      showValidationSnackBar(context, 'Enter a valid amount, wallet, and category.');
      return;
    }
    setState(() => _busy = true);

    try {
      final repo = ref.read(transactionRepositoryProvider);
      if (_editing) {
        await repo
            .update(widget.transaction!.copyWith(
              walletId: _walletId,
              categoryId: _categoryId,
              type: _type,
              amount: amount,
              date: _date,
              note: _noteController.text.trim(),
            ))
            .timeout(_writeTimeout);
      } else {
        await repo
            .create(TransactionDraft(
              walletId: _walletId!,
              categoryId: _categoryId!,
              type: _type,
              amount: amount,
              date: _date,
              note: _noteController.text.trim(),
            ))
            .timeout(_writeTimeout);
      }
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, 'Still saving — this is taking longer than usual.');
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Saving transaction failed', error: e, stackTrace: stackTrace, name: 'TransactionFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't save. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(transactionRepositoryProvider).delete(widget.transaction!.id).timeout(_writeTimeout);
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, 'Still deleting — this is taking longer than usual.');
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Deleting transaction failed', error: e, stackTrace: stackTrace, name: 'TransactionFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't delete. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Active wallets, plus this transaction's own wallet even if it's since
    // been archived (so editing it doesn't crash) — but never any OTHER
    // archived wallet, so a new/different transaction can't be assigned to
    // a closed account.
    final allWallets = ref.watch(walletListIncludingArchivedProvider).valueOrNull ?? const <Wallet>[];
    final wallets = allWallets.where((w) => !w.archived || w.id == widget.transaction?.walletId).toList();
    final categories = ref.watch(_type == TransactionType.income ? incomeCategoryListProvider : expenseCategoryListProvider).valueOrNull ??
        const <Category>[];

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.firstWhereOrNull((w) => !w.archived)?.id ?? wallets.first.id;
    }
    if ((_categoryId == null || !categories.any((c) => c.id == _categoryId)) && categories.isNotEmpty) {
      _categoryId = categories.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Transaction' : 'New Transaction'),
        actions: [
          if (_editing) IconButton(onPressed: _busy ? null : _delete, icon: const Icon(LucideIcons.trash2)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SegmentedButton<TransactionType>(
            segments: const [
              ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
              ButtonSegment(value: TransactionType.income, label: Text('Income')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _categoryId = null;
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Amount'),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _walletId,
            decoration: const InputDecoration(labelText: 'Wallet'),
            items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.archived ? '${w.name} (Archived)' : w.name))).toList(),
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            decoration: const InputDecoration(labelText: 'Category'),
            items: categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _categoryId = v),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Date'),
            subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(LucideIcons.calendar),
            onTap: _pickDate,
          ),
          TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optional)')),
          const SizedBox(height: 32),
          ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}
