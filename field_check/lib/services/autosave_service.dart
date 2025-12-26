// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class AutosaveService {
  static final AutosaveService _instance = AutosaveService._internal();
  factory AutosaveService() => _instance;
  AutosaveService._internal();

  Timer? _saveTimer;
  final Map<String, dynamic> _pendingData = {};
  final Set<String> _dirtyKeys = {};
  static const Duration saveInterval = Duration(seconds: 10);
  bool _isDirty = false;

  Future<void> initialize() async {
    // Don't start timer immediately - wait for first data change
    print('AutosaveService: Initialized in event-driven mode');
  }

  void _startAutoSave() {
    _saveTimer?.cancel();
    // Only start timer if there's dirty data
    if (_isDirty && _dirtyKeys.isNotEmpty) {
      _saveTimer = Timer(saveInterval, () {
        _savePendingData();
        // Stop timer after saving, restart on next change
        _saveTimer?.cancel();
        _saveTimer = null;
      });
    }
  }

  Future<void> saveData(String key, Map<String, dynamic> data) async {
    _pendingData[key] = {
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'id': const Uuid().v4(),
    };
    _dirtyKeys.add(key);
    _isDirty = true;
    
    // Also save to SharedPreferences for immediate access
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('autosave_$key', jsonEncode(data));
    
    // Start event-driven save timer
    _startAutoSave();
  }

  Future<Map<String, dynamic>?> getData(String key) async {
    // First try to get from memory
    if (_pendingData.containsKey(key)) {
      return _pendingData[key]['data'];
    }

    // Then try SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final dataString = prefs.getString('autosave_$key');
    if (dataString != null) {
      try {
        return jsonDecode(dataString);
      } catch (e) {
        print('Error parsing autosave data for key $key: $e');
      }
    }

    // No database fallback needed since we're using SharedPreferences only

    return null;
  }

  Future<void> _savePendingData() async {
    if (_dirtyKeys.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      
      for (final key in _dirtyKeys) {
        if (_pendingData.containsKey(key)) {
          final data = _pendingData[key];
          await prefs.setString('autosave_$key', jsonEncode(data));
        }
      }
      
      _dirtyKeys.clear();
      _isDirty = false;
      print('AutosaveService: Saved ${_pendingData.length} items to SharedPreferences');
    } catch (e) {
      print('AutosaveService: Error saving to SharedPreferences: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final unsyncedData = <Map<String, dynamic>>[];
      
      for (final key in keys) {
        if (key.startsWith('autosave_') && !key.endsWith('_synced')) {
          final dataString = prefs.getString(key);
          if (dataString != null) {
            final data = jsonDecode(dataString);
            unsyncedData.add({
              'id': data['id'],
              'key': key.replaceFirst('autosave_', ''),
              'data': data,
              'timestamp': data['timestamp'],
            });
          }
        }
      }
      
      return unsyncedData;
    } catch (e) {
      print('AutosaveService: Error getting unsynced data: $e');
      return [];
    }
  }

  Future<void> markAsSynced(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('autosave_${id}_synced', true);
    } catch (e) {
      print('AutosaveService: Error marking as synced: $e');
    }
  }

  Future<void> clearData(String key) async {
    _pendingData.remove(key);
    _dirtyKeys.remove(key);

    // Clear from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('autosave_$key');
  }

  Future<void> clearAllData() async {
    _pendingData.clear();
    _dirtyKeys.clear();

    // Clear SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('autosave_')) {
        await prefs.remove(key);
      }
    }
  }

  Future<void> forceSave() async {
    await _savePendingData();
  }

  void dispose() {
    _saveTimer?.cancel();
  }
}
