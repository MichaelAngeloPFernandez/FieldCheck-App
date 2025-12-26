// ignore_for_file: deprecated_member_use
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

Future<void> saveUsersJson(String jsonStr) async {
  final bytes = utf8.encode(jsonStr);
  final blob = html.Blob([bytes], 'application/json');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)..download = 'users-backup.json';
  anchor.click();
  html.Url.revokeObjectUrl(url);
}