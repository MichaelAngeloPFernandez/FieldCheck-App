import 'dart:convert';

import 'package:field_check/utils/http_util.dart';

class ChatService {
  static const String _basePath = '/api/chat';

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

  Future<List<Map<String, dynamic>>> listConversations() async {
    final res = await HttpUtil()
        .get('$_basePath/conversations')
        .timeout(const Duration(seconds: 15));

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
    final res = await HttpUtil()
        .post('$_basePath/conversations', body: {'otherUserId': otherUserId})
        .timeout(const Duration(seconds: 15));

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

  Future<List<Map<String, dynamic>>> listMessages(
    String conversationId, {
    int limit = 60,
    String? before,
  }) async {
    final qp = <String, String>{'limit': limit.toString()};
    if (before != null && before.trim().isNotEmpty) {
      qp['before'] = before.trim();
    }

    final res = await HttpUtil()
        .get(
          '$_basePath/conversations/$conversationId/messages',
          queryParams: qp,
        )
        .timeout(const Duration(seconds: 15));

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
    final res = await HttpUtil()
        .post(
          '$_basePath/conversations/$conversationId/messages',
          body: {'body': body},
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 201) {
      throw Exception(_formatHttpError('Send message', res));
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw Exception('Invalid send message response');
  }

  Future<void> markConversationRead(String conversationId) async {
    final res = await HttpUtil()
        .post('$_basePath/conversations/$conversationId/mark-read')
        .timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception(_formatHttpError('Mark conversation read', res));
    }
  }
}
