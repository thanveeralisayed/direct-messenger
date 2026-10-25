import 'message_model.dart';

class ContactModel {
  final String username;
  final String identityPublicKey;
  final String safetyNumber;
  final bool isVerified;
  final int createdAt;

  ContactModel({
    required this.username,
    required this.identityPublicKey,
    required this.safetyNumber,
    this.isVerified = false,
    required this.createdAt,
  });

  ContactModel copyWith({
    String? username,
    String? identityPublicKey,
    String? safetyNumber,
    bool? isVerified,
    int? createdAt,
  }) {
    return ContactModel(
      username: username ?? this.username,
      identityPublicKey: identityPublicKey ?? this.identityPublicKey,
      safetyNumber: safetyNumber ?? this.safetyNumber,
      isVerified: isVerified ?? this.isVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'username': username,
      'identity_public_key': identityPublicKey,
      'safety_number': safetyNumber,
      'is_verified': isVerified ? 1 : 0,
      'created_at': createdAt,
    };
  }

  factory ContactModel.fromMap(Map<String, dynamic> map) {
    return ContactModel(
      username: map['username'] as String,
      identityPublicKey: map['identity_public_key'] as String,
      safetyNumber: map['safety_number'] as String,
      isVerified: (map['is_verified'] as int) == 1,
      createdAt: map['created_at'] as int,
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
