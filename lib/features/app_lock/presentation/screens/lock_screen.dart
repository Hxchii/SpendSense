import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  final _pinController = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoBiometric());
  }

  Future<void> _maybeAutoBiometric() async {
    final profile = ref.read(userProfileProvider).valueOrNull;
    if (profile?.appLockType == AppLockType.biometric) {
      await _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    setState(() => _checking = true);
    final ok = await tryBiometricUnlock(ref.read(localAuthProvider));
    setState(() => _checking = false);
    if (ok) {
      ref.read(appUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = 'Biometric authentication failed.');
    }
  }

  Future<void> _submitPin() async {
    final ok = await ref.read(pinStoreProvider).verifyPin(_pinController.text.trim());
    if (ok) {
      ref.read(appUnlockedProvider.notifier).state = true;
    } else {
      setState(() => _error = 'Incorrect PIN.');
      _pinController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final isPin = profile?.appLockType == AppLockType.pin;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colors.brandSoft, shape: BoxShape.circle),
                  child: Icon(LucideIcons.lockKeyhole, size: 30, color: colors.brand),
                ),
                const SizedBox(height: 16),
                Text('SpendSense is locked', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 24),
                if (isPin) ...[
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    obscureText: true,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(labelText: 'Enter PIN'),
                    onSubmitted: (_) => _submitPin(),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _submitPin, child: const Text('Unlock'))),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _checking ? null : _tryBiometric,
                      icon: const Icon(LucideIcons.fingerprint),
                      label: Text(_checking ? 'Checking…' : 'Unlock with biometrics'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
