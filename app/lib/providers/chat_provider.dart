import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/crypto_service.dart';
import '../core/database/local_db.dart';
import '../core/models/contact_model.dart';
import '../core/models/message_model.dart';
import 'auth_provider.dart';

class ChatProvider extends ChangeNotifier {
  final AuthProvider authProvider;
  final LocalDatabase _db = LocalDatabase.instance;
  final CryptoService _crypto = CryptoService();
  final Uuid _uuid = const Uuid();

  List<ConversationSummary> _conversations = [];
  List<ConversationSummary> get conversations => _conversations;

  String? _activeChatUser;
  String? get activeChatUser => _activeChatUser;

  ContactModel? _activeContact;
  ContactModel? get activeContact => _activeContact;

  List<MessageModel> _activeMessages = [];
  List<MessageModel> get activeMessages => _activeMessages;

  final Map<String, bool> _typingUsers = {};
  bool isUserTyping(String user) => _typingUsers[user.toLowerCase()] ?? false;

  StreamSubscription? _msgSub;
  StreamSubscription? _ackSub;
  StreamSubscription? _deliverySub;
  StreamSubscription? _typingSub;
  Timer? _purgeTimer;

  ChatProvider({required this.authProvider}) {
    _bindRelayEvents();
    loadConversations();
    _startPeriodicPurge();
  }

  void _bindRelayEvents() {
    final relay = authProvider.relayClient;

    _msgSub = relay.onMessageReceived.listen(_handleIncomingMessage);
    _ackSub = relay.onServerAck.listen(_handleServerAck);
    _deliverySub = relay.onDeliveryReceipt.listen(_handleDeliveryReceipt);
    _typingSub = relay.onTyping.listen(_handleTypingIndicator);
  }

