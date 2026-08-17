import 'package:spendsense/core/utils/money.dart';

enum FinancialGoal { saveMore, trackDaily, reduceSpending, emergencyFund, payOffDebt, manageBudget, custom }

enum AppThemeMode { light, dark, system }

enum AppLockType { none, pin, biometric }

class NotificationPrefs {
  const NotificationPrefs({
    this.budgetAlerts = true,
    this.billReminders = true,
    this.savingsGoalReminders = true,
  });

  final bool budgetAlerts;
  final bool billReminders;
  final bool savingsGoalReminders;

  NotificationPrefs copyWith({
    bool? budgetAlerts,
    bool? billReminders,
    bool? savingsGoalReminders,
  }) {
    return NotificationPrefs(
      budgetAlerts: budgetAlerts ?? this.budgetAlerts,
      billReminders: billReminders ?? this.billReminders,
      savingsGoalReminders: savingsGoalReminders ?? this.savingsGoalReminders,
    );
  }
}

class UserProfile {
  const UserProfile({
    this.displayName = '',
    this.currencySymbol = '₱',
    this.monthlyIncome,
    this.monthlyBudget,
    this.financialGoal = FinancialGoal.trackDaily,
    this.customGoalText,
    this.themeMode = AppThemeMode.system,
    this.notificationPrefs = const NotificationPrefs(),
    this.appLockType = AppLockType.none,
    this.pinHash,
    this.onboardingComplete = false,
  });

  final String displayName;
  final String currencySymbol;
  final Money? monthlyIncome;
  final Money? monthlyBudget;
  final FinancialGoal financialGoal;
  final String? customGoalText;
  final AppThemeMode themeMode;
  final NotificationPrefs notificationPrefs;
  final AppLockType appLockType;
  final String? pinHash;
  final bool onboardingComplete;

  UserProfile copyWith({
    String? displayName,
    String? currencySymbol,
    Money? monthlyIncome,
    Money? monthlyBudget,
    FinancialGoal? financialGoal,
    String? customGoalText,
    AppThemeMode? themeMode,
    NotificationPrefs? notificationPrefs,
    AppLockType? appLockType,
    String? pinHash,
    bool? onboardingComplete,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
      currencySymbol: currencySymbol ?? this.currencySymbol,
      monthlyIncome: monthlyIncome ?? this.monthlyIncome,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      financialGoal: financialGoal ?? this.financialGoal,
      customGoalText: customGoalText ?? this.customGoalText,
      themeMode: themeMode ?? this.themeMode,
      notificationPrefs: notificationPrefs ?? this.notificationPrefs,
      appLockType: appLockType ?? this.appLockType,
      pinHash: pinHash ?? this.pinHash,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }
}
