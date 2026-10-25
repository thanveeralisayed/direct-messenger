import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  static const _channel = MethodChannel('com.direct.chat/security');
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: true),
  );

  static const _keyAppLock = 'direct_app_lock_enabled';
  static const _keyScreenshotBlock = 'direct_screenshot_block_enabled';

  // --- Screenshot / Task Switcher Privacy (FLAG_SECURE) ---

  Future<void> setScreenshotProtection(bool enable) async {
    await _storage.write(key: _keyScreenshotBlock, value: enable ? '1' : '0');
    try {
      await _channel.invokeMethod('setSecureFlag', {'enable': enable});
    } catch (_) {
      // Desktop / Web / unsupported platforms ignore native channel gracefully
    }
  }

  Future<bool> isScreenshotProtectionEnabled() async {
    final val = await _storage.read(key: _keyScreenshotBlock);
    // Default to true for zero-knowledge privacy
    return val == null || val == '1';
  }

  // --- Biometric & Device Lock ---

  Future<bool> canAuthenticate() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheck || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate({String reason = 'Unlock Direct Chat'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
      );
    } catch (_) {
      return false;
    }
  }

  Future<bool> isAppLockEnabled() async {
    final val = await _storage.read(key: _keyAppLock);
    return val == '1';
  }

  Future<void> setAppLockEnabled(bool enable) async {
    await _storage.write(key: _keyAppLock, value: enable ? '1' : '0');
  }
}
