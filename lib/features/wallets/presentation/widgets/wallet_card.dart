import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class WalletCard extends ConsumerWidget {
  const WalletCard({super.key, required this.wallet, this.onTap});

  final Wallet wallet;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balance = ref.watch(walletBalanceProvider(wallet.id));
    final currency = ref.watch(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';
    final color = DataPalette.adaptive(wallet.colorHex, Theme.of(context).brightness);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), foregroundColor: color, child: Icon(walletTypeIcon(wallet.type.name))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(wallet.name, style: Theme.of(context).textTheme.titleMedium),
                    Text(wallet.type.name, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Text(balance.format(currency), style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}
