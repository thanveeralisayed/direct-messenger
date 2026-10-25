import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:direct/core/crypto/crypto_service.dart';

void main() {
  group('Cryptographic Advanced Edge Cases & Extreme Payload Robustness', () {
    late CryptoService crypto;

    setUp(() {
      crypto = CryptoService();
    });

    test('Unicode, multi-byte UTF-8, RTL, and complex emoji sequences roundtrip with exact fidelity', () async {
      final aliceKeyPair = await crypto.generateIdentityKeyPair();
      final alicePubKey = await aliceKeyPair.extractPublicKey();

      final extremeUnicodeTexts = [
        'Hello World! 🚀 Direct E2EE',
        'Complex emojis: 👨‍👩‍👧‍👦 🏳️‍🌈 👩🏽‍💻 🕵️‍♂️ 🦄',
        'RTL Arabic: مرحبا بك في تطبيق دايركت للمحادثات المشفرة',
        'RTL Hebrew: שלום עולם! אבטחה מקצה לקצה',
        'East Asian: 🔒 终极端到端加密 - プライバシー保護 - 개인정보 보호',
        'Devanagari: नमस्ते दुनिया! पूर्णतया सुरक्षित संदेश',
        'Accents & Symbols: Ça va être l\'été! ¿Dónde está el baño? § ± © ® ™ € £ ¥',
        'Control characters & newlines: Line 1\r\nLine 2\tTabbed\bBackspace\u0000NullChar',
        'Mathematical & Greek: ∀x ∈ ℝ, ∃y : y > x, α β γ δ π ∑ ∏ √ ∫ ∞',
      ];

      for (final text in extremeUnicodeTexts) {
        final payload = await crypto.encryptMessage(
          plaintext: text,
          recipientPublicKey: alicePubKey,
        );

        final decrypted = await crypto.decryptMessage(
          payload: payload,
          recipientKeyPair: aliceKeyPair,
        );

        expect(decrypted, equals(text), reason: 'Failed for text: $text');
      }
    });

    test('Attacker corrupts ephemeral public key: Decryption rejects and throws exception', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      final payload = await crypto.encryptMessage(
        plaintext: 'Top secret communication',
        recipientPublicKey: pubKey,
      );

      // Tamper with the ephemeral public key by flipping bits
      final rawKeyBytes = base64Decode(payload.ephemeralPublicKey);
      rawKeyBytes[0] ^= 0xAA;
      final tamperedKey = base64Encode(rawKeyBytes);

      final tamperedPayload = EncryptedPayload(
        ephemeralPublicKey: tamperedKey,
        iv: payload.iv,
        ciphertext: payload.ciphertext,
      );

      expect(
        () async => await crypto.decryptMessage(
          payload: tamperedPayload,
          recipientKeyPair: keyPair,
        ),
        throwsA(anything),
      );
    });

    test('Corrupted base64 formatting in payload fields fails gracefully with exception', () async {
      final keyPair = await crypto.generateIdentityKeyPair();

      // Non-base64 characters
      final garbagePayload1 = EncryptedPayload(
        ephemeralPublicKey: '@@@NOT_BASE_64!!!###',
        iv: 'valid-base-64==',
        ciphertext: 'valid-base-64==',
      );
      expect(
        () async => await crypto.decryptMessage(payload: garbagePayload1, recipientKeyPair: keyPair),
        throwsA(anything),
      );

      // Malformed IV
      final garbagePayload2 = EncryptedPayload(
        ephemeralPublicKey: 'dGVzdA==',
        iv: '???NOT_BASE64???',
        ciphertext: 'dGVzdA==',
      );
      expect(
        () async => await crypto.decryptMessage(payload: garbagePayload2, recipientKeyPair: keyPair),
        throwsA(anything),
      );
    });

    test('High-volume sequential messages produce strictly distinct ephemeral keypairs and nonces', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      final ephemeralKeys = <String>{};
      final ivs = <String>{};
      final ciphertexts = <String>{};

      const iterations = 50;
      for (int i = 0; i < iterations; i++) {
        final payload = await crypto.encryptMessage(
          plaintext: 'Message iteration: $i',
          recipientPublicKey: pubKey,
        );

        // Every single message MUST use a unique ephemeral key
        expect(ephemeralKeys.contains(payload.ephemeralPublicKey), isFalse);
        ephemeralKeys.add(payload.ephemeralPublicKey);

        // Every single message MUST use a unique IV/nonce
        expect(ivs.contains(payload.iv), isFalse);
        ivs.add(payload.iv);

        // Every ciphertext must be unique
        expect(ciphertexts.contains(payload.ciphertext), isFalse);
        ciphertexts.add(payload.ciphertext);
      }

      expect(ephemeralKeys.length, equals(iterations));
      expect(ivs.length, equals(iterations));
    });

    test('Large binary simulated payload (500 KB) encrypts and decrypts with 100% byte integrity', () async {
      final keyPair = await crypto.generateIdentityKeyPair();
      final pubKey = await keyPair.extractPublicKey();

      // 500 KB binary payload
      final largeBytes = Uint8List(500 * 1024);
      for (int i = 0; i < largeBytes.length; i++) {
        largeBytes[i] = (i * 31 + 17) % 256;
      }
      final largeBase64 = base64Encode(largeBytes);

      final payload = await crypto.encryptMessage(
        plaintext: largeBase64,
        recipientPublicKey: pubKey,
      );

      final decrypted = await crypto.decryptMessage(
        payload: payload,
        recipientKeyPair: keyPair,
      );

      expect(decrypted, equals(largeBase64));
      final recoveredBytes = base64Decode(decrypted);
      expect(recoveredBytes, equals(largeBytes));
    });
  });
}
