import 'dart:async';

import 'package:field_check/screens/chat_conversation_screen.dart';
import 'package:field_check/services/chat_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:field_check/providers/auth_provider.dart';

class ChatScreen extends StatefulWidget {
  final String? initialConversationId;

  const ChatScreen({super.key, this.initialConversationId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final RealtimeService _realtimeService = RealtimeService();

  StreamSubscription<Map<String, dynamic>>? _chatSub;
  StreamSubscription<Map<String, dynamic>>? _unreadCountsSub;
  Timer? _debouncedReload;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];
  bool _showArchived = false;
  bool _loadingAdmins = false;
  String? _onlineAdminId;

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is int) {
      try {
        return DateTime.fromMillisecondsSinceEpoch(v);
      } catch (_) {
        return null;
      }
    }
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  DateTime? _conversationSortTs(Map<String, dynamic> c) {
    return _parseDate(
          c['lastMessageAt'] ??
              c['updatedAt'] ??
              c['lastMessageCreatedAt'] ??
              c['createdAt'],
        ) ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _unreadCount(Map<String, dynamic> c) {
    final raw = c['unreadCount'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  void _sortConversations() {
    _conversations.sort((a, b) {
      final at =
          _conversationSortTs(a) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt =
          _conversationSortTs(b) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cmp = bt.compareTo(at);
      if (cmp != 0) return cmp;
      return _unreadCount(b).compareTo(_unreadCount(a));
    });
  }

  void _scheduleReload() {
    _debouncedReload?.cancel();
    _debouncedReload = Timer(const Duration(milliseconds: 350), () {
      _load();
    });
  }

  void _applyChatMessageEvent(Map<String, dynamic> data) {
    String readId(dynamic v) => (v ?? '').toString();

    String convoId = '';
    try {
      convoId = readId(
        data['conversationId'] ?? data['conversationID'] ?? data['convoId'],
      );
      if (convoId.trim().isEmpty && data['conversation'] is Map) {
        convoId = readId((data['conversation'] as Map)['id']);
      }
      if (convoId.trim().isEmpty && data['message'] is Map) {
        convoId = readId((data['message'] as Map)['conversationId']);
      }
    } catch (_) {}

    if (convoId.trim().isEmpty) {
      // Fallback: backend payload shape may differ; refresh list.
      _scheduleReload();
      return;
    }

    final body =
        (data['body'] ??
                (data['message'] is Map
                    ? (data['message'] as Map)['body']
                    : null) ??
                '')
            .toString();
    final createdAt = _parseDate(
      data['createdAt'] ??
          (data['message'] is Map
              ? (data['message'] as Map)['createdAt']
              : null),
    );

    if (!mounted) return;
    setState(() {
      final idx = _conversations.indexWhere(
        (c) => (c['id'] ?? '').toString() == convoId,
      );
      if (idx == -1) {
        _scheduleReload();
        return;
      }

      final c = Map<String, dynamic>.from(_conversations[idx]);
      c['lastMessagePreview'] = body;
      c['lastMessageAt'] =
          createdAt?.toIso8601String() ?? DateTime.now().toIso8601String();

      // If you are not currently in the conversation, unread count will be
      // refreshed by unreadCounts/persistence. For snappy UI, increment locally.
      c['unreadCount'] = _unreadCount(c) + 1;

      _conversations
        ..removeAt(idx)
        ..insert(0, c);
      _sortConversations();
    });
  }

  @override
  void initState() {
    super.initState();
    _load();

    _realtimeService.initialize();
    _chatSub = _realtimeService.chatStream.listen((data) {
      _applyChatMessageEvent(data);
    });
    _unreadCountsSub = _realtimeService.unreadCountsStream.listen((_) {
      // Keep list consistent with server truth without being too chatty.
      _scheduleReload();
    });

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

  @override
  void dispose() {
    _debouncedReload?.cancel();
    _chatSub?.cancel();
    _unreadCountsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _chatService.listConversations(
        archived: _showArchived,
      );
      if (!mounted) return;
      setState(() {
        _conversations = items;
        _sortConversations();
        _loading = false;
      });

      final auth = context.read<AuthProvider>();
      if (!_showArchived && !auth.isAdmin) {
        await _loadOnlineAdmins();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadOnlineAdmins() async {
    if (_loadingAdmins) return;
    if (!mounted) return;
    setState(() {
      _loadingAdmins = true;
      _onlineAdminId = null;
    });
    try {
      final admins = await _chatService.listOnlineAdmins();
      if (!mounted) return;
      setState(() {
        _onlineAdminId = admins.isNotEmpty
            ? (admins.first['id'] ?? admins.first['_id'] ?? '').toString()
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _onlineAdminId = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingAdmins = false;
        });
      }
    }
  }

  Future<void> _messageAdmin() async {
    final adminId = (_onlineAdminId ?? '').trim();
    if (adminId.isEmpty) return;
    try {
      final convoId = await _chatService.getOrCreateConversation(
        otherUserId: adminId,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatConversationScreen(conversationId: convoId),
        ),
      );
      _scheduleReload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _archiveConversation(String conversationId) async {
    try {
      await _chatService.archiveConversation(conversationId);
      _scheduleReload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _unarchiveConversation(String conversationId) async {
    try {
      await _chatService.unarchiveConversation(conversationId);
      _scheduleReload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _deleteConversation(String conversationId) async {
    try {
      await _chatService.deleteConversation(conversationId);
      _scheduleReload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();
    final showMessageAdmin = !auth.isAdmin && !_showArchived;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        actions: [
          if (showMessageAdmin)
            IconButton(
              onPressed:
                  (_loadingAdmins || (_onlineAdminId ?? '').trim().isEmpty)
                  ? null
                  : _messageAdmin,
              icon: const Icon(Icons.support_agent),
              tooltip: _loadingAdmins
                  ? 'Checking admin availability...'
                  : ((_onlineAdminId ?? '').trim().isEmpty)
                  ? 'Admin is offline'
                  : 'Message Admin',
            ),
          IconButton(
            onPressed: () {
              setState(() {
                _showArchived = !_showArchived;
              });
              _load();
            },
            icon: Icon(
              _showArchived ? Icons.inbox_outlined : Icons.archive_outlined,
            ),
            tooltip: _showArchived ? 'Show inbox' : 'Show archived',
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
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
                    FilledButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : (_conversations.isEmpty)
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _showArchived
                          ? 'No archived conversations'
                          : 'No conversations yet',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (!_showArchived) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed:
                            (_loadingAdmins ||
                                (_onlineAdminId ?? '').trim().isEmpty)
                            ? null
                            : _messageAdmin,
                        child: Text(
                          _loadingAdmins
                              ? 'Checking admin availability...'
                              : ((_onlineAdminId ?? '').trim().isEmpty)
                              ? 'Admin is offline'
                              : 'Message Admin',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final c = _conversations[index];
                final other = c['otherUser'];
                final isGroup = c['isGroup'] == true;
                final title = (c['title'] ?? '').toString().trim();
                final otherName = other is Map
                    ? (other['name'] ?? 'User').toString()
                    : 'User';
                final displayName = isGroup
                    ? (title.isNotEmpty ? title : 'Group chat')
                    : otherName;
                final preview = (c['lastMessagePreview'] ?? '').toString();
                final unread = _unreadCount(c);
                final id = (c['id'] ?? '').toString();

                final canModify = !isGroup;

                return Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName.substring(0, 1).toUpperCase()
                            : 'C',
                      ),
                    ),
                    title: Text(
                      displayName,
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
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (unread > 0)
                          Container(
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
                          ),
                        if (canModify)
                          PopupMenuButton<String>(
                            onSelected: (value) {
                              if (id.isEmpty) return;
                              if (value == 'archive') {
                                _archiveConversation(id);
                              } else if (value == 'unarchive') {
                                _unarchiveConversation(id);
                              } else if (value == 'delete') {
                                _deleteConversation(id);
                              }
                            },
                            itemBuilder: (context) {
                              final isArchived = c['archived'] == true;
                              return <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: isArchived ? 'unarchive' : 'archive',
                                  child: Text(
                                    isArchived ? 'Unarchive' : 'Archive',
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'delete',
                                  child: Text('Delete'),
                                ),
                              ];
                            },
                          ),
                      ],
                    ),
                    onTap: () async {
                      final convoId = (c['id'] ?? '').toString();
                      if (convoId.trim().isEmpty) return;

                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatConversationScreen(conversationId: convoId),
                        ),
                      );

                      _scheduleReload();
                    },
                  ),
                );
              },
            ),
    );
  }
}
