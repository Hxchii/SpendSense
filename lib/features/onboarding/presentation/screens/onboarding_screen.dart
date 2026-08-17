import 'dart:async';
import 'dart:developer' as developer;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/theme/app_colors.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/core/widgets/validation_snackbar.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/wallets/application/wallet_providers.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';

/// A Firestore write only resolves once the SERVER acknowledges it, which
/// offline never happens — but the record is already durable in the local
/// cache and syncs later, so past this point setup counts as done.
const _writeTimeout = Duration(seconds: 5);

/// A blank money field legitimately means "not set", but the `[0-9.]`
/// formatter still lets a typo like "1.2.3" through — that must never be
/// banked as ₱0.00, so it parses to null and the caller rejects it.
Money? _parseMoney(String text) {
  final value = num.tryParse(text.trim());
  return value == null ? null : Money.fromMajor(value);
}

bool _isUsableAmount(String text) => text.trim().isEmpty || _parseMoney(text) != null;

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;

  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _budgetController = TextEditingController();
  final _pinController = TextEditingController();
  final _walletNameController = TextEditingController(text: 'Cash');
  final _walletBalanceController = TextEditingController();
  String _currency = '₱';
  FinancialGoal _goal = FinancialGoal.trackDaily;
  WalletType _walletType = WalletType.cash;
  AppLockType _lockType = AppLockType.none;
  NotificationPrefs _notifPrefs = const NotificationPrefs();
  bool _busy = false;
  bool _walletCreated = false;

  static const _lastPage = 3;

  static const _goalOptions = [
    (goal: FinancialGoal.saveMore, label: 'Save More Money', icon: LucideIcons.piggyBank),
    (goal: FinancialGoal.trackDaily, label: 'Track Daily Expenses', icon: LucideIcons.notebook),
    (goal: FinancialGoal.reduceSpending, label: 'Reduce Monthly Spending', icon: LucideIcons.trendingDown),
    (goal: FinancialGoal.emergencyFund, label: 'Build an Emergency Fund', icon: LucideIcons.shieldCheck),
    (goal: FinancialGoal.payOffDebt, label: 'Pay Off Existing Debt', icon: LucideIcons.creditCard),
    (goal: FinancialGoal.manageBudget, label: 'Manage Personal Budget', icon: LucideIcons.pieChart),
    (goal: FinancialGoal.custom, label: 'Custom Goal', icon: LucideIcons.sparkles),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _incomeController.dispose();
    _budgetController.dispose();
    _pinController.dispose();
    _walletNameController.dispose();
    _walletBalanceController.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 0 && (!_isUsableAmount(_incomeController.text) || !_isUsableAmount(_budgetController.text))) {
      showValidationSnackBar(context, 'Enter valid amounts for your monthly income and budget.');
      return;
    }
    if (_page == 2) {
      if (_walletNameController.text.trim().isEmpty) {
        showValidationSnackBar(context, 'Give your wallet a name so we know where money is coming from.');
        return;
      }
      if (!_isUsableAmount(_walletBalanceController.text)) {
        showValidationSnackBar(context, 'Enter a valid current balance.');
        return;
      }
    }
    if (_page == _lastPage) {
      _finish();
      return;
    }
    _pageController.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _back() {
    if (_page == 0) return;
    _pageController.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// Triggers the OS camera-permission prompt now (mirrors how
  /// ReceiptScanScreen initializes a controller) so the user isn't asked
  /// again the first time they open Scan Receipt.
  Future<void> _requestCameraPermission() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final controller = CameraController(cameras.first, ResolutionPreset.low, enableAudio: false);
      await controller.initialize();
      await controller.dispose();
    } catch (e, stackTrace) {
      developer.log('Onboarding camera permission request failed', error: e, stackTrace: stackTrace, name: 'OnboardingScreen');
    }
  }

  /// Each write is issued on its own so a hung server ack can't stop the
  /// next one from reaching the local cache — the profile update is what
  /// routes the user out of onboarding, so it has to land either way.
  Future<void> _queuedWrite(Future<void> Function() write) async {
    try {
      await write().timeout(_writeTimeout);
    } on TimeoutException {
      developer.log('Onboarding write not acknowledged yet; it will sync later', name: 'OnboardingScreen');
    }
  }

  Future<void> _finish() async {
    if (_busy) return;
    setState(() => _busy = true);

    // Resolved before the first await: the profile update routes this screen
    // away the moment it lands, and ref is unusable once we're disposed.
    final pinStore = ref.read(pinStoreProvider);
    final walletRepo = ref.read(walletRepositoryProvider);
    final profileRepo = ref.read(userProfileRepositoryProvider);
    final unlocked = ref.read(appUnlockedProvider.notifier);
    final notifications = ref.read(notificationServiceProvider);

    try {
      // Permissions FIRST, while this screen is still mounted and in front of
      // the user. The profile write below flips onboardingComplete, which
      // redirects away the instant it lands locally — anything asked after
      // that would pop over the dashboard instead of reading as part of setup.
      await _requestCameraPermission();
      if (_notifPrefs.budgetAlerts || _notifPrefs.billReminders || _notifPrefs.savingsGoalReminders) {
        await notifications.requestPermission();
      }

      if (_lockType == AppLockType.pin && _pinController.text.trim().length >= 4) {
        await pinStore.savePin(_pinController.text.trim());
      }

      // Remembered across retries: if a later step fails and the user taps
      // Get Started again, a brand-new account must not end up with two
      // wallets.
      if (!_walletCreated) {
        await _queuedWrite(() => walletRepo.create(WalletDraft(
              name: _walletNameController.text.trim(),
              type: _walletType,
              startingBalance: _parseMoney(_walletBalanceController.text) ?? Money.zero,
              colorHex: '#2a78d6',
            )));
        _walletCreated = true;
      }

      final current = await profileRepo.get();
      await _queuedWrite(() => profileRepo.update(current.copyWith(
            displayName: _nameController.text.trim(),
            currencySymbol: _currency,
            monthlyIncome: _parseMoney(_incomeController.text),
            monthlyBudget: _parseMoney(_budgetController.text),
            financialGoal: _goal,
            notificationPrefs: _notifPrefs,
            appLockType: _lockType,
            onboardingComplete: true,
          )));
      if (_lockType != AppLockType.none) {
        unlocked.state = true;
      }
    } catch (e, stackTrace) {
      developer.log('Finishing onboarding failed', error: e, stackTrace: stackTrace, name: 'OnboardingScreen');
      if (mounted) showValidationSnackBar(context, "Couldn't finish setting up. Please try again.");
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: List.generate(_lastPage + 1, (i) {
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= _page ? colors.brand : colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [_profileStep(colors), _goalStep(colors), _walletStep(colors), _preferencesStep(colors)],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    if (_page > 0) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _back,
                          child: const Text('Back'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: _page > 0 ? 2 : 1,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _next,
                        child: Text(_busy
                            ? 'Setting up…'
                            : _page == _lastPage
                                ? 'Get Started'
                                : 'Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _profileStep(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors.brandSoft, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Icon(LucideIcons.wallet, size: 26, color: colors.brand),
          ),
          const SizedBox(height: 20),
          Text('Welcome to SpendSense', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text("Let's set up your profile — everything stays on this device.",
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 28),
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Display name (optional)')),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _currency,
            decoration: const InputDecoration(labelText: 'Preferred currency'),
            items: const [
              DropdownMenuItem(value: '₱', child: Text('₱ Philippine Peso')),
              DropdownMenuItem(value: '\$', child: Text('\$ US Dollar')),
              DropdownMenuItem(value: '€', child: Text('€ Euro')),
            ],
            onChanged: (v) => setState(() => _currency = v ?? '₱'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _incomeController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Monthly income (optional)'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _budgetController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Monthly budget (optional)'),
          ),
        ],
      ),
    );
  }

  Widget _goalStep(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What brings you here?', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Pick your primary financial goal.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 24),
          for (final option in _goalOptions)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SelectCard(
                icon: option.icon,
                label: option.label,
                selected: _goal == option.goal,
                onTap: () => setState(() => _goal = option.goal),
              ),
            ),
        ],
      ),
    );
  }

  Widget _walletStep(AppColors colors) {
    const types = [
      (type: WalletType.cash, label: 'Cash', icon: LucideIcons.banknote),
      (type: WalletType.bank, label: 'Bank', icon: LucideIcons.landmark),
      (type: WalletType.eWallet, label: 'E-Wallet', icon: LucideIcons.smartphone),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add your first wallet', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('Where do you keep your money? You can add more later.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 24),
          Row(
            children: [
              for (final option in types) ...[
                Expanded(
                  child: _SelectCard(
                    compact: true,
                    icon: option.icon,
                    label: option.label,
                    selected: _walletType == option.type,
                    onTap: () => setState(() {
                      _walletType = option.type;
                      _walletNameController.text = option.label == 'E-Wallet' ? 'GCash' : option.label;
                    }),
                  ),
                ),
                if (option != types.last) const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _walletNameController,
            decoration: const InputDecoration(labelText: 'Wallet name'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _walletBalanceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(
              labelText: 'Current balance',
              prefixText: '$_currency ',
            ),
          ),
        ],
      ),
    );
  }

  Widget _preferencesStep(AppColors colors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Preferences', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text('You can change these anytime in Settings.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colors.textSecondary)),
          const SizedBox(height: 20),
          Text('Notifications', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            "We'll ask for camera and notification access when you finish, so nothing interrupts you later.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          SwitchListTile(
            title: const Text('Budget alerts'),
            subtitle: const Text('When a budget hits 80% or goes over'),
            value: _notifPrefs.budgetAlerts,
            onChanged: (v) => setState(() => _notifPrefs = _notifPrefs.copyWith(budgetAlerts: v)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Bill reminders'),
            subtitle: const Text('When a recurring bill is due or auto-paid'),
            value: _notifPrefs.billReminders,
            onChanged: (v) => setState(() => _notifPrefs = _notifPrefs.copyWith(billReminders: v)),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            title: const Text('Savings goal reminders'),
            subtitle: const Text('Progress nudges and auto-contributions'),
            value: _notifPrefs.savingsGoalReminders,
            onChanged: (v) => setState(() => _notifPrefs = _notifPrefs.copyWith(savingsGoalReminders: v)),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          Text('App lock (optional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SelectCard(
                  compact: true,
                  icon: LucideIcons.lockOpen,
                  label: 'None',
                  selected: _lockType == AppLockType.none,
                  onTap: () => setState(() => _lockType = AppLockType.none),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectCard(
                  compact: true,
                  icon: LucideIcons.keyRound,
                  label: 'PIN',
                  selected: _lockType == AppLockType.pin,
                  onTap: () => setState(() => _lockType = AppLockType.pin),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SelectCard(
                  compact: true,
                  icon: LucideIcons.fingerprint,
                  label: 'Biometric',
                  selected: _lockType == AppLockType.biometric,
                  onTap: () => setState(() => _lockType = AppLockType.biometric),
                ),
              ),
            ],
          ),
          if (_lockType == AppLockType.pin) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              obscureText: true,
              maxLength: 6,
              decoration: const InputDecoration(labelText: 'Set a 4-6 digit PIN'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  const _SelectCard({required this.icon, required this.label, required this.selected, required this.onTap, this.compact = false});

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 16 : 14),
        decoration: BoxDecoration(
          color: selected ? colors.brandSoft : colors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? colors.brand : Colors.transparent, width: 1.5),
        ),
        child: compact
            ? Column(
                children: [
                  Icon(icon, size: 20, color: selected ? colors.brand : colors.textSecondary),
                  const SizedBox(height: 6),
                  Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? colors.brand : colors.textSecondary)),
                ],
              )
            : Row(
                children: [
                  Icon(icon, size: 20, color: selected ? colors.brand : colors.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
                  if (selected) Icon(LucideIcons.circleCheck, size: 18, color: colors.brand),
                ],
              ),
      ),
    );
  }
}
