import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptedPayload {
  final String ephemeralPublicKey; // Base64
  final String iv; // Base64 (12 bytes)
  final String ciphertext; // Base64 (ciphertext + 16-byte GCM tag)

  EncryptedPayload({
    required this.ephemeralPublicKey,
    required this.iv,
    required this.ciphertext,
  });

  Map<String, dynamic> toJson() => {
        'ephemeralPublicKey': ephemeralPublicKey,
        'iv': iv,
        'ciphertext': ciphertext,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      ephemeralPublicKey: json['ephemeralPublicKey'] as String,
      iv: json['iv'] as String,
      ciphertext: json['ciphertext'] as String,
    );
  }
}

class CryptoService {
  final X25519 _keyExchange = X25519();
  final AesGcm _cipher = AesGcm.with256bits();
  final Sha256 _hash = Sha256();

  /// Generates a new long-term identity key pair for the user
  Future<SimpleKeyPair> generateIdentityKeyPair() async {
    return await _keyExchange.newKeyPair();
  }

  /// Exports a key pair's public key as a Base64 string
  Future<String> exportPublicKey(SimpleKeyPair keyPair) async {
    final pk = await keyPair.extractPublicKey();
    return base64Encode(pk.bytes);
  }

  /// Exports private key bytes as Base64 for local secure storage
  Future<String> exportPrivateKey(SimpleKeyPair keyPair) async {
    final pkData = await keyPair.extract();
    return base64Encode(pkData.bytes);
  }

  /// Imports private key bytes from Base64 string and derives key pair
  Future<SimpleKeyPair> importPrivateKey(String base64PrivateKey) async {
    final bytes = base64Decode(base64PrivateKey);
    return await _keyExchange.newKeyPairFromSeed(bytes);
  }

  /// Imports a public key from Base64 string
  SimplePublicKey importPublicKey(String base64PublicKey) {
    final bytes = base64Decode(base64PublicKey);
    return SimplePublicKey(bytes, type: KeyPairType.x25519);
  }

  /// Derives an AES-256 key from a Diffie-Hellman shared secret using HKDF
  Future<SecretKey> _deriveAesKey({
    required SimpleKeyPair localKeyPair,
    required SimplePublicKey remotePublicKey,
    required List<int> salt,
  }) async {
    final sharedSecret = await _keyExchange.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );

    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    return await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('Direct-E2EE-Session'),
    );
  }

  /// Encrypts a message using Ephemeral Diffie-Hellman + AES-256-GCM (Forward Secrecy per message)
  Future<EncryptedPayload> encryptMessage({
    required String plaintext,
    required SimplePublicKey recipientPublicKey,
  }) async {
    // 1. Generate an ephemeral one-time keypair for this message
    final ephemeralKeyPair = await _keyExchange.newKeyPair();
    final ephemeralPublicKey = await ephemeralKeyPair.extractPublicKey();

    // 2. Derive shared symmetric secret between ephemeral private key and recipient public key
    final salt = _cipher.newNonce();
    final aesKey = await _deriveAesKey(
      localKeyPair: ephemeralKeyPair,
      remotePublicKey: recipientPublicKey,
      salt: salt,
    );

    // 3. Encrypt payload
    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await _cipher.encrypt(
      plaintextBytes,
      secretKey: aesKey,
      nonce: salt,
    );

    return EncryptedPayload(
      ephemeralPublicKey: base64Encode(ephemeralPublicKey.bytes),
      iv: base64Encode(secretBox.nonce),
      ciphertext: base64Encode(secretBox.cipherText + secretBox.mac.bytes),
    );
  }

  /// Decrypts a message using recipient's identity private key and the message's ephemeral public key
  Future<String> decryptMessage({
    required EncryptedPayload payload,
    required SimpleKeyPair recipientKeyPair,
  }) async {
    final ephemeralPkBytes = base64Decode(payload.ephemeralPublicKey);
    final ephemeralPublicKey = SimplePublicKey(ephemeralPkBytes, type: KeyPairType.x25519);
    final nonce = base64Decode(payload.iv);
    final combinedCiphertext = base64Decode(payload.ciphertext);

    // AES-GCM tag is the last 16 bytes
    if (combinedCiphertext.length < 16) {
      throw Exception('Ciphertext is too short to contain authentication tag');
    }

    final cipherTextBytes = combinedCiphertext.sublist(0, combinedCiphertext.length - 16);
    final macBytes = combinedCiphertext.sublist(combinedCiphertext.length - 16);

    // Derive shared symmetric secret
    final aesKey = await _deriveAesKey(
      localKeyPair: recipientKeyPair,
      remotePublicKey: ephemeralPublicKey,
      salt: nonce,
    );

    final secretBox = SecretBox(
      cipherTextBytes,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final decryptedBytes = await _cipher.decrypt(
      secretBox,
      secretKey: aesKey,
    );

    return utf8.decode(decryptedBytes);
  }

  /// Generates a human-readable safety number / fingerprint for out-of-band key verification
  Future<String> generateFingerprint(String publicKeyBase64) async {
    final hash = await _hash.hash(base64Decode(publicKeyBase64));
    final hex = hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
    // Format into 6 blocks of 4 digits: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX
    final blocks = <String>[];
    for (int i = 0; i < 24; i += 4) {
      blocks.add(hex.substring(i, i + 4));
    }
    return blocks.join(' ');
  }
}
