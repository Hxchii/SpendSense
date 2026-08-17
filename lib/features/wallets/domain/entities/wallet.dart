import 'package:spendsense/core/utils/money.dart';

enum WalletType { cash, bank, eWallet, credit }

class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    required this.type,
    required this.startingBalance,
    required this.colorHex,
    this.archived = false,
  });

  final String id;
  final String name;
  final WalletType type;
  final Money startingBalance;
  final String colorHex;
  final bool archived;

  Wallet copyWith({
    String? name,
    WalletType? type,
    Money? startingBalance,
    String? colorHex,
    bool? archived,
  }) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      startingBalance: startingBalance ?? this.startingBalance,
      colorHex: colorHex ?? this.colorHex,
      archived: archived ?? this.archived,
    );
  }
}

class WalletDraft {
  const WalletDraft({
    required this.name,
    required this.type,
    required this.startingBalance,
    required this.colorHex,
  });

  final String name;
  final WalletType type;
  final Money startingBalance;
  final String colorHex;
}
