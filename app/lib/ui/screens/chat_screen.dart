import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/models/contact_model.dart';
import '../../core/models/message_model.dart';
import '../../providers/chat_provider.dart';
import '../dialogs/safety_number_dialog.dart';
import '../theme.dart';

class ChatScreen extends StatefulWidget {
  final ContactModel contact;

  const ChatScreen({super.key, required this.contact});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _typingDebounce;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChatProvider>().openChat(widget.contact.username);
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text, ChatProvider chat) {
    if (text.isNotEmpty) {
      chat.sendTyping(widget.contact.username, true);
      _typingDebounce?.cancel();
      _typingDebounce = Timer(const Duration(seconds: 2), () {
        chat.sendTyping(widget.contact.username, false);
      });
    } else {
      chat.sendTyping(widget.contact.username, false);
    }
  }

  Future<void> _handleSend(ChatProvider chat) async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    _inputController.clear();
    chat.sendTyping(widget.contact.username, false);
    setState(() => _isSending = true);

    try {
      await chat.sendMessage(
        recipient: widget.contact.username,
        plaintext: text,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: DirectTheme.error,
            content: Text('Failed to send: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  String _formatDisappearingDuration(int seconds) {
    if (seconds <= 0) return 'Off';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    if (seconds < 86400) return '${seconds ~/ 3600}h';
    return '${seconds ~/ 86400}d';
  }

  void _showDisappearingSettings(BuildContext context, ChatProvider chat) {
    final currentSeconds = chat.activeContact?.disappearingSeconds ?? 0;

    showModalBottomSheet(
      context: context,
      backgroundColor: DirectTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined, color: DirectTheme.primary),
                      SizedBox(width: 10),
                      Text(
                        'Disappearing Messages',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'When enabled, new messages sent and received in this chat will automatically delete from both devices after the timer expires.',
                    style: TextStyle(color: DirectTheme.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTimerTile(ctx, chat, 'Off', 0, currentSeconds == 0),
                _buildTimerTile(ctx, chat, '30 Seconds (Fast test)', 30, currentSeconds == 30),
                _buildTimerTile(ctx, chat, '1 Hour', 3600, currentSeconds == 3600),
                _buildTimerTile(ctx, chat, '24 Hours (Recommended)', 86400, currentSeconds == 86400),
                _buildTimerTile(ctx, chat, '7 Days', 604800, currentSeconds == 604800),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimerTile(BuildContext ctx, ChatProvider chat, String label, int seconds, bool isSelected) {
    return ListTile(
      title: Text(label, style: TextStyle(color: isSelected ? DirectTheme.primary : DirectTheme.textPrimary)),
      trailing: isSelected ? const Icon(Icons.check, color: DirectTheme.primary) : null,
      onTap: () {
        chat.setDisappearingTimer(widget.contact.username, seconds);
        Navigator.pop(ctx);
      },
    );
  }

  Widget _buildStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.pending:
        return const Icon(Icons.access_time, size: 13, color: DirectTheme.textMuted);
      case MessageStatus.sent:
        return const Icon(Icons.check, size: 14, color: DirectTheme.textSecondary);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: DirectTheme.textSecondary);
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 14, color: DirectTheme.primary);
      case MessageStatus.failed:
        return const Icon(Icons.error_outline, size: 14, color: DirectTheme.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final isTyping = chat.isUserTyping(widget.contact.username);
    final disappearingSeconds = chat.activeContact?.disappearingSeconds ?? 0;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          chat.closeChat();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: DirectTheme.surfaceLight,
                child: Text(
                  widget.contact.username.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: DirectTheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${widget.contact.username}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DirectTheme.textPrimary,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.lock, size: 10, color: DirectTheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          isTyping ? 'typing...' : 'End-to-End Encrypted',
                          style: TextStyle(
                            fontSize: 11,
                            color: isTyping ? DirectTheme.primary : DirectTheme.textMuted,
                            fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Disappearing Messages',
              icon: Icon(
                Icons.timer_outlined,
                color: disappearingSeconds > 0 ? DirectTheme.primary : DirectTheme.textSecondary,
              ),
              onPressed: () => _showDisappearingSettings(context, chat),
            ),
            IconButton(
              tooltip: 'Verify Safety Number',
              icon: const Icon(Icons.security, color: DirectTheme.primary),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => SafetyNumberDialog(
                    username: widget.contact.username,
                    publicKey: widget.contact.identityPublicKey,
                    safetyNumber: widget.contact.safetyNumber,
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          children: [
            // Disappearing Messages Banner (if active)
            if (disappearingSeconds > 0)
              GestureDetector(
                onTap: () => _showDisappearingSettings(context, chat),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                  color: DirectTheme.primary.withValues(alpha: 0.12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.timer_outlined, size: 14, color: DirectTheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Disappearing messages active: ${_formatDisappearingDuration(disappearingSeconds)}',
                        style: const TextStyle(
                          color: DirectTheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // E2EE Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              color: const Color(0xFF0F1722),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shield_outlined, size: 13, color: DirectTheme.primary),
                  SizedBox(width: 6),
                  Text(
                    'Direct session • Server never sees or stores these messages',
                    style: TextStyle(
                      color: DirectTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Message List
            Expanded(
              child: chat.activeMessages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_open, size: 40, color: DirectTheme.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          const Text(
                            'No messages here yet.',
                            style: TextStyle(color: DirectTheme.textMuted, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Say hello to initiate your encrypted direct chat!',
                            style: TextStyle(color: DirectTheme.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      itemCount: chat.activeMessages.length,
                      itemBuilder: (context, index) {
                        final msg = chat.activeMessages[index];
                        final isOutgoing = msg.isOutgoing;
                        final time = DateFormat('HH:mm').format(
                          DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
                        );

                        return Align(
                          alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isOutgoing
                                  ? DirectTheme.outgoingBubble
                                  : DirectTheme.incomingBubble,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: Radius.circular(isOutgoing ? 16 : 4),
                                bottomRight: Radius.circular(isOutgoing ? 4 : 16),
                              ),
                              border: Border.all(
                                color: isOutgoing
                                    ? DirectTheme.primary.withValues(alpha: 0.3)
                                    : const Color(0xFF243245),
                                width: 0.8,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: isOutgoing
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.content,
                                  style: const TextStyle(
                                    color: DirectTheme.textPrimary,
                                    fontSize: 15,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (msg.expiresAt != null && msg.expiresAt! > 0) ...[
                                      const Icon(Icons.timer_outlined, size: 11, color: DirectTheme.primary),
                                      const SizedBox(width: 3),
                                    ],
                                    Text(
                                      time,
                                      style: TextStyle(
                                        color: DirectTheme.textMuted.withValues(alpha: 0.9),
                                        fontSize: 10,
                                      ),
                                    ),
                                    if (isOutgoing) ...[
                                      const SizedBox(width: 4),
                                      _buildStatusIcon(msg.status),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Typing indicator banner
            if (isTyping)
              Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Text(
                  '@${widget.contact.username} is typing...',
                  style: const TextStyle(
                    color: DirectTheme.primary,
                    fontStyle: FontStyle.italic,
                    fontSize: 12,
                  ),
                ),
              ),

            // Input Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: const BoxDecoration(
                color: DirectTheme.surface,
                border: Border(
                  top: BorderSide(color: Color(0xFF1E2838), width: 1),
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        style: const TextStyle(color: DirectTheme.textPrimary, fontSize: 15),
                        textInputAction: TextInputAction.send,
                        onChanged: (val) => _onTextChanged(val, chat),
                        onSubmitted: (_) => _handleSend(chat),
                        decoration: InputDecoration(
                          hintText: 'End-to-end encrypted message...',
                          hintStyle: const TextStyle(color: DirectTheme.textMuted, fontSize: 14),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: true,
                          fillColor: DirectTheme.surfaceLight,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: const BoxDecoration(
                        color: DirectTheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: DirectTheme.background, size: 20),
                        onPressed: () => _handleSend(chat),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
