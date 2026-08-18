import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_base_url.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';
import 'package:spendsense/features/categories/application/category_providers.dart';
import 'package:spendsense/features/categories/domain/entities/category.dart';
import 'package:spendsense/features/export/application/export_service.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/transactions/application/transaction_providers.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    Future<void> updateProfile(UserProfile Function(UserProfile) update) async {
      final repo = ref.read(userProfileRepositoryProvider);
      await repo.update(update(profile));
    }

    // Permission must be requested from a real tap, not lazily when a
    // reminder later fires — browsers silently auto-reject requests that
    // aren't tied to a user gesture.
    Future<void> onReminderToggleChanged(bool enabled, UserProfile Function(UserProfile) update) async {
      await updateProfile(update);
      if (!enabled) return;
      final granted = await ref.read(notificationServiceProvider).requestPermission();
      if (context.mounted) {
        showValidationSnackBar(
          context,
          granted
              ? 'Notifications enabled — you\'ll get a real system notification when this fires.'
              : 'Notifications are blocked or unavailable — you\'ll still see reminders in-app.',
        );
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(LucideIcons.user)),
            title: Text(profile.displayName.isEmpty ? 'Add your name' : profile.displayName),
            subtitle: const Text('Tap to edit profile'),
            onTap: () => _editProfileDialog(context, ref, profile),
          ),
          const Divider(),
          const _SectionLabel('Appearance'),
          RadioGroup<AppThemeMode>(
            groupValue: profile.themeMode,
            onChanged: (v) => updateProfile((p) => p.copyWith(themeMode: v)),
            child: Column(
              children: [
                for (final mode in AppThemeMode.values)
                  RadioListTile<AppThemeMode>(value: mode, title: Text(_themeModeLabel(mode))),
              ],
            ),
          ),
          const Divider(),
          const _SectionLabel('Notifications'),
          SwitchListTile(
            title: const Text('Budget alerts'),
            subtitle: const Text('When a budget hits 80% or goes over its limit'),
            value: profile.notificationPrefs.budgetAlerts,
            onChanged: (v) => onReminderToggleChanged(v, (p) => p.copyWith(notificationPrefs: p.notificationPrefs.copyWith(budgetAlerts: v))),
          ),
          SwitchListTile(
            title: const Text('Bill reminders'),
            subtitle: const Text('When a recurring bill is due or auto-paid'),
            value: profile.notificationPrefs.billReminders,
            onChanged: (v) => onReminderToggleChanged(v, (p) => p.copyWith(notificationPrefs: p.notificationPrefs.copyWith(billReminders: v))),
          ),
          SwitchListTile(
            title: const Text('Savings goal reminders'),
            subtitle: const Text('Progress nudges and auto-contribution alerts'),
            value: profile.notificationPrefs.savingsGoalReminders,
            onChanged: (v) =>
                onReminderToggleChanged(v, (p) => p.copyWith(notificationPrefs: p.notificationPrefs.copyWith(savingsGoalReminders: v))),
          ),
          const Divider(),
          const _SectionLabel('Security'),
          ListTile(
            title: const Text('App lock'),
            subtitle: Text(_appLockLabel(profile.appLockType)),
            trailing: const Icon(LucideIcons.chevronRight, size: 16),
            onTap: () => _appLockDialog(context, ref, profile),
          ),
          const Divider(),
          const _SectionLabel('Data'),
          ListTile(
            leading: const Icon(LucideIcons.fileSpreadsheet),
            title: const Text('Export as CSV'),
            onTap: () => _export(context, ref, asCsv: true),
          ),
          ListTile(
            leading: const Icon(LucideIcons.fileText),
            title: const Text('Export as PDF'),
            onTap: () => _export(context, ref, asCsv: false),
          ),
          const Divider(),
          const _SectionLabel('Server'),
          ListTile(
            leading: const Icon(LucideIcons.server),
            title: const Text('API address'),
            subtitle: Text(ref.watch(apiBaseUrlProvider)),
            trailing: const Icon(LucideIcons.pencil, size: 18),
            onTap: () => _editApiBaseUrl(context, ref),
          ),
          const Divider(),
          const _SectionLabel('Debug'),
          ListTile(
            leading: const Icon(LucideIcons.rotateCcw),
            title: const Text('Restart onboarding'),
            onTap: () => updateProfile((p) => p.copyWith(onboardingComplete: false)),
          ),
        ],
      ),
    );
  }

  /// Lets the server be repointed without rebuilding the app — the address
  /// changes whenever the API is redeployed or the machine running it joins a
  /// different network, and whoever is testing usually can't rebuild.
  Future<void> _editApiBaseUrl(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: ref.read(apiBaseUrlProvider));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API address'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://your-api.example.com'),
            ),
            const SizedBox(height: 12),
            Text(
              'Where SpendSense stores your data. Change this only if you were given a different address.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, '__reset__'), child: const Text('Reset')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;

    if (result == '__reset__') {
      await clearApiBaseUrl(ref.read(secureStorageProvider), ref.read(apiBaseUrlProvider.notifier));
    } else {
      final normalized = normalizeBaseUrl(result);
      if (normalized.isEmpty) {
        if (context.mounted) showValidationSnackBar(context, 'Enter an address, or tap Reset.');
        return;
      }
      await saveApiBaseUrl(ref.read(secureStorageProvider), ref.read(apiBaseUrlProvider.notifier), normalized);
    }

    // Every repository holds a client built from the old address, so they all
    // have to be rebuilt for the change to take effect.
    ref.invalidate(apiClientProvider);
    if (context.mounted) {
      showValidationSnackBar(context, 'Server updated. Pull down on the dashboard to reload.');
    }
  }

  Future<void> _editProfileDialog(BuildContext context, WidgetRef ref, UserProfile profile) async {
    final controller = TextEditingController(text: profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (name != null) {
      await ref.read(userProfileRepositoryProvider).update(profile.copyWith(displayName: name));
    }
  }

  Future<void> _appLockDialog(BuildContext context, WidgetRef ref, UserProfile profile) async {
    final chosen = await showDialog<AppLockType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('App lock'),
        children: [
          for (final type in AppLockType.values)
            SimpleDialogOption(onPressed: () => Navigator.pop(context, type), child: Text(_appLockLabel(type))),
        ],
      ),
    );
    if (chosen == null || !context.mounted) return;

    if (chosen == AppLockType.pin) {
      final controller = TextEditingController();
      final pin = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Set a PIN'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            obscureText: true,
            maxLength: 6,
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      if (pin == null || pin.length < 4) return;
      await ref.read(pinStoreProvider).savePin(pin);
    }

    // Never store a lock the device can't actually satisfy — the lock screen
    // is the only route out, so enabling biometrics with nothing enrolled
    // would leave the account permanently unopenable.
    if (chosen == AppLockType.biometric) {
      final auth = ref.read(localAuthProvider);
      var available = false;
      try {
        available = (await auth.canCheckBiometrics || await auth.isDeviceSupported()) &&
            (await auth.getAvailableBiometrics()).isNotEmpty;
      } catch (_) {
        available = false;
      }
      if (!available) {
        if (context.mounted) {
          showValidationSnackBar(
            context,
            'No fingerprint or face unlock is set up on this device. Set one up in your phone settings first, or use a PIN.',
          );
        }
        return;
      }
    }

    if (chosen == AppLockType.none) {
      await ref.read(pinStoreProvider).clearPin();
    }

    await ref.read(userProfileRepositoryProvider).update(profile.copyWith(appLockType: chosen));
    ref.read(appUnlockedProvider.notifier).state = true;
  }

  Future<void> _export(BuildContext context, WidgetRef ref, {required bool asCsv}) async {
    // Read the repositories directly rather than the autoDispose list
    // providers: those aren't kept alive by this screen, so a cold read
    // returns loading/empty and every lookup silently falls back to
    // "Uncategorized"/"Unknown" in the exported file.
    final transactions = await ref.read(transactionRepositoryProvider).watchAll().first;
    final categories = <String, Category>{
      for (final c in await ref.read(categoryRepositoryProvider).watchAll(includeArchived: true).first) c.id: c
    };
    final wallets = <String, Wallet>{
      for (final w in await ref.read(walletRepositoryProvider).watchAll(includeArchived: true).first) w.id: w
    };
    final currency = ref.read(userProfileProvider).valueOrNull?.currencySymbol ?? '₱';

    final service = ExportService();
    if (asCsv) {
      await service.exportCsv(transactions: transactions, categoriesById: categories, walletsById: wallets, currency: currency);
    } else {
      await service.exportPdf(transactions: transactions, categoriesById: categories, walletsById: wallets, currency: currency);
    }
  }
}

String _themeModeLabel(AppThemeMode mode) => switch (mode) {
      AppThemeMode.light => 'Light',
      AppThemeMode.dark => 'Dark',
      AppThemeMode.system => 'Match system',
    };

String _appLockLabel(AppLockType type) => switch (type) {
      AppLockType.none => 'Off',
      AppLockType.pin => 'PIN',
      AppLockType.biometric => 'Biometric',
    };

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: context.colors.brand)),
    );
  }
}
