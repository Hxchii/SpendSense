import 'dart:async';
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
  ///
  /// Only `paused` counts: `hidden` is also delivered on the way back up, and
  /// the biometric prompt itself can background the app — re-locking on
  /// either would bounce the user between the prompt and the lock screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;
    if (ref.read(biometricPromptActiveProvider)) return;
    ref.read(appUnlockedProvider.notifier).state = false;
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

/// A bare spinner reads as a hang once startup runs long, and it can: a
/// suspended free-tier server takes most of a minute to answer its first
/// request. Explaining that after a few seconds is the difference between
/// waiting and force-quitting.
class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  bool _slow = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (_slow) ...[
                const SizedBox(height: 24),
                Text(
                  'Waking up the server…',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'This can take up to a minute the first time after a while. It’s much quicker after that.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
