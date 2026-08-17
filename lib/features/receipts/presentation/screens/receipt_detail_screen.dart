import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/receipts/application/receipt_providers.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';

class ReceiptDetailScreen extends ConsumerWidget {
  const ReceiptDetailScreen({super.key, required this.receipt});

  final Receipt receipt;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(receiptRepositoryProvider).delete(receipt.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt'),
        actions: [
          IconButton(onPressed: () => _delete(context, ref), icon: const Icon(LucideIcons.trash2)),
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
