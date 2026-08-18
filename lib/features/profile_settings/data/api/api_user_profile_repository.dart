import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/core/utils/money.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/profile_settings/domain/repositories/user_profile_repository.dart';

/// Same repository, same contracts, backed by the Laravel API instead of
/// Firestore directly. The profile is a single document rather than a
/// subcollection, so it uses the dedicated `/profile` endpoints instead of
/// ApiCollection — the serialization below is unchanged from the Firestore
/// version. As there is no server push, [watch] serves a locally cached
/// profile and re-emits after every write, exactly as ApiCollection does.
class ApiUserProfileRepository implements UserProfileRepository {
  // ignore: prefer_initializing_formals — private field, public named param.
  ApiUserProfileRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  UserProfile? _cache;
  final _controller = StreamController<UserProfile>.broadcast();

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
  Stream<UserProfile> watch() async* {
    yield _cache ?? await get();
    yield* _controller.stream;
  }

  @override
  Future<UserProfile> get() async {
    final response = await _client.get('/profile');
    final data = (response is Map ? response['data'] : null) as Map<String, dynamic>?;
    // An empty object means no profile stored yet, i.e. a brand-new account:
    // a default profile has onboardingComplete false, which is what routes
    // the user to onboarding.
    final profile = data == null || data.isEmpty ? const UserProfile() : _fromJson(data);
    _cache = profile;
    return profile;
  }

  @override
  Future<UserProfile> update(UserProfile profile) async {
    await _client.put('/profile', _normalize(_toJson(profile)));
    _cache = profile;
    _controller.add(profile);
    return profile;
  }

  /// Recursively replaces values the JSON encoder can't handle, mirroring
  /// ApiCollection. The profile writes none today, but a field added later
  /// can't silently break encoding.
  static Map<String, dynamic> _normalize(Map<String, dynamic> json) {
    return json.map((key, value) => MapEntry(key, _normalizeValue(value)));
  }

  static dynamic _normalizeValue(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map<String, dynamic>) return _normalize(value);
    if (value is List) return value.map(_normalizeValue).toList();
    return value;
  }
}
