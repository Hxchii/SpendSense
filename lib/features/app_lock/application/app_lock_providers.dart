import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecurePinStore {
  SecurePinStore(this._storage);
  final FlutterSecureStorage _storage;
  static const _key = 'spendsense_app_lock_pin';

  Future<void> savePin(String pin) => _storage.write(key: _key, value: pin);

  Future<bool> verifyPin(String pin) async => (await _storage.read(key: _key)) == pin;

  Future<bool> hasPin() async => (await _storage.read(key: _key)) != null;

  Future<void> clearPin() => _storage.delete(key: _key);
}

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) => const FlutterSecureStorage());

final pinStoreProvider = Provider<SecurePinStore>((ref) => SecurePinStore(ref.watch(secureStorageProvider)));

final localAuthProvider = Provider<LocalAuthentication>((ref) => LocalAuthentication());

/// Session-level unlock flag. Always resets to false on a fresh app start;
/// the router redirects to the lock screen whenever the profile requires a
/// lock and this is false.
final appUnlockedProvider = StateProvider<bool>((ref) => false);

Future<bool> tryBiometricUnlock(LocalAuthentication auth) async {
  try {
    final canCheck = await auth.canCheckBiometrics || await auth.isDeviceSupported();
    if (!canCheck) return false;
    return await auth.authenticate(
      localizedReason: 'Unlock SpendSense',
      persistAcrossBackgrounding: true,
    );
  } catch (_) {
    return false;
  }
}
