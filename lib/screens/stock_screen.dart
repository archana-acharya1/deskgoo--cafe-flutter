import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../state/auth.dart';
import '../config.dart';
import 'stock_detail_screen.dart';

String _serverMsg(String action, int code, String body) {
  try {
    final d = jsonDecode(body);
    final msg = (d['error'] ?? d['message'] ?? body).toString();
    return '$action ($code): $msg';
  } catch (_) {
    return '$action ($code): $body';
  }
}

final stocksProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/stocks'),
    headers: {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    },
  );
  if (r.statusCode != 200) {
    throw Exception('Load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['stocks'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});
  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  bool get _canManage {
    final role = (ref.read(authStateProvider)?.roleName ?? '').toLowerCase();
    return role == 'admin' || role == 'manager';
  }

  Map<String, String> _headers() {
    final token = ref.read(authStateProvider)?.token ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<void> _createStockDialog() async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final alertCtrl = TextEditingController(text: '0');
    bool autoDecrement = false;
    final itemIdCtrl = TextEditingController();

    final key = GlobalKey<FormState>();
    final nav = Navigator.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFDF6EC),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Form(
              key: key,
              child: ListView(
                shrinkWrap: true,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Add Stock',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF7043))),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Stock name', border: OutlineInputBorder()),
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: unitCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Unit (e.g. 250ml / bottle / kg)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Quantity', border: OutlineInputBorder()),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Required';
                      final d = double.tryParse(t);
                      if (d == null || d < 0) return 'Invalid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: priceCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Purchase price (per unit)',
                        border: OutlineInputBorder()),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: alertCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Alert threshold',
                        border: OutlineInputBorder()),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: itemIdCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Linked item ID (optional)',
                        border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Auto decrement (sold items auto-decrement)',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: autoDecrement,
                        activeColor: const Color(0xFFFF7043),
                        onChanged: (v) {
                          setState(() {
                            autoDecrement = v;
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => nav.pop(),
                              child: const Text('Cancel'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF7043)),
                          onPressed: () async {
                            if (!key.currentState!.validate()) return;
                            final body = {
                              'name': nameCtrl.text.trim(),
                              'unit': unitCtrl.text.trim(),
                              'quantity':
                              double.tryParse(qtyCtrl.text.trim()) ?? 0,
                              'alertThreshold':
                              double.tryParse(alertCtrl.text.trim()) ?? 0,
                              'autoDecrement': autoDecrement,
                              if (itemIdCtrl.text.trim().isNotEmpty)
                                'item': itemIdCtrl.text.trim(),
                            };

                            try {
                              final r = await http.post(
                                Uri.parse('${AppConfig.apiBase}/stocks'),
                                headers: _headers(),
                                body: jsonEncode(body),
                              );
                              if (r.statusCode ~/ 100 != 2) {
                                final msg = _serverMsg('Create failed',
                                    r.statusCode, r.body);
                                if (mounted)
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(msg)));
                                return;
                              }
                              if (mounted) {
                                ref.refresh(stocksProvider);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Stock created')));
                                nav.pop();
                              }
                            } catch (e) {
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')));
                            }
                          },
                          child: const Text('Create',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _card(Map<String, dynamic> s) {
    final name = (s['name'] ?? '') as String;
    final unit = (s['unit'] ?? '') as String;
    final qty = (s['quantity'] as num?)?.toDouble() ?? 0.0;
    final alert = (s['alertThreshold'] as num?)?.toDouble() ?? 0.0;
    final autoDec = (s['autoDecrement'] as bool?) ?? false;
    final id = (s['_id'] ?? '').toString();

    final isLow = qty <= alert && alert > 0;

    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => StockDetailScreen(stockId: id)),
        );
        if (mounted) ref.refresh(stocksProvider);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF3E8), Color(0xFFFFE6D6)],
          ),
          border: Border.all(color: const Color(0x1A000000)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stock title + unit tag
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6A3B13),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(.08),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.green.withOpacity(.22)),
                    ),
                    child: Text(
                      unit.isEmpty ? '—' : unit,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Remaining stock + Low stock badge
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Remaining: ${qty.toStringAsFixed(2)} $unit',
                      style: TextStyle(
                        color: isLow ? Colors.redAccent : Colors.brown.shade800,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  if (isLow)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'Low Stock',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 6),

              // Alert + Auto badge
              Row(
                children: [
                  Text(
                    'Alert at: ${alert.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const Spacer(),
                  if (autoDec)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF7043).withOpacity(.08),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: const Color(0xFFFF7043).withOpacity(.22),
                        ),
                      ),
                      child: const Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF7043),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stocksAsync = ref.watch(stocksProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: const Text('Stocks', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFFFF7043),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search stocks…',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: stocksAsync.when(
              loading: () =>
              const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Error: $e'))),
              data: (all) {
                final list = all.where((m) {
                  final n = (m['name'] ?? '').toString().toLowerCase();
                  return _query.isEmpty || n.contains(_query);
                }).toList();

                if (list.isEmpty) {
                  return RefreshIndicator(
                    onRefresh: () async => ref.refresh(stocksProvider),
                    child: ListView(
                      children: const [
                        SizedBox(height: 80),
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: Colors.black26),
                        SizedBox(height: 12),
                        Center(child: Text('No stocks found')),
                        SizedBox(height: 80),
                      ],
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(stocksProvider),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.86,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _card(list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton(
        backgroundColor: const Color(0xFFFF7043),
        onPressed: _createStockDialog,
        child: const Icon(Icons.add, color: Colors.white),
      )
          : null,
    );
  }
}
