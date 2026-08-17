import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

abstract class WalletRepository {
  Stream<List<Wallet>> watchAll({bool includeArchived = false});
  Future<Wallet?> getById(String id);
  Future<Wallet> create(WalletDraft draft);
  Future<Wallet> update(Wallet wallet);
  Future<void> archive(String id);
}
