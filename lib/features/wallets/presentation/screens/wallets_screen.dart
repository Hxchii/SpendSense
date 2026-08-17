import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/widgets/empty_state.dart';
import 'package:spendsense/core/widgets/section_card.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';
import 'package:spendsense/features/wallets/presentation/widgets/wallet_card.dart';

class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletListIncludingArchivedProvider);
    final colors = context.colors;

    return Scaffold(
      appBar: AppBar(title: const Text('Wallets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/wallets/new'),
        child: const Icon(LucideIcons.plus),
      ),
      body: wallets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: LucideIcons.wallet,
              title: 'No wallets yet',
              message: 'Add a cash, bank, or e-wallet account to start tracking.',
            );
          }
          final active = list.where((w) => !w.archived).toList();
          final archived = list.where((w) => w.archived).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final wallet in active) ...[
                WalletCard(wallet: wallet, onTap: () => context.push('/wallets/edit', extra: wallet)),
                const SizedBox(height: 12),
              ],
              if (archived.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Archived', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colors.textMuted)),
                const SizedBox(height: 8),
                for (final wallet in archived) ...[
                  _ArchivedWalletTile(wallet: wallet),
                  const SizedBox(height: 8),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ArchivedWalletTile extends ConsumerWidget {
  const _ArchivedWalletTile({required this.wallet});
  final Wallet wallet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(wallet.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => ref.read(walletRepositoryProvider).update(wallet.copyWith(archived: false)),
            child: const Text('Unarchive'),
          ),
        ],
      ),
    );
  }
}
