import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/message_model.dart';
import '../models/contact_model.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._internal();
  Database? _db;

  LocalDatabase._internal();

  // Constructor for in-memory or custom database testing
  LocalDatabase.withDatabase(Database db) : _db = db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'direct_chats.db');

    return await openDatabase(
      dbPath,
      version: 3,
      onCreate: (db, version) async {
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

        await db.execute('''
          CREATE INDEX idx_messages_conversation 
          ON messages (conversation_user, timestamp ASC)
        ''');

        await db.execute('''
          CREATE INDEX idx_messages_expires 
          ON messages (expires_at)
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE contacts ADD COLUMN disappearing_seconds INTEGER NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE messages ADD COLUMN expires_at INTEGER');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_messages_expires ON messages (expires_at)');
          } catch (_) {}
        }
        if (oldVersion < 3) {
          try {
            await db.execute("ALTER TABLE messages ADD COLUMN message_type TEXT NOT NULL DEFAULT 'text'");
            await db.execute('ALTER TABLE messages ADD COLUMN media_path TEXT');
          } catch (_) {}
        }
      },
    );
  }

  // --- Contacts ---

  Future<void> saveContact(ContactModel contact) async {
    final db = await database;
    await db.insert(
      'contacts',
      contact.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateContactDisappearingTimer(String username, int seconds) async {
    final db = await database;
    await db.update(
      'contacts',
      {'disappearing_seconds': seconds},
      where: 'username = ?',
      whereArgs: [username.toLowerCase()],
    );
  }

  Future<void> updateContactVerification(String username, bool isVerified) async {
    final db = await database;
    await db.update(
      'contacts',
      {'is_verified': isVerified ? 1 : 0},
      where: 'username = ?',
      whereArgs: [username.toLowerCase()],
    );
  }

  Future<ContactModel?> getContact(String username) async {
    final db = await database;
    final maps = await db.query(
      'contacts',
      where: 'username = ?',
      whereArgs: [username.toLowerCase()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ContactModel.fromMap(maps.first);
  }

  Future<List<ContactModel>> getAllContacts() async {
    final db = await database;
    final maps = await db.query('contacts', orderBy: 'username ASC');
    return maps.map((m) => ContactModel.fromMap(m)).toList();
  }

  // --- Messages & Disappearing Messages Purge ---

  /// Purges any messages whose expires_at timestamp has passed
  Future<int> purgeExpiredMessages([int? nowMs]) async {
    final db = await database;
    final currentTime = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final count = await db.delete(
      'messages',
      where: 'expires_at IS NOT NULL AND expires_at > 0 AND expires_at <= ?',
      whereArgs: [currentTime],
    );
    return count;
  }

  Future<void> saveMessage(MessageModel message) async {
    final db = await database;
    await db.insert(
      'messages',
      message.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateMessageStatus(String id, MessageStatus status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status.name},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<MessageModel>> getMessages(String conversationUser, [int? nowMs]) async {
    await purgeExpiredMessages(nowMs);
    final db = await database;
    final currentTime = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final maps = await db.query(
      'messages',
      where: 'conversation_user = ? AND (expires_at IS NULL OR expires_at = 0 OR expires_at > ?)',
      whereArgs: [conversationUser.toLowerCase(), currentTime],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => MessageModel.fromMap(m)).toList();
  }

  Future<List<ConversationSummary>> getConversations([int? nowMs]) async {
    await purgeExpiredMessages(nowMs);
    final contacts = await getAllContacts();
    final summaries = <ConversationSummary>[];

    final db = await database;
    final currentTime = nowMs ?? DateTime.now().millisecondsSinceEpoch;

    for (final contact in contacts) {
      final latestMsgQuery = await db.query(
        'messages',
        where: 'conversation_user = ? AND (expires_at IS NULL OR expires_at = 0 OR expires_at > ?)',
        whereArgs: [contact.username.toLowerCase(), currentTime],
        orderBy: 'timestamp DESC',
        limit: 1,
      );

      MessageModel? lastMsg;
      if (latestMsgQuery.isNotEmpty) {
        lastMsg = MessageModel.fromMap(latestMsgQuery.first);
      }

      final unreadCountQuery = await db.rawQuery(
        '''
        SELECT COUNT(*) as count FROM messages 
        WHERE conversation_user = ? AND is_outgoing = 0 AND status != 'read'
        AND (expires_at IS NULL OR expires_at = 0 OR expires_at > ?)
        ''',
        [contact.username.toLowerCase(), currentTime],
      );
      final unreadCount = (unreadCountQuery.first['count'] as int?) ?? 0;

      summaries.add(ConversationSummary(
        contact: contact,
        lastMessage: lastMsg,
        unreadCount: unreadCount,
      ));
    }

    // Sort by most recent message timestamp descending
    summaries.sort((a, b) {
      final tA = a.lastMessage?.timestamp ?? a.contact.createdAt;
      final tB = b.lastMessage?.timestamp ?? b.contact.createdAt;
      return tB.compareTo(tA);
    });

    return summaries;
  }

  Future<void> markConversationAsRead(String conversationUser) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': MessageStatus.read.name},
      where: 'conversation_user = ? AND is_outgoing = 0',
      whereArgs: [conversationUser.toLowerCase()],
    );
  }

  Future<void> deleteConversation(String conversationUser) async {
    final db = await database;
    await db.delete(
      'messages',
      where: 'conversation_user = ?',
      whereArgs: [conversationUser.toLowerCase()],
    );
  }

  Future<void> wipeAllData() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('contacts');
  }
}
