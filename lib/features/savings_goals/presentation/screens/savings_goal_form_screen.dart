import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/utils/category_icons.dart';
import 'package:spendsense/core/utils/iterable_extensions.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/savings_goals/application/savings_goal_providers.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// A Firestore write only resolves once the SERVER acknowledges it, which
/// offline never happens — but the record is already durable in the local
/// cache and syncs later, so past this point the save counts as done.
const _writeTimeout = Duration(seconds: 5);

class SavingsGoalFormScreen extends ConsumerStatefulWidget {
  const SavingsGoalFormScreen({super.key, this.goal});

  final SavingsGoal? goal;

  @override
  ConsumerState<SavingsGoalFormScreen> createState() => _SavingsGoalFormScreenState();
}

class _SavingsGoalFormScreenState extends ConsumerState<SavingsGoalFormScreen> {
  late final _nameController = TextEditingController(text: widget.goal?.name ?? '');
  late final _targetController = TextEditingController(text: widget.goal == null ? '' : widget.goal!.targetAmount.major.toStringAsFixed(2));
  late DateTime? _targetDate = widget.goal?.targetDate;
  late String _iconKey = widget.goal?.iconKey ?? 'shield';
  late bool _remindMe = widget.goal?.reminderFrequency != null;
  late GoalReminderFrequency _reminderFrequency = widget.goal?.reminderFrequency ?? GoalReminderFrequency.weekly;
  late bool _autoContribute = widget.goal?.isAutoContributing ?? false;
  late final _autoContributeController =
      TextEditingController(text: widget.goal?.autoContributeAmount == null ? '' : widget.goal!.autoContributeAmount!.major.toStringAsFixed(2));
  late GoalReminderFrequency _autoContributeFrequency = widget.goal?.autoContributeFrequency ?? GoalReminderFrequency.monthly;
  late String? _walletId = widget.goal?.walletId;
  bool _busy = false;

  bool get _editing => widget.goal != null;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _autoContributeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (_busy) return;
    final target = Money.fromMajor(num.tryParse(_targetController.text.trim()) ?? 0);
    if (_nameController.text.trim().isEmpty || target.minorUnits <= 0) {
      showValidationSnackBar(context, 'Enter a goal name and a valid target amount.');
      return;
    }
    final autoContributeAmount = _autoContribute ? Money.fromMajor(num.tryParse(_autoContributeController.text.trim()) ?? 0) : null;
    if (_autoContribute && (autoContributeAmount == null || autoContributeAmount.minorUnits <= 0 || _walletId == null)) {
      showValidationSnackBar(context, 'Enter a valid auto-contribute amount and choose a wallet.');
      return;
    }

    // Keep the existing schedule if the reminder was already on with the
    // same frequency — only reset the clock when it's newly enabled or the
    // frequency changed, so saving an unrelated edit doesn't push it back.
    final alreadyScheduled = widget.goal?.reminderFrequency == _reminderFrequency && widget.goal?.nextReminderDate != null;
    final nextReminderDate = !_remindMe
        ? null
        : alreadyScheduled
            ? widget.goal!.nextReminderDate
            : _advancedReminderDate(DateTime.now(), _reminderFrequency);
    final alreadyContributing =
        widget.goal?.autoContributeFrequency == _autoContributeFrequency && widget.goal?.nextContributionDate != null;
    final nextContributionDate = !_autoContribute
        ? null
        : alreadyContributing
            ? widget.goal!.nextContributionDate
            : _advancedReminderDate(DateTime.now(), _autoContributeFrequency);

    setState(() => _busy = true);

