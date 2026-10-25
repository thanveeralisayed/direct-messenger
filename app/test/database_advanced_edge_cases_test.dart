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

  group('LocalDatabase Advanced Edge Cases & Multi-User State Isolation', () {
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

      await rawDb.execute('''
        CREATE INDEX idx_messages_conversation 
        ON messages (conversation_user, timestamp ASC)
      ''');

      localDb = LocalDatabase.withDatabase(rawDb);
    });

    tearDown(() async {
      await rawDb.close();
    });

    test('Unread counts across multiple contacts with markConversationAsRead isolation', () async {
      // Setup Bob and Charlie contacts
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));
      await localDb.saveContact(ContactModel(
        username: 'charlie',
        identityPublicKey: 'charlie-key',
        safetyNumber: '2222',
        createdAt: 1000,
      ));

      // Bob sends 3 incoming messages
      for (int i = 1; i <= 3; i++) {
        await localDb.saveMessage(MessageModel(
          id: 'bob-msg-$i',
          conversationUser: 'bob',
          sender: 'bob',
          recipient: 'alice',
          content: 'Bob msg $i',
          timestamp: 2000 + i,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ));
      }

      // Alice sends 1 outgoing message to Bob (MUST NOT count towards unread)
      await localDb.saveMessage(MessageModel(
        id: 'alice-out-1',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Outgoing to Bob',
        timestamp: 2005,
        status: MessageStatus.sent,
        isOutgoing: true,
      ));

      // Charlie sends 2 incoming messages
      for (int i = 1; i <= 2; i++) {
        await localDb.saveMessage(MessageModel(
          id: 'charlie-msg-$i',
          conversationUser: 'charlie',
          sender: 'charlie',
          recipient: 'alice',
          content: 'Charlie msg $i',
          timestamp: 2010 + i,
          status: MessageStatus.delivered,
          isOutgoing: false,
        ));
      }

      // Check initial unread counts
      final convsBefore = await localDb.getConversations();
      final bobConvBefore = convsBefore.firstWhere((c) => c.contact.username == 'bob');
      final charlieConvBefore = convsBefore.firstWhere((c) => c.contact.username == 'charlie');

      expect(bobConvBefore.unreadCount, equals(3));
      expect(charlieConvBefore.unreadCount, equals(2));

      // Mark Bob conversation as read
      await localDb.markConversationAsRead('bob');

      final convsAfter = await localDb.getConversations();
      final bobConvAfter = convsAfter.firstWhere((c) => c.contact.username == 'bob');
      final charlieConvAfter = convsAfter.firstWhere((c) => c.contact.username == 'charlie');

      // Bob unread count reset to 0; Charlie unread count remains 2
      expect(bobConvAfter.unreadCount, equals(0));
      expect(charlieConvAfter.unreadCount, equals(2));

      // Check message statuses in Bob's thread: incoming are 'read', outgoing is still 'sent'
      final bobMessages = await localDb.getMessages('bob');
      final incomingBob = bobMessages.where((m) => !m.isOutgoing);
      final outgoingBob = bobMessages.where((m) => m.isOutgoing);

      for (final m in incomingBob) {
        expect(m.status, equals(MessageStatus.read));
      }
      for (final m in outgoingBob) {
        expect(m.status, equals(MessageStatus.sent));
      }
    });

    test('deleteConversation strictly removes thread messages while leaving contact and other threads intact', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));
      await localDb.saveContact(ContactModel(
        username: 'charlie',
        identityPublicKey: 'charlie-key',
        safetyNumber: '2222',
        createdAt: 1000,
      ));

      await localDb.saveMessage(MessageModel(
        id: 'msg-b1',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Hi from Bob',
        timestamp: 1000,
        status: MessageStatus.read,
        isOutgoing: false,
      ));
      await localDb.saveMessage(MessageModel(
        id: 'msg-c1',
        conversationUser: 'charlie',
        sender: 'charlie',
        recipient: 'alice',
        content: 'Hi from Charlie',
        timestamp: 1000,
        status: MessageStatus.read,
        isOutgoing: false,
      ));

      // Delete Bob's conversation
      await localDb.deleteConversation('bob');

      // Bob's messages are wiped
      final bobMsgs = await localDb.getMessages('bob');
      expect(bobMsgs.isEmpty, isTrue);

      // Charlie's messages remain intact
      final charlieMsgs = await localDb.getMessages('charlie');
      expect(charlieMsgs.length, equals(1));
      expect(charlieMsgs.first.content, equals('Hi from Charlie'));

      // Both contacts still exist in the database
      final contacts = await localDb.getAllContacts();
      expect(contacts.length, equals(2));

      // Bob conversation summary shows lastMessage == null
      final convs = await localDb.getConversations();
      final bobSummary = convs.firstWhere((c) => c.contact.username == 'bob');
      expect(bobSummary.lastMessage, isNull);
    });

    test('Out-of-order insertion: getMessages guarantees strict chronological ascending sort order', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));

      // Insert messages in intentionally scrambled chronological order
      final timestamps = [5000, 1000, 4000, 2000, 3000];
      for (final ts in timestamps) {
        await localDb.saveMessage(MessageModel(
          id: 'msg-ts-$ts',
          conversationUser: 'bob',
          sender: 'bob',
          recipient: 'alice',
          content: 'Timestamp $ts',
          timestamp: ts,
          status: MessageStatus.read,
          isOutgoing: false,
        ));
      }

      final messages = await localDb.getMessages('bob');
      expect(messages.length, equals(5));

      // Verify strict ascending order
      for (int i = 0; i < messages.length - 1; i++) {
        expect(messages[i].timestamp < messages[i + 1].timestamp, isTrue);
      }
      expect(messages.first.timestamp, equals(1000));
      expect(messages.last.timestamp, equals(5000));
    });

    test('Conversations list is strictly sorted descending by the latest message activity timestamp', () async {
      await localDb.saveContact(ContactModel(username: 'user1', identityPublicKey: 'k1', safetyNumber: '1', createdAt: 100));
      await localDb.saveContact(ContactModel(username: 'user2', identityPublicKey: 'k2', safetyNumber: '2', createdAt: 200));
      await localDb.saveContact(ContactModel(username: 'user3', identityPublicKey: 'k3', safetyNumber: '3', createdAt: 300));

      // user2 sent latest message at T=10000
      await localDb.saveMessage(MessageModel(
        id: 'm2',
        conversationUser: 'user2',
        sender: 'user2',
        recipient: 'alice',
        content: 'Latest',
        timestamp: 10000,
        status: MessageStatus.delivered,
        isOutgoing: false,
      ));

      // user1 sent message at T=5000
      await localDb.saveMessage(MessageModel(
        id: 'm1',
        conversationUser: 'user1',
        sender: 'user1',
        recipient: 'alice',
        content: 'Older',
        timestamp: 5000,
        status: MessageStatus.delivered,
        isOutgoing: false,
      ));

      // user3 has no messages, only createdAt at T=300

      final convs = await localDb.getConversations();
      expect(convs.length, equals(3));
      // First is user2 (T=10000)
      expect(convs[0].contact.username, equals('user2'));
      // Second is user1 (T=5000)
      expect(convs[1].contact.username, equals('user1'));
      // Third is user3 (T=300)
      expect(convs[2].contact.username, equals('user3'));
    });

    test('High volume stress test: Insert 100 messages and query with perfect integrity', () async {
      await localDb.saveContact(ContactModel(
        username: 'stress_user',
        identityPublicKey: 'key',
        safetyNumber: '1234',
        createdAt: 1000,
      ));

      for (int i = 0; i < 100; i++) {
        await localDb.saveMessage(MessageModel(
          id: 'stress-msg-$i',
          conversationUser: 'stress_user',
          sender: i.isEven ? 'stress_user' : 'alice',
          recipient: i.isEven ? 'alice' : 'stress_user',
          content: 'Stress message payload content iteration $i',
          timestamp: 1000 + i,
          status: MessageStatus.sent,
          isOutgoing: i.isOdd,
        ));
      }

      final messages = await localDb.getMessages('stress_user');
      expect(messages.length, equals(100));
      expect(messages.first.id, equals('stress-msg-0'));
      expect(messages.last.id, equals('stress-msg-99'));
    });
  });
}
