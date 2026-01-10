import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../services/user_service.dart';

class HttpUtil {
  final String _baseUrl = ApiConfig.baseUrl;

  Future<Map<String, String>> _authHeaders(Map<String, String>? headers) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final merged = {'Accept': 'application/json', ...?headers};
    if (!(merged.containsKey('Authorization')) && token != null) {
      merged['Authorization'] = 'Bearer $token';
    }
    return merged;
  }

  Future<http.Response> _retryIfUnauthorized(
    Future<http.Response> Function() send,
  ) async {
    var res = await send();
    if (res.statusCode == 401) {
      final refreshed = await UserService().refreshAccessToken();
      if (refreshed) {
        res = await send();
      }
    }
    return res;
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: queryParams);
    final mergedHeaders = await _authHeaders(headers);
    return _retryIfUnauthorized(() => http.get(uri, headers: mergedHeaders));
  }

  Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = await _authHeaders({
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    });
    return _retryIfUnauthorized(
      () => http.post(
        uri,
        headers: mergedHeaders,
        body: body != null ? json.encode(body) : null,
      ),
    );
  }

  Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = await _authHeaders({
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    });
    return _retryIfUnauthorized(
      () => http.put(
        uri,
        headers: mergedHeaders,
        body: body != null ? json.encode(body) : null,
      ),
    );
  }

  Future<http.Response> patch(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl$path',
    ).replace(queryParameters: queryParams);
    final mergedHeaders = await _authHeaders({
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    });
    return _retryIfUnauthorized(
      () => http.patch(
        uri,
        headers: mergedHeaders,
        body: body != null ? json.encode(body) : null,
      ),
    );
  }

  Future<http.Response> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = await _authHeaders(headers);
    return _retryIfUnauthorized(() => http.delete(uri, headers: mergedHeaders));
  }
}
