import 'package:cloud_firestore/cloud_firestore.dart';

/// Thin wrapper over a per-user Firestore subcollection.
///
/// Every domain repository stores its documents under
/// `users/{uid}/{name}/{docId}`, so one signed-in user's data is fully
/// isolated and a single security rule covers the whole app. Sorting and
/// filtering stay in Dart rather than in Firestore queries, so the
/// repositories keep the exact ordering contracts the in-memory versions
/// established without needing a composite index for every screen.
class FirestoreCollection<T> {
  FirestoreCollection({
    required this.firestore,
    required this.uid,
    required this.name,
    required this.toJson,
    required this.fromJson,
  });

  final FirebaseFirestore firestore;
  final String uid;
  final String name;
  final Map<String, dynamic> Function(T value) toJson;
  final T Function(String id, Map<String, dynamic> json) fromJson;

  CollectionReference<Map<String, dynamic>> get ref => firestore.collection('users').doc(uid).collection(name);

  Stream<List<T>> watch() {
    return ref.snapshots().map((snap) => snap.docs.map((d) => fromJson(d.id, d.data())).toList());
  }

  Future<List<T>> getAll() async {
    final snap = await ref.get();
    return snap.docs.map((d) => fromJson(d.id, d.data())).toList();
  }

  Future<T?> getById(String id) async {
    final doc = await ref.doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    return fromJson(doc.id, data);
  }

  /// Writes with a caller-supplied id so entity ids stay client-generated
  /// UUIDs, matching how the rest of the app creates them.
  Future<void> put(String id, T value) => ref.doc(id).set(toJson(value));

  Future<void> delete(String id) => ref.doc(id).delete();
}