  void _startPeriodicPurge() {
    _purgeTimer?.cancel();
    _purgeTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final purged = await _db.purgeExpiredMessages();
      if (purged > 0) {
        if (_activeChatUser != null) {
          _activeMessages = await _db.getMessages(_activeChatUser!);
        }
        await loadConversations();
        notifyListeners();
      }
    });
  }

  Future<void> loadConversations() async {
    _conversations = await _db.getConversations();
    notifyListeners();
  }

  Future<void> openChat(String username) async {
    _activeChatUser = username.toLowerCase();
    _activeContact = await _db.getContact(_activeChatUser!);
    await _db.markConversationAsRead(_activeChatUser!);
    _activeMessages = await _db.getMessages(_activeChatUser!);
    loadConversations();
    notifyListeners();
  }

  void closeChat() {
    _activeChatUser = null;
    _activeContact = null;
    _activeMessages = [];
    notifyListeners();
  }

  Future<void> setDisappearingTimer(String username, int seconds) async {
    final targetUser = username.toLowerCase();
    await _db.updateContactDisappearingTimer(targetUser, seconds);
    if (_activeChatUser == targetUser) {
      _activeContact = await _db.getContact(targetUser);
    }
    await loadConversations();
    notifyListeners();
  }

  Future<void> setContactVerified(String username, bool isVerified) async {
    final targetUser = username.toLowerCase();
    await _db.updateContactVerification(targetUser, isVerified);
    if (_activeChatUser == targetUser) {
      _activeContact = await _db.getContact(targetUser);
    }
    await loadConversations();
    notifyListeners();
  }

  VerificationResult verifyScannedQr(String scannedData, String targetUsername) {
    if (!scannedData.startsWith('direct:key:')) {
      return VerificationResult(isValid: false, errorMessage: 'Invalid Direct QR code format');
    }
    final parts = scannedData.split(':');
    if (parts.length < 4) {
      return VerificationResult(isValid: false, errorMessage: 'Malformed QR code payload');
    }
    final qrUsername = parts[2].toLowerCase();
    final qrPubKey = parts.sublist(3).join(':');

    if (qrUsername != targetUsername.toLowerCase()) {
      return VerificationResult(
        isValid: false,
        errorMessage: 'QR code belongs to @$qrUsername, but you are verifying @$targetUsername',
      );
    }

    final storedPubKey = _activeContact?.identityPublicKey;
    if (storedPubKey != null && storedPubKey != qrPubKey) {
      return VerificationResult(
        isValid: false,
        isMismatch: true,
        errorMessage: 'CRITICAL SECURITY WARNING: Public key does NOT match! Possible Man-in-the-Middle attack.',
      );
    }

    return VerificationResult(isValid: true, matchedUsername: qrUsername);
  }

  Future<ContactModel?> addContact(String username) async {
    final cleanUser = username.trim().toLowerCase();
    if (cleanUser == authProvider.username) {
      throw Exception("You cannot add yourself as a contact");
    }

    // Check if contact already exists locally
    final existing = await _db.getContact(cleanUser);
    if (existing != null) return existing;

    // Fetch identity public key from server directory
    final info = await authProvider.relayClient.getPublicKey(cleanUser);
    final pubKeyStr = info['identityPublicKey'] as String;
    final safetyNumber = await _crypto.generateFingerprint(pubKeyStr);

    final contact = ContactModel(
      username: cleanUser,
      identityPublicKey: pubKeyStr,
      safetyNumber: safetyNumber,
      isVerified: false,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _db.saveContact(contact);
    await loadConversations();
    return contact;
  }

  Future<String?> _saveMediaFile(String id, String fileName, Uint8List bytes) async {
    if (kIsWeb) return null;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(docsDir.path, 'direct_media'));
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      final filePath = p.join(mediaDir.path, '${id}_$fileName');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      debugPrint('Error saving media file: $e');
      return null;
    }
  }

  Future<void> sendMessage({
    required String recipient,
    required String plaintext,
  }) async {
    final myUsername = authProvider.username;
    final myKeyPair = authProvider.identityKeyPair;
    if (myUsername == null || myKeyPair == null) return;

    final targetUser = recipient.toLowerCase();

    // 1. Ensure recipient contact exists
    ContactModel? contact = await _db.getContact(targetUser);
    contact ??= await addContact(targetUser);
    if (contact == null) {
      throw Exception('Could not resolve recipient contact');
    }

    // 2. Prepare message metadata with disappearing timer
    final messageId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final int? expiresAt = (contact.disappearingSeconds > 0)
        ? now + (contact.disappearingSeconds * 1000)
        : null;

    final localMsg = MessageModel(
      id: messageId,
      conversationUser: targetUser,
      sender: myUsername,
      recipient: targetUser,
      content: plaintext,
      timestamp: now,
      status: MessageStatus.pending,
      isOutgoing: true,
      expiresAt: expiresAt,
      messageType: 'text',
    );

    // Save to local SQLite
    await _db.saveMessage(localMsg);
    if (_activeChatUser == targetUser) {
      _activeMessages.add(localMsg);
      notifyListeners();
    }
    await loadConversations();

    // 3. Encrypt payload with recipient's public key (E2EE)
    try {
      final recipientPublicKey = _crypto.importPublicKey(contact.identityPublicKey);
      final encryptedPayload = await _crypto.encryptMessage(
        plaintext: plaintext,
        recipientPublicKey: recipientPublicKey,
      );

      // 4. Send encrypted packet over WebSocket
      authProvider.relayClient.sendMessagePacket(
        id: messageId,
        to: targetUser,
        timestamp: now,
        ephemeralPublicKey: encryptedPayload.ephemeralPublicKey,
        iv: encryptedPayload.iv,
        ciphertext: encryptedPayload.ciphertext,
        disappearingSeconds: contact.disappearingSeconds,
      );
    } catch (e) {
      await _db.updateMessageStatus(messageId, MessageStatus.failed);
      _updateLocalMessageStatus(messageId, MessageStatus.failed);
    }
  }

  Future<void> sendImageMessage({
    required String recipient,
    required Uint8List imageBytes,
    required String fileName,
    String caption = '',
  }) async {
    final myUsername = authProvider.username;
    final myKeyPair = authProvider.identityKeyPair;
    if (myUsername == null || myKeyPair == null) return;

    final targetUser = recipient.toLowerCase();
    ContactModel? contact = await _db.getContact(targetUser);
    contact ??= await addContact(targetUser);
    if (contact == null) throw Exception('Could not resolve recipient contact');

    final messageId = _uuid.v4();
    final now = DateTime.now().millisecondsSinceEpoch;
    final int? expiresAt = (contact.disappearingSeconds > 0)
        ? now + (contact.disappearingSeconds * 1000)
        : null;

    // Save local copy of media
    final localSavedPath = await _saveMediaFile(messageId, fileName, imageBytes);

    final localMsg = MessageModel(
      id: messageId,
      conversationUser: targetUser,
      sender: myUsername,
      recipient: targetUser,
      content: caption,
      timestamp: now,
      status: MessageStatus.pending,
      isOutgoing: true,
      expiresAt: expiresAt,
      messageType: 'image',
      mediaPath: localSavedPath,
    );

    await _db.saveMessage(localMsg);
    if (_activeChatUser == targetUser) {
      _activeMessages.add(localMsg);
      notifyListeners();
    }
    await loadConversations();

    // Format media payload and encrypt end-to-end with AES-256-GCM
    final payloadJson = jsonEncode({
      'type': 'image',
      'caption': caption,
      'fileName': fileName,
      'bytes': base64Encode(imageBytes),
    });

    try {
      final recipientPublicKey = _crypto.importPublicKey(contact.identityPublicKey);
      final encryptedPayload = await _crypto.encryptMessage(
        plaintext: payloadJson,
        recipientPublicKey: recipientPublicKey,
      );

      authProvider.relayClient.sendMessagePacket(
        id: messageId,
        to: targetUser,
        timestamp: now,
        ephemeralPublicKey: encryptedPayload.ephemeralPublicKey,
        iv: encryptedPayload.iv,
        ciphertext: encryptedPayload.ciphertext,
        disappearingSeconds: contact.disappearingSeconds,
      );
    } catch (e) {
      await _db.updateMessageStatus(messageId, MessageStatus.failed);
      _updateLocalMessageStatus(messageId, MessageStatus.failed);
    }
  }

  Future<void> _handleIncomingMessage(Map<String, dynamic> packet) async {
    final myKeyPair = authProvider.identityKeyPair;
    if (myKeyPair == null) return;

    final id = packet['id'] as String;
    final from = (packet['from'] as String).toLowerCase();
    final timestamp = packet['timestamp'] as int;
    final packetTtl = packet['disappearingSeconds'] as int?;

    // Check if we already processed this message
    final existing = await _db.getMessages(from);
    if (existing.any((m) => m.id == id)) return;

    // Ensure sender is in contacts
    ContactModel? contact = await _db.getContact(from);
    if (contact == null) {
      try {
        contact = await addContact(from);
      } catch (_) {}
    }

    // Sync disappearing timer if packet specifies one
    if (packetTtl != null && contact != null && contact.disappearingSeconds != packetTtl) {
      await _db.updateContactDisappearingTimer(from, packetTtl);
      contact = contact.copyWith(disappearingSeconds: packetTtl);
      if (_activeChatUser == from) {
        _activeContact = contact;
      }
    }

    final effectiveTtl = packetTtl ?? contact?.disappearingSeconds ?? 0;
    final int? expiresAt = (effectiveTtl > 0) ? timestamp + (effectiveTtl * 1000) : null;

    try {
      // Decrypt message payload locally
      final encrypted = EncryptedPayload(
        ephemeralPublicKey: packet['ephemeralPublicKey'] as String,
        iv: packet['iv'] as String,
        ciphertext: packet['ciphertext'] as String,
      );

      final decryptedText = await _crypto.decryptMessage(
        payload: encrypted,
        recipientKeyPair: myKeyPair,
      );

      // Check if decrypted payload is an encrypted image
      String messageType = 'text';
      String? mediaPath;
      String content = decryptedText;

      if (decryptedText.startsWith('{"type":"image"')) {
        try {
          final parsed = jsonDecode(decryptedText) as Map<String, dynamic>;
          if (parsed['type'] == 'image') {
            messageType = 'image';
            content = (parsed['caption'] as String?) ?? '';
            final rawBase64 = parsed['bytes'] as String?;
            final fileName = (parsed['fileName'] as String?) ?? 'photo.jpg';
            if (rawBase64 != null) {
              final bytes = base64Decode(rawBase64);
              mediaPath = await _saveMediaFile(id, fileName, bytes);
            }
          }
        } catch (_) {}
      }

      final isCurrentlyOpen = _activeChatUser == from;
      final msg = MessageModel(
        id: id,
        conversationUser: from,
        sender: from,
        recipient: authProvider.username!,
        content: content,
        timestamp: timestamp,
        status: isCurrentlyOpen ? MessageStatus.read : MessageStatus.delivered,
        isOutgoing: false,
        expiresAt: expiresAt,
        messageType: messageType,
        mediaPath: mediaPath,
      );

      await _db.saveMessage(msg);

      // Return delivery acknowledgment to sender
      authProvider.relayClient.sendDeliveryAck(messageId: id, sender: from);

      if (isCurrentlyOpen) {
        _activeMessages.add(msg);
        notifyListeners();
      }
      await loadConversations();
    } catch (err) {
      debugPrint('Failed to decrypt incoming packet from $from: $err');
    }
  }

  Future<void> _handleServerAck(Map<String, dynamic> ack) async {
    final id = ack['id'] as String;
    await _db.updateMessageStatus(id, MessageStatus.sent);
    _updateLocalMessageStatus(id, MessageStatus.sent);
  }

  Future<void> _handleDeliveryReceipt(Map<String, dynamic> receipt) async {
    final id = receipt['id'] as String;
    await _db.updateMessageStatus(id, MessageStatus.delivered);
    _updateLocalMessageStatus(id, MessageStatus.delivered);
  }

  void _handleTypingIndicator(Map<String, dynamic> event) {
    final from = (event['from'] as String).toLowerCase();
    final isTyping = event['isTyping'] as bool? ?? false;
    _typingUsers[from] = isTyping;
    notifyListeners();
  }

  void _updateLocalMessageStatus(String id, MessageStatus status) {
    final index = _activeMessages.indexWhere((m) => m.id == id);
    if (index != -1) {
      _activeMessages[index] = _activeMessages[index].copyWith(status: status);
      notifyListeners();
    }
    loadConversations();
  }

  void sendTyping(String recipient, bool isTyping) {
    authProvider.relayClient.sendTyping(to: recipient.toLowerCase(), isTyping: isTyping);
  }

  Future<void> deleteChat(String username) async {
    await _db.deleteConversation(username);
    if (_activeChatUser == username.toLowerCase()) {
      _activeMessages.clear();
    }
    await loadConversations();
  }

  Future<void> wipeAllData() async {
    await _db.wipeAllData();
    _conversations.clear();
    _activeMessages.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _purgeTimer?.cancel();
    _msgSub?.cancel();
    _ackSub?.cancel();
    _deliverySub?.cancel();
    _typingSub?.cancel();
    super.dispose();
  }
}
