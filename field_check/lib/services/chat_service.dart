import 'dart:async';
import 'dart:convert';

import 'package:field_check/config/api_config.dart';
import 'package:field_check/utils/http_util.dart';

class ChatService {
  static const String _basePath = '/api/chat';

  static String? _resolvedBaseUrl;

  List<String> _baseUrlCandidates() {
    final items = <String>[
      ApiConfig.chatBaseUrl,
      ApiConfig.baseUrl,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final unique = <String>[];
    for (final u in items) {
      if (!unique.contains(u)) unique.add(u);
    }
    return unique;
  }

  HttpUtil _client([String? baseUrl]) =>
      HttpUtil(baseUrl: (baseUrl ?? ApiConfig.chatBaseUrl));

  Future<dynamic> _withFailover(
    String action,
    Future<dynamic> Function(String baseUrl) request, {
    Set<int> retryStatusCodes = const {404},
  }) async {
    final candidates = _baseUrlCandidates();
    if (candidates.isEmpty) {
      throw Exception('$action failed: No base URL configured');
    }

    final ordered = <String>[];
    final cached = (_resolvedBaseUrl ?? '').trim();
    if (cached.isNotEmpty && candidates.contains(cached)) {
      ordered.add(cached);
    }
    for (final c in candidates) {
      if (!ordered.contains(c)) ordered.add(c);
    }

    dynamic lastRes;
    Object? lastError;
    for (final baseUrl in ordered.take(2)) {
      try {
        final res = await request(baseUrl);
        lastRes = res;
        final status = res.statusCode as int?;
        if (status != null && retryStatusCodes.contains(status)) {
          continue;
        }
        _resolvedBaseUrl = baseUrl;
        return res;
      } on TimeoutException catch (e) {
        lastError = e;
        continue;
      } catch (e) {
        lastError = e;
        break;
      }
    }

    if (lastRes != null) {
      throw Exception(_formatHttpError(action, lastRes));
    }
    throw Exception('$action failed${lastError == null ? '' : ': $lastError'}');
  }

  String _formatHttpError(String action, dynamic res) {
    try {
      final status = res.statusCode;
      final rawBody = (res.body ?? '').toString();
      String? message;
      if (rawBody.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(rawBody);
          if (decoded is Map) {
            final m = decoded['message'];
            if (m != null) {
              message = m.toString();
            }
          }
        } catch (_) {
          // ignore decode errors
        }
      }

      final detail = (message != null && message.trim().isNotEmpty)
          ? message.trim()
          : (rawBody.trim().isNotEmpty ? rawBody.trim() : 'No response body');

      return '$action failed (HTTP $status): $detail';
    } catch (_) {
      return '$action failed';
    }
  }

  Future<List<Map<String, dynamic>>> listOnlineAdmins() async {
    final res = await _withFailover(
      'Load online admins',
      (baseUrl) => _client(
        baseUrl,
      ).get('$_basePath/admins/online').timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Load online admins', res));
    }

    if (res.body.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> listConversations({
    bool archived = false,
  }) async {
    final qp = <String, String>{};
    if (archived) {
      qp['archived'] = 'true';
    }
    final res = await _withFailover(
      'Load conversations',
      (baseUrl) => _client(baseUrl)
          .get('$_basePath/conversations', queryParams: qp)
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Load conversations', res));
    }

    if (res.body.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }

    return <Map<String, dynamic>>[];
  }

  Future<String> getOrCreateConversation({required String otherUserId}) async {
    final res = await _withFailover(
      'Create conversation',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/conversations', body: {'otherUserId': otherUserId})
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Create conversation', res));
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final id = (decoded['id'] ?? '').toString();
      if (id.isNotEmpty) return id;
    }

    throw Exception('Invalid conversation response');
  }

  Future<void> archiveConversation(String conversationId) async {
    final res = await _withFailover(
      'Archive conversation',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/conversations/$conversationId/archive')
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Archive conversation', res));
    }
  }

  Future<void> unarchiveConversation(String conversationId) async {
    final res = await _withFailover(
      'Unarchive conversation',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/conversations/$conversationId/unarchive')
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Unarchive conversation', res));
    }
  }

  Future<void> deleteConversation(String conversationId) async {
    final res = await _withFailover(
      'Delete conversation',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/conversations/$conversationId/delete')
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Delete conversation', res));
    }
  }

  Future<String> createGroupConversation({
    required String title,
    required List<String> participantUserIds,
  }) async {
    final body = {'title': title, 'participantUserIds': participantUserIds};
    final res = await _withFailover(
      'Create group conversation',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/group-conversations', body: body)
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 201) {
      throw Exception(_formatHttpError('Create group conversation', res));
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map) {
      final id = (decoded['id'] ?? '').toString();
      if (id.isNotEmpty) return id;
    }
    throw Exception('Invalid create group response');
  }

  Future<void> addGroupMembers(
    String conversationId, {
    required List<String> userIds,
  }) async {
    final res = await _withFailover(
      'Add group members',
      (baseUrl) => _client(baseUrl)
          .post(
            '$_basePath/group-conversations/$conversationId/members/add',
            body: {'userIds': userIds},
          )
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Add group members', res));
    }
  }

  Future<void> removeGroupMembers(
    String conversationId, {
    required List<String> userIds,
  }) async {
    final res = await _withFailover(
      'Remove group members',
      (baseUrl) => _client(baseUrl)
          .post(
            '$_basePath/group-conversations/$conversationId/members/remove',
            body: {'userIds': userIds},
          )
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Remove group members', res));
    }
  }

  Future<List<Map<String, dynamic>>> listMessages(
    String conversationId, {
    int limit = 60,
    String? before,
  }) async {
    final qp = <String, String>{'limit': limit.toString()};
    if (before != null && before.trim().isNotEmpty) {
      qp['before'] = before.trim();
    }

    final res = await _withFailover(
      'Load messages',
      (baseUrl) => _client(baseUrl)
          .get(
            '$_basePath/conversations/$conversationId/messages',
            queryParams: qp,
          )
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Load messages', res));
    }

    if (res.body.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(res.body);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>> sendMessage(
    String conversationId, {
    required String body,
  }) async {
    final res = await _withFailover(
      'Send message',
      (baseUrl) => _client(baseUrl)
          .post(
            '$_basePath/conversations/$conversationId/messages',
            body: {'body': body},
          )
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 201) {
      throw Exception(_formatHttpError('Send message', res));
    }

    if ((res.body ?? '').toString().trim().isEmpty) {
      throw Exception('Invalid send message response');
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw Exception('Invalid send message response');
  }

  Future<void> markConversationRead(String conversationId) async {
    final res = await _withFailover(
      'Mark conversation read',
      (baseUrl) => _client(baseUrl)
          .post('$_basePath/conversations/$conversationId/mark-read')
          .timeout(const Duration(seconds: 15)),
    );

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Mark conversation read', res));
    }
  }
}
