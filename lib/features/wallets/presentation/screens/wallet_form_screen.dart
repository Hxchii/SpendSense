import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/data_palette.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class WalletFormScreen extends ConsumerStatefulWidget {
  const WalletFormScreen({super.key, this.wallet});

  final Wallet? wallet;

  @override
  ConsumerState<WalletFormScreen> createState() => _WalletFormScreenState();
}

class _WalletFormScreenState extends ConsumerState<WalletFormScreen> {
  late final _nameController = TextEditingController(text: widget.wallet?.name ?? '');
  late final _balanceController = TextEditingController(
    text: widget.wallet == null ? '' : widget.wallet!.startingBalance.major.toStringAsFixed(2),
  );
  late WalletType _type = widget.wallet?.type ?? WalletType.cash;

  // Validated dataviz-skill categorical palette, in fixed slot order.
  static const _colors = ['#2a78d6', '#eb6834', '#1baf7a', '#eda100', '#e87ba4', '#008300', '#4a3aa7', '#e34948'];
  late String _colorHex = widget.wallet?.colorHex ?? _colors.first;

  bool get _editing => widget.wallet != null;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      showValidationSnackBar(context, 'Enter a wallet name.');
      return;
    }
    final repo = ref.read(walletRepositoryProvider);
    final startingBalance = Money.fromMajor(num.tryParse(_balanceController.text.trim()) ?? 0);

    if (_editing) {
      await repo.update(widget.wallet!.copyWith(name: _nameController.text.trim(), type: _type, colorHex: _colorHex));
    } else {
      await repo.create(WalletDraft(name: _nameController.text.trim(), type: _type, startingBalance: startingBalance, colorHex: _colorHex));
    }
    if (mounted) context.pop();
  }

  Future<void> _archive() async {
    await ref.read(walletRepositoryProvider).archive(widget.wallet!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Wallet' : 'New Wallet'),
        actions: [
          if (_editing) IconButton(onPressed: _archive, icon: const Icon(LucideIcons.archive)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Wallet name')),
          const SizedBox(height: 16),
          DropdownButtonFormField<WalletType>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: WalletType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          if (!_editing) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _balanceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Starting balance'),
            ),
          ],
          const SizedBox(height: 16),
          Text('Color', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: _colors.map((hex) {
              final selected = hex == _colorHex;
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: DataPalette.adaptive(hex, Theme.of(context).brightness),
                  child: selected ? const Icon(LucideIcons.check, color: Colors.white, size: 18) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 32),
          ElevatedButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}
