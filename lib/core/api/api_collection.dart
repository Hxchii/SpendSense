import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:spendsense/core/api/api_client.dart';

/// Thin wrapper over one per-account collection on the SpendSense API.
///
/// Deliberately mirrors the interface of the Firestore version it replaces, so
/// each domain repository swaps one constructor call and keeps its own
/// serialization untouched.
///
/// Two differences are worth knowing about:
///
/// * There is no server push. [watch] serves a locally cached list and
///   re-emits it after every write, which keeps the UI as immediate as it was
///   before; what it no longer does is notice a change made on another device
///   until something calls [refresh].
/// * Firestore's `Timestamp` cannot be JSON-encoded, so writes normalize it to
///   an ISO-8601 string, which the API stores as a real timestamp and returns
///   in the same form. The repositories' existing decoders already accept ISO
///   strings, so none of them needed changing.
class ApiCollection<T> {
  ApiCollection({
    required this.client,
    required this.name,
    required this.toJson,
    required this.fromJson,
    required this.idOf,
  });

  final ApiClient client;
  final String name;
  final Map<String, dynamic> Function(T value) toJson;
  final T Function(String id, Map<String, dynamic> json) fromJson;

  /// Lets a local write update the cache in place instead of costing a second
  /// round trip just to learn what the server already agreed to store.
  final String Function(T value) idOf;

  List<T>? _cache;
  final _controller = StreamController<List<T>>.broadcast();

  /// Each subscriber gets its own list. Firestore handed out a fresh list per
  /// snapshot, and some repositories sort what they receive in place — with a
  /// shared cache that would quietly reorder every other subscriber's data.
  Stream<List<T>> watch() async* {
    yield <T>[...(_cache ?? await getAll())];
    yield* _controller.stream.map((items) => <T>[...items]);
  }

  Future<List<T>> getAll() async {
    final response = await client.get('/$name');
    final rows = (response is Map ? response['data'] : null) as List<dynamic>? ?? const [];
    final items = rows.whereType<Map<String, dynamic>>().map(_parse).whereType<T>().toList();
    _cache = items;
    return items;
  }

  Future<T?> getById(String id) async {
    try {
      final response = await client.get('/$name/$id');
      final row = (response is Map ? response['data'] : null) as Map<String, dynamic>?;
      return row == null ? null : _parse(row);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Writes with a caller-supplied id so entity ids stay client-generated
  /// UUIDs, matching how the rest of the app creates them.
  Future<void> put(String id, T value) async {
    await client.put('/$name/$id', _normalize(toJson(value)));
    final next = <T>[...?_cache?.where((e) => idOf(e) != id), value];
    _cache = next;
    _controller.add(next);
  }

  Future<void> delete(String id) async {
    await client.delete('/$name/$id');
    final next = <T>[...?_cache?.where((e) => idOf(e) != id)];
    _cache = next;
    _controller.add(next);
  }

  /// Re-reads from the server and notifies watchers. Used by pull-to-refresh,
  /// since nothing else will surface a change made elsewhere.
  Future<void> refresh() async {
    _controller.add(await getAll());
  }

  T? _parse(Map<String, dynamic> row) {
    final id = row['id'];
    if (id is! String) return null;
    return fromJson(id, row);
  }

  /// Recursively replaces values the JSON encoder can't handle. Firestore's
  /// `Timestamp` is the only one the repositories produce today, but DateTime
  /// is covered too so a future repository can't silently break encoding.
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