    try {
      final repo = ref.read(savingsGoalRepositoryProvider);
      if (_editing) {
        await repo
            .update(widget.goal!.copyWith(
              name: _nameController.text.trim(),
              targetAmount: target,
              targetDate: _targetDate,
              iconKey: _iconKey,
              reminderFrequency: _remindMe ? _reminderFrequency : null,
              nextReminderDate: nextReminderDate,
              clearReminder: !_remindMe,
              walletId: _autoContribute ? _walletId : null,
              autoContributeAmount: autoContributeAmount,
              autoContributeFrequency: _autoContribute ? _autoContributeFrequency : null,
              nextContributionDate: nextContributionDate,
              clearAutoContribute: !_autoContribute,
            ))
            .timeout(_writeTimeout);
      } else {
        await repo
            .create(SavingsGoalDraft(
              name: _nameController.text.trim(),
              targetAmount: target,
              iconKey: _iconKey,
              targetDate: _targetDate,
              reminderFrequency: _remindMe ? _reminderFrequency : null,
              nextReminderDate: nextReminderDate,
              walletId: _autoContribute ? _walletId : null,
              autoContributeAmount: autoContributeAmount,
              autoContributeFrequency: _autoContribute ? _autoContributeFrequency : null,
              nextContributionDate: nextContributionDate,
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
      developer.log('Saving savings goal failed', error: e, stackTrace: stackTrace, name: 'SavingsGoalFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't save. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await ref.read(savingsGoalRepositoryProvider).delete(widget.goal!.id).timeout(_writeTimeout);
      if (mounted) context.pop();
    } on TimeoutException {
      if (mounted) {
        showValidationSnackBar(context, "Deleted. It will sync when you're back online.");
        context.pop();
      }
    } catch (e, stackTrace) {
      developer.log('Deleting savings goal failed', error: e, stackTrace: stackTrace, name: 'SavingsGoalFormScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't delete. Please try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime _advancedReminderDate(DateTime from, GoalReminderFrequency frequency) {
    return frequency == GoalReminderFrequency.weekly
        ? from.add(const Duration(days: 7))
        : DateTime(from.year, from.month + 1, from.day);
  }

  @override
  Widget build(BuildContext context) {
    // Active wallets, plus this goal's own auto-contribute wallet even if
    // it's since been archived (so editing it doesn't crash) — but never
    // any OTHER archived wallet, so a newly-enabled auto-contribute can't
    // be pointed at a closed account.
    final allWallets = ref.watch(walletListIncludingArchivedProvider).valueOrNull ?? const <Wallet>[];
    final wallets = allWallets.where((w) => !w.archived || w.id == widget.goal?.walletId).toList();
    _walletId ??= wallets.firstWhereOrNull((w) => !w.archived)?.id ?? (wallets.isNotEmpty ? wallets.first.id : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Savings Goal' : 'New Savings Goal'),
        actions: [
          if (_editing) IconButton(onPressed: _busy ? null : _delete, icon: const Icon(LucideIcons.trash2)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Goal name')),
          const SizedBox(height: 16),
          TextField(
            controller: _targetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Target amount'),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Target date (optional)'),
            subtitle: Text(_targetDate == null ? 'Not set' : '${_targetDate!.year}-${_targetDate!.month.toString().padLeft(2, '0')}-${_targetDate!.day.toString().padLeft(2, '0')}'),
            trailing: const Icon(LucideIcons.calendar),
            onTap: _pickDate,
          ),
          const SizedBox(height: 16),
          Text('Icon', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: goalIconChoices.map((key) {
              final selected = key == _iconKey;
              final colors = context.colors;
              return GestureDetector(
                onTap: () => setState(() => _iconKey = key),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: selected ? colors.brand : colors.brandSoft,
                  foregroundColor: selected ? Colors.white : colors.brand,
                  child: Icon(categoryIcon(key)),
                ),
              );
            }).toList(),
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Remind me to contribute'),
            subtitle: const Text('A nudge shows up on your dashboard on a schedule, so this goal doesn\'t go quiet.'),
            value: _remindMe,
            onChanged: (v) => setState(() => _remindMe = v),
          ),
          if (_remindMe) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<GoalReminderFrequency>(
              initialValue: _reminderFrequency,
              decoration: const InputDecoration(labelText: 'How often'),
              items: const [
                DropdownMenuItem(value: GoalReminderFrequency.weekly, child: Text('Weekly')),
                DropdownMenuItem(value: GoalReminderFrequency.monthly, child: Text('Monthly')),
              ],
              onChanged: (v) => setState(() => _reminderFrequency = v ?? _reminderFrequency),
            ),
          ],
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-contribute'),
            subtitle: const Text('Automatically moves money from a wallet into this goal on a schedule — you can always undo the latest one.'),
            value: _autoContribute,
            onChanged: (v) => setState(() => _autoContribute = v),
          ),
          if (_autoContribute) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _autoContributeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Amount per contribution'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<GoalReminderFrequency>(
              initialValue: _autoContributeFrequency,
              decoration: const InputDecoration(labelText: 'How often'),
              items: const [
                DropdownMenuItem(value: GoalReminderFrequency.weekly, child: Text('Weekly')),
                DropdownMenuItem(value: GoalReminderFrequency.monthly, child: Text('Monthly')),
              ],
              onChanged: (v) => setState(() => _autoContributeFrequency = v ?? _autoContributeFrequency),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _walletId,
              decoration: const InputDecoration(labelText: 'Wallet'),
              items: wallets.map((w) => DropdownMenuItem(value: w.id, child: Text(w.archived ? '${w.name} (Archived)' : w.name))).toList(),
              onChanged: (v) => setState(() => _walletId = v),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save')),
        ],
      ),
    );
  }
}
