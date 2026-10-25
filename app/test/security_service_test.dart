import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:direct/core/security/security_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecurityService and App Lock Tests', () {
    late SecurityService security;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      security = SecurityService();
    });

    test('Screenshot protection is enabled by default for zero-knowledge privacy', () async {
      final defaultEnabled = await security.isScreenshotProtectionEnabled();
      expect(defaultEnabled, true);

      await security.setScreenshotProtection(false);
      final disabled = await security.isScreenshotProtectionEnabled();
      expect(disabled, false);

      await security.setScreenshotProtection(true);
      final reEnabled = await security.isScreenshotProtectionEnabled();
      expect(reEnabled, true);
    });

    test('App Lock persistence toggle works accurately', () async {
      final defaultLock = await security.isAppLockEnabled();
      expect(defaultLock, false);

      await security.setAppLockEnabled(true);
      final enabled = await security.isAppLockEnabled();
      expect(enabled, true);

      await security.setAppLockEnabled(false);
      final disabled = await security.isAppLockEnabled();
      expect(disabled, false);
    });
  });
}
