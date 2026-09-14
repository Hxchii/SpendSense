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
  /// The hosted Laravel API is the default; local development can still
  /// override it with `--dart-define=API_BASE_URL=...`.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://spendsense-8h7o.onrender.com',
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
