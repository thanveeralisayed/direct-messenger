import 'package:flutter_test/flutter_test.dart';
import 'package:direct/core/crypto/crypto_service.dart';

void main() {
  test('E2EE encryption and decryption between Alice and Bob', () async {
    final crypto = CryptoService();

    // 1. Generate identity key pairs for Alice and Bob
    final bobKeyPair = await crypto.generateIdentityKeyPair();

    final bobPublicKeyStr = await crypto.exportPublicKey(bobKeyPair);
    final bobPublicKey = crypto.importPublicKey(bobPublicKeyStr);

    // 2. Alice encrypts a secret message for Bob
    const originalSecret = 'Hello Bob! This is an end-to-end encrypted direct message 🔒';
    final encryptedPayload = await crypto.encryptMessage(
      plaintext: originalSecret,
      recipientPublicKey: bobPublicKey,
    );

    expect(encryptedPayload.ephemeralPublicKey.isNotEmpty, true);
    expect(encryptedPayload.iv.isNotEmpty, true);
    expect(encryptedPayload.ciphertext.isNotEmpty, true);
    expect(encryptedPayload.ciphertext, isNot(contains(originalSecret)));

    // 3. Bob decrypts the message using his private key
    final decryptedMessage = await crypto.decryptMessage(
      payload: encryptedPayload,
      recipientKeyPair: bobKeyPair,
    );

    expect(decryptedMessage, equals(originalSecret));

    // 4. Test Key Export and Import
    final bobPrivStr = await crypto.exportPrivateKey(bobKeyPair);
    final importedBobKeyPair = await crypto.importPrivateKey(bobPrivStr);

    final decryptedWithImported = await crypto.decryptMessage(
      payload: encryptedPayload,
      recipientKeyPair: importedBobKeyPair,
    );
    expect(decryptedWithImported, equals(originalSecret));

    // 5. Safety Fingerprint
    final fingerprint = await crypto.generateFingerprint(bobPublicKeyStr);
    expect(fingerprint.length, greaterThan(20));
  });
}
