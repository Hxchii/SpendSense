import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
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
  // Watching the stream keeps this reactive to sign-out/sign-in, but its
  // first event only arrives on a microtask — so a synchronous read during
  // the first frame after startup would see null even though sign-in has
  // already completed. Falling back to the synchronously-available
  // currentUser closes that gap; without it the one-shot sweep providers
  // read a null uid, cache an error, and (being non-autoDispose) never retry.
  final fromStream = ref.watch(authStateProvider).valueOrNull;
  return fromStream?.uid ?? ref.watch(firebaseAuthProvider).currentUser?.uid;
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

/// Signs in, then has the API set up the account's default categories.
/// The whole UI waits on this, so by the time any screen builds there is
/// both a uid and a usable category list.
final appSessionProvider = FutureProvider<void>((ref) async {
  await ref.watch(ensureSignedInProvider.future);
  await bootstrapAccount(client: ref.watch(apiClientProvider));
});
