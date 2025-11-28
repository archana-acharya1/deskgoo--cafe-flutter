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
          if (stocks.isEmpty) {
            return const Center(child: Text('No stock added yet'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(itemStockProvider),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: stocks.length,
              itemBuilder: (_, i) {
                final s = stocks[i];
                final name = s['item']?['name'] ?? '';
                final variant = s['variantUnit'] ?? '';
                final quantity = s['quantity']?.toString() ?? '0';
                return Card(
                  child: ListTile(
                    title: Text('$name ($variant)'),
                    subtitle: Text(
                        'Quantity: $quantity${_getConversionFactorText(s)}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showAddQuantityDialog(s),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('Delete Stock'),
                                content: Text(
                                    'Are you sure you want to delete $name ($variant) stock?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                    ),
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm != true) return;

                            final token =
                                ref.read(authStateProvider)?.token ?? '';
                            final r = await http.delete(
                              Uri.parse(
                                  '${AppConfig.apiBase}/item-stock/${s['_id']}'),
                              headers: {
                                'Authorization': 'Bearer $token',
                                'Accept': 'application/json',
                              },
                            );

                            if (r.statusCode ~/ 100 == 2) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Stock deleted')),
                              );
                              ref.refresh(itemStockProvider);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Failed to delete: ${r.body}')),
                              );
                            }
                          },
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

  // Helper to display conversion factor
  String _getConversionFactorText(Map<String, dynamic> stock) {
    final variants = stock['item']?['variants'] as List? ?? [];
    final variant = variants.firstWhere(
            (v) => v['unit'] == stock['variantUnit'],
        orElse: () => null);
    if (variant == null) return '';
    final factor = variant['conversionFactor'];
    if (factor != null && factor != 1) return ' (x$factor)';
    return '';
  }

  Future<void> _showAddStockDialog() async {
    final items = await ref.read(itemsProvider.future); // get list of items
    Map<String, dynamic>? selectedItem;
    String? selectedVariant;
    final qtyCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Item Stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selectedItem,
                hint: const Text('Select Item'),
                items: items.map((it) {
                  return DropdownMenuItem<Map<String, dynamic>>(
                    value: it,
                    child: Text(it['name']),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    selectedItem = val;
                    selectedVariant = null; // reset variant
                  });
                },
              ),
              const SizedBox(height: 12),
              if (selectedItem != null)
                DropdownButtonFormField<String>(
                  value: selectedVariant,
                  hint: const Text('Select Variant'),
                  items: (selectedItem!['variants'] as List)
                      .map<DropdownMenuItem<String>>((v) {
                    final factor = v['conversionFactor'] ?? 1;
                    return DropdownMenuItem<String>(
                      value: v['unit'],
                      child:
                      Text(v['unit'] + (factor != 1 ? ' (x$factor)' : '')),
                    );
                  }).toList(),
                  onChanged: (val) {
                    setState(() => selectedVariant = val);
                  },
                ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedItem == null ||
                    selectedVariant == null ||
                    qtyCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                        Text('Please select item, variant and quantity')),
                  );
                  return;
                }

                final quantity = double.tryParse(qtyCtrl.text);
                if (quantity == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invalid quantity')),
                  );
                  return;
                }

                final token = ref.read(authStateProvider)?.token ?? '';
                final uri = Uri.parse('${AppConfig.apiBase}/item-stock');
                final r = await http.post(
                  uri,
                  headers: {
                    'Authorization': 'Bearer $token',
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                  },
                  body: jsonEncode({
                    'itemId': selectedItem!['_id'],
                    'variantUnit': selectedVariant,
                    'quantity': quantity,
                  }),
                );

                if (r.statusCode ~/ 100 != 2) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: ${r.body}')),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Stock updated')),
                  );
                  ref.refresh(itemStockProvider); // refresh list
                  Navigator.pop(context);
                }
              },
              child: const Text('Add Stock'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF7043),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddQuantityDialog(Map<String, dynamic> stock) async {
    final qtyCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Add Quantity to ${stock['item']?['name']}'),
        content: TextField(
          controller: qtyCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantity to add'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final qty = double.tryParse(qtyCtrl.text);
              if (qty == null) return;
              final token = ref.read(authStateProvider)?.token ?? '';
              final r = await http.put(
                Uri.parse('${AppConfig.apiBase}/item-stock/${stock['_id']}'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Accept': 'application/json',
                  'Content-Type': 'application/json'
                },
                body: jsonEncode({'quantity': qty}),
              );
              if (r.statusCode ~/ 100 == 2) {
                Navigator.pop(context);
                ref.refresh(itemStockProvider);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${r.body}')),
                );
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
