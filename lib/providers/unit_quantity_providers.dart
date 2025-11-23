import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../state/auth.dart';
import '../config.dart';

final unitsProvider = FutureProvider<List<String>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/items/distinct-units'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );

  if (r.statusCode != 200) {
    throw Exception('Failed to load units: ${r.statusCode}');
  }

  final decoded = jsonDecode(r.body);
  final list = decoded is List ? decoded : (decoded['units'] as List? ?? []);
  return list.map((u) => u.toString()).toList();
});

final quantitiesProvider = FutureProvider<List<String>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/items/quantities'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );

  if (r.statusCode != 200) {
    throw Exception('Failed to load quantities: ${r.statusCode}');
  }

  final decoded = jsonDecode(r.body);
  final list = decoded is List ? decoded : (decoded['quantities'] as List? ?? []);
  return list.map((q) => q.toString()).toList();
});
