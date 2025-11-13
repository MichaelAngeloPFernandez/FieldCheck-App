import 'dart:io';

Future<void> saveUsersJson(String jsonStr) async {
  final file = File('users-backup.json');
  await file.writeAsString(jsonStr);
}