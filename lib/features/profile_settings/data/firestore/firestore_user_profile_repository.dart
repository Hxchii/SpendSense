import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/profile_settings/domain/repositories/user_profile_repository.dart';

/// The profile is a single document (`users/{uid}`) rather than a
/// subcollection, so it doesn't use FirestoreCollection.
class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository({required FirebaseFirestore firestore, required String uid})
      : _doc = firestore.collection('users').doc(uid);

  final DocumentReference<Map<String, dynamic>> _doc;

  static Map<String, dynamic> _toJson(UserProfile p) => {
        'displayName': p.displayName,
        'currencySymbol': p.currencySymbol,
        'monthlyIncomeMinor': p.monthlyIncome?.minorUnits,
        'monthlyBudgetMinor': p.monthlyBudget?.minorUnits,
        'financialGoal': p.financialGoal.name,
        'customGoalText': p.customGoalText,
        'themeMode': p.themeMode.name,
        'notificationPrefs': {
          'budgetAlerts': p.notificationPrefs.budgetAlerts,
          'billReminders': p.notificationPrefs.billReminders,
          'savingsGoalReminders': p.notificationPrefs.savingsGoalReminders,
        },
        'appLockType': p.appLockType.name,
        'onboardingComplete': p.onboardingComplete,
      };

  static UserProfile _fromJson(Map<String, dynamic> json) {
    final prefs = json['notificationPrefs'] as Map<String, dynamic>? ?? const {};
    return UserProfile(
      displayName: json['displayName'] as String? ?? '',
      currencySymbol: json['currencySymbol'] as String? ?? '₱',
      monthlyIncome: _money(json['monthlyIncomeMinor']),
      monthlyBudget: _money(json['monthlyBudgetMinor']),
      financialGoal: FinancialGoal.values.firstWhere(
        (g) => g.name == json['financialGoal'],
        orElse: () => FinancialGoal.trackDaily,
      ),
      customGoalText: json['customGoalText'] as String?,
      themeMode: AppThemeMode.values.firstWhere(
        (m) => m.name == json['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      notificationPrefs: NotificationPrefs(
        budgetAlerts: prefs['budgetAlerts'] as bool? ?? true,
        billReminders: prefs['billReminders'] as bool? ?? true,
        savingsGoalReminders: prefs['savingsGoalReminders'] as bool? ?? true,
      ),
      appLockType: AppLockType.values.firstWhere(
        (t) => t.name == json['appLockType'],
        orElse: () => AppLockType.none,
      ),
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    );
  }

  static Money? _money(Object? v) => v == null ? null : Money((v as num).toInt());

  @override
  Stream<UserProfile> watch() {
    return _doc.snapshots().map((snap) {
      final data = snap.data();
      // No document yet means a brand-new install: a default profile has
      // onboardingComplete false, which is what routes the user to onboarding.
      return data == null ? const UserProfile() : _fromJson(data);
    });
  }

  @override
  Future<UserProfile> get() async {
    final snap = await _doc.get();
    final data = snap.data();
    return data == null ? const UserProfile() : _fromJson(data);
  }

  @override
  Future<UserProfile> update(UserProfile profile) async {
    await _doc.set(_toJson(profile), SetOptions(merge: true));
    return profile;
  }
}
