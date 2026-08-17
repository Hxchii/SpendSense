import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/firebase/firebase_providers.dart';
import 'package:spendsense/features/profile_settings/data/firestore/firestore_user_profile_repository.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/profile_settings/domain/repositories/user_profile_repository.dart';

/// THE swap point for the profile/settings domain.
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return FirestoreUserProfileRepository(firestore: ref.watch(firestoreProvider), uid: ref.watch(requireUidProvider));
});

final userProfileProvider = StreamProvider<UserProfile>((ref) {
  return ref.watch(userProfileRepositoryProvider).watch();
});
