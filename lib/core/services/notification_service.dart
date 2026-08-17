import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// Thin wrapper around flutter_local_notifications. Only `show()` (an
/// immediate, right-now notification) is used — true scheduled/background
/// notifications (zonedSchedule/periodicallyShow) throw UnsupportedError on
/// web, so this app fires a real OS notification at the moment an existing
/// sweep (see recurring_bill_providers.dart / savings_goal_providers.dart)
/// detects something's due, rather than relying on the OS to wake the app.
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _nextId = 0;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(defaultActionName: 'Open'),
      );
      // Explicitly false/null means the platform plugin itself reported
      // failure (e.g. the web service worker didn't register) — don't mark
      // ready in that case, or every later call silently no-ops forever.
      final ok = await _plugin.initialize(settings: settings);
      _ready = ok ?? false;
      if (!_ready) {
        developer.log('NotificationService.initialize: platform returned $ok', name: 'NotificationService');
      }
    } catch (e) {
      // Never let a notification-setup failure break app startup — this is
      // a nice-to-have, not core functionality.
      developer.log('NotificationService.initialize failed: $e', name: 'NotificationService');
    }
  }

  /// Must be called from a real user gesture (a tap) — browsers silently
  /// auto-reject permission requests that aren't. Returns whether
  /// permission is granted after the call.
  Future<bool> requestPermission() async {
    if (!_ready) await initialize();
    if (!_ready) {
      developer.log('NotificationService.requestPermission: not initialized, cannot request', name: 'NotificationService');
      return false;
    }
    try {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<WebFlutterLocalNotificationsPlugin>();
        if (web == null) {
          developer.log('NotificationService.requestPermission: web plugin did not resolve', name: 'NotificationService');
          return false;
        }
        final granted = await web.requestNotificationsPermission() ?? false;
        developer.log('NotificationService.requestPermission (web): granted=$granted', name: 'NotificationService');
        return granted;
      }

      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;

      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;

      // Platforms with no explicit permission step (desktop Windows/Linux/macOS
      // notification-center style) — nothing to request, treat as available.
      return true;
    } catch (e) {
      developer.log('NotificationService.requestPermission failed: $e', name: 'NotificationService');
      return false;
    }
  }

  Future<void> show({required String title, required String body}) async {
    if (!_ready) await initialize();
    if (!_ready) return;
    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails('spendsense_reminders', 'Reminders', importance: Importance.defaultImportance),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
        linux: LinuxNotificationDetails(),
      );
      await _plugin.show(id: _nextId++, title: title, body: body, notificationDetails: details);
    } catch (e) {
      // A denied/unsupported browser permission ends up here — the in-app
      // dashboard banner still covers the same information either way.
      developer.log('NotificationService.show failed: $e', name: 'NotificationService');
    }
  }
}
