import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:direct/core/models/contact_model.dart';
import 'package:direct/core/models/message_model.dart';
import 'package:direct/core/database/local_db.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('LocalDatabase Edge Cases & Hardening Tests', () {
    late Database rawDb;
    late LocalDatabase localDb;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Create v3 schema
      await rawDb.execute('''
        CREATE TABLE contacts (
          username TEXT PRIMARY KEY,
          identity_public_key TEXT NOT NULL,
          safety_number TEXT NOT NULL,
          is_verified INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          disappearing_seconds INTEGER NOT NULL DEFAULT 0
        )
      ''');

      await rawDb.execute('''
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

      localDb = LocalDatabase.withDatabase(rawDb);
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('SQL injection payloads in usernames and contents are safely sanitized', () async {
      const maliciousUser = "attacker'; DROP TABLE messages; --";
      const maliciousContent = "Hello'; DELETE FROM contacts; SELECT 'pwned";

      final contact = ContactModel(
        username: maliciousUser,
        identityPublicKey: 'test-key',
        safetyNumber: '1111 2222',
        createdAt: 1000,
      );

      // Save contact with SQL injection username
      await localDb.saveContact(contact);
      final retrievedContact = await localDb.getContact(maliciousUser);
      expect(retrievedContact?.username, maliciousUser.toLowerCase());

      // Save message with SQL injection content
      final msg = MessageModel(
        id: 'msg-sql-1',
        conversationUser: maliciousUser,
        sender: maliciousUser,
        recipient: 'alice',
        content: maliciousContent,
        timestamp: 1000,
        status: MessageStatus.sent,
        isOutgoing: false,
      );
      await localDb.saveMessage(msg);

      // Verify tables still exist and message is intact
      final messages = await localDb.getMessages(maliciousUser);
      expect(messages.length, 1);
      expect(messages.first.content, maliciousContent);
    });

    test('Duplicate message insertion updates existing record without error or duplicates', () async {
      const msgId = 'unique-id-999';

      final initialMsg = MessageModel(
        id: msgId,
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Original attempt',
        timestamp: 1000,
        status: MessageStatus.pending,
        isOutgoing: true,
      );
      await localDb.saveMessage(initialMsg);

      // Re-send / duplicate arrival with updated status
      final updatedMsg = initialMsg.copyWith(
        status: MessageStatus.delivered,
        content: 'Updated content',
      );
      await localDb.saveMessage(updatedMsg);

      final list = await localDb.getMessages('bob');
      expect(list.length, 1); // Not duplicated
      expect(list.first.status, MessageStatus.delivered);
      expect(list.first.content, 'Updated content');
    });

    test('Conversation with all messages expired returns contact with lastMessage == null without crash', () async {
      final contact = ContactModel(
        username: 'charlie',
        identityPublicKey: 'key',
        safetyNumber: '1111',
        createdAt: 1000,
      );
      await localDb.saveContact(contact);

      // Add a message that expires at T=2000
      await localDb.saveMessage(MessageModel(
        id: 'msg-charlie',
        conversationUser: 'charlie',
        sender: 'charlie',
        recipient: 'alice',
        content: 'Ephemeral hello',
        timestamp: 1000,
        status: MessageStatus.read,
        isOutgoing: false,
        expiresAt: 2000,
      ));

      // Before expiry at T=1500
      final convsBefore = await localDb.getConversations(1500);
      expect(convsBefore.first.lastMessage, isNotNull);

      // After expiry at T=2500
      final convsAfter = await localDb.getConversations(2500);
      expect(convsAfter.length, 1);
      expect(convsAfter.first.contact.username, 'charlie');
      expect(convsAfter.first.lastMessage, isNull);
      expect(convsAfter.first.unreadCount, 0);

      final msgsAfter = await localDb.getMessages('charlie', 2500);
      expect(msgsAfter.isEmpty, true);
    });

    test('Exact boundary expiry: now == expires_at is purged, now == expires_at - 1 is retained', () async {
      const boundaryTime = 50000;

      await localDb.saveMessage(MessageModel(
        id: 'msg-boundary',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Boundary test',
        timestamp: 1000,
        status: MessageStatus.sent,
        isOutgoing: true,
        expiresAt: boundaryTime,
      ));

      // 1 ms before boundary: retained
      final msgsBefore = await localDb.getMessages('bob', boundaryTime - 1);
      expect(msgsBefore.length, 1);

      // Exactly at boundary: purged
      final msgsAt = await localDb.getMessages('bob', boundaryTime);
      expect(msgsAt.isEmpty, true);
    });

    test('wipeAllData completely empties database and allows clean re-use', () async {
      await localDb.saveContact(ContactModel(
        username: 'user1',
        identityPublicKey: 'key1',
        safetyNumber: '1111',
        createdAt: 1000,
      ));

      await localDb.saveMessage(MessageModel(
        id: 'm1',
        conversationUser: 'user1',
        sender: 'user1',
        recipient: 'me',
        content: 'test',
        timestamp: 1000,
        status: MessageStatus.delivered,
        isOutgoing: false,
      ));

      expect((await localDb.getAllContacts()).length, 1);
      expect((await localDb.getMessages('user1')).length, 1);

      // Burn account / wipe all data
      await localDb.wipeAllData();

      expect((await localDb.getAllContacts()).isEmpty, true);
      expect((await localDb.getConversations()).isEmpty, true);
      expect((await localDb.getMessages('user1')).isEmpty, true);

      // Clean re-use after wipe
      await localDb.saveContact(ContactModel(
        username: 'fresh_user',
        identityPublicKey: 'key2',
        safetyNumber: '2222',
        createdAt: 2000,
      ));
      expect((await localDb.getAllContacts()).length, 1);
    });
  });
}
