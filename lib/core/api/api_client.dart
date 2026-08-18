import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:spendsense/core/api/api_base_url.dart';

/// Thrown when the API is unreachable or answers with an error, so callers can
/// tell a real failure from an empty result.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  /// The server is up but refused the request as unauthenticated — usually a
  /// token that expired while the app was backgrounded.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Talks to the SpendSense Laravel API.
///
/// Every request carries the caller's Firebase ID token; the server verifies
/// it and derives the account from the token's subject, so no uid is ever sent
/// in a path. Tokens are fetched per request rather than cached here because
/// the Firebase SDK already caches them and transparently refreshes one that
/// is close to expiring.
class ApiClient {
  ApiClient({required this.baseUrl, required this.auth, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final FirebaseAuth auth;
  final http.Client _http;

  /// Generous because a free-tier host suspends an idle service and takes
  /// most of a minute to wake — a shorter timeout means the first request
  /// after any quiet period always fails, which reads as the app being
  /// broken rather than merely slow.
  static const _timeout = Duration(seconds: 75);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  Future<Map<String, String>> _headers() async {
    final user = auth.currentUser;
    if (user == null) {
      throw ApiException('Not signed in.', statusCode: 401);
    }
    final token = await user.getIdToken();
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> put(String path, Map<String, dynamic> body) => _send('PUT', path, body: body);

  Future<dynamic> post(String path, Map<String, dynamic> body) => _send('POST', path, body: body);

  Future<void> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = _uri(path);
    final headers = await _headers();

    http.Response response;
    try {
      response = await switch (method) {
        'GET' => _http.get(uri, headers: headers),
        'PUT' => _http.put(uri, headers: headers, body: jsonEncode(body)),
        'POST' => _http.post(uri, headers: headers, body: jsonEncode(body)),
        'DELETE' => _http.delete(uri, headers: headers),
        _ => throw ArgumentError('Unsupported method $method'),
      }
          .timeout(_timeout);
    } catch (e) {
      throw ApiException("Couldn't reach the SpendSense server. Check your connection.");
    }

    if (response.statusCode == 204 || response.body.isEmpty) return null;

    final decoded = _decode(response);
    if (response.statusCode >= 400) {
      final message = decoded is Map && decoded['message'] is String
          ? decoded['message'] as String
          : 'Request failed (${response.statusCode}).';
      throw ApiException(message, statusCode: response.statusCode);
    }
    return decoded;
  }

  dynamic _decode(http.Response response) {
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      // A proxy or a PHP fatal error can return HTML; surfacing the raw body
      // would put a page of markup in front of the user.
      throw ApiException('The server returned an unexpected response.', statusCode: response.statusCode);
    }
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: ref.watch(apiBaseUrlProvider), auth: FirebaseAuth.instance);
});
