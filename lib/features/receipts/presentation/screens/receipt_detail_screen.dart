import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/receipts/application/receipt_providers.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';

/// A Firestore write only resolves once the SERVER acknowledges it, which
/// offline never happens — but the change is already durable in the local
/// cache and syncs later, so past this point the delete counts as done.
const _writeTimeout = Duration(seconds: 5);

class ReceiptDetailScreen extends ConsumerStatefulWidget {
  const ReceiptDetailScreen({super.key, required this.receipt});

  final Receipt receipt;

  @override
  ConsumerState<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends ConsumerState<ReceiptDetailScreen> {
  bool _busy = false;

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(receiptRepositoryProvider).delete(widget.receipt.id).timeout(_writeTimeout);
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, "Deleted. It will sync when you're back online.");
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Deleting receipt failed', error: e, stackTrace: stackTrace, name: 'ReceiptDetailScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't delete. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final receipt = widget.receipt;
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(onPressed: _busy ? null : _delete, icon: const Icon(LucideIcons.trash2)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(receipt.merchant, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(DateFormat.yMMMd().format(receipt.date), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          if (receipt.items.isNotEmpty) ...[
            Text('Items', style: Theme.of(context).textTheme.titleSmall),
            for (final item in receipt.items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item.qty > 1 ? '${item.name} x${item.qty}' : item.name),
                trailing: Text(item.price.format(currency)),
              ),
            const Divider(height: 32),
          ],
          _AmountRow(label: 'Subtotal', amount: receipt.subtotal.format(currency)),
          if (receipt.tax.minorUnits != 0) _AmountRow(label: 'Tax', amount: receipt.tax.format(currency)),
          if (receipt.discount.minorUnits != 0) _AmountRow(label: 'Discount', amount: '-${receipt.discount.format(currency)}'),
          const SizedBox(height: 8),
          _AmountRow(label: 'Total', amount: receipt.total.format(currency), emphasize: true),
        ],
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({required this.label, required this.amount, this.emphasize = false});

  final String label;
  final String amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize ? Theme.of(context).textTheme.titleMedium : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(amount, style: style),
        ],
      ),
    );
  }
}
