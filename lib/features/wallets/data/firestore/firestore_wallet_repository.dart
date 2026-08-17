import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/firebase/firestore_collection.dart';
import 'package:spendsense/core/utils/id.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';
import 'package:spendsense/features/wallets/domain/repositories/wallet_repository.dart';

class FirestoreWalletRepository implements WalletRepository {
  FirestoreWalletRepository({required FirebaseFirestore firestore, required String uid})
      : _c = FirestoreCollection<Wallet>(
          firestore: firestore,
          uid: uid,
          name: 'wallets',
          toJson: _toJson,
          fromJson: _fromJson,
        );

  final FirestoreCollection<Wallet> _c;

  static Map<String, dynamic> _toJson(Wallet w) => {
        'name': w.name,
        'type': w.type.name,
        'startingBalanceMinor': w.startingBalance.minorUnits,
        'colorHex': w.colorHex,
        'archived': w.archived,
      };

  static Wallet _fromJson(String id, Map<String, dynamic> json) => Wallet(
        id: id,
        name: json['name'] as String? ?? '',
        type: WalletType.values.firstWhere(
          (t) => t.name == json['type'],
          orElse: () => WalletType.cash,
        ),
        startingBalance: Money((json['startingBalanceMinor'] as num?)?.toInt() ?? 0),
        colorHex: json['colorHex'] as String? ?? '#4C6FFF',
        archived: json['archived'] as bool? ?? false,
      );

  @override
  Stream<List<Wallet>> watchAll({bool includeArchived = false}) {
    return _c.watch().map((wallets) {
      final visible = wallets.where((w) => includeArchived || !w.archived).toList();
      visible.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return visible;
    });
  }

  @override
  Future<Wallet?> getById(String id) => _c.getById(id);

  @override
  Future<Wallet> create(WalletDraft draft) async {
    final wallet = Wallet(
      id: newId(),
      name: draft.name,
      type: draft.type,
      startingBalance: draft.startingBalance,
      colorHex: draft.colorHex,
    );
    await _c.put(wallet.id, wallet);
    return wallet;
  }

  @override
  Future<Wallet> update(Wallet wallet) async {
    await _c.put(wallet.id, wallet);
    return wallet;
  }

  @override
  Future<void> archive(String id) async {
    final existing = await _c.getById(id);
    if (existing == null) return;
    await _c.put(id, existing.copyWith(archived: true));
  }
}
