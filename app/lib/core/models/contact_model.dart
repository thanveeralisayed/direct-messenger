import 'message_model.dart';

class ContactModel {
  final String username;
  final String identityPublicKey;
  final String safetyNumber;
  final bool isVerified;
  final int createdAt;
  final int disappearingSeconds; // 0 = off, 30 = 30s, 3600 = 1h, 86400 = 24h, 604800 = 7d

  ContactModel({
    required this.username,
    required this.identityPublicKey,
    required this.safetyNumber,
    this.isVerified = false,
    required this.createdAt,
    this.disappearingSeconds = 0,
  });

  ContactModel copyWith({
    String? username,
    String? identityPublicKey,
    String? safetyNumber,
    bool? isVerified,
    int? createdAt,
    int? disappearingSeconds,
  }) {
    return ContactModel(
      username: username ?? this.username,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      safetyNumber: safetyNumber ?? this.safetyNumber,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
      disappearingSeconds: disappearingSeconds ?? this.disappearingSeconds,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'identity_public_key': identityPublicKey,
      'safety_number': safetyNumber,
      'is_verified': isVerified ? 1 : 0,
      'created_at': createdAt,
      'disappearing_seconds': disappearingSeconds,
    };
  }

  factory ContactModel.fromMap(Map<String, dynamic> map) {
    return ContactModel(
      username: map['username'] as String,
      identityPublicKey: map['identity_public_key'] as String,
      safetyNumber: map['safety_number'] as String,
      isVerified: (map['is_verified'] as int) == 1,
      createdAt: map['created_at'] as int,
      disappearingSeconds: (map['disappearing_seconds'] as int?) ?? 0,
    );
  }
}

class ConversationSummary {
  final ContactModel contact;
  final MessageModel? lastMessage;
  final int unreadCount;

  ConversationSummary({
    required this.contact,
    this.lastMessage,
    this.unreadCount = 0,
  });
}
