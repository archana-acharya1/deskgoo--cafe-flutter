import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';

import '../config.dart';
import '../state/auth.dart';

class ExtractedAuth {
  final String? token;
  final String? roleName;
  const ExtractedAuth({this.token, this.roleName});
}

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  String get _baseUrl => AppConfig.apiBase;

  ExtractedAuth _getAuth() {
    final auth = ref.read(authStateProvider);
    return ExtractedAuth(token: auth?.token, roleName: auth?.roleName);
  }

  /// ---- Role helpers (keep superadmin invisible on the frontend) ----

  /// Extract a role name from either a string or a `{ name: ... }` map.
  String _extractRoleName(dynamic role) {
    if (role is Map && role['name'] is String) return role['name'] as String;
    if (role is String) return role;
    return '';
  }

  /// Normalize a role label to letters-only lowercase (e.g., "Super-Admin" -> "superadmin").
  String _normRole(String roleName) =>
      roleName.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  /// Decide if a given role name should be hidden in the UI.
  bool _isHiddenRoleName(String roleName) => _normRole(roleName) == 'superadmin';

  /// Decide if a given user map should be hidden in the UI.
  bool _shouldHideUser(Map<String, dynamic> item) {
    final rn = _extractRoleName(item['role']);
    return _isHiddenRoleName(rn);
  }

  late Future<List<dynamic>> _usersFuture;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _usersFuture = fetchItems();
  }

  Future<List<dynamic>> fetchItems() async {
    final auth = _getAuth();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      throw Exception("No auth token. Please log in again.");
    }

    final response = await http.get(
      Uri.parse("$_baseUrl/users"),
      headers: {
        "Authorization": "Bearer $token",
        "Accept": "application/json",
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      // Base list from API
      final raw = (data["users"] as List?)?.whereType<dynamic>().toList() ?? [];

      // Ensure we only feed the UI non-superadmin users
      final filtered = raw
          .whereType<Map<String, dynamic>>()
          .where((m) => !_shouldHideUser(m))
          .toList();

      return filtered;
    } else {
      throw Exception("Failed to load users: ${response.statusCode} ${response.body}");
    }
  }

  Future<void> _createUser({
    required String name,
    required String email,
    required String password,
    required String role,
  }) async {
    final auth = _getAuth();
    final token = auth.token;
    if (token == null || token.isEmpty) {
      throw Exception("No auth token. Please log in again.");
    }

    // Frontend safety: never allow creating 'superadmin' from UI
    if (_isHiddenRoleName(role)) {
      throw Exception("Invalid role.");
    }

    final body = jsonEncode({
      "name": name,
      "email": email,
      "password": password,
      "role": role,
    });

    final response = await http.post(
      Uri.parse("$_baseUrl/users"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String msg = "Failed to create user";
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data["message"] is String) {
          msg = data["message"];
        } else if (data is Map && data["error"] is String) {
          msg = data["error"];
        }
      } catch (_) {}
      throw Exception(msg);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _usersFuture = fetchItems();
    });
    await _usersFuture;
  }

  String _initials(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return '?';
    final parts = n.split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts.first[0] : '';
    final last = parts.length > 1 ? parts.last[0] : '';
    final s = (first + last).toUpperCase();
    return s.isEmpty ? '?' : s;
  }

  Color _roleColor(String role) {
    switch (_normRole(role)) {
      case 'manager':
        return const Color(0xFF1565C0);
      case 'staff':
        return const Color(0xFF2E7D32);
      default:
        return const Color(0xFF6D4C41);
    }
  }

  Widget _buildUserCard(Map<String, dynamic> item) {
    final name = (item['name'] ?? 'No Name') as String;
    final email = (item['email'] ?? '') as String;
    final roleName = _extractRoleName(item['role']).trim();

    final roleClr = _roleColor(roleName);

    return Card(
      elevation: 1.5,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: roleClr.withOpacity(.12),
                child: Text(
                  _initials(name),
                  style: TextStyle(
                    color: roleClr,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleClr.withOpacity(.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: roleClr.withOpacity(.25)),
                          ),
                          child: Text(
                            roleName.isEmpty
                                ? 'No Role'
                                : roleName[0].toUpperCase() + roleName.substring(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: roleClr,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                onSelected: (v) {},
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'view', child: Text('View')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openAddUserModal() async {
    final themeColor = const Color(0xFFF57C00);
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    final currentRole = (_getAuth().roleName ?? '').toLowerCase();

    // Choose a safe default role for the current user's level
    // - manager -> can create 'staff' (default to staff)
    // - admin/superadmin -> can create 'manager' (default to manager)
    String roleValue = currentRole == 'manager' ? 'staff' : 'manager';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDF6EC),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: StatefulBuilder(
            builder: (ctx, setSheetState) {
              // Allowable creation options, never include superadmin in the UI
              final roleItems = <DropdownMenuItem<String>>[
                if (currentRole == 'admin' || currentRole == 'superadmin')
                  const DropdownMenuItem(value: "manager", child: Text("Manager")),
                if (currentRole == 'admin' || currentRole == 'manager' || currentRole == 'superadmin')
                  const DropdownMenuItem(value: "staff", child: Text("Staff")),
              ];

              final hasValue = roleItems.any((e) => e.value == roleValue);
              final effectiveValue = hasValue && !_isHiddenRoleName(roleValue) ? roleValue : null;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        "Add User",
                        style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                          color: themeColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: "Name",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return "Required";
                          final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+$");
                          if (!emailRegex.hasMatch(v.trim())) {
                            return "Enter a valid email";
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordCtrl,
                        decoration: const InputDecoration(
                          labelText: "Password",
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                        validator: (v) => (v == null || v.length < 6) ? "Min 6 characters" : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: effectiveValue,
                        items: roleItems,
                        onChanged: (v) {
                          if (v != null) setSheetState(() => roleValue = v);
                        },
                        decoration: const InputDecoration(
                          labelText: "Role",
                          border: OutlineInputBorder(),
                        ),
                        validator: (_) {
                          // Ensure a valid, visible role is chosen
                          if (!roleItems.any((e) => e.value == roleValue)) {
                            return "Please choose a role";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text("Cancel"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: themeColor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                try {
                                  await _createUser(
                                    name: nameCtrl.text.trim(),
                                    email: emailCtrl.text.trim(),
                                    password: passwordCtrl.text,
                                    role: roleValue,
                                  );
                                  if (context.mounted) {
                                    Navigator.of(ctx).pop();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("User created")),
                                    );
                                    setState(() {
                                      _usersFuture = fetchItems(); // refresh
                                    });
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(e.toString())),
                                    );
                                  }
                                }
                              },
                              child: const Text("Create"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFFF57C00);
    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: const Text(
          "User Management",
          style: TextStyle(color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: themeColor,
        elevation: 2,
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: "Search users by name, email, or role",
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Colors.black12),
                ),
              ),
            ),
          ),

          // List
          Expanded(
            child: FutureBuilder<List<dynamic>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        "Error: ${snapshot.error}",
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                // Double-protect: exclude superadmins even if backend response changes
                final allItems = (snapshot.data ?? [])
                    .whereType<Map<String, dynamic>>()
                    .where((m) => !_shouldHideUser(m))
                    .toList();

                final items = allItems.where((m) {
                  final name = (m['name'] ?? '').toString().toLowerCase();
                  final email = (m['email'] ?? '').toString().toLowerCase();
                  final roleName = _extractRoleName(m['role']).toLowerCase();
                  if (_query.isEmpty) return true;
                  return name.contains(_query) || email.contains(_query) || roleName.contains(_query);
                }).toList();

                if (items.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.group_outlined, size: 64, color: Colors.black26),
                        SizedBox(height: 12),
                        Center(
                          child: Text(
                            "No users found",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(height: 4),
                        Center(
                          child: Text(
                            "Try changing your search or add a new user.",
                            style: TextStyle(color: Colors.black54),
                          ),
                        ),
                        SizedBox(height: 80),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(top: 6, bottom: 90),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 2),
                    itemBuilder: (context, index) =>
                        _buildUserCard(items[index] as Map<String, dynamic>),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF7043),
        onPressed: _openAddUserModal,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
