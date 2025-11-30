// ignore_for_file: unnecessary_underscores
import 'package:flutter/material.dart';
import '../services/user_service.dart';
import '../models/user_model.dart';

class ManageAdminsScreen extends StatefulWidget {
  const ManageAdminsScreen({super.key, this.showInactiveOnly = false});
  final bool showInactiveOnly;
  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  final UserService _userService = UserService();
  late Future<List<UserModel>> _adminsFuture;
  final TextEditingController _searchController = TextEditingController();
  String _filterStatus = 'all';
  final Set<String> _selectedAdminIds = {};
  bool _isSelectMode = false;

  @override
  void initState() {
    super.initState();
    _adminsFuture = _userService.fetchAdmins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _adminsFuture = _userService.fetchAdmins();
      _selectedAdminIds.clear();
      _isSelectMode = false;
    });
  }

  List<UserModel> _filterAdmins(List<UserModel> admins) {
    List<UserModel> filtered = admins;

    // Apply search filter
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      filtered = filtered
          .where(
            (e) =>
                e.name.toLowerCase().contains(query) ||
                e.email.toLowerCase().contains(query) ||
                (e.username?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }

    // Apply status filter
    if (_filterStatus == 'active') {
      filtered = filtered.where((e) => e.isActive).toList();
    } else if (_filterStatus == 'inactive') {
      filtered = filtered.where((e) => !e.isActive).toList();
    } else if (_filterStatus == 'verified') {
      filtered = filtered.where((e) => e.isVerified).toList();
    } else if (_filterStatus == 'unverified') {
      filtered = filtered.where((e) => !e.isVerified).toList();
    }

    return filtered;
  }

  Future<void> _deactivateSelected() async {
    if (_selectedAdminIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Multiple'),
        content: Text(
          'Deactivate ${_selectedAdminIds.length} administrator(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        for (final id in _selectedAdminIds) {
          await _userService.deactivateUser(id);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedAdminIds.length} administrator(s) deactivated',
            ),
          ),
        );
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedAdminIds.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Multiple'),
        content: Text(
          'Permanently delete ${_selectedAdminIds.length} administrator(s)? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        for (final id in _selectedAdminIds) {
          await _userService.deleteUser(id);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_selectedAdminIds.length} administrator(s) deleted',
            ),
          ),
        );
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _addAdmin() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Administrator'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                TextFormField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Temporary Password',
                  ),
                  obscureText: true,
                  validator: (v) =>
                      (v == null || v.length < 6) ? 'Min 6 characters' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _userService.register(
          nameController.text.trim(),
          emailController.text.trim(),
          passwordController.text,
          role: 'admin',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Administrator added')));
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add administrator: $e')),
        );
      }
    }
  }

  Future<void> _confirmAndDelete(UserModel user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Administrator'),
        content: Text('Are you sure you want to delete ${user.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _userService.deleteUser(user.id);
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Administrator deleted')));
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Future<void> _deactivate(UserModel user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate Administrator'),
        content: Text('Deactivate ${user.name}\'s account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _userService.deactivateUser(user.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Administrator deactivated')),
        );
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to deactivate: $e')));
      }
    }
  }

  Future<void> _reactivate(UserModel user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reactivate Administrator'),
        content: Text('Reactivate ${user.name}\'s account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reactivate'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _userService.reactivateUser(user.id);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Administrator reactivated')),
        );
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to reactivate: $e')));
      }
    }
  }

  Future<void> _edit(UserModel user) async {
    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    String role = user.role;
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Administrator'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                TextFormField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(
                      value: 'employee',
                      child: Text('Employee'),
                    ),
                  ],
                  onChanged: (v) => role = v ?? role,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _userService.updateUserByAdmin(
          user.id,
          name: nameController.text.trim(),
          email: emailController.text.trim(),
          role: role,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Administrator updated')));
        await _refresh();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Administrators'),
        backgroundColor: const Color(0xFF2688d4),
        actions: [
          if (!_isSelectMode)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed: _addAdmin,
                icon: const Icon(Icons.person_add),
                label: const Text('Add Admin'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2688d4),
                ),
              ),
            ),
          if (_isSelectMode && _selectedAdminIds.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'deactivate':
                    _deactivateSelected();
                    break;
                  case 'delete':
                    _deleteSelected();
                    break;
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'deactivate',
                  child: Text('Deactivate (${_selectedAdminIds.length})'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete (${_selectedAdminIds.length})'),
                ),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade100,
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, email, or username...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                // Filter chips
                Wrap(
                  spacing: 8,
                  children: [
                    FilterChip(
                      label: const Text('All'),
                      selected: _filterStatus == 'all',
                      onSelected: (_) => setState(() => _filterStatus = 'all'),
                    ),
                    FilterChip(
                      label: const Text('Active'),
                      selected: _filterStatus == 'active',
                      onSelected: (_) =>
                          setState(() => _filterStatus = 'active'),
                    ),
                    FilterChip(
                      label: const Text('Inactive'),
                      selected: _filterStatus == 'inactive',
                      onSelected: (_) =>
                          setState(() => _filterStatus = 'inactive'),
                    ),
                    FilterChip(
                      label: const Text('Verified'),
                      selected: _filterStatus == 'verified',
                      onSelected: (_) =>
                          setState(() => _filterStatus = 'verified'),
                    ),
                    FilterChip(
                      label: const Text('Unverified'),
                      selected: _filterStatus == 'unverified',
                      onSelected: (_) =>
                          setState(() => _filterStatus = 'unverified'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Select mode toggle
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: Icon(
                      _isSelectMode
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                    ),
                    label: Text(
                      _isSelectMode ? 'Exit Select Mode' : 'Select Mode',
                    ),
                    onPressed: () {
                      setState(() {
                        _isSelectMode = !_isSelectMode;
                        if (!_isSelectMode) {
                          _selectedAdminIds.clear();
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          // Admin list
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: FutureBuilder<List<UserModel>>(
                future: _adminsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: ${snapshot.error}'));
                  }
                  final admins = snapshot.data ?? [];
                  final filtered = _filterAdmins(admins);

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _searchController.text.isNotEmpty
                            ? 'No administrators match your search'
                            : 'No administrators found',
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final UserModel user = filtered[index];
                      final isSelected = _selectedAdminIds.contains(user.id);

                      return ListTile(
                        leading: _isSelectMode
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedAdminIds.remove(user.id);
                                    } else {
                                      _selectedAdminIds.add(user.id);
                                    }
                                  });
                                },
                              )
                            : const CircleAvatar(
                                child: Icon(Icons.admin_panel_settings),
                              ),
                        title: Text(user.name),
                        subtitle: Text(
                          '${user.email} · ${user.role}${user.isActive ? '' : ' · Inactive'}${user.isVerified ? '' : ' · Unverified'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: _isSelectMode
                            ? null
                            : PopupMenuButton<String>(
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _edit(user);
                                      break;
                                    case 'deactivate':
                                      _deactivate(user);
                                      break;
                                    case 'reactivate':
                                      _reactivate(user);
                                      break;
                                    case 'delete':
                                      _confirmAndDelete(user);
                                      break;
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Edit'),
                                  ),
                                  PopupMenuItem(
                                    value: user.isActive
                                        ? 'deactivate'
                                        : 'reactivate',
                                    child: Text(
                                      user.isActive
                                          ? 'Deactivate'
                                          : 'Reactivate',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete'),
                                  ),
                                ],
                              ),
                        onTap: _isSelectMode
                            ? () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedAdminIds.remove(user.id);
                                  } else {
                                    _selectedAdminIds.add(user.id);
                                  }
                                });
                              }
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
