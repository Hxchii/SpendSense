import 'package:spendsense/features/profile_settings/domain/entities/user_profile.dart';

abstract class UserProfileRepository {
  Stream<UserProfile> watch();
  Future<UserProfile> get();
  Future<UserProfile> update(UserProfile profile);
}
