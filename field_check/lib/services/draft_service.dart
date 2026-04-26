import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Service for saving and retrieving ticket form drafts locally
/// 
/// Features:
/// - Auto-save drafts every 30 seconds
/// - Recover unsaved work on crash
/// - Manual save/load
/// - Draft history
class DraftService {
  static const String _draftKeyPrefix = 'ticket_draft_';
  static const String _draftListKey = 'ticket_drafts_list';

  late SharedPreferences _prefs;

  /// Initialize storage
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Save draft (auto-called every 30s or manually)
  Future<void> saveDraft({
    required String templateId,
    required Map<String, dynamic> formData,
    required String requesterEmail,
  }) async {
    try {
      final draftId = '${templateId}_${requesterEmail}';
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      final draft = {
        'id': draftId,
        'templateId': templateId,
        'formData': formData,
        'requesterEmail': requesterEmail,
        'savedAt': timestamp,
        'version': 1,
      };

      // Save draft
      await _prefs.setString(
        '$_draftKeyPrefix$draftId',
        jsonEncode(draft),
      );

      // Update draft list
      await _updateDraftList(draftId, timestamp);
    } catch (e) {
      print('Draft save error: $e');
    }
  }

  /// Load draft if exists
  Future<Map<String, dynamic>?> loadDraft({
    required String templateId,
    required String requesterEmail,
  }) async {
    try {
      final draftId = '${templateId}_${requesterEmail}';
      final json = _prefs.getString('$_draftKeyPrefix$draftId');

      if (json == null) return null;

      final draft = jsonDecode(json) as Map<String, dynamic>;
      return draft;
    } catch (e) {
      print('Draft load error: $e');
      return null;
    }
  }

  /// List all drafts
  Future<List<Map<String, dynamic>>> listDrafts() async {
    try {
      final draftIds = _getDraftIds();
      final drafts = <Map<String, dynamic>>[];

      for (final draftId in draftIds) {
        final json = _prefs.getString('$_draftKeyPrefix$draftId');
        if (json != null) {
          drafts.add(jsonDecode(json) as Map<String, dynamic>);
        }
      }

      // Sort by saved time (newest first)
      drafts.sort((a, b) => (b['savedAt'] as int).compareTo(a['savedAt'] as int));
      return drafts;
    } catch (e) {
      print('List drafts error: $e');
      return [];
    }
  }

  /// Delete draft
  Future<void> deleteDraft({
    required String templateId,
    required String requesterEmail,
  }) async {
    try {
      final draftId = '${templateId}_${requesterEmail}';
      await _prefs.remove('$_draftKeyPrefix$draftId');
      await _removeDraftFromList(draftId);
    } catch (e) {
      print('Draft delete error: $e');
    }
  }

  /// Clear all drafts
  Future<void> clearAllDrafts() async {
    try {
      final draftIds = _getDraftIds();
      for (final draftId in draftIds) {
        await _prefs.remove('$_draftKeyPrefix$draftId');
      }
      await _prefs.remove(_draftListKey);
    } catch (e) {
      print('Clear drafts error: $e');
    }
  }

  /// Get draft metadata (time saved, field count, etc.)
  Map<String, dynamic> getDraftMetadata(Map<String, dynamic> draft) {
    final savedAt = DateTime.fromMillisecondsSinceEpoch(
      draft['savedAt'] as int,
    );
    final formData = draft['formData'] as Map<String, dynamic>? ?? {};
    final fieldCount = formData.length;

    return {
      'templateId': draft['templateId'],
      'savedAt': savedAt,
      'formattedTime': _formatTime(savedAt),
      'fieldCount': fieldCount,
    };
  }

  void _updateDraftIds(List<String> ids) {
    _prefs.setStringList(_draftListKey, ids);
  }

  Future<void> _updateDraftList(String draftId, int timestamp) async {
    var ids = _getDraftIds();
    if (!ids.contains(draftId)) {
      ids.add(draftId);
    }
    _updateDraftIds(ids);
  }

  Future<void> _removeDraftFromList(String draftId) async {
    var ids = _getDraftIds();
    ids.remove(draftId);
    _updateDraftIds(ids);
  }

  List<String> _getDraftIds() {
    return _prefs.getStringList(_draftListKey) ?? [];
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes == 0) return 'Just now';
    if (diff.inHours == 0) return '${diff.inMinutes}m ago';
    if (diff.inDays == 0) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${time.day}/${time.month}/${time.year}';
  }
}
