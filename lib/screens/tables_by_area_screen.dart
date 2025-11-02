import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/auth.dart';
import '../config.dart';
import 'order_screen.dart';

String _serverMsg(String action, int code, String body) {
  try {
    final d = jsonDecode(body);
    final msg = (d['error'] ?? d['message'] ?? body).toString();
    return '$action ($code): $msg';
  } catch (_) {
    return '$action ($code): $body';
  }
}

final tablesByAreaProvider =
FutureProvider.family<List<Map<String, dynamic>>, String>((ref, areaId) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final headers = {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/tables?areaId=$areaId'),
    headers: headers,
  );
  if (r.statusCode != 200) {
    throw Exception('Load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['tables'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class TablesByAreaScreen extends ConsumerWidget {
  final String areaId;
  final String areaName;
  const TablesByAreaScreen({
    super.key,
    required this.areaId,
    required this.areaName,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'occupied':
        return const Color(0xFFB71C1C); // red
      case 'reserved':
        return const Color(0xFFF57C00); // orange
      default:
        return const Color(0xFF2E7D32); // green
    }
  }

  Widget _legendChip(Color color, String label, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('$label: $count', style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tablesAsync = ref.watch(tablesByAreaProvider(areaId));

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: Text('Tables • $areaName', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFFF7043),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.refresh(tablesByAreaProvider(areaId)),
          )
        ],
      ),
      body: tablesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Error: $e', textAlign: TextAlign.center),
        )),
        data: (tables) {
          if (tables.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => ref.refresh(tablesByAreaProvider(areaId)),
              child: ListView(
                children: const [
                  SizedBox(height: 80),
                  Icon(Icons.table_bar, size: 64, color: Colors.black26),
                  SizedBox(height: 12),
                  Center(child: Text('No tables in this area', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                  SizedBox(height: 80),
                ],
              ),
            );
          }

          final available = tables.where((t) => (t['status'] ?? 'available') == 'available').length;
          final occupied  = tables.where((t) => (t['status'] ?? 'available') == 'occupied').length;
          final reserved  = tables.where((t) => (t['status'] ?? 'available') == 'reserved').length;

          return RefreshIndicator(
            onRefresh: () async => ref.refresh(tablesByAreaProvider(areaId)),
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _legendChip(const Color(0xFF2E7D32), 'Available', available),
                        _legendChip(const Color(0xFFB71C1C), 'Occupied', occupied),
                        _legendChip(const Color(0xFFF57C00), 'Reserved', reserved),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    delegate: SliverChildBuilderDelegate(
                          (context, i) {
                        final t = tables[i];
                        final status = (t['status'] ?? 'available') as String;
                        final color = _statusColor(status);
                        final name = (t['name'] ?? 'No name').toString();
                        final cap  = (t['capacity'] as num?)?.toInt() ?? 1;

                        return InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => OrderScreen(
                                  initialTableId: (t['_id'] ?? '').toString(),
                                  order: null,
                                  isEdit: false,
                                ),
                              ),
                            );
                          },
                          child: Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(.08),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(color: color.withOpacity(.25)),
                                    ),
                                    child: Text(
                                      status[0].toUpperCase() + status.substring(1),
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
                                    ),
                                  ),
                                  const Spacer(),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text('Cap: $cap', style: TextStyle(fontSize: 12, color: Colors.brown.shade700)),
                                      const Icon(Icons.keyboard_arrow_right, size: 18, color: Colors.black38),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: tables.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF7043),
        onPressed: () => ref.refresh(tablesByAreaProvider(areaId)),
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }
}
