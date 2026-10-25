import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:direct/core/models/contact_model.dart';
import 'package:direct/core/database/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Out-of-Band Key QR Verification Logic Tests', () {
    const targetUser = 'bob';
    const legitimatePubKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA-bob-original-key';
    const attackerFakePubKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA-ATTACKER-FAKE-KEY';

    VerificationResult verifyQr(String rawData, String target, String storedKey) {
      if (!rawData.startsWith('direct:key:')) {
        return VerificationResult(isValid: false, errorMessage: 'Invalid Direct QR code format');
      }
      final parts = rawData.split(':');
      if (parts.length < 4) {
        return VerificationResult(isValid: false, errorMessage: 'Malformed QR code payload');
      }
      final qrUsername = parts[2].toLowerCase();
      final qrPubKey = parts.sublist(3).join(':');

      if (qrUsername != target.toLowerCase()) {
        return VerificationResult(
          isValid: false,
          errorMessage: 'QR code belongs to @$qrUsername, but you are verifying @$target',
        );
      }

      if (storedKey != qrPubKey) {
        return VerificationResult(
          isValid: false,
          isMismatch: true,
          errorMessage: 'CRITICAL SECURITY WARNING: Public key does NOT match! Possible Man-in-the-Middle attack.',
        );
      }

      return VerificationResult(isValid: true, matchedUsername: qrUsername);
    }

    test('Valid QR code authenticates contact perfectly', () {
      final qrString = 'direct:key:$targetUser:$legitimatePubKey';
      final result = verifyQr(qrString, targetUser, legitimatePubKey);

      expect(result.isValid, true);
      expect(result.isMismatch, false);
      expect(result.matchedUsername, 'bob');
    });

    test('QR code for a different user is rejected', () {
      final qrString = 'direct:key:charlie:$legitimatePubKey';
      final result = verifyQr(qrString, targetUser, legitimatePubKey);

      expect(result.isValid, false);
      expect(result.isMismatch, false);
      expect(result.errorMessage, contains('belongs to @charlie'));
    });

    test('Key Mismatch triggers critical security warning (MitM protection)', () {
      final qrString = 'direct:key:$targetUser:$attackerFakePubKey';
      final result = verifyQr(qrString, targetUser, legitimatePubKey);

      expect(result.isValid, false);
      expect(result.isMismatch, true);
      expect(result.errorMessage, contains('CRITICAL SECURITY WARNING'));
    });

    test('Malformed and garbage strings fail gracefully without crashing', () {
      expect(verifyQr('https://example.com', targetUser, legitimatePubKey).isValid, false);
      expect(verifyQr('direct:invalid', targetUser, legitimatePubKey).isValid, false);
      expect(verifyQr('direct:key:', targetUser, legitimatePubKey).isValid, false);
      expect(verifyQr('', targetUser, legitimatePubKey).isValid, false);
    });

    test('LocalDatabase updates and persists verification state', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      await db.execute('''
        CREATE TABLE contacts (
          username TEXT PRIMARY KEY,
          identity_public_key TEXT NOT NULL,
          safety_number TEXT NOT NULL,
          is_verified INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          disappearing_seconds INTEGER NOT NULL DEFAULT 0
        )
      ''');

      final localDb = LocalDatabase.withDatabase(db);

      // Save initial unverified contact
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: legitimatePubKey,
        safetyNumber: '1234 5678',
        isVerified: false,
        createdAt: 1000,
      ));

      final initial = await localDb.getContact('bob');
      expect(initial?.isVerified, false);

      // Verify
      await localDb.updateContactVerification('bob', true);
      final verified = await localDb.getContact('bob');
      expect(verified?.isVerified, true);

      // Unverify
      await localDb.updateContactVerification('bob', false);
      final unverified = await localDb.getContact('bob');
      expect(unverified?.isVerified, false);

      await db.close();
    });
  });
}
