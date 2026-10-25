import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:direct/core/crypto/crypto_service.dart';

void main() {
  group('Cryptographic Edge Cases & Security Guarantees', () {
    late CryptoService crypto;

    setUp(() {
      crypto = CryptoService();
    });

    test('Ciphertext tampering / corrupted byte causes decryption to fail (Auth Tag Verification)', () async {
      final aliceKeyPair = await crypto.generateIdentityKeyPair();
      final alicePubKey = await aliceKeyPair.extractPublicKey();

      const secret = 'Highly classified payload';
      final payload = await crypto.encryptMessage(
        plaintext: secret,
        recipientPublicKey: alicePubKey,
      );

      // Tamper with ciphertext by flipping one byte
      final rawCipher = base64Decode(payload.ciphertext);
      rawCipher[0] ^= 0xFF; // Flip bits
      final tamperedPayload = EncryptedPayload(
        ephemeralPublicKey: payload.ephemeralPublicKey,
        iv: payload.iv,
        ciphertext: base64Encode(rawCipher),
      );

      // Decryption MUST throw an exception and reject tampered data
      expect(
        () async => await crypto.decryptMessage(
          payload: tamperedPayload,
          recipientKeyPair: aliceKeyPair,
        ),
        throwsA(anything),
      );
    });

    test('Decryption with wrong recipient private key fails completely', () async {
      final intendedRecipient = await crypto.generateIdentityKeyPair();
      final unintendedRecipient = await crypto.generateIdentityKeyPair();

      final intendedPubKey = await intendedRecipient.extractPublicKey();

      const secret = 'For intended recipient eyes only';
      final payload = await crypto.encryptMessage(
        plaintext: secret,
        recipientPublicKey: intendedPubKey,
      );

      // Unintended recipient tries to decrypt
      expect(
        () async => await crypto.decryptMessage(
          payload: payload,
          recipientKeyPair: unintendedRecipient,
        ),
        throwsA(anything),
      );
    });

    test('Ciphertext truncated before authentication tag throws explicit exception', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      final payload = await crypto.encryptMessage(
        plaintext: 'Test',
        recipientPublicKey: pubKey,
      );

      // Truncate to less than 16 bytes (AES-GCM tag is 16 bytes)
      final truncatedPayload = EncryptedPayload(
        ephemeralPublicKey: payload.ephemeralPublicKey,
        iv: payload.iv,
        ciphertext: base64Encode(Uint8List(8)), // Only 8 bytes
      );

      expect(
        () async => await crypto.decryptMessage(
          payload: truncatedPayload,
          recipientKeyPair: keyPair,
        ),
        throwsA(predicate((e) => e.toString().contains('Ciphertext is too short'))),
      );
    });

    test('Empty plaintext encryption and decryption works cleanly', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      final payload = await crypto.encryptMessage(
        plaintext: '',
        recipientPublicKey: pubKey,
      );

      final decrypted = await crypto.decryptMessage(
        payload: payload,
        recipientKeyPair: keyPair,
      );

      expect(decrypted, equals(''));
    });

    test('Large payload encryption (100 KB text) preserves exact data', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      // Create a large 100 KB string
      final largeString = 'Direct E2EE Chat Security Verification ' * 2600;

      final payload = await crypto.encryptMessage(
        plaintext: largeString,
        recipientPublicKey: pubKey,
      );

      final decrypted = await crypto.decryptMessage(
        payload: payload,
        recipientKeyPair: keyPair,
      );

      expect(decrypted, equals(largeString));
    });

    test('Nonce & Ephemeral Key Uniqueness: Encrypting the same message twice produces different ciphertexts', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      const text = 'Repeat message';
      final p1 = await crypto.encryptMessage(plaintext: text, recipientPublicKey: pubKey);
      final p2 = await crypto.encryptMessage(plaintext: text, recipientPublicKey: pubKey);

      // Ephemeral keys must be unique
      expect(p1.ephemeralPublicKey, isNot(equals(p2.ephemeralPublicKey)));
      // IVs must be unique
      expect(p1.iv, isNot(equals(p2.iv)));
      // Ciphertexts must be unique
      expect(p1.ciphertext, isNot(equals(p2.ciphertext)));
    });

    test('Fingerprint generation is deterministic for identical public keys and differs for different keys', () async {
      final k1 = await crypto.generateIdentityKeyPair();
      final k2 = await crypto.generateIdentityKeyPair();

      final pub1 = await crypto.exportPublicKey(k1);
      final pub2 = await crypto.exportPublicKey(k2);

      final fp1a = await crypto.generateFingerprint(pub1);
      final fp1b = await crypto.generateFingerprint(pub1);
      final fp2 = await crypto.generateFingerprint(pub2);

      expect(fp1a, equals(fp1b)); // Deterministic
      expect(fp1a, isNot(equals(fp2))); // Unique per key
      // Format: 6 blocks of 4 hex chars = 29 characters total including spaces
      expect(fp1a.split(' ').length, equals(6));
    });
  });
}
