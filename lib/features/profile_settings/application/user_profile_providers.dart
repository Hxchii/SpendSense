import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spendsense/core/api/api_client.dart';
import 'package:spendsense/features/profile_settings/data/api/api_user_profile_repository.dart';
import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';
import 'package:spendsense/features/profile_settings/domain/repositories/user_profile_repository.dart';

/// THE swap point for the profile/settings domain.
final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return ApiUserProfileRepository(client: ref.watch(apiClientProvider));
});

final userProfileProvider = StreamProvider<UserProfile>((ref) {
  return ref.watch(userProfileRepositoryProvider).watch();
});
