import 'package:spendsense/core/api/api_client.dart';

/// Asks the API to give this account its default categories.
///
/// The rule lives on the server rather than here, so it holds for any client
/// and an account created before a new default existed picks it up on its
/// next launch. The endpoint only writes categories that are genuinely
/// absent, which makes calling this on every launch safe.
Future<void> bootstrapAccount({required ApiClient client}) async {
  await client.post('/bootstrap', const {});
}
