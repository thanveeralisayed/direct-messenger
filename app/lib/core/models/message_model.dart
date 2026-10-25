enum MessageStatus {
  pending, // Queued locally in outbox
  sent, // Transmitted to server (server_ack relayed or buffered)
  delivered, // Delivered to peer device
  read, // Read by peer
  failed, // Delivery failed
}

class MessageModel {
  final String id;
  final String conversationUser; // Username of chat partner
  final String sender; // Sender username
  final String recipient; // Recipient username
  final String content; // Plaintext content (decrypted locally)
  final int timestamp; // Milliseconds epoch
  final MessageStatus status;
  final bool isOutgoing;
  final int? expiresAt; // Epoch ms when message should auto-delete (or null if never)

  MessageModel({
    required this.id,
    required this.conversationUser,
    required this.sender,
    required this.recipient,
    required this.content,
    required this.timestamp,
    required this.status,
    required this.isOutgoing,
    this.expiresAt,
  });

  bool get isExpired {
    if (expiresAt == null || expiresAt! <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch >= expiresAt!;
  }

  MessageModel copyWith({
    String? id,
    String? conversationUser,
    String? sender,
    String? recipient,
    String? content,
    int? timestamp,
    MessageStatus? status,
    bool? isOutgoing,
    int? expiresAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      conversationUser: conversationUser ?? this.conversationUser,
      sender: sender ?? this.sender,
      recipient: recipient ?? this.recipient,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'conversation_user': conversationUser,
      'sender': sender,
      'recipient': recipient,
      'content': content,
      'timestamp': timestamp,
      'status': status.name,
      'is_outgoing': isOutgoing ? 1 : 0,
      'expires_at': expiresAt,
    };
  }

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      conversationUser: map['conversation_user'] as String,
      sender: map['sender'] as String,
      recipient: map['recipient'] as String,
      content: map['content'] as String,
      timestamp: map['timestamp'] as int,
      status: MessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MessageStatus.sent,
      ),
      isOutgoing: (map['is_outgoing'] as int) == 1,
      expiresAt: map['expires_at'] as int?,
    );
  }
}
