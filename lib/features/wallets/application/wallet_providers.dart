import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/wallets/data/api/api_wallet_repository.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';
import 'package:spendsense/features/wallets/domain/repositories/wallet_repository.dart';

/// THE swap point for the wallets domain.
final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return ApiWalletRepository(client: ref.watch(apiClientProvider));
});

final walletListProvider = StreamProvider.autoDispose<List<Wallet>>((ref) {
  return ref.watch(walletRepositoryProvider).watchAll();
});

/// Includes archived wallets — for pickers on forms that edit an EXISTING
/// record (transactions, recurring bills), so a wallet archived after the
/// fact still appears as an option instead of crashing the dropdown (its
/// items must contain the record's current value). New-record pickers
/// should keep using [walletListProvider] so archived wallets can't be
/// chosen for anything new.
final walletListIncludingArchivedProvider = StreamProvider.autoDispose<List<Wallet>>((ref) {
  return ref.watch(walletRepositoryProvider).watchAll(includeArchived: true);
});

/// Wallet balance is never stored — always starting balance + the live sum
/// of that wallet's transactions, so it can never drift out of sync.
final walletBalanceProvider = Provider.family<Money, String>((ref, walletId) {
  final wallets = ref.watch(walletListProvider).valueOrNull ?? const [];
  Wallet? wallet;
  for (final w in wallets) {
    if (w.id == walletId) {
      wallet = w;
      break;
    }
  }
  if (wallet == null) return Money.zero;

  final transactions = ref.watch(transactionListProvider(null)).valueOrNull ?? const [];
  var net = Money.zero;
  for (final t in transactions) {
    if (t.walletId == walletId) net = net + t.signedAmount;
  }
  return wallet.startingBalance + net;
});

final totalBalanceProvider = Provider<Money>((ref) {
  final wallets = ref.watch(walletListProvider).valueOrNull ?? const [];
  var total = Money.zero;
  for (final w in wallets) {
    total = total + ref.watch(walletBalanceProvider(w.id));
  }
  return total;
});
