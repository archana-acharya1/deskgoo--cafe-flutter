import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/socket_provider.dart';

import '../state/auth.dart';
import 'dashboard.dart';
import '../config.dart';

class ExtractedAuth {
  final String? token;
  final String? roleName;
  final String? restaurantId; // Added restaurantId
  const ExtractedAuth({this.token, this.roleName, this.restaurantId});
}

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  final _formKey = GlobalKey<FormState>();

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email is required';
    final email = v.trim();
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(email)) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'At least 6 characters';
    return null;
  }

  ExtractedAuth _extractTokenRoleAndRestaurant(Map<String, dynamic> data) {
    final token = data['token'] as String?;
    final roleName = data['role'] as String?;
    final restaurantId = data['restaurantId'] as String?; // Extract restaurantId
    return ExtractedAuth(token: token, roleName: roleName, restaurantId: restaurantId);
  }

  Future<void> _loginUser() async {
    if (!_formKey.currentState!.validate()) return;

    final email = emailController.text.trim();
    final password = passwordController.text;

    setState(() => _isLoading = true);

    final body = jsonEncode({"email": email, "password": password});

    try {
      final response = await http.post(
        Uri.parse("${AppConfig.apiBase}/auth/login"),
        headers: {"Content-Type": "application/json"},
        body: body,
      );

      setState(() => _isLoading = false);

      Map<String, dynamic>? parsed;
      try {
        final raw = jsonDecode(response.body);
        if (raw is Map<String, dynamic>) parsed = raw;
      } catch (_) {}

      if (response.statusCode == 200) {
        if (parsed == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Unexpected response format")),
          );
          return;
        }

        final extracted = _extractTokenRoleAndRestaurant(parsed);
        final token = extracted.token;
        final roleFromApi = extracted.roleName;
        final restaurantId = extracted.restaurantId;

        if (token == null || token.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login succeeded but token missing")),
          );
          return;
        }
        if (roleFromApi == null || roleFromApi.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login succeeded but role missing")),
          );
          return;
        }
        if (restaurantId == null || restaurantId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Login succeeded but restaurant ID missing")),
          );
          return;
        }

        ref.read(authStateProvider.notifier).state = AuthState(
          token: token,
          roleName: roleFromApi,
          restaurantId: restaurantId,
        );

        final socketService = ref.read(socketProvider);
        socketService.instance.connect();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Dashboard()),
        );


      } else {
        final serverMsg = parsed != null && parsed['message'] is String
            ? parsed!['message'] as String
            : 'Invalid email, password, or role';
        debugPrint('REQ: $body');
        debugPrint('RES ${response.statusCode}: ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("(${response.statusCode}) $serverMsg")),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFF8B4513);
    final accentColor = const Color(0xFFFF7043);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 5,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Deskgoo Cafe",
                          style: TextStyle(
                            color: themeColor,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 8),
                        Image.asset(
                          'assets/images/splash_logo.png',
                          height: 30,
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Login to your account",
                      style: TextStyle(
                        color: Colors.grey[700],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: emailController,
                      validator: _validateEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: "Email",
                        prefixIcon: const Icon(Icons.person, color: Colors.brown),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFFF8F0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: passwordController,
                      validator: _validatePassword,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock, color: Colors.brown),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: Colors.brown,
                          ),
                          onPressed: () => setState(() {
                            _obscurePassword = !_obscurePassword;
                          }),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFFFF8F0),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _loginUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Text(
                          "Login",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "© 2025 Deskgoo Cafe",
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}