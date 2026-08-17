import 'dart:async';
import 'dart:developer' as developer;

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

/// A Firestore write only resolves once the SERVER acknowledges it, which
/// offline never happens — but the record is already durable in the local
/// cache and syncs later, so past this point the save counts as done.
const _writeTimeout = Duration(seconds: 5);

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
  bool _busy = false;

  bool get _editing => widget.wallet != null;

  @override
  void dispose() {
    _nameController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_nameController.text.trim().isEmpty) {
      showValidationSnackBar(context, 'Enter a wallet name.');
      return;
    }
    // Left blank still means zero, but a typo like "1.2.3" must never be
    // silently banked as ₱0.00.
    final balanceText = _balanceController.text.trim();
    final balance = balanceText.isEmpty ? 0 : num.tryParse(balanceText);
    if (balance == null) {
      showValidationSnackBar(context, 'Enter a valid starting balance.');
      return;
    }
    setState(() => _busy = true);

    try {
      final repo = ref.read(walletRepositoryProvider);
      if (_editing) {
        await repo.update(widget.wallet!.copyWith(name: _nameController.text.trim(), type: _type, colorHex: _colorHex)).timeout(_writeTimeout);
      } else {
        await repo
            .create(WalletDraft(
              name: _nameController.text.trim(),
              type: _type,
              startingBalance: Money.fromMajor(balance),
              colorHex: _colorHex,
            ))
            .timeout(_writeTimeout);
      }
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, "Saved. It will sync when you're back online.");
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Saving wallet failed', error: e, stackTrace: stackTrace, name: 'WalletFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't save. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(walletRepositoryProvider).archive(widget.wallet!.id).timeout(_writeTimeout);
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, "Archived. It will sync when you're back online.");
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Archiving wallet failed', error: e, stackTrace: stackTrace, name: 'WalletFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't archive. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Wallet' : 'New Wallet'),
        actions: [
          if (_editing) IconButton(onPressed: _busy ? null : _archive, icon: const Icon(LucideIcons.archive)),
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
          ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}
