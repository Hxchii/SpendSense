import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';

class TransactionTile extends ConsumerWidget {
  const TransactionTile({super.key, required this.transaction, this.onTap});

  final Transaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final wallets = ref.watch(walletListIncludingArchivedProvider).valueOrNull ?? const [];
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final category = categories.where((c) => c.id == transaction.categoryId).firstOrNull;
    final wallet = wallets.where((w) => w.id == transaction.walletId).firstOrNull;
    final isIncome = transaction.type == TransactionType.income;
    final brightness = Theme.of(context).brightness;
    final color = category != null ? DataPalette.adaptive(category.colorHex, brightness) : Colors.grey;

    final subtitleParts = [
      if (transaction.note.isNotEmpty) transaction.note,
      if (wallet != null) wallet.name,
      DateFormat.yMMMd().format(transaction.date),
    ];

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        child: Icon(categoryIcon(category?.iconKey ?? 'other')),
      ),
      title: Text(category?.name ?? 'Uncategorized'),
      subtitle: Text(subtitleParts.join(' · ')),
      trailing: Text(
        '${isIncome ? '+' : '-'}${transaction.amount.format(currency)}',
        style: TextStyle(
          color: isIncome ? AppTheme.income(brightness) : AppTheme.expense(brightness),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
