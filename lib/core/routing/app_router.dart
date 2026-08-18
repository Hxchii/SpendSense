import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:spendsense/core/routing/app_shell.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';
import 'package:spendsense/features/app_lock/presentation/screens/lock_screen.dart';
import 'package:spendsense/features/budgets/domain/entities/budget.dart';
import 'package:spendsense/features/budgets/presentation/screens/budget_form_screen.dart';
import 'package:spendsense/features/budgets/presentation/screens/budgets_screen.dart';
import 'package:spendsense/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:spendsense/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/profile_settings/presentation/screens/settings_screen.dart';
import 'package:spendsense/features/ai_assistant/presentation/screens/assistant_screen.dart';
import 'package:spendsense/features/receipts/domain/entities/receipt.dart';
import 'package:spendsense/features/receipts/presentation/screens/receipt_detail_screen.dart';
import 'package:spendsense/features/receipts/presentation/screens/receipt_review_screen.dart';
import 'package:spendsense/features/receipts/presentation/screens/receipt_scan_screen.dart';
import 'package:spendsense/features/receipts/presentation/screens/receipts_screen.dart';
import 'package:spendsense/features/recurring_bills/domain/entities/recurring_bill.dart';
import 'package:spendsense/features/recurring_bills/presentation/screens/recurring_bill_form_screen.dart';
import 'package:spendsense/features/recurring_bills/presentation/screens/recurring_bills_screen.dart';
import 'package:spendsense/features/reports/presentation/screens/reports_screen.dart';
import 'package:spendsense/features/savings_goals/domain/entities/savings_goal.dart';
import 'package:spendsense/features/savings_goals/presentation/screens/savings_goal_form_screen.dart';
import 'package:spendsense/features/savings_goals/presentation/screens/savings_goals_screen.dart';
import 'package:spendsense/features/transactions/domain/entities/transaction.dart';
import 'package:spendsense/features/transactions/presentation/screens/transaction_form_screen.dart';
import 'package:spendsense/features/transactions/presentation/screens/transactions_screen.dart';
import 'package:spendsense/features/wallets/domain/entities/wallet.dart';
import 'package:spendsense/features/wallets/presentation/screens/wallet_form_screen.dart';
import 'package:spendsense/features/wallets/presentation/screens/wallets_screen.dart';

class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(userProfileProvider, (previous, next) => notifyListeners());
    ref.listen(appUnlockedProvider, (previous, next) => notifyListeners());
  }
}

final _routerRefreshProvider = Provider<_RouterRefreshNotifier>((ref) => _RouterRefreshNotifier(ref));

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final profile = ref.read(userProfileProvider).valueOrNull;
      final loc = state.matchedLocation;

      // The profile is unknown only while it is still loading or after the
      // request failed. Never route to the lock screen on that basis: the lock
      // screen has no way out while the profile stays unknown, which would
      // strand the user outside their own app with no recovery. Startup
      // already waits for the profile (see appSessionProvider), so reaching
      // here means something went wrong, and the screens' own error states
      // explain it far better than a lock screen can.
      if (profile == null) {
        return loc == '/lock' ? '/' : null;
      }
      if (!profile.onboardingComplete) {
        return loc.startsWith('/onboarding') ? null : '/onboarding';
      }
      if (loc.startsWith('/onboarding')) return '/';

      final needsLock = profile.appLockType != AppLockType.none;
      final unlocked = ref.read(appUnlockedProvider);
      if (needsLock && !unlocked) {
        return loc == '/lock' ? null : '/lock';
      }
      if ((!needsLock || unlocked) && loc == '/lock') return '/';

      return null;
    },
    routes: [
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingScreen()),
      GoRoute(path: '/lock', builder: (context, state) => const LockScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
          GoRoute(path: '/transactions', builder: (context, state) => const TransactionsScreen()),
          GoRoute(path: '/budgets', builder: (context, state) => const BudgetsScreen()),
          GoRoute(path: '/assistant', builder: (context, state) => const AssistantScreen()),
          GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
        ],
      ),
      GoRoute(
        path: '/wallets',
        builder: (context, state) => const WalletsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (context, state) => const WalletFormScreen()),
          GoRoute(path: 'edit', builder: (context, state) => WalletFormScreen(wallet: state.extra as Wallet?)),
        ],
      ),
      GoRoute(
        path: '/transactions/new',
        builder: (context, state) => const TransactionFormScreen(),
      ),
      GoRoute(
        path: '/transactions/edit',
        builder: (context, state) => TransactionFormScreen(transaction: state.extra as Transaction?),
      ),
      GoRoute(path: '/budgets/new', builder: (context, state) => const BudgetFormScreen()),
      GoRoute(path: '/budgets/edit', builder: (context, state) => BudgetFormScreen(budget: state.extra as Budget?)),
      GoRoute(
        path: '/savings-goals',
        builder: (context, state) => const SavingsGoalsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (context, state) => const SavingsGoalFormScreen()),
          GoRoute(path: 'edit', builder: (context, state) => SavingsGoalFormScreen(goal: state.extra as SavingsGoal?)),
        ],
      ),
      GoRoute(
        path: '/recurring-bills',
        builder: (context, state) => const RecurringBillsScreen(),
        routes: [
          GoRoute(path: 'new', builder: (context, state) => const RecurringBillFormScreen()),
          GoRoute(path: 'edit', builder: (context, state) => RecurringBillFormScreen(bill: state.extra as RecurringBill?)),
        ],
      ),
      GoRoute(
        path: '/receipts',
        builder: (context, state) => const ReceiptsScreen(),
        routes: [
          GoRoute(path: 'scan', builder: (context, state) => const ReceiptScanScreen()),
          GoRoute(path: 'detail', builder: (context, state) => ReceiptDetailScreen(receipt: state.extra as Receipt)),
          GoRoute(
            path: 'review',
            // Reachable without valid `extra` on a hard page refresh (web) or a stale
            // deep link — there's no scan result to review in that case, so bounce
            // back to the receipts list instead of crashing on the cast.
            redirect: (context, state) => state.extra is ReceiptReviewArgs ? null : '/receipts',
            builder: (context, state) {
              final args = state.extra as ReceiptReviewArgs;
              return ReceiptReviewScreen(scanResult: args.scanResult, imagePath: args.imagePath);
            },
          ),
        ],
      ),
      GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
    ],
  );
});

class ReceiptReviewArgs {
  const ReceiptReviewArgs({required this.scanResult, required this.imagePath});
  final ReceiptScanResult scanResult;
  final String imagePath;
}
