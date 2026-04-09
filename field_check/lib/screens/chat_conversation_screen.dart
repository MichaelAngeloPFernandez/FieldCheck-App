import 'dart:async';

import 'package:field_check/services/chat_service.dart';
import 'package:field_check/services/realtime_service.dart';
import 'package:field_check/services/user_service.dart';
import 'package:flutter/material.dart';

class ChatConversationScreen extends StatefulWidget {
  final String conversationId;

  const ChatConversationScreen({super.key, required this.conversationId});

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
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

      // de-dupe by id
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

      final sentId = (sent['id'] ?? '').toString();
      if (sentId.isNotEmpty && mounted) {
        final exists = _messages.any(
          (m) => (m['id'] ?? '').toString() == sentId,
        );
        if (!exists) {
          setState(() {
            _messages.add(sent);
          });
        }
      }

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversation'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_error != null)
                ? Center(
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
                  )
                : ListView.builder(
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
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? theme.colorScheme.primary
                                : theme.colorScheme.surface,
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
                      disabledBackgroundColor: theme.colorScheme.primary
                          .withValues(alpha: 0.4),
                      disabledForegroundColor: theme.colorScheme.onPrimary
                          .withValues(alpha: 0.85),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Icon(Icons.send_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
