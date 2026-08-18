import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:spendsense/core/config/environment.dart';
import 'package:spendsense/features/app_lock/application/app_lock_providers.dart';

/// Where the API lives, overridable at runtime.
///
/// The compiled-in `API_BASE_URL` is only a default. The server moves — a
/// laptop's LAN address changes with the network, and a hosted URL changes
/// when it is redeployed — and rebuilding and reinstalling an APK every time
/// that happens is not workable, especially for anyone testing a build they
/// did not compile. So the value is editable in Settings and remembered.
final apiBaseUrlProvider = StateProvider<String>((ref) => Environment.apiBaseUrl);

const _storageKey = 'api_base_url';

/// Reads the saved override, if any. Awaited during startup so the very first
/// request already goes to the right place.
Future<void> loadSavedApiBaseUrl(Ref ref) async {
  final storage = ref.read(secureStorageProvider);
  final saved = await storage.read(key: _storageKey);
  if (saved != null && saved.trim().isNotEmpty) {
    ref.read(apiBaseUrlProvider.notifier).state = saved.trim();
  }
}

// Take the pieces rather than a ref, so these work identically from a
// provider (Ref) and from a widget (WidgetRef), which have no common type.
Future<void> saveApiBaseUrl(FlutterSecureStorage storage, StateController<String> controller, String url) async {
  final normalized = normalizeBaseUrl(url);
  await storage.write(key: _storageKey, value: normalized);
  controller.state = normalized;
}

Future<void> clearApiBaseUrl(FlutterSecureStorage storage, StateController<String> controller) async {
  await storage.delete(key: _storageKey);
  controller.state = Environment.apiBaseUrl;
}

/// Accepts what a person would actually type — a bare host, a trailing slash,
/// a pasted `/api/health` — and turns it into the origin the client expects.
String normalizeBaseUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return url;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  url = url.replaceFirst(RegExp(r'/+$'), '');
  url = url.replaceFirst(RegExp(r'/api(/v1)?(/health)?$'), '');
  return url;
}
