import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/receipts/application/receipt_providers.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

class ReceiptReviewScreen extends ConsumerStatefulWidget {
  const ReceiptReviewScreen({super.key, required this.scanResult, required this.imagePath});

  final ReceiptScanResult scanResult;
  final String imagePath;

  @override
  ConsumerState<ReceiptReviewScreen> createState() => _ReceiptReviewScreenState();
}

class _ReceiptReviewScreenState extends ConsumerState<ReceiptReviewScreen> {
  late final _merchantController = TextEditingController(text: widget.scanResult.merchant);
  late final _totalController = TextEditingController(text: widget.scanResult.total.major.toStringAsFixed(2));
  String? _categoryId;
  String? _walletId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.scanResult.suggestedCategoryId;
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_categoryId == null || _walletId == null) {
      showValidationSnackBar(context, 'Add a wallet and category before saving — you don\'t have any set up yet.');
      return;
    }
    setState(() => _saving = true);

    final total = Money.fromMajor(num.tryParse(_totalController.text.trim()) ?? 0);
    final txn = await ref.read(transactionRepositoryProvider).create(TransactionDraft(
          walletId: _walletId!,
          categoryId: _categoryId!,
          type: TransactionType.expense,
          amount: total,
          date: widget.scanResult.date,
          note: _merchantController.text.trim(),
          source: TransactionSource.receipt,
        ));

    await ref.read(receiptRepositoryProvider).save(Receipt(
          id: newId(),
          merchant: _merchantController.text.trim(),
          date: widget.scanResult.date,
          items: widget.scanResult.items,
          subtotal: widget.scanResult.subtotal,
          tax: widget.scanResult.tax,
          discount: widget.scanResult.discount,
          total: total,
          suggestedCategoryId: _categoryId,
          status: ReceiptStatus.confirmed,
          duplicateOfReceiptId: widget.scanResult.duplicateOfReceiptId,
          linkedTransactionId: txn.id,
        ));

    // pop, not go('/receipts') — Review already sits directly on top of the
    // existing Receipts screen (Scan replaced itself with Review via
    // pushReplacement), so popping back to it keeps the back button intact
    // instead of resetting the stack out from under it.
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(expenseCategoryListProvider).valueOrNull ?? const [];
    final wallets = ref.watch(walletListProvider).valueOrNull ?? const [];
    _categoryId ??= categories.isNotEmpty ? categories.first.id : null;
    _walletId ??= wallets.isNotEmpty ? wallets.first.id : null;

    final isDuplicate = widget.scanResult.duplicateOfReceiptId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Scan')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (isDuplicate)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(LucideIcons.alertTriangle, color: Theme.of(context).colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This looks like a duplicate of a receipt you already saved. Review before continuing.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          Text('Confidence: ${(widget.scanResult.confidence * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(controller: _merchantController, decoration: const InputDecoration(labelText: 'Merchant')),
          const SizedBox(height: 16),
          TextField(
            controller: _totalController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Total'),
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
            items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.name))).toList(),
            onChanged: (v) => setState(() => _walletId = v),
          ),
          const SizedBox(height: 16),
          if (widget.scanResult.items.isNotEmpty) ...[
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            for (final item in widget.scanResult.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.name),
                trailing: Text(item.price.format('₱')),
              ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save Transaction')),
        ],
      ),
    );
  }
}
