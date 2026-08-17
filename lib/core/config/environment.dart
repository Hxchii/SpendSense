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

  /// Once the real Laravel backend exists, this becomes the backend's own
  /// key management and this flag goes away. For now, the assistant calls
  /// Gemini directly from the app when a key is supplied via
  /// `--dart-define-from-file=env.json` (see env.example.json) — falls back
  /// to the fake assistant when no key is configured, so the app still runs
  /// standalone without one.
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
  static bool get hasGeminiApiKey => geminiApiKey.isNotEmpty;

  static Future<void> latency() async {
    if (simulateMockLatency) await Future.delayed(mockLatency);
  }
}
