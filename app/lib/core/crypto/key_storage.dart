import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

class KeyStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: true,
    ),
  );

  static const _keyToken = 'direct_auth_token';
  static const _keyUsername = 'direct_auth_username';
  static const _keyPrivateKey = 'direct_private_key';
  static const _keyPublicKey = 'direct_public_key';
  static const _keyServerUrl = 'direct_server_url';

  Future<void> saveAuthSession({
    required String token,
    required String username,
    required String privateKeyBase64,
    required String publicKeyBase64,
  }) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPrivateKey, value: privateKeyBase64);
    await _storage.write(key: _keyPublicKey, value: publicKeyBase64);
  }

  Future<String?> getToken() => _storage.read(key: _keyToken);
  Future<String?> getUsername() => _storage.read(key: _keyUsername);
  Future<String?> getPrivateKey() => _storage.read(key: _keyPrivateKey);
  Future<String?> getPublicKey() => _storage.read(key: _keyPublicKey);

  Future<String> getServerUrl() async {
    // In production mode (enableServerConfigUI == false), strictly use defaultServerUrl
    if (!AppConfig.enableServerConfigUI) {
      return AppConfig.defaultServerUrl;
    }

    final url = await _storage.read(key: _keyServerUrl);
    if (url != null && url.trim().isNotEmpty) {
      final trimmed = url.trim();
      // If a local IP was previously saved during testing, but the default URL is now a cloud URL, purge the stale local IP
      final isLocalStored = trimmed.contains('192.168.') || trimmed.contains('10.0.2.2') || trimmed.contains('localhost');
      final isCloudDefault = AppConfig.defaultServerUrl.startsWith('https://');
      if (isLocalStored && isCloudDefault) {
        await _storage.delete(key: _keyServerUrl);
        return AppConfig.defaultServerUrl;
      }
      return trimmed;
    }

    if (kIsWeb) return 'http://localhost:8080';
    return AppConfig.defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    await _storage.write(key: _keyServerUrl, value: url);
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPrivateKey);
    await _storage.delete(key: _keyPublicKey);
  }
}
