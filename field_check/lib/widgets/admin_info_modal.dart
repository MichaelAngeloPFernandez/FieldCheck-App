import 'package:flutter/material.dart';
import 'package:field_check/models/user_model.dart';
import 'package:field_check/services/user_service.dart';

class AdminInfoModal extends StatefulWidget {
  const AdminInfoModal({super.key});

  @override
  State<AdminInfoModal> createState() => _AdminInfoModalState();
}

class _AdminInfoModalState extends State<AdminInfoModal> {
  final UserService _userService = UserService();
  late Future<List<UserModel>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _userService.fetchAllUsers();
  }

  Future<void> _refresh() async {
    setState(() {
      _usersFuture = _userService.fetchAllUsers();
    });
  }

  Future<void> _resetPassword(UserModel user) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reset Password: ${user.username ?? user.email}'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password (min 6 chars)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final pass = controller.text.trim();
    if (pass.length < 6) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    try {
      await _userService.resetUserPasswordByAdmin(user.id, pass);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successful')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Reset failed: $e')),
      );
    }
  }

  Widget _buildUserTile(UserModel user) {
    final subtitleLines = <String>[];
    if (user.email.isNotEmpty) subtitleLines.add('Email: ${user.email}');
    if ((user.phone ?? '').isNotEmpty) subtitleLines.add('Phone: ${user.phone}');
    subtitleLines.add('Role: ${user.role}');
    subtitleLines.add('Active: ${user.isActive ? 'Yes' : 'No'}');
    subtitleLines.add('Verified: ${user.isVerified ? 'Yes' : 'No'}');

    return Card(
      child: ListTile(
        leading: Icon(
          user.role == 'admin' ? Icons.admin_panel_settings : Icons.badge,
        ),
        title: Text(user.username ?? user.name),
        subtitle: Text(subtitleLines.join('\n')),
        isThreeLine: true,
        trailing: IconButton(
          tooltip: 'Reset password',
          icon: const Icon(Icons.key),
          onPressed: () => _resetPassword(user),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Admin Info',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _refresh,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<UserModel>>(
                future: _usersFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Failed to load users: ${snapshot.error}'),
                    );
                  }

                  final users = (snapshot.data ?? [])
                    ..sort((a, b) {
                      if (a.role != b.role) {
                        return a.role == 'admin' ? -1 : 1;
                      }
                      return (a.username ?? a.name).compareTo(b.username ?? b.name);
                    });

                  if (users.isEmpty) {
                    return const Center(child: Text('No users found.'));
                  }

                  return ListView.builder(
                    itemCount: users.length,
                    itemBuilder: (context, i) => _buildUserTile(users[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
