import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../state/auth.dart';

class ManualStockScreen extends ConsumerStatefulWidget {
  const ManualStockScreen({super.key});

  @override
  ConsumerState<ManualStockScreen> createState() => _ManualStockScreenState();
}

class _ManualStockScreenState extends ConsumerState<ManualStockScreen> {
  List<Map<String, dynamic>> _stocks = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadStocks();
  }

  Future<void> _loadStocks() async {
    setState(() => _loading = true);
    final token = ref.read(authStateProvider)?.token ?? '';
    try {
      final res = await http.get(
        Uri.parse('${AppConfig.apiBase}/stocks'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
        },
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _stocks = List<Map<String, dynamic>>.from(data['stocks'] ?? []);
        });
      } else {
        throw Exception('Error ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to load: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decrementStock(String stockId, double newQty) async {
    final token = ref.read(authStateProvider)?.token ?? '';
    try {
      final res = await http.put(
        Uri.parse('${AppConfig.apiBase}/stocks/$stockId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'quantity': newQty}),
      );
      if (res.statusCode ~/ 100 != 2) {
        throw Exception('Error ${res.statusCode}');
      }
      _loadStocks();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Update failed: $e')),
      );
    }
  }

  void _showDecrementDialog(Map<String, dynamic> stock) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Decrease ${stock['name']}'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Decrease by',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final dec = double.tryParse(ctrl.text.trim()) ?? 0;
              final current = (stock['quantity'] ?? 0).toDouble();
              if (dec <= 0 || dec > current) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid amount')),
                );
                return;
              }
              Navigator.pop(context);
              _decrementStock(stock['_id'], current - dec);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manual = _stocks.where((s) => s['autoDecrement'] == false).toList();
    final auto = _stocks.where((s) => s['autoDecrement'] == true).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Stock'),
        backgroundColor: const Color(0xFFF57C00),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStocks,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadStocks,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (auto.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Auto-decrement Stocks",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  ...auto.map((s) => Card(
                    child: ListTile(
                      title: Text(s['name'] ?? ''),
                      subtitle:
                      Text('Qty: ${s['quantity']} | Auto linked'),
                    ),
                  )),
                  const SizedBox(height: 12),
                ],
              ),
            const Text("Manual Stocks",
                style: TextStyle(fontWeight: FontWeight.bold)),
            ...manual.map((s) => Card(
              child: ListTile(
                title: Text(s['name'] ?? ''),
                subtitle: Text('Qty: ${s['quantity']}'),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => _showDecrementDialog(s),
                ),
              ),
            )),
          ],
        ),
      ),
    );
  }
}
