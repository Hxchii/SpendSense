import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/account_bootstrap.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

/// The signed-in user's uid, or null while auth is still resolving.
///
/// Sign-in is anonymous: the app has no login screen by design (it's a
/// personal, on-device finance tracker), but Firestore still needs a stable
/// identity to scope and secure each user's documents under `users/{uid}`.
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid;
});

/// The uid, asserted to exist. Repository providers use this because the app
/// shell gates the entire UI behind [ensureSignedInProvider] — nothing that
/// reads a repository can build before sign-in has resolved.
final requireUidProvider = Provider<String>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) throw StateError('Repository accessed before sign-in resolved.');
  return uid;
});

/// Ensures an anonymous session exists. Watched once at app startup.
final ensureSignedInProvider = FutureProvider<User>((ref) async {
  final auth = ref.watch(firebaseAuthProvider);
  final existing = auth.currentUser;
  if (existing != null) return existing;
  final credential = await auth.signInAnonymously();
  return credential.user!;
});

/// Signs in, then writes the default categories for a brand-new account.
/// The whole UI waits on this, so by the time any screen builds there is
/// both a uid and a usable category list.
final appSessionProvider = FutureProvider<void>((ref) async {
  final user = await ref.watch(ensureSignedInProvider.future);
  await bootstrapAccount(firestore: ref.watch(firestoreProvider), uid: user.uid);
});
