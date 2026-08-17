import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/core/routing/app_router.dart';
import 'package:spendsense/core/services/notification_service.dart';
import 'package:spendsense/core/theme/app_theme.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';
import 'package:spendsense/features/profile_settings/application/user_profile_providers.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: SpendSenseApp()));
}

/// One-shot per app session — sets up the notification plugin (and, on web,
/// registers its service worker) without requesting permission yet. That
/// happens later, from an explicit user gesture (see settings_screen.dart).
final _notificationInitProvider = FutureProvider<void>((ref) {
  return ref.read(notificationServiceProvider).initialize();
});

class SpendSenseApp extends ConsumerStatefulWidget {
  const SpendSenseApp({super.key});

  @override
  ConsumerState<SpendSenseApp> createState() => _SpendSenseAppState();
}

class _SpendSenseAppState extends ConsumerState<SpendSenseApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Re-arms the app lock whenever the app leaves the foreground, so
  /// returning to it requires the PIN/biometric again. Without this the lock
  /// would only ever be checked once, at cold start.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      ref.read(appUnlockedProvider.notifier).state = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_notificationInitProvider);
    final session = ref.watch(appSessionProvider);

    return MaterialApp(
      title: 'SpendSense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: switch (session) {
        AsyncLoading() => const _SplashScreen(),
        AsyncError(:final error) => _StartupErrorScreen(error: error),
        _ => const _SignedInApp(),
      },
    );
  }
}

/// Everything past this point can assume a signed-in uid exists, which is
/// what lets the repository providers read it synchronously.
class _SignedInApp extends ConsumerWidget {
  const _SignedInApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(userProfileProvider).valueOrNull?.themeMode ?? AppThemeMode.system;

    return MaterialApp.router(
      title: 'SpendSense',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      },
      routerConfig: router,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text(
                "Couldn't connect to your account.",
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Check your internet connection and restart the app.\n\n$error',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
