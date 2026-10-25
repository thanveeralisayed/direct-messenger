import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/contact_model.dart';
import '../../core/network/relay_client.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../dialogs/add_contact_dialog.dart';
import '../dialogs/safety_number_dialog.dart';
import '../dialogs/security_settings_dialog.dart';
import '../theme.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return DateFormat('HH:mm').format(date);
    }
    return DateFormat('MMM d').format(date);
  }

  Widget _buildConnectionIndicator(RelayClient relay) {
    return StreamBuilder<RelayConnectionState>(
      stream: relay.onStateChanged,
      initialData: relay.state,
      builder: (context, snapshot) {
        final state = snapshot.data ?? RelayConnectionState.disconnected;
        Color color = DirectTheme.error;
        String label = 'Offline';
        switch (state) {
          case RelayConnectionState.connected:
            color = DirectTheme.success;
            label = 'Live Relay';
            break;
          case RelayConnectionState.connecting:
            color = DirectTheme.warning;
            label = 'Connecting...';
            break;
          case RelayConnectionState.disconnected:
            color = DirectTheme.error;
            label = 'Offline';
            break;
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMyFingerprint(BuildContext context, AuthProvider auth) {
    if (auth.publicKeyBase64 == null || auth.safetyNumber == null) return;
    showDialog(
      context: context,
      builder: (_) => SafetyNumberDialog(
        username: auth.username ?? 'me',
        publicKey: auth.publicKeyBase64!,
        safetyNumber: auth.safetyNumber!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final chat = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.shield, color: DirectTheme.primary, size: 22),
            const SizedBox(width: 8),
            const Text('Direct', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            _buildConnectionIndicator(auth.relayClient),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'My Safety Fingerprint',
            icon: const Icon(Icons.qr_code, color: DirectTheme.textSecondary),
            onPressed: () => _showMyFingerprint(context, auth),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: DirectTheme.textSecondary),
            color: DirectTheme.surface,
            onSelected: (value) async {
              if (value == 'fingerprint') {
                _showMyFingerprint(context, auth);
              } else if (value == 'security') {
                showDialog(
                  context: context,
                  builder: (_) => const SecuritySettingsDialog(),
                );
              } else if (value == 'logout') {
                await auth.logout();
              } else if (value == 'wipe') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: DirectTheme.surface,
                    title: const Text('Wipe All Local Data?'),
                    content: const Text(
                      'This will delete all local chat history and contacts from this device. '
                      'Since no chats are stored on the server, this action cannot be undone.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: DirectTheme.error),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Wipe Permanently'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  await chat.wipeAllData();
                  await auth.logout();
                }
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'fingerprint',
                child: Row(
                  children: [
                    const Icon(Icons.key, size: 18, color: DirectTheme.primary),
                    const SizedBox(width: 8),
                    Text('@${auth.username} Key Fingerprint'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'security',
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: DirectTheme.primary),
                    SizedBox(width: 8),
                    Text('Privacy & Security'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'wipe',
                child: Row(
                  children: [
                    Icon(Icons.delete_forever, size: 18, color: DirectTheme.error),
                    SizedBox(width: 8),
                    Text('Wipe Device Data', style: TextStyle(color: DirectTheme.error)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: DirectTheme.textSecondary),
                    SizedBox(width: 8),
                    Text('Sign Out'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: chat.conversations.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: DirectTheme.surfaceLight,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF243245)),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: DirectTheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No direct chats yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tap the plus button below to add a contact by their username and initiate a direct end-to-end encrypted session.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: chat.conversations.length,
              separatorBuilder: (_, _) => const Divider(
                color: Color(0xFF1E2838),
                height: 1,
                indent: 72,
              ),
              itemBuilder: (context, index) {
                final summary = chat.conversations[index];
                final contact = summary.contact;
                final lastMsg = summary.lastMessage;
                final isTyping = chat.isUserTyping(contact.username);

                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: DirectTheme.surfaceLight,
                    child: Text(
                      contact.username.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: DirectTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '@${contact.username}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: DirectTheme.textPrimary,
                            ),
                          ),
                          if (contact.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, size: 14, color: DirectTheme.success),
                          ],
                        ],
                      ),
                      if (lastMsg != null)
                        Text(
                          _formatTimestamp(lastMsg.timestamp),
                          style: const TextStyle(
                            fontSize: 12,
                            color: DirectTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: isTyping
                        ? const Text(
                            'typing...',
                            style: TextStyle(
                              color: DirectTheme.primary,
                              fontStyle: FontStyle.italic,
                              fontSize: 13,
                            ),
                          )
                        : Text(
                            lastMsg?.content ?? 'End-to-end encrypted session ready',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: summary.unreadCount > 0
                                  ? DirectTheme.textPrimary
                                  : DirectTheme.textSecondary,
                              fontWeight: summary.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                  ),
                  trailing: summary.unreadCount > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: DirectTheme.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${summary.unreadCount}',
                            style: const TextStyle(
                              color: DirectTheme.background,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(contact: contact),
                      ),
                    );
                  },
                  onLongPress: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: DirectTheme.surface,
                        title: Text('Delete chat with @${contact.username}?'),
                        content: const Text(
                          'This will erase this conversation history locally from this device.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DirectTheme.error,
                            ),
                            onPressed: () {
                              chat.deleteChat(contact.username);
                              Navigator.pop(ctx);
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New Encrypted Chat',
        child: const Icon(Icons.add_comment_outlined),
        onPressed: () async {
          final newContact = await showDialog<ContactModel?>(
            context: context,
            builder: (_) => const AddContactDialog(),
          );

          if (newContact != null && context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatScreen(contact: newContact),
              ),
            );
          }
        },
      ),
    );
  }
}
