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

  group('Disappearing Messages Model Tests', () {
    test('ContactModel correctly stores and copies disappearingSeconds', () {
      final contact = ContactModel(
        username: 'bob',
        identityPublicKey: 'test-key-base64',
        safetyNumber: '1234 5678',
        createdAt: 1000,
        disappearingSeconds: 86400, // 24 hours
      );

      expect(contact.disappearingSeconds, 86400);

      final map = contact.toMap();
      expect(map['disappearing_seconds'], 86400);

      final restored = ContactModel.fromMap(map);
      expect(restored.disappearingSeconds, 86400);

      final updated = contact.copyWith(disappearingSeconds: 0);
      expect(updated.disappearingSeconds, 0);
    });

    test('MessageModel isExpired logic and serialization', () {
      final now = DateTime.now().millisecondsSinceEpoch;

      final permanentMsg = MessageModel(
        id: 'msg-1',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'I live forever',
        timestamp: now,
        status: MessageStatus.delivered,
        isOutgoing: true,
        expiresAt: null,
      );
      expect(permanentMsg.isExpired, false);

      final expiredMsg = MessageModel(
        id: 'msg-2',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'I disappear fast',
        timestamp: now - 5000,
        status: MessageStatus.delivered,
        isOutgoing: true,
        expiresAt: now - 1000, // Expired 1 second ago
      );
      expect(expiredMsg.isExpired, true);

      final map = expiredMsg.toMap();
      expect(map['expires_at'], now - 1000);

      final restored = MessageModel.fromMap(map);
      expect(restored.expiresAt, now - 1000);
      expect(restored.isExpired, true);
    });
  });

  group('Disappearing Messages LocalDatabase Integration Tests', () {
    late Database rawDb;
    late LocalDatabase localDb;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

      // Create v2 tables
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

    test('Full lifecycle: save, query before expiry, auto-purge on expiry, fallback summary', () async {
      const baseTime = 1700000000000;

      // 1. Save contact
      final bob = ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key-data',
        safetyNumber: '9999 8888',
        createdAt: baseTime,
        disappearingSeconds: 30, // 30 seconds timer
      );
      await localDb.saveContact(bob);

      // 2. Insert messages with staggered expiration:
      // Msg A: Permanent (no expiration)
      await localDb.saveMessage(MessageModel(
        id: 'msg-a',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Permanent message A',
        timestamp: baseTime,
        status: MessageStatus.read,
        isOutgoing: false,
        expiresAt: null,
      ));

      // Msg B: Expires in 30 seconds (baseTime + 30,000)
      await localDb.saveMessage(MessageModel(
        id: 'msg-b',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Disappearing message B (30s)',
        timestamp: baseTime + 1000,
        status: MessageStatus.delivered,
        isOutgoing: true,
        expiresAt: baseTime + 30000,
      ));

      // Msg C: Expires in 60 seconds (baseTime + 60,000)
      await localDb.saveMessage(MessageModel(
        id: 'msg-c',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Disappearing message C (60s)',
        timestamp: baseTime + 2000,
        status: MessageStatus.delivered,
        isOutgoing: true,
        expiresAt: baseTime + 60000,
      ));

      // Msg D: Incoming Unread message, expires in 30 seconds
      await localDb.saveMessage(MessageModel(
        id: 'msg-d',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Unread secret from Bob',
        timestamp: baseTime + 3000,
        status: MessageStatus.delivered,
        isOutgoing: false,
        expiresAt: baseTime + 30000,
      ));

      // 3. At T + 10s: None have expired
      final msgsT10 = await localDb.getMessages('bob', baseTime + 10000);
      expect(msgsT10.length, 4);

      final convsT10 = await localDb.getConversations(baseTime + 10000);
      expect(convsT10.length, 1);
      expect(convsT10.first.unreadCount, 1); // Msg D is unread
      expect(convsT10.first.lastMessage?.id, 'msg-d'); // Latest is D

      // 4. At T + 35s: Msg B and Msg D have expired!
      final purgedCount1 = await localDb.purgeExpiredMessages(baseTime + 35000);
      expect(purgedCount1, 2); // exactly B and D purged

      final msgsT35 = await localDb.getMessages('bob', baseTime + 35000);
      expect(msgsT35.length, 2);
      expect(msgsT35.map((m) => m.id).toList(), ['msg-a', 'msg-c']);

      final convsT35 = await localDb.getConversations(baseTime + 35000);
      expect(convsT35.first.unreadCount, 0); // Msg D was purged, unread dropped to 0!
      expect(convsT35.first.lastMessage?.id, 'msg-c'); // Latest valid is now Msg C

      // 5. At T + 65s: Msg C has also expired!
      final purgedCount2 = await localDb.purgeExpiredMessages(baseTime + 65000);
      expect(purgedCount2, 1); // C purged

      final msgsT65 = await localDb.getMessages('bob', baseTime + 65000);
      expect(msgsT65.length, 1);
      expect(msgsT65.first.id, 'msg-a'); // Only Msg A remains

      final convsT65 = await localDb.getConversations(baseTime + 65000);
      expect(convsT65.first.lastMessage?.id, 'msg-a'); // Summary falls back to Msg A

      // 6. At T + 1,000,000s (Years later): Msg A is never deleted
      final purgedFuture = await localDb.purgeExpiredMessages(baseTime + 1000000000);
      expect(purgedFuture, 0);

      final msgsFuture = await localDb.getMessages('bob', baseTime + 1000000000);
      expect(msgsFuture.length, 1);
      expect(msgsFuture.first.id, 'msg-a');
    });

    test('Updating contact disappearing timer updates setting', () async {
      final contact = ContactModel(
        username: 'alice',
        identityPublicKey: 'alice-key',
        safetyNumber: '1111 2222',
        createdAt: 1000,
        disappearingSeconds: 0,
      );
      await localDb.saveContact(contact);

      await localDb.updateContactDisappearingTimer('alice', 3600);
      final updated = await localDb.getContact('alice');
      expect(updated?.disappearingSeconds, 3600);
    });
  });
}
