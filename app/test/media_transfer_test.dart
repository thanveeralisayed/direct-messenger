import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:direct/core/crypto/crypto_service.dart';
import 'package:direct/core/models/message_model.dart';
import 'package:direct/core/database/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Encrypted Media Transfer Tests', () {
    test('End-to-end binary payload encryption, decryption, and byte fidelity', () async {
      final crypto = CryptoService();

      // 1. Generate keys for Alice and Bob
      final aliceKeyPair = await crypto.generateIdentityKeyPair();
      final bobKeyPair = await crypto.generateIdentityKeyPair();
      final bobPubKey = await bobKeyPair.extractPublicKey();

      // 2. Simulate raw image bytes (e.g. 512 bytes of binary JPEG data)
      final originalBytes = Uint8List.fromList(List.generate(512, (i) => (i * 7 + 13) % 256));
      const originalCaption = 'Secret blueprint snapshot 📷';
      const originalFileName = 'blueprint.jpg';

      // 3. Package as media payload JSON
      final mediaPayloadJson = jsonEncode({
        'type': 'image',
        'caption': originalCaption,
        'fileName': originalFileName,
        'bytes': base64Encode(originalBytes),
      });

      // 4. Encrypt with Bob's public key (Forward Secrecy AES-256-GCM)
      final encryptedPayload = await crypto.encryptMessage(
        plaintext: mediaPayloadJson,
        recipientPublicKey: bobPubKey,
      );

      // Verify server cannot see the payload or filename
      expect(encryptedPayload.ciphertext, isNot(contains('blueprint')));
      expect(encryptedPayload.ciphertext, isNot(contains(originalCaption)));

      // 5. Bob decrypts the packet
      final decryptedJson = await crypto.decryptMessage(
        payload: encryptedPayload,
        recipientKeyPair: bobKeyPair,
      );

      final parsed = jsonDecode(decryptedJson) as Map<String, dynamic>;
      expect(parsed['type'], 'image');
      expect(parsed['caption'], originalCaption);
      expect(parsed['fileName'], originalFileName);

      final restoredBytes = base64Decode(parsed['bytes'] as String);
      expect(restoredBytes, equals(originalBytes));
    });

    test('LocalDatabase stores and retrieves image message metadata accurately', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Initialize v3 schema
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

      await db.execute('''
        CREATE TABLE messages (
          id TEXT PRIMARY KEY,
          conversation_user TEXT NOT NULL,
          sender TEXT NOT NULL,
          recipient TEXT NOT NULL,
          content TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          status TEXT NOT NULL,
          is_outgoing INTEGER NOT NULL,
          expires_at INTEGER,
          message_type TEXT NOT NULL DEFAULT 'text',
          media_path TEXT
        )
      ''');

      final localDb = LocalDatabase.withDatabase(db);

      final imgMsg = MessageModel(
        id: 'img-uuid-001',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Check this encrypted photo',
        timestamp: 1000,
        status: MessageStatus.delivered,
        isOutgoing: true,
        messageType: 'image',
        mediaPath: '/data/user/0/com.direct.chat/app_flutter/direct_media/photo.jpg',
      );

      await localDb.saveMessage(imgMsg);

      final messages = await localDb.getMessages('bob');
      expect(messages.length, 1);
      final retrieved = messages.first;
      expect(retrieved.id, 'img-uuid-001');
      expect(retrieved.isImage, true);
      expect(retrieved.messageType, 'image');
      expect(retrieved.mediaPath, '/data/user/0/com.direct.chat/app_flutter/direct_media/photo.jpg');
      expect(retrieved.content, 'Check this encrypted photo');

      await db.close();
    });
  });
}
