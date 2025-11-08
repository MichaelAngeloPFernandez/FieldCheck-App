import 'dart:convert';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class HttpUtil {
  final String _baseUrl = ApiConfig.baseUrl;

  Future<http.Response> get(String path, {Map<String, String>? queryParams, Map<String, String>? headers}) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final mergedHeaders = {'Accept': 'application/json', ...?headers};
    return await http.get(uri, headers: mergedHeaders);
  }

  Future<http.Response> post(String path, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = {'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers};
    return await http.post(
      uri,
      headers: mergedHeaders,
      body: json.encode(body),
    );
  }

  Future<http.Response> put(String path, {Map<String, dynamic>? body, Map<String, String>? headers}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = {'Content-Type': 'application/json', 'Accept': 'application/json', ...?headers};
    return await http.put(
      uri,
      headers: mergedHeaders,
      body: json.encode(body),
    );
  }

  Future<http.Response> patch(String path, {Map<String, String>? headers, Map<String, dynamic>? body, Map<String, String>? queryParams}) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);
    final mergedHeaders = {
      'Accept': 'application/json',
      ...?headers,
    };
    return await http.patch(uri, headers: mergedHeaders, body: body != null ? json.encode(body) : null);
  }

  Future<http.Response> delete(String path, {Map<String, String>? headers}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final mergedHeaders = {'Accept': 'application/json', ...?headers};
    return await http.delete(uri, headers: mergedHeaders);
  }
}