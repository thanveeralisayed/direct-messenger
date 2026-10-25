import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cryptography/cryptography.dart';
import 'package:direct/core/models/contact_model.dart';
import 'package:direct/core/models/message_model.dart';
import 'package:direct/core/database/local_db.dart';
import 'package:direct/core/network/relay_client.dart';
import 'package:direct/providers/auth_provider.dart';
import 'package:direct/providers/chat_provider.dart';

// Fake RelayClient for unit testing without network
class FakeRelayClient extends RelayClient {
  final messageController = StreamController<Map<String, dynamic>>.broadcast();
  final ackController = StreamController<Map<String, dynamic>>.broadcast();
  final deliveryController = StreamController<Map<String, dynamic>>.broadcast();
  final typingController = StreamController<Map<String, dynamic>>.broadcast();

  final List<Map<String, dynamic>> sentPackets = [];

  FakeRelayClient() : super(baseUrl: 'http://fake.test');

  @override
  Stream<Map<String, dynamic>> get onMessageReceived => messageController.stream;
  @override
  Stream<Map<String, dynamic>> get onServerAck => ackController.stream;
  @override
  Stream<Map<String, dynamic>> get onDeliveryReceipt => deliveryController.stream;
  @override
  Stream<Map<String, dynamic>> get onTyping => typingController.stream;

  @override
  void sendMessagePacket({
    required String id,
    required String to,
    required int timestamp,
    required String ephemeralPublicKey,
    required String iv,
    required String ciphertext,
    int? disappearingSeconds,
  }) {
    sentPackets.add({
      'type': 'message',
      'id': id,
      'to': to,
      'timestamp': timestamp,
      'ephemeralPublicKey': ephemeralPublicKey,
      'iv': iv,
      'ciphertext': ciphertext,
      'disappearingSeconds': disappearingSeconds,
    });
  }

  @override
  void sendDeliveryAck({required String messageId, required String sender}) {
    sentPackets.add({
      'type': 'delivery_ack',
      'id': messageId,
      'sender': sender,
    });
  }

  @override
  void sendTyping({required String to, required bool isTyping}) {
    sentPackets.add({
      'type': 'typing',
      'to': to,
      'isTyping': isTyping,
    });
  }

  @override
  void dispose() {
    messageController.close();
    ackController.close();
    deliveryController.close();
    typingController.close();
    super.dispose();
  }
}

// Fake AuthProvider with predetermined credentials
class FakeAuthProvider extends AuthProvider {
  final FakeRelayClient _fakeRelay = FakeRelayClient();
  final SimpleKeyPair? _keyPair;

  FakeAuthProvider(this._keyPair);

  @override
  String? get username => 'alice';
  @override
  String? get token => 'fake-token-alice';
  @override
  SimpleKeyPair? get identityKeyPair => _keyPair;
  @override
  bool get isLoggedIn => true;
  @override
  RelayClient get relayClient => _fakeRelay;

  FakeRelayClient get fakeRelay => _fakeRelay;
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ChatProvider Comprehensive State & Event Handling Tests', () {
    late Database rawDb;
    late LocalDatabase localDb;
    late SimpleKeyPair aliceKeyPair;
    late FakeAuthProvider fakeAuth;
    late ChatProvider chatProvider;

    setUp(() async {
      rawDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

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

      aliceKeyPair = await X25519().newKeyPair();
      fakeAuth = FakeAuthProvider(aliceKeyPair);
      chatProvider = ChatProvider(authProvider: fakeAuth, db: localDb);
    });

    tearDown(() async {
      chatProvider.dispose();
      fakeAuth.fakeRelay.dispose();
      await rawDb.close();
    });

    test('Server Ack updates local message status to sent and notifies UI', () async {
      // Save initial pending message
      await localDb.saveMessage(MessageModel(
        id: 'msg-test-ack',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Hello Bob',
        timestamp: 1000,
        status: MessageStatus.pending,
        isOutgoing: true,
      ));

      await chatProvider.openChat('bob');
      expect(chatProvider.activeMessages.first.status, MessageStatus.pending);

      // Simulate incoming server ack
      fakeAuth.fakeRelay.ackController.add({'id': 'msg-test-ack'});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(chatProvider.activeMessages.first.status, MessageStatus.sent);
      final inDb = await localDb.getMessages('bob');
      expect(inDb.first.status, MessageStatus.sent);
    });

    test('Delivery Receipt updates local message status to delivered', () async {
      await localDb.saveMessage(MessageModel(
        id: 'msg-test-delivery',
        conversationUser: 'bob',
        sender: 'alice',
        recipient: 'bob',
        content: 'Ping Bob',
        timestamp: 1000,
        status: MessageStatus.sent,
        isOutgoing: true,
      ));

      await chatProvider.openChat('bob');
      expect(chatProvider.activeMessages.first.status, MessageStatus.sent);

      // Simulate delivery receipt from Bob
      fakeAuth.fakeRelay.deliveryController.add({'id': 'msg-test-delivery'});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(chatProvider.activeMessages.first.status, MessageStatus.delivered);
      final inDb = await localDb.getMessages('bob');
      expect(inDb.first.status, MessageStatus.delivered);
    });

