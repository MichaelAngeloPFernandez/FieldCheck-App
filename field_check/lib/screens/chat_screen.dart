import 'dart:async';

import 'package:field_check/screens/chat_conversation_screen.dart';
import 'package:field_check/services/chat_service.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  final String? initialConversationId;

  const ChatScreen({super.key, this.initialConversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();

    final convoId = widget.initialConversationId;
    if (convoId != null && convoId.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatConversationScreen(conversationId: convoId),
          ),
        );
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _chatService.listConversations();
      if (!mounted) return;
      setState(() {
        _conversations = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Failed to load conversations',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : (_conversations.isEmpty)
                  ? Center(
                      child: Text(
                        'No conversations yet',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      itemCount: _conversations.length,
                      itemBuilder: (context, index) {
                        final c = _conversations[index];
                        final other = c['otherUser'];
                        final otherName = other is Map
                            ? (other['name'] ?? 'User').toString()
                            : 'User';
                        final preview = (c['lastMessagePreview'] ?? '').toString();
                        final unreadRaw = c['unreadCount'];
                        final unread = unreadRaw is int
                            ? unreadRaw
                            : unreadRaw is num
                                ? unreadRaw.toInt()
                                : int.tryParse(unreadRaw?.toString() ?? '') ?? 0;

                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.08,
                              ),
                            ),
                          ),
                          child: ListTile(
                            onTap: () {
                              final id = (c['id'] ?? '').toString();
                              if (id.isEmpty) return;
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatConversationScreen(
                                    conversationId: id,
                                  ),
                                ),
                              );
                            },
                            leading: CircleAvatar(
                              child: Text(
                                otherName.isNotEmpty
                                    ? otherName.substring(0, 1).toUpperCase()
                                    : 'U',
                              ),
                            ),
                            title: Text(
                              otherName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: unread > 0
                                    ? FontWeight.w800
                                    : FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              preview.isNotEmpty ? preview : 'Tap to open chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: unread > 0
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      unread > 99 ? '99+' : unread.toString(),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onPrimary,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
    );
  }
}
