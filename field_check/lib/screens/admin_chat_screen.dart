import 'dart:async';

import 'package:field_check/services/chat_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:flutter/material.dart';

class AdminChatScreen extends StatefulWidget {
  const AdminChatScreen({super.key});

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final ChatService _chatService = ChatService();
  final UserService _userService = UserService();
  final RealtimeService _realtimeService = RealtimeService();

  StreamSubscription<Map<String, dynamic>>? _chatSub;
  StreamSubscription<Map<String, dynamic>>? _unreadCountsSub;
  Timer? _debouncedReload;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _conversations = <Map<String, dynamic>>[];
  bool _showArchived = false;

  String? _selectedConversationId;

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

  @override
  void initState() {
    super.initState();
    _load();

    _realtimeService.initialize();
    _chatSub = _realtimeService.chatStream.listen((_) {
      _scheduleReload();
    });
    _unreadCountsSub = _realtimeService.unreadCountsStream.listen((_) {
      _scheduleReload();
    });
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

        if (_selectedConversationId == null && _conversations.isNotEmpty) {
          _selectedConversationId =
              (_conversations.first['id'] ?? '').toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
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
      if (_selectedConversationId == conversationId) {
        setState(() {
          _selectedConversationId = null;
        });
      }
      _scheduleReload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _createGroupChat() async {
    final titleController = TextEditingController();
    final queryController = TextEditingController();

    final selectedUserIds = <String>{};
    List<Map<String, dynamic>> allUsers = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> filtered = <Map<String, dynamic>>[];
    bool loading = true;
    String? loadError;

    void applyFilter() {
      final q = queryController.text.trim().toLowerCase();
      if (q.isEmpty) {
        filtered = List<Map<String, dynamic>>.from(allUsers);
      } else {
        filtered = allUsers.where((u) {
          final name = (u['name'] ?? '').toString().toLowerCase();
          final email = (u['email'] ?? '').toString().toLowerCase();
          final employeeId = (u['employeeId'] ?? '').toString().toLowerCase();
          return name.contains(q) || email.contains(q) || employeeId.contains(q);
        }).toList();
      }
      filtered.sort((a, b) {
        final an = (a['name'] ?? '').toString().toLowerCase();
        final bn = (b['name'] ?? '').toString().toLowerCase();
        return an.compareTo(bn);
      });
    }

    Future<void> loadUsers(StateSetter setModalState) async {
      try {
        final users = await _userService.fetchAllUsers();
        final meId = (_userService.currentUser?.id ?? '').toString();
        allUsers = users
            .where(
              (u) => u.id != meId,
            )
            .map(
              (u) => {
                'id': u.id,
                'name': u.name,
                'email': u.email,
                'role': u.role,
                'employeeId': u.employeeId,
              },
            )
            .toList();
        applyFilter();
        setModalState(() {
          loading = false;
          loadError = null;
        });
      } catch (e) {
        setModalState(() {
          loading = false;
          loadError = e.toString();
        });
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (loading && allUsers.isEmpty && loadError == null) {
              unawaited(loadUsers(setModalState));
            }

            return AlertDialog(
              title: const Text('Create group chat'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: queryController,
                      onChanged: (_) {
                        setModalState(() {
                          applyFilter();
                        });
                      },
                      decoration: const InputDecoration(
                        labelText: 'Search users',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (loadError != null)
                      Text(loadError!)
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final u = filtered[index];
                            final id = (u['id'] ?? '').toString();
                            final name = (u['name'] ?? '').toString();
                            final role = (u['role'] ?? '').toString();
                            final employeeId = (u['employeeId'] ?? '').toString();
                            final subtitle = [
                              if (employeeId.trim().isNotEmpty) employeeId,
                              if (role.trim().isNotEmpty) role,
                            ].join(' · ');

                            final checked = selectedUserIds.contains(id);
                            return CheckboxListTile(
                              value: checked,
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    selectedUserIds.add(id);
                                  } else {
                                    selectedUserIds.remove(id);
                                  }
                                });
                              },
                              title: Text(name),
                              subtitle:
                                  subtitle.trim().isEmpty ? null : Text(subtitle),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;

    final title = titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Title is required')));
      return;
    }

    if (selectedUserIds.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least 2 participants'),
        ),
      );
      return;
    }

    try {
      final convoId = await _chatService.createGroupConversation(
        title: title,
        participantUserIds: selectedUserIds.toList(growable: false),
      );
      if (!mounted) return;
      setState(() {
        _showArchived = false;
        _selectedConversationId = convoId;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Widget _buildConversationList(BuildContext context, {required bool isWide}) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
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
      );
    }

    if (_conversations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _showArchived ? 'No archived conversations' : 'No conversations yet',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
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

        final isSelected = isWide && _selectedConversationId == id;

        return Card(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.08) : null,
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
                fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
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
                        child: Text(isArchived ? 'Unarchive' : 'Archive'),
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
            onTap: () {
              if (id.trim().isEmpty) return;
              if (isWide) {
                setState(() {
                  _selectedConversationId = id;
                });
              } else {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: Text(displayName)),
                      body: _AdminConversationPane(conversationId: id),
                    ),
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 980;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin Chat'),
            actions: [
              IconButton(
                onPressed: _createGroupChat,
                icon: const Icon(Icons.add),
                tooltip: 'Create group chat',
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _showArchived = !_showArchived;
                    if (_showArchived) {
                      _selectedConversationId = null;
                    }
                  });
                  _load();
                },
                icon: Icon(
                  _showArchived
                      ? Icons.inbox_outlined
                      : Icons.archive_outlined,
                ),
                tooltip: _showArchived ? 'Show inbox' : 'Show archived',
              ),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: isWide
              ? Row(
                  children: [
                    SizedBox(
                      width: 360,
                      child: _buildConversationList(context, isWide: true),
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _selectedConversationId == null
                          ? const Center(
                              child: Text('Select a conversation'),
                            )
                          : _AdminConversationPane(
                              conversationId: _selectedConversationId!,
                            ),
                    ),
                  ],
                )
              : _buildConversationList(context, isWide: false),
        );
      },
    );
  }
}