    test('Real-time typing indicator updates isUserTyping map and state', () async {
      expect(chatProvider.isUserTyping('bob'), isFalse);

      // Bob starts typing
      fakeAuth.fakeRelay.typingController.add({'from': 'bob', 'isTyping': true});
      await Future.delayed(const Duration(milliseconds: 50));
      expect(chatProvider.isUserTyping('bob'), isTrue);

      // Case insensitivity check
      expect(chatProvider.isUserTyping('BOB'), isTrue);

      // Bob stops typing
      fakeAuth.fakeRelay.typingController.add({'from': 'bob', 'isTyping': false});
      await Future.delayed(const Duration(milliseconds: 50));
      expect(chatProvider.isUserTyping('bob'), isFalse);
    });

    test('openChat marks conversation as read and loads messages, closeChat cleans up', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));

      await localDb.saveMessage(MessageModel(
        id: 'unread-1',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Unread content',
        timestamp: 1000,
        status: MessageStatus.delivered,
        isOutgoing: false,
      ));

      // Before opening chat, check message is delivered
      final beforeMsgs = await localDb.getMessages('bob');
      expect(beforeMsgs.first.status, MessageStatus.delivered);

      // Open chat with bob
      await chatProvider.openChat('bob');
      expect(chatProvider.activeChatUser, 'bob');
      expect(chatProvider.activeContact?.username, 'bob');
      expect(chatProvider.activeMessages.length, 1);

      // After opening, message is marked as read
      final afterMsgs = await localDb.getMessages('bob');
      expect(afterMsgs.first.status, MessageStatus.read);

      // Close chat
      chatProvider.closeChat();
      expect(chatProvider.activeChatUser, isNull);
      expect(chatProvider.activeContact, isNull);
      expect(chatProvider.activeMessages.isEmpty, isTrue);
    });

    test('Disappearing timer toggle persists and updates activeContact', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
        disappearingSeconds: 0,
      ));

      await chatProvider.openChat('bob');
      expect(chatProvider.activeContact?.disappearingSeconds, 0);

      // Update disappearing timer to 300 seconds (5 minutes)
      await chatProvider.setDisappearingTimer('bob', 300);

      expect(chatProvider.activeContact?.disappearingSeconds, 300);
      final updatedContact = await localDb.getContact('bob');
      expect(updatedContact?.disappearingSeconds, 300);
    });

    test('Contact verification toggle persists and updates activeContact', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
        isVerified: false,
      ));

      await chatProvider.openChat('bob');
      expect(chatProvider.activeContact?.isVerified, isFalse);

      await chatProvider.setContactVerified('bob', true);
      expect(chatProvider.activeContact?.isVerified, isTrue);

      final inDb = await localDb.getContact('bob');
      expect(inDb?.isVerified, isTrue);
    });

    test('deleteChat removes messages and clears active messages if thread is open', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));
      await localDb.saveMessage(MessageModel(
        id: 'msg-del',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Ephemeral hello',
        timestamp: 1000,
        status: MessageStatus.read,
        isOutgoing: false,
      ));

      await chatProvider.openChat('bob');
      expect(chatProvider.activeMessages.length, 1);

      await chatProvider.deleteChat('bob');
      expect(chatProvider.activeMessages.isEmpty, isTrue);
      expect((await localDb.getMessages('bob')).isEmpty, isTrue);
    });

    test('wipeAllData completely empties all chat provider lists and local tables', () async {
      await localDb.saveContact(ContactModel(
        username: 'bob',
        identityPublicKey: 'bob-key',
        safetyNumber: '1111',
        createdAt: 1000,
      ));
      await localDb.saveMessage(MessageModel(
        id: 'msg-wipe',
        conversationUser: 'bob',
        sender: 'bob',
        recipient: 'alice',
        content: 'Burn everything',
        timestamp: 1000,
        status: MessageStatus.read,
        isOutgoing: false,
      ));

      await chatProvider.openChat('bob');
      await chatProvider.loadConversations();
      expect(chatProvider.conversations.isNotEmpty, isTrue);
      expect(chatProvider.activeMessages.isNotEmpty, isTrue);

      await chatProvider.wipeAllData();
      expect(chatProvider.conversations.isEmpty, isTrue);
      expect(chatProvider.activeMessages.isEmpty, isTrue);
      expect((await localDb.getAllContacts()).isEmpty, isTrue);
    });
  });
}
