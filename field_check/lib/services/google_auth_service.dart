import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class GoogleAuthService {
  final String _clientId = const String.fromEnvironment('GOOGLE_CLIENT_ID');
  late final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: _clientId.isEmpty ? null : _clientId,
  );

  Future<bool> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) return false;
    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) return false;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/api/users/google-signin'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'idToken': idToken}),
    );
    if (res.statusCode != 200) return false;
    final data = json.decode(res.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    final token = data['token'] as String?;
    final refreshToken = data['refreshToken'] as String?;
    if (token != null) await prefs.setString('auth_token', token);
    if (refreshToken != null) await prefs.setString('refresh_token', refreshToken);
    return true;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('refresh_token');
  }
}