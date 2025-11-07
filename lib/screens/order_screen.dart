import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models/order_model.dart';
import '../services/print_service.dart';
import '../state/auth.dart';
import '../config.dart';
import '../services/kot_printer.dart';

String _serverMsg(String action, int code, String body) {
  try {
    final d = jsonDecode(body);
    final msg = (d['error'] ?? d['message'] ?? body).toString();
    return '$action ($code): $msg';
  } catch (_) {
    return '$action ($code): $body';
  }
}

class LoadingOverlay {
  static OverlayEntry? _entry;

  static void show(BuildContext context) {
    if (_entry != null) return;
    final overlay = Overlay.of(context, rootOverlay: true) ?? Overlay.of(context);
    if (overlay == null) return;
    _entry = OverlayEntry(
      builder: (_) => Stack(
        children: const [
          ModalBarrier(dismissible: false, color: Color(0x55000000)),
          Center(child: CircularProgressIndicator()),
        ],
      ),
    );
    overlay.insert(_entry!);
  }

  static void hide() {
    try {
      _entry?.remove();
    } catch (_) {}
    _entry = null;
  }
}

// NOTE: items provider changed to a family so it can accept an optional categoryId.
final orderItemsCatalogProvider =
FutureProvider.family<List<Map<String, dynamic>>, String?>((ref, categoryId) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final url = (categoryId == null || categoryId.isEmpty)
      ? '${AppConfig.apiBase}/items'
      : '${AppConfig.apiBase}/items/by-category/$categoryId';
  final r = await http
      .get(
    Uri.parse(url),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  )
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) {
    throw Exception('Items load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['items'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

final orderTablesProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http
      .get(
    Uri.parse('${AppConfig.apiBase}/tables'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  )
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) {
    throw Exception('Tables load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['tables'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

/// NEW: categories provider
final orderCategoriesProvider =
FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http
      .get(
    Uri.parse('${AppConfig.apiBase}/categories'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  )
      .timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) {
    throw Exception('Categories load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['categories'] as List?) ?? [];
  return list.cast<Map<String, dynamic>>();
});

class OrderScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? order;
  final bool isEdit;
  final String? initialTableId;

  const OrderScreen({
    super.key,
    this.order,
    this.isEdit = false,
    this.initialTableId,
  });

  @override
  ConsumerState<OrderScreen> createState() => _OrderScreenState();
}

class _OrderLine {
  final String itemId;
  final String itemName;
  final String unitName;
  final double price;
  int quantity;
  _OrderLine({
    required this.itemId,
    required this.itemName,
    required this.unitName,
    required this.price,
    required this.quantity,
  });
}

class _OrderScreenState extends ConsumerState<OrderScreen> {
  String? _tableId;
  String? _areaName;

  final List<_OrderLine> _lines = [];

  final _paidCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _paymentStatus = 'Paid';
  String? _customerName;

  final _searchCtrl = TextEditingController();
  String _query = '';

  bool _submitting = false;

  Timer? _debounce;

  // NEW: selected category id
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (mounted) {
          setState(() => _query = _searchCtrl.text.trim().toLowerCase());
        }
      });
    });

    final o = widget.order;
    if (o != null && widget.isEdit) {
      final table = o['table'];
      if (table is Map && table['_id'] is String) {
        _tableId = table['_id'] as String;
      } else if (table is String) {
        _tableId = table;
      }
      final area = o['area'];
      if (area is Map && area['name'] is String) {
        _areaName = area['name'] as String;
      }

      final items =
          (o['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      for (final it in items) {
        final item = it['item'];
        final itemId = item is Map
            ? (item['_id']?.toString() ?? '')
            : it['item']?.toString() ?? '';
        final itemName =
        item is Map ? (item['name']?.toString() ?? '') : '';
        final unit = (it['unitName'] ?? '').toString();
        final price = (it['price'] as num?)?.toDouble() ?? 0.0;
        final qty = (it['quantity'] as num?)?.toInt() ?? 1;
        if (itemId.isNotEmpty && unit.isNotEmpty && price >= 0) {
          _lines.add(_OrderLine(
              itemId: itemId,
              itemName: itemName,
              unitName: unit,
              price: price,
              quantity: qty));
        }
      }

      _paymentStatus = (o['paymentStatus'] ?? 'Paid') as String;
      final paid = (o['paidAmount'] as num?)?.toDouble() ?? 0.0;
      _paidCtrl.text = paid.toStringAsFixed(2);
      _customerName = (o['customerName'] as String?);
      _noteCtrl.text = (o['note'] ?? '').toString();
    } else if (widget.initialTableId != null) {
      _tableId = widget.initialTableId;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _paidCtrl.dispose();
    _noteCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double get total => _lines.fold(0.0, (s, l) => s + l.price * l.quantity);
  double get paid => double.tryParse(_paidCtrl.text.trim()) ?? 0.0;
  double get due => (total - paid).clamp(0, double.infinity);

  Map<String, String> _headers() {
    final token = ref.read(authStateProvider)?.token ?? '';
    return {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
  }

  Future<_ChosenUnit?> _chooseUnitDialog({
    required String itemName,
    required List<Map<String, dynamic>> variants,
  }) async {
    if (variants.isEmpty) return null;

    int selectedIndex = 0;
    int qty = 1;

    return showDialog<_ChosenUnit>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          String unitLabel(int i) {
            final u = (variants[i]['unit'] ?? '').toString();
            final p = (variants[i]['price'] as num?)?.toDouble() ?? 0.0;
            return u.isEmpty
                ? 'Rs ${p.toStringAsFixed(2)}'
                : '$u — Rs ${p.toStringAsFixed(2)}';
          }

          return AlertDialog(
            title: Text('Add $itemName'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: selectedIndex,
                  items: List.generate(
                    variants.length,
                        (i) => DropdownMenuItem(
                      value: i,
                      child: Text(unitLabel(i)),
                    ),
                  ),
                  onChanged: (v) => setS(() => selectedIndex = v ?? 0),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => setS(() {
                        if (qty > 1) qty--;
                      }),
                      icon: const Icon(Icons.remove_circle),
                    ),
                    Text('$qty',
                        style:
                        const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => setS(() => qty++),
                      icon: const Icon(Icons.add_circle),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () {
                  final v = variants[selectedIndex];
                  final unit = (v['unit'] ?? '').toString();
                  final price =
                      (v['price'] as num?)?.toDouble() ?? 0.0;
                  Navigator.pop(
                      ctx,
                      _ChosenUnit(
                          unitName: unit, price: price, qty: qty));
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _addItemFromCatalog(Map<String, dynamic> item) async {
    final name = (item['name'] ?? '').toString();
    final id = (item['_id'] ?? '').toString();
    final variants =
        (item['variants'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    if (variants.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This item has no variants')));
      return;
    }

    final chosen =
    await _chooseUnitDialog(itemName: name, variants: variants);
    if (chosen == null) return;

    if (!mounted) return;
    setState(() {
      final idx = _lines.indexWhere((l) =>
      l.itemId == id && l.unitName == chosen.unitName);
      if (idx != -1) {
        _lines[idx].quantity += chosen.qty;
      } else {
        _lines.add(_OrderLine(
          itemId: id,
          itemName: name,
          unitName: chosen.unitName,
          price: chosen.price,
          quantity: chosen.qty,
        ));
      }
      if (_paymentStatus == 'Paid') {
        _paidCtrl.text = total.toStringAsFixed(2);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
        Text('Added $name (${chosen.unitName}) ×${chosen.qty}')));
  }

  Future<void> _withOverlay(Future<void> Function() body) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    LoadingOverlay.show(context);
    try {
      await body();
    } finally {
      LoadingOverlay.hide();
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createOrder() async {
    if (_tableId == null || _tableId!.isEmpty || _lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a table and add items.')));
      return;
    }

    FocusScope.of(context).unfocus();

    final items = _lines
        .map((l) => {
      'item': l.itemId,
      'unitName': l.unitName,
      'price': l.price,
      'quantity': l.quantity,
    })
        .toList();

    final payload = {
      'tableId': _tableId,
      'items': items,
      'paymentStatus': _paymentStatus,
      'customerName':
      _paymentStatus == 'Credit' ? _customerName : null,
      'note':
      _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    };

    await _withOverlay(() async {
      try {
        final r = await http
            .post(
          Uri.parse('${AppConfig.apiBase}/orders'),
          headers: _headers(),
          body: jsonEncode(payload),
        )
            .timeout(const Duration(seconds: 20));

        if (!mounted) return;
        if (r.statusCode ~/ 100 != 2) {
          final msg =
          _serverMsg('Create failed', r.statusCode, r.body);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(msg)));
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order placed')));

        // === KOT Printing ===
        final tables = await ref.read(orderTablesProvider.future);
        final selectedTable =
        tables.firstWhere((t) => t['_id'] == _tableId, orElse: () => {});

        final kotData = {
          'tableName': selectedTable['name'] ?? '-',
          'areaName': (selectedTable['area'] is Map)
              ? selectedTable['area']['name']
              : '-',
          'orderNumber': DateTime.now().millisecondsSinceEpoch.toString(),
          'type': 'Placed',
          'timestamp': DateTime.now().toString(),
          'items': _lines
              .map((l) => {
            'name': l.itemName,
            'unitName': l.unitName,
            'qty': l.quantity,
          }).toList(),
        };

        await KotPrinter.printKot(kotData);

        if (!mounted) return;
        Navigator.of(context).pop(true);
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
            Text('Request timed out. Check network/API.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Network error: $e')));
      }
    });
  }

  Future<void> _updateOrder() async {
    if (!widget.isEdit || widget.order == null) return;
    if (_tableId == null || _tableId!.isEmpty || _lines.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please select a table and add items.')));
      return;
    }

    FocusScope.of(context).unfocus();

    final id = (widget.order!['_id'] ?? '').toString();
    final items = _lines
        .map((l) => {
      'item': l.itemId,
      'unitName': l.unitName,
      'price': l.price,
      'quantity': l.quantity,
    })
        .toList();

    final payload = {
      'items': items,
      'paymentStatus': _paymentStatus,
      'customerName':
      _paymentStatus == 'Credit' ? _customerName : null,
      'note':
      _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    };

    await _withOverlay(() async {
      try {
        final r = await http
            .put(
          Uri.parse('${AppConfig.apiBase}/orders/$id'),
          headers: _headers(),
          body: jsonEncode(payload),
        )
            .timeout(const Duration(seconds: 20));

        if (!mounted) return;
        if (r.statusCode ~/ 100 != 2) {
          final msg =
          _serverMsg('Update failed', r.statusCode, r.body);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Order updated')));

        // === KOT Printing ===
        final tables = await ref.read(orderTablesProvider.future);
        final selectedTable =
        tables.firstWhere((t) => t['_id'] == _tableId, orElse: () => {});

        final kotData = {
          'tableName': selectedTable['name'] ?? '-',
          'areaName': (selectedTable['area'] is Map)
              ? selectedTable['area']['name']
              : '-',
          'orderNumber': (widget.order?['_id'] ?? 'N/A').toString(),
          'type': 'Updated',
          'timestamp': DateTime.now().toString(),
          'items': _lines
              .map((l) => {
            'name': l.itemName,
            'unitName': l.unitName,
            'qty': l.quantity,
          }).toList(),
        };

        await KotPrinter.printKot(kotData);

        if (!mounted) return;
        Navigator.of(context).pop(true);
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
            Text('Request timed out. Check network/API.')));
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Network error: $e')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // use categories provider and items provider (family) with selected category
    final categoriesAsync = ref.watch(orderCategoriesProvider);
    final itemsAsync = ref.watch(orderItemsCatalogProvider(_selectedCategoryId));
    final tablesAsync = ref.watch(orderTablesProvider);

    final themeColor = const Color(0xFFF57C00);
    final accentColor = const Color(0xFFFF7043);

    return Scaffold(
      backgroundColor: const Color(0xFFFDF6EC),
      appBar: AppBar(
        title: Text(widget.isEdit ? 'Edit Order' : 'New Order',
            style: const TextStyle(color: Colors.white)),
        centerTitle: true,
        backgroundColor: themeColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionHeader(
                title: 'Table Selection',
                icon: Icons.table_restaurant,
                color: themeColor),
            const SizedBox(height: 8),

            tablesAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text('Failed to load tables: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (tables) {
                if (tables.isEmpty) {
                  return const Text(
                    'No tables found. Create a table first.',
                    style: TextStyle(color: Colors.red),
                  );
                }

                final exists =
                    _tableId != null && tables.any((t) => t['_id'] == _tableId);
                if (!exists) {
                  _tableId = tables.first['_id'] as String;
                }

                final tSel = tables.firstWhere(
                      (t) => t['_id'] == _tableId,
                  orElse: () => tables.first,
                );
                final a = tSel['area'];
                _areaName =
                (a is Map && a['name'] is String) ? a['name'] as String : null;

                return DropdownButtonFormField<String>(
                  value: _tableId,
                  decoration: InputDecoration(
                    labelText: 'Table',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (v) => setState(() => _tableId = v),
                  items: tables
                      .map((t) => DropdownMenuItem(
                    value: t['_id'] as String,
                    child: Text(
                      '${t['name']} — ${(t['area'] is Map) ? t['area']['name'] : ''}',
                    ),
                  ))
                      .toList(),
                );
              },
            ),

            const SizedBox(height: 20),

            _SectionHeader(
                title: 'Add Items',
                icon: Icons.add_shopping_cart,
                color: themeColor),
            const SizedBox(height: 8),

            // SEARCH + CATEGORY ROW (category dropdown added next to search)
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Search item...',
                      filled: true,
                      fillColor: Colors.white,
                      border:
                      OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: categoriesAsync.when(
                    loading: () => Container(
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    error: (e, _) => Text('Category error: $e',
                        style: const TextStyle(color: Colors.red)),
                    data: (cats) {
                      // include All option (null)
                      final items = <DropdownMenuItem<String?>>[
                        const DropdownMenuItem(value: null, child: Text('All')),
                        ...cats.map((c) {
                          return DropdownMenuItem(
                            value: c['_id'] as String,
                            child: Text(c['name'] ?? ''),
                          );
                        }).toList(),
                      ];

                      return DropdownButtonFormField<String?>(
                        value: _selectedCategoryId,
                        decoration: InputDecoration(
                          labelText: 'Category',
                          border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        items: items,
                        onChanged: (v) => setState(() => _selectedCategoryId = v),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            itemsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, _) => Text('Error loading items: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (items) {
                final filtered = _query.isEmpty
                    ? items
                    : items
                    .where((it) =>
                    (it['name'] ?? '')
                        .toString()
                        .toLowerCase()
                        .contains(_query))
                    .toList();

                if (filtered.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No items found for your search.',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: filtered.map((it) {
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                      ),
                      onPressed: () => _addItemFromCatalog(it),
                      child: Text(it['name'] ?? 'Item'),
                    );
                  }).toList(),
                );
              },
            ),

            const SizedBox(height: 20),

            if (_lines.isNotEmpty) ...[
              _SectionHeader(
                  title: 'Selected Items',
                  icon: Icons.list_alt,
                  color: themeColor),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.white,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _lines.length,
                  itemBuilder: (_, i) {
                    final l = _lines[i];
                    return ListTile(
                      contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      title: Text('${l.itemName} (${l.unitName})',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          'Rs ${l.price.toStringAsFixed(2)} × ${l.quantity}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                if (l.quantity > 1) {
                                  l.quantity--;
                                } else {
                                  _lines.removeAt(i);
                                }
                                if (_paymentStatus == 'Paid') {
                                  _paidCtrl.text = total.toStringAsFixed(2);
                                }
                              });
                            },
                            icon: const Icon(Icons.remove_circle,
                                color: Colors.red),
                          ),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                l.quantity++;
                                if (_paymentStatus == 'Paid') {
                                  _paidCtrl.text = total.toStringAsFixed(2);
                                }
                              });
                            },
                            icon: const Icon(Icons.add_circle,
                                color: Colors.green),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 20),

            _SectionHeader(
                title: 'Payment',
                icon: Icons.payment,
                color: themeColor),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: _paymentStatus,
              decoration: InputDecoration(
                labelText: 'Payment Status',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
              items: const [
                DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                DropdownMenuItem(value: 'Credit', child: Text('Credit')),
              ],
              onChanged: (v) => setState(() {
                _paymentStatus = v ?? 'Paid';
                if (_paymentStatus == 'Paid') {
                  _paidCtrl.text = total.toStringAsFixed(2);
                } else {
                  _paidCtrl.clear();
                }
              }),
            ),
            const SizedBox(height: 12),

            if (_paymentStatus == 'Credit')
              TextField(
                decoration: InputDecoration(
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (v) => _customerName = v.trim(),
              ),
            if (_paymentStatus == 'Credit')
              const SizedBox(height: 12),

            TextField(
              controller: _paidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
              decoration: InputDecoration(
                labelText: 'Paid Amount',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (_) => setState(() {}),
            ),

            const SizedBox(height: 12),

            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: 'Note',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 20),

            Container(
              padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Total: Rs ${total.toStringAsFixed(2)}',
                      style:
                      const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Paid: Rs ${paid.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text('Due: Rs ${due.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 14,
                          color: due > 0 ? Colors.red : Colors.green)),
                ],
              ),
            ),


            ElevatedButton.icon(
              icon: const Icon(Icons.print),
              label: const Text('Print Receipt'),
              onPressed: () {
                if (_lines.isEmpty) return;

                // 1️⃣ Calculate subtotal
                final subtotal = total;

                // 2️⃣ Calculate VAT, discount, final amount
                final discountAmount = 0.0; // no discount applied
                final vatAmount = subtotal * 0.13; // 13% VAT
                final finalAmount = subtotal - discountAmount + vatAmount;

                // 3️⃣ Build OrderModel with proper item IDs
                final order = OrderModel(
                  id: DateTime.now().millisecondsSinceEpoch.toString(), // order id
                  tableName: _tableId ?? 'Unknown',
                  area: _areaName ?? '',
                  items: _lines.map((l) => OrderItemModel(
                    id: DateTime.now().millisecondsSinceEpoch.toString() + l.itemName, // unique id
                    name: l.itemName,
                    unitName: l.unitName,
                    price: l.price,
                    quantity: l.quantity,
                  )).toList(),
                  paymentStatus: _paymentStatus,
                  paidAmount: paid,
                  customerName: _customerName,
                  note: _noteCtrl.text.trim(),
                  createdAt: DateTime.now(),
                  restaurantName: 'Deskgoo Cafe',
                  vatPercent: 13.0,
                  vatAmount: vatAmount,
                  discountAmount: discountAmount,
                  finalAmount: finalAmount,
                );

                // 4️⃣ Print receipt safely
                PrintService.printOrderReceipt(
                  order,
                  context: context,
                  vatAmount: vatAmount,
                  discountAmount: discountAmount,
                  finalAmount: finalAmount,
                );
              },
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: accentColor,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _submitting
                        ? null
                        : widget.isEdit
                        ? _updateOrder
                        : _createOrder,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: Text(
                      widget.isEdit ? 'Update Order' : 'Place Order',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;

  const _SectionHeader(
      {required this.title, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16, color: color)),
      ],
    );
  }
}

class _ChosenUnit {
  final String unitName;
  final double price;
  final int qty;

  _ChosenUnit({
    required this.unitName,
    required this.price,
    required this.qty,
  });
}
