// ignore_for_file: deprecated_member_use
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class UrlUtil {
  static void updateTabQueryParam(int index) {
    if (!kIsWeb) return;

    try {
      final uri = Uri.base;
      final newUri = uri.replace(
        queryParameters: {...uri.queryParameters, 'tab': index.toString()},
      );
      html.window.history.replaceState(null, 'FieldCheck', newUri.toString());
    } catch (e) {
      debugPrint('Error updating URL: $e');
    }
  }

  static void updateUrl(String path, Map<String, String> queryParams) {
    if (!kIsWeb) return;

    try {
      final uri = Uri.base.replace(path: path, queryParameters: queryParams);
      html.window.history.replaceState(null, 'FieldCheck', uri.toString());
    } catch (e) {
      debugPrint('Error updating URL: $e');
    }
  }
}