class _AdminConversationPane extends StatefulWidget {
  final String conversationId;
  const _AdminConversationPane({required this.conversationId});

  @override
  State<_AdminConversationPane> createState() => _AdminConversationPaneState();
}

class _AdminConversationPaneState extends State<_AdminConversationPane> {
  final ChatService _chatService = ChatService();
  final RealtimeService _realtimeService = RealtimeService();
  final UserService _userService = UserService();

  final TextEditingController _composer = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<Map<String, dynamic>>? _chatSub;

  bool _loading = true;
  String? _error;
  bool _sending = false;

  bool _loadingOlder = false;
  bool _hasMore = true;

  List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _load();

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      if (_loading || _loadingOlder || !_hasMore) return;
      if (_scrollController.position.pixels <= 120) {
        _loadOlder();
      }
    });

    _chatSub = _realtimeService.chatStream.listen((event) {
      try {
        final convoId = (event['conversationId'] ?? '').toString();
        if (convoId != widget.conversationId) return;

        final id = (event['id'] ?? '').toString();
        if (id.isEmpty) return;

        final existingIdx = _messages.indexWhere(
          (m) => (m['id'] ?? '').toString() == id,
        );
        if (existingIdx >= 0) return;

        if (!mounted) return;
        setState(() {
          _messages.add({
            'id': id,
            'conversationId': convoId,
            'body': (event['body'] ?? '').toString(),
            'createdAt': (event['createdAt'] ?? '').toString(),
            'senderUser': {'id': (event['senderUserId'] ?? '').toString()},
          });
        });

        _markReadImmediate();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scrollToBottom();
        });
      } catch (_) {}
    });
  }

  @override
  void didUpdateWidget(covariant _AdminConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conversationId != widget.conversationId) {
      _load();
    }
  }

  Future<void> _markReadImmediate() async {
    try {
      await _chatService.markConversationRead(widget.conversationId);
    } catch (_) {}
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });

    try {
      final items = await _chatService.listMessages(
        widget.conversationId,
        limit: 60,
      );
      if (!mounted) return;
      setState(() {
        _messages = items;
        _hasMore = items.length >= 60;
        _loading = false;
      });

      await _markReadImmediate();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasMore) return;
    if (_messages.isEmpty) return;

    final oldestId = (_messages.first['id'] ?? '').toString();
    if (oldestId.trim().isEmpty) return;

    if (!mounted) return;
    setState(() {
      _loadingOlder = true;
      _error = null;
    });

    final beforePixels = _scrollController.hasClients
        ? _scrollController.position.pixels
        : null;
    final beforeMax = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;

    try {
      final older = await _chatService.listMessages(
        widget.conversationId,
        limit: 60,
        before: oldestId,
      );
      if (!mounted) return;

      final existingIds = _messages
          .map((m) => (m['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();
      final filtered = older
          .where((m) => !existingIds.contains((m['id'] ?? '').toString()))
          .toList();

      setState(() {
        if (filtered.isNotEmpty) {
          _messages = [...filtered, ..._messages];
        }
        _hasMore = older.length >= 60;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!_scrollController.hasClients) return;
        if (beforePixels == null || beforeMax == null) return;
        final afterMax = _scrollController.position.maxScrollExtent;
        final delta = afterMax - beforeMax;
        if (delta > 0) {
          _scrollController.jumpTo(beforePixels + delta);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingOlder = false;
        });
      }
    }
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    final max = _scrollController.position.maxScrollExtent;
    _scrollController.animateTo(
      max,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    if (_sending) return;

    if (!mounted) return;
    setState(() {
      _sending = true;
    });

    try {
      final sent = await _chatService.sendMessage(
        widget.conversationId,
        body: text,
      );
      _composer.clear();
      if (!mounted) return;

      final id = (sent['id'] ?? '').toString();
      if (id.isNotEmpty) {
        final existing = _messages.indexWhere(
          (m) => (m['id'] ?? '').toString() == id,
        );
        if (existing == -1) {
          setState(() {
            _messages.add(sent);
          });
        }
      }

      await _markReadImmediate();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _scrollToBottom();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _chatSub?.cancel();
    _composer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final me = _userService.currentUser;
    final myId = (me?.id ?? '').toString();

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Failed to load messages',
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
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            itemCount: _messages.length + (_loadingOlder ? 1 : 0),
            itemBuilder: (context, index) {
              if (_loadingOlder && index == 0) {
                return const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final msgIndex = _loadingOlder ? index - 1 : index;
              final msg = _messages[msgIndex];
              final sender = msg['senderUser'];
              final senderId = sender is Map
                  ? (sender['id'] ?? '').toString()
                  : (msg['senderUserId'] ?? '').toString();
              final mine = senderId.isNotEmpty && senderId == myId;

              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color:
                        mine ? theme.colorScheme.primary : theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.08,
                      ),
                    ),
                  ),
                  child: Text(
                    (msg['body'] ?? '').toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: mine
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sending ? null : _send,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.4),
                    disabledForegroundColor:
                        theme.colorScheme.onPrimary.withValues(alpha: 0.85),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
