/// Central place for build-time flags. All toggled via --dart-define.
class Environment {
  Environment._();

  /// Adds artificial latency to mock repositories so loading states are
  /// actually exercised during development. Defaults on for realism.
  static const bool simulateMockLatency = bool.fromEnvironment(
    'SIMULATE_MOCK_LATENCY',
    defaultValue: true,
  );

  static const Duration mockLatency = Duration(milliseconds: 220);

  /// Base URL of the Laravel API, without a trailing slash.
  ///
  /// `php artisan serve --host=0.0.0.0` binds the machine's LAN address, so a
  /// phone on the same Wi-Fi reaches it at `http://<your-laptop-ip>:8000`.
  /// 10.0.2.2 is how the Android emulator refers to the host machine.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  /// Gemini is called through the API so the key stays on the server instead
  /// of shipping inside the APK, where it can be extracted. This flag only
  /// remains for running the app against Google directly during development.
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static bool get hasGeminiApiKey => geminiApiKey.isNotEmpty;

  static Future<void> latency() async {
    if (simulateMockLatency) await Future.delayed(mockLatency);
  }
}
