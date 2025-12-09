import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../state/auth.dart';

final itemsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/items'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) throw Exception('Failed to load items');
  return (jsonDecode(r.body)['items'] as List).cast<Map<String, dynamic>>();
});

final itemStockProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/item-stock'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) throw Exception('Failed to load item stock');
  return (jsonDecode(r.body)['stocks'] as List).cast<Map<String, dynamic>>();
});

class ItemStockScreen extends ConsumerStatefulWidget {
  const ItemStockScreen({super.key});

  @override
  ConsumerState<ItemStockScreen> createState() => _ItemStockScreenState();
}

class _ItemStockScreenState extends ConsumerState<ItemStockScreen> {
  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(itemStockProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Item Stock'),
        backgroundColor: const Color(0xFFFF7043),
      ),
      body: stockAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (stocks) {
          if (stocks.isEmpty) return const Center(child: Text('No stock added yet'));
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(itemStockProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: stocks.length,
              itemBuilder: (_, i) {
                final s = stocks[i];
                final item = s['item'] ?? {};
                final name = item['name'] ?? '';
                final variants = (item['variants'] as List? ?? []);
                final quantity = s['quantity']?.toString() ?? '0';

                return Card(
                  child: ListTile(
                    title: Text(name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Stock: $quantity'),
                        if (variants.isNotEmpty)
                          Text(
                            'Variants: ${variants.map((v) => "${v['unit']}(${v['stockQuantity'] ?? 0})").join(', ')}',
                            style: const TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showUpdateQuantityDialog(s),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteStock(s['_id'], name),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddStockDialog,
        backgroundColor: const Color(0xFFFF7043),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _deleteStock(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Stock'),
        content: Text('Are you sure you want to delete $name stock?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final token = ref.read(authStateProvider)?.token ?? '';
    final r = await http.delete(
      Uri.parse('${AppConfig.apiBase}/item-stock/$id'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );

    if (r.statusCode ~/ 100 == 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock deleted')));
      ref.refresh(itemStockProvider);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: ${r.body}')));
    }
  }
  Future<void> _showAddStockDialog() async {
    final items = await ref.read(itemsProvider.future);
    Map<String, dynamic>? selectedItem;
    Map<String, dynamic>? selectedVariant;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          final qtyCtrl = TextEditingController();

          return AlertDialog(
            title: const Text('Add Item Stock'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedItem,
                    hint: const Text('Select Item'),
                    items: items.map<DropdownMenuItem<Map<String, dynamic>>>((it) {
                      return DropdownMenuItem<Map<String, dynamic>>(
                        value: it,
                        child: Text(it['name'].toString()),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedItem = val;
                        selectedVariant = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (selectedItem != null)
                    DropdownButtonFormField<Map<String, dynamic>>(
                      value: selectedVariant,
                      hint: const Text('Select Variant'),
                      items: (selectedItem!['variants'] as List)
                          .cast<Map<String, dynamic>>()
                          .map((v) {
                        final factor = (v['conversionFactor'] ?? 1).toDouble();
                        return DropdownMenuItem<Map<String, dynamic>>(
                          value: v,
                          child: Text('${v['unit']} ${factor != 1 ? '(x$factor)' : ''}'),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => selectedVariant = val),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: qtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () {
                qtyCtrl.dispose();
                Navigator.pop(context);
              }, child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (selectedItem == null || selectedVariant == null || qtyCtrl.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select item, variant, and quantity')));
                    return;
                  }

                  final quantity = double.tryParse(qtyCtrl.text);
                  if (quantity == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invalid quantity')));
                    return;
                  }

                  final factor = (selectedVariant!['conversionFactor'] ?? 1).toDouble();
                  final finalQty = quantity * factor;

                  final token = ref.read(authStateProvider)?.token ?? '';
                  final r = await http.post(
                    Uri.parse('${AppConfig.apiBase}/item-stock'),
                    headers: {
                      'Authorization': 'Bearer $token',
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                    },
                    body: jsonEncode({
                      'itemId': selectedItem!['_id'],
                      'variantUnit': selectedVariant!['unit'],
                      'quantity': finalQty,
                    }),
                  );

                  if (r.statusCode ~/ 100 != 2) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: ${r.body}')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Stock added')));
                    ref.refresh(itemStockProvider);
                    qtyCtrl.dispose(); // dispose after done
                    Navigator.pop(context);
                  }
                },
                child: const Text('Add Stock'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
              ),
            ],
          );
        },
      ),
    );
  }
  Future<void> _showUpdateQuantityDialog(Map<String, dynamic> stock) async {
    Map<String, dynamic>? selectedVariant;
    final qtyCtrl = TextEditingController();

    final variants = (stock['item']?['variants'] as List? ?? []).cast<Map<String, dynamic>>();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Update Quantity for ${stock['item']?['name'] ?? 'Item'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  value: selectedVariant,
                  hint: const Text('Select Variant'),
                  items: variants.map((v) {
                    final factor = (v['conversionFactor'] ?? 1).toDouble();
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: v,
                      child: Text('${v['unit'] ?? ''}${factor != 1 ? ' (x$factor)' : ''}'),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (!mounted) return;
                    setState(() => selectedVariant = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Quantity to add/decrement',
                      border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (selectedVariant == null || qtyCtrl.text.isEmpty) return;

                final inputQty = double.tryParse(qtyCtrl.text);
                if (inputQty == null) return;

                final factor = (selectedVariant!['conversionFactor'] ?? 1).toDouble();
                final finalQty = inputQty * factor;

                final token = ref.read(authStateProvider)?.token ?? '';
                final r = await http.put(
                  Uri.parse('${AppConfig.apiBase}/item-stock/${stock['_id']}'),
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                    'Accept': 'application/json'
                  },
                  body: jsonEncode({'quantity': finalQty}),
                );

                if (!mounted) return;

                if (r.statusCode ~/ 100 == 2) {
                  Navigator.pop(context);
                  ref.refresh(itemStockProvider);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: ${r.body}')));
                }
              },
              child: const Text('Update'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF7043)),
            ),
          ],
        ),
      ),
    );
  }
}
