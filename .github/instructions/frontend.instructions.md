---
name: frontend-quality
description: "Frontend/Flutter development guidelines. Use when: building UI screens, fixing Flutter/Dart code, or improving mobile/web features. Prevents common crashes, ensures error handling, and improves performance."
applyTo: "field_check/lib/**/*.dart"
---

# Frontend (Flutter/Dart) Development Guidelines

## Critical Requirements for All Services & Screens

### 1. HTTP Request Error Handling (REQUIRED)
All HTTP requests must have timeouts and error handling:

```dart
// ✅ CORRECT
Future<List<Report>> getReports({String? type}) async {
  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/reports${type != null ? '?type=$type' : ''}'),
      headers: _getHeaders(),
    ).timeout(
      Duration(seconds: 30),
      onTimeout: () => throw TimeoutException('Request timed out'),
    );
    
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List)
          .map((r) => Report.fromJson(r))
          .toList();
    } else if (response.statusCode == 401) {
      // Handle auth failure
      throw UnauthorizedException('Session expired');
    } else {
      throw Exception('Failed to load reports: ${response.statusCode}');
    }
  } catch (e) {
    print('Error fetching reports: $e');
    rethrow;
  }
}

// ❌ WRONG - No timeout, poor error handling
Future<List<Report>> getReports() async {
  final response = await http.get(Uri.parse('$baseUrl/api/reports'));
  return (jsonDecode(response.body) as List)
      .map((r) => Report.fromJson(r))
      .toList();
}
```

### 2. Null Safety & Resource Management (REQUIRED)
Never access potentially null objects without checking:

```dart
// ✅ CORRECT - Null checks before use
if (_prefs != null) {
  _prefs!.setString('token', token);
}

// For SharedPreferences, ensure it's initialized
Future<void> initPrefs() async {
  _prefs = await SharedPreferences.getInstance();
}

// ❌ WRONG - Could throw NPE
_prefs.setString('token', token); // _prefs might be null!
```

### 3. Real-Time Socket.io Connection Handling (REQUIRED)
Socket connections must reconnect on failure:

```dart
// ✅ CORRECT - Auto-reconnect with backoff
void _initSocket() {
  socket = IO.io(baseUrl, <String, dynamic>{
    'transports': ['websocket'],
    'autoConnect': true,
    'reconnection': true,
    'reconnectionDelay': 1000,
    'reconnectionDelayMax': 5000,
    'reconnectionAttempts': 5,
  });
  
  socket.on('disconnect', (_) {
    print('Socket disconnected, will reconnect...');
    // Will auto-reconnect based on settings above
  });
}

// ❌ WRONG - No reconnection logic
void _initSocket() {
  socket = IO.io(baseUrl);
  socket.connect();
}
```

### 4. Location Service Validation (REQUIRED)
Validate GPS accuracy before trusting location data:

```dart
// ✅ CORRECT - Check accuracy
Future<LatLng?> getCurrentLocation() async {
  try {
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: Duration(seconds: 10),
    );
    
    // Validate accuracy (accept within 50m)
    if (position.accuracy > 50.0) {
      print('Low accuracy: ${position.accuracy}m, retrying...');
      return null; // Could retry
    }
    
    return LatLng(position.latitude, position.longitude);
  } catch (e) {
    print('Location error: $e');
    return null;
  }
}

// ❌ WRONG - No accuracy check
Future<LatLng> getCurrentLocation() async {
  final position = await Geolocator.getCurrentPosition();
  return LatLng(position.latitude, position.longitude);
}
```

### 5. API Query Parameters (REQUIRED)
Always pass required query parameters correctly:

```dart
// When fetching reports, MUST include type parameter
// ✅ CORRECT
Future<List<Report>> getReports() async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/reports?type=attendance'),
    headers: _getHeaders(),
  );
  // ...
}

// ❌ WRONG - Missing type parameter, returns 0 results
Future<List<Report>> getReports() async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/reports'), // Missing ?type=attendance
    headers: _getHeaders(),
  );
  // ...
}
```

## Known Issues to Fix

| File | Issue | Fix |
|------|-------|-----|
| services/http_util.dart | No timeouts on requests | Add `.timeout(Duration(seconds: 30))` to all requests |
| services/http_util.dart | Infinite retry on 401 | Don't retry on auth failure |
| services/location_service.dart | No accuracy validation | Check position.accuracy before returning |
| services/geofence_service.dart | No socket reconnection | Set `'reconnection': true` in socket config |
| services/auth_service.dart | Null _prefs risk | Check `if (_prefs != null)` before use |
| services/report_service.dart | Missing type parameter | Use `?type=attendance` in queries |
| screens/avatar_upload.dart | Fake URL return | Implement actual multipart file upload |

## Critical Bugs to Debug

1. **Auto check-in on login**: Search for auto-check-in logic in dashboard initialization
2. **Geofence list not scrollable**: Ensure ListView/SingleChildScrollView wraps geofence list
3. **Location search not working**: Verify geocoding plugin is imported and initialized
4. **UI buttons still visible**: Verify register/google buttons are fully removed (not just hidden)

## Performance Checklist
- [ ] All HTTP requests have timeouts
- [ ] No infinite loops in retry logic
- [ ] Socket.io configured for auto-reconnect
- [ ] Location requests use appropriate accuracy level
- [ ] List views have proper scrolling
- [ ] No memory leaks from unclosed streams/sockets
