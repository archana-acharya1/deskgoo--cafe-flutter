import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/auth.dart';
import 'order_screen.dart';
import '../config.dart';

import '../providers/socket_provider.dart';
import '../providers/socket_listeners.dart';

String _imgUrl(String? p) {
  if (p == null || p.isEmpty) return '';
  return p.startsWith('http')
      ? p
      : '${AppConfig.hostBase}${p.startsWith('/') ? '' : '/'}$p';
}

Color _statusColor(String status) {
  switch (status) {
    case 'occupied':
      return const Color(0xFFB71C1C);
    case 'reserved':
      return const Color(0xFFF57C00);
    default:
      return const Color(0xFF2E7D32);
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

final areasProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/areas'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) throw Exception('Failed to load areas: ${r.body}');
  return (jsonDecode(r.body)['areas'] as List).cast<Map<String, dynamic>>();
});

final tablesByAreaProvider =
FutureProvider.family<List<Map<String, dynamic>>, String>((ref, areaId) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/tables?areaId=$areaId'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) throw Exception('Failed to load tables: ${r.body}');
  return (jsonDecode(r.body)['tables'] as List).cast<Map<String, dynamic>>();
});

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  @override
  void initState() {
    super.initState();

    final socketService = ref.read(socketProvider);
    setupSocketListeners(ref);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = const Color(0xFFF57C00);
    final areasAsync = ref.watch(areasProvider);

    Future<bool> _confirmExit() async {
      final ans = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Exit App?'),
          content: const Text('Do you really want to close Deskgoo Cafe?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
              child: const Text('Exit'),
            ),
          ],
        ),
      );
      return ans ?? false;
    }

    return WillPopScope(
      onWillPop: _confirmExit,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDF6EC),
        appBar: AppBar(
          title: const Text("Areas", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          centerTitle: true,
          backgroundColor: themeColor,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.refresh(areasProvider),
            ),
          ],
        ),
        body: areasAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (areas) {
            if (areas.isEmpty) {
              return const Center(child: Text("No areas found."));
            }
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: .86,
              ),
              itemCount: areas.length,
              itemBuilder: (context, index) {
                final area = areas[index];
                final areaName = (area['name'] ?? 'Area').toString();
                final url = _imgUrl(area['image'] as String?);

                return InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TablesByAreaScreen(
                          areaId: area['_id'],
                          areaName: areaName,
                          areaImageUrl: url,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 10,
                          child: url.isEmpty
                              ? const ColoredBox(
                              color: Colors.white,
                              child: Center(child: Icon(Icons.image_outlined, color: Colors.black26)))
                              : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            areaName,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class TablesByAreaScreen extends ConsumerWidget {
  final String areaId;
  final String areaName;
  final String? areaImageUrl;

  const TablesByAreaScreen({
    super.key,
    required this.areaId,
    required this.areaName,
    this.areaImageUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeColor = const Color(0xFFF57C00);
    final tablesAsync = ref.watch(tablesByAreaProvider(areaId));

    Future<bool> _confirmLeave() async {
      final ans = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave this screen?'),
          content: const Text('Do you want to go back to Areas?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Stay'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
      return ans ?? false;
    }

    return WillPopScope(
      onWillPop: _confirmLeave,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDF6EC),
        appBar: AppBar(
          title: Text(areaName, style: const TextStyle(color: Colors.white)),
          backgroundColor: themeColor,
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => ref.refresh(tablesByAreaProvider(areaId)),
            ),
          ],
        ),
        body: tablesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (tables) {
            if (tables.isEmpty) {
              return RefreshIndicator(
                onRefresh: () async => ref.refresh(tablesByAreaProvider(areaId)),
                child: ListView(
                  children: [
                    if ((areaImageUrl ?? '').isNotEmpty)
                      AspectRatio(
                        aspectRatio: 16 / 6,
                        child: Image.network(areaImageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    const SizedBox(height: 80),
                    const Icon(Icons.table_bar, size: 64, color: Colors.black26),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text('No tables in this area.',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              );
            }

            final available = tables.where((t) => (t['status'] ?? 'available') == 'available').length;
            final occupied = tables.where((t) => (t['status'] ?? 'available') == 'occupied').length;
            final reserved = tables.where((t) => (t['status'] ?? 'available') == 'reserved').length;

            return RefreshIndicator(
              onRefresh: () async => ref.refresh(tablesByAreaProvider(areaId)),
              child: CustomScrollView(
                slivers: [
                  if ((areaImageUrl ?? '').isNotEmpty)
                    SliverToBoxAdapter(
                      child: AspectRatio(
                        aspectRatio: 16 / 6,
                        child: Image.network(areaImageUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
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
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.82,
                      ),
                      delegate: SliverChildBuilderDelegate(
                            (context, index) {
                          final t = tables[index];
                          final status = (t['status'] ?? 'available') as String;
                          final color = _statusColor(status);
                          final name = (t['name'] ?? 'Table').toString();
                          final cap = (t['capacity'] as num?)?.toInt() ?? 1;
                          final tableImg = _imgUrl(t['image'] as String?);

                          return InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderScreen(initialTableId: t['_id']),
                                ),
                              );
                            },
                            child: Card(
                              elevation: 3,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 6,
                                    child: (tableImg.isEmpty)
                                        ? const ColoredBox(
                                        color: Colors.white,
                                        child: Center(
                                            child: Icon(Icons.table_bar, color: Colors.black26)))
                                        : Image.network(
                                      tableImg,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                      const Center(child: Icon(Icons.broken_image_outlined)),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration:
                                              BoxDecoration(color: color, shape: BoxShape.circle),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold, fontSize: 16),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: color.withOpacity(.08),
                                            borderRadius: BorderRadius.circular(999),
                                            border:
                                            Border.all(color: color.withOpacity(.25)),
                                          ),
                                          child: Text(
                                            status[0].toUpperCase() + status.substring(1),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: color),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text('Cap: $cap',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.brown.shade700)),
                                            const Icon(Icons.keyboard_arrow_right,
                                                size: 18, color: Colors.black38),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
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
      ),
    );
  }
}
