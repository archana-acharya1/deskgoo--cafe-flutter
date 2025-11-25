import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:nepali_date_picker/nepali_date_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order_model.dart';
import '../services/print_service.dart';
import '../state/auth.dart';
import 'order_screen.dart';
import '../config.dart';
import '../providers/socket_provider.dart';


String _serverMsg(String action, int code, String body) {
  try {
    final d = jsonDecode(body);
    final msg = (d['error'] ?? d['message'] ?? body).toString();
    return '$action ($code): $msg';
  } catch (_) {
    return '$action ($code): $body';
  }
}

final ordersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final token = ref.read(authStateProvider)?.token ?? '';
  final r = await http.get(
    Uri.parse('${AppConfig.apiBase}/orders'),
    headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
  );
  if (r.statusCode != 200) {
    throw Exception('Orders load failed: ${r.statusCode} ${r.body}');
  }
  final list = (jsonDecode(r.body)['orders'] as List?) ?? [];

  list.sort((a, b) {
    final ad = DateTime.tryParse((a as Map)['createdAt']?.toString() ?? '');
    final bd = DateTime.tryParse((b as Map)['createdAt']?.toString() ?? '');
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return bd.compareTo(ad);
  });

  return list.cast<Map<String, dynamic>>();
});

class OrdersListScreen extends ConsumerStatefulWidget {
  const OrdersListScreen({super.key});

  @override
  ConsumerState<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends ConsumerState<OrdersListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _selectMode = false;
  final Set<String> _selectedIds = <String>{};
  late List<Map<String, dynamic>> _currentFilteredOrders;
  late List<String> _currentFilteredIds;

  // Nepali date filter fields
  NepaliDateTime? _fromDate;
  NepaliDateTime? _toDate;

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

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });

    final socket = ref.read(socketProvider);
    socket.instance.on('order_created', (_) => ref.refresh(ordersProvider));
    socket.instance.on('order_updated', (_) => ref.refresh(ordersProvider));
    socket.instance.on('order_deleted', (_) => ref.refresh(ordersProvider));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    final socket = ref.read(socketProvider);
    socket.instance.off('order_created');
    socket.instance.off('order_updated');
    socket.instance.off('order_deleted');
    super.dispose();
  }

  Future<void> _deleteOrder(String id) async {
    final r = await http.delete(
      Uri.parse('${AppConfig.apiBase}/orders/$id'),
      headers: _headers(),
    );
    if (r.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Delete failed', r.statusCode, r.body));
    }
  }

  Future<void> _markPaid(Map<String, dynamic> order) async {
    final id = (order['_id'] ?? '').toString();
    if (id.isEmpty) return;

    final r = await http.put(
      Uri.parse('${AppConfig.apiBase}/orders/$id'),
      headers: _headers(),
      body: jsonEncode({
        "paymentStatus": "Paid",
        "customerName": null,
      }),
    );
    if (r.statusCode ~/ 100 != 2) {
      throw Exception(_serverMsg('Mark Paid failed', r.statusCode, r.body));
    }
    if (mounted) ref.refresh(ordersProvider);
  }

  Future<Map<String, dynamic>?> _selectPaymentMethodDialog(
      Map<String, dynamic> order,
      ) async {
    String? method = 'cash';
    String? othersCombo;
    final TextEditingController splitAController = TextEditingController();
    final TextEditingController splitBController = TextEditingController();

    final double orderAmount = (order['finalAmount'] is num)
        ? (order['finalAmount'] as num).toDouble()
        : ((order['totalAmount'] is num)
        ? (order['totalAmount'] as num).toDouble()
        : 0.0);

    void showErr(String msg) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          Widget othersSplitWidget() {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Choose split type:',
                        style: TextStyle(fontWeight: FontWeight.w600))),
                RadioListTile<String>(
                  title: const Text('Cash + Card'),
                  value: 'cash-card',
                  groupValue: othersCombo,
                  onChanged: (v) => setState(() => othersCombo = v),
                ),
                RadioListTile<String>(
                  title: const Text('Cash + Online'),
                  value: 'cash-online',
                  groupValue: othersCombo,
                  onChanged: (v) => setState(() => othersCombo = v),
                ),
                RadioListTile<String>(
                  title: const Text('Card + Online'),
                  value: 'card-online',
                  groupValue: othersCombo,
                  onChanged: (v) => setState(() => othersCombo = v),
                ),
                const SizedBox(height: 8),
                if (othersCombo != null)
                  Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: splitAController,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: InputDecoration(
                                labelText: othersCombo == 'cash-card'
                                    ? 'Cash amount'
                                    : othersCombo == 'cash-online'
                                    ? 'Cash amount'
                                    : 'Card amount',
                                hintText:
                                orderAmount > 0 ? orderAmount.toStringAsFixed(2) : '',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: splitBController,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration: InputDecoration(
                                labelText: othersCombo == 'cash-card'
                                    ? 'Card amount'
                                    : othersCombo == 'cash-online'
                                    ? 'Online amount'
                                    : 'Online amount',
                                hintText:
                                orderAmount > 0 ? orderAmount.toStringAsFixed(2) : '',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Total should equal order amount: Rs ${orderAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Select Payment Method'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<String>(
                    title: const Text('Cash'),
                    value: 'cash',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v),
                  ),
                  RadioListTile<String>(
                    title: const Text('Card'),
                    value: 'card',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v),
                  ),
                  RadioListTile<String>(
                    title: const Text('Online'),
                    value: 'online',
                    groupValue: method,
                    onChanged: (v) => setState(() => method = v),
                  ),
                  RadioListTile<String>(
                    title: const Text('Others (Split Payments)'),
                    value: 'others',
                    groupValue: method,
                    onChanged: (v) => setState(() {
                      method = v;
                      othersCombo = othersCombo ?? 'cash-card';
                    }),
                  ),
                  if (method == 'others') othersSplitWidget(),
                  const SizedBox(height: 6),
                  // optional: allow marking as Credit
                  CheckboxListTile(
                    value: method == 'credit',
                    onChanged: (val) {
                      if (val == true) {
                        setState(() {
                          method = 'credit';
                        });
                      } else {
                        setState(() {
                          method = 'cash';
                        });
                      }
                    },
                    title:
                    const Text('Mark as Credit (customer will pay later)'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx, null);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (method == null) {
                    showErr('Select a payment method');
                    return;
                  }

                  final split = {'cash': 0.0, 'card': 0.0, 'online': 0.0};
                  String? othersField;
                  if (method == 'others') {
                    if (othersCombo == null) {
                      showErr('Select a split type for Others');
                      return;
                    }
                    final a =
                        double.tryParse(splitAController.text.trim()) ?? 0.0;
                    final b =
                        double.tryParse(splitBController.text.trim()) ?? 0.0;
                    if (a <= 0 && b <= 0) {
                      showErr('Enter amounts for both split fields');
                      return;
                    }
                    final total = a + b;
                    if ((orderAmount > 0) &&
                        (total - orderAmount).abs() > 0.01) {
                      showErr(
                          'Split total (${total.toStringAsFixed(2)}) must equal order amount (${orderAmount.toStringAsFixed(2)})');
                      return;
                    }
                    if (othersCombo == 'cash-card') {
                      split['cash'] = a;
                      split['card'] = b;
                    } else if (othersCombo == 'cash-online') {
                      split['cash'] = a;
                      split['online'] = b;
                    } else if (othersCombo == 'card-online') {
                      split['card'] = a;
                      split['online'] = b;
                    }
                    othersField = othersCombo;
                  } else if (method == 'credit') {
                  } else {
                    final amt = orderAmount;
                    if (method == 'cash') split['cash'] = amt;
                    if (method == 'card') split['card'] = amt;
                    if (method == 'online') split['online'] = amt;
                  }

                  final payload = {
                    'method': method,
                    'split': {
                      'cash': (split['cash'] ?? 0.0).toDouble(),
                      'card': (split['card'] ?? 0.0).toDouble(),
                      'online': (split['online'] ?? 0.0).toDouble(),
                    },
                    'others': othersField,
                  };

                  Navigator.pop(ctx, payload);
                },
                child: const Text('Continue'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _checkoutOrder(Map<String, dynamic> order) async {
    final id = (order['_id'] ?? '').toString();
    if (id.isEmpty) return;

    final paymentMethod = await _selectPaymentMethodDialog(order);
    if (paymentMethod == null) return;

    String paymentStatus = 'Paid';
    if ((paymentMethod['method']?.toString() ?? '') == 'credit') {
      paymentStatus = 'Credit';
    }

    try {
      final r = await http.patch(
        Uri.parse('${AppConfig.apiBase}/orders/$id/checkout'),
        headers: _headers(),
        body: jsonEncode({
          "force": true,
          "paymentMethod": paymentMethod,
          "paymentStatus": paymentStatus,
        }),
      );
      if (r.statusCode ~/ 100 != 2) {
        throw Exception(_serverMsg('Checkout failed', r.statusCode, r.body));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Checked out via ${paymentMethod['method']}')),
      );
      ref.refresh(ordersProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _cancelOrder(String orderId) async {
    try {
      final r = await http.patch(
        Uri.parse('${AppConfig.apiBase}/orders/$orderId/cancel'),
        headers: _headers(),
        body: jsonEncode({
          "cancelReason": "Cancelled from app",
        }),
      );

      if (r.statusCode ~/ 100 != 2) {
        throw Exception(
          'Cancel failed (${r.statusCode}): ${r.body}',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order Cancelled')),
        );
        ref.refresh(ordersProvider);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }



  Future<void> bulkCheckoutSelected({required bool force}) async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No orders selected')),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.apiBase}/orders/checkout-bulk'),
        headers: _headers(),
        body: jsonEncode({
          "ids": _selectedIds.toList(),
          "force": force,
        }),
      );

      if (response.statusCode ~/ 100 != 2) {
        String msg;
        try {
          final data = jsonDecode(response.body);
          msg = (data['error'] ?? data['message'] ?? response.body).toString();
        } catch (_) {
          msg = response.body;
        }
        throw Exception('Bulk checkout failed: $msg');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final ok = (data['ok'] as num?)?.toInt() ?? 0;
      final failed = (data['failed'] as num?)?.toInt() ?? 0;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk checkout: $ok success • $failed failed')),
      );

      ref.refresh(ordersProvider);

      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Bulk checkout error: $e')),
      );
    }
  }

  Future<void> _bulkMarkPaidSelected() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No orders selected')));
      return;
    }

    try {
      for (final id in _selectedIds) {
        final order = _currentFilteredOrders.firstWhere((o) => o['_id'] == id);
        await _markPaid(order);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Selected orders marked as paid')));
      ref.refresh(ordersProvider);
      setState(() {
        _selectMode = false;
        _selectedIds.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Bulk mark paid error: $e')));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Due':
        return const Color(0xFFF57C00);
      case 'Credit':
        return const Color(0xFF6D4C41);
      default:
        return const Color(0xFF2E7D32);
    }
  }

  void _enterSelectMode(String id) {
    setState(() {
      _selectMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _selectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  // -------------------- INVOICE HELPERS --------------------

  /// Fetch saved receipt by orderId; returns parsed JSON or null.
  Future<Map<String, dynamic>?> _fetchReceiptJson(String orderId) async {
    final token = ref.read(authStateProvider)?.token ?? '';
    if (token.isEmpty) return null;
    final res = await http.get(
      Uri.parse('${AppConfig.apiBase}/receipts/$orderId'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (res.statusCode != 200) return null;
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Fetch restaurant settings (same endpoint used elsewhere)
  Future<Map<String, dynamic>?> _fetchRestaurantSettings() async {
    final token = ref.read(authStateProvider)?.token ?? '';
    if (token.isEmpty) return null;
    final res = await http.get(
      Uri.parse('${AppConfig.apiBase}/restaurant-settings'),
      headers: {'Authorization': 'Bearer $token', 'Accept': 'application/json'},
    );
    if (res.statusCode != 200) return null;
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      // many implementations return { settings: { ... } } like other files
      if (body.containsKey('settings')) return body['settings'] as Map<String, dynamic>;
      return body;
    } catch (_) {
      return null;
    }
  }

  /// Build invoice PDF bytes (A4) from order JSON + receipt JSON + restaurant settings.
  Future<Uint8List> _buildInvoicePdfBytes(
      Map<String, dynamic> orderJson,
      Map<String, dynamic> receiptJson,
      Map<String, dynamic>? settings,
      ) async {
    final doc = pw.Document();
    final pw.ThemeData base = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.openSansRegular(),
      bold: await PdfGoogleFonts.openSansBold(),
    );

    final restaurantName = settings?['restaurantName']?.toString() ?? receiptJson['restaurantName']?.toString() ?? 'Restaurant';
    final vatNo = settings?['vatNo']?.toString() ?? '';
    final panNo = settings?['panNo']?.toString() ?? '';
    final address = settings?['address']?.toString() ?? '';
    final phone = settings?['phone']?.toString() ?? '';
    final email = settings?['email']?.toString() ?? '';
    final footerNote = settings?['footerNote']?.toString() ?? 'Thank you for dining with us!';

    // invoice number: prefer order serial (orderId) else fallback to order _id
    final invoiceNumber = (orderJson['orderId'] ?? orderJson['orderNumber'] ?? orderJson['_id'] ?? '').toString();

    // payment method
    String paymentMethod = '';
    try {
      final pm = orderJson['paymentMethod'];
      if (pm is Map) {
        paymentMethod = (pm['method']?.toString() ?? pm['type']?.toString() ?? '').toString();
      } else if (pm is String) {
        paymentMethod = pm;
      } else {
        paymentMethod = (receiptJson['paymentMethod']?.toString() ?? orderJson['paymentMethod']?.toString() ?? '');
      }
    } catch (_) {
      paymentMethod = '';
    }

    // times
    final receiptPrintedAt = receiptJson['printedAt'] != null
        ? DateTime.tryParse(receiptJson['printedAt'].toString())
        : (receiptJson['createdAt'] != null ? DateTime.tryParse(receiptJson['createdAt'].toString()) : null);
    final receiptPrintedStr = receiptPrintedAt != null ? receiptPrintedAt.toLocal().toString() : '';
    final invoiceGeneratedAt = DateTime.now().toLocal().toString();

    // Items: from receiptJson items preferred
    final itemsRaw = (receiptJson['items'] as List?) ?? (orderJson['items'] as List?) ?? [];
    final items = itemsRaw.map((m) {
      final map = m as Map<String, dynamic>;
      final name = (map['name'] ?? '').toString();
      final unit = (map['unitName'] ?? map['unit'] ?? '').toString();
      final price = (map['price'] is num) ? (map['price'] as num).toDouble() : 0.0;
      final qty = (map['quantity'] is num) ? (map['quantity'] as num).toDouble() : ((map['qty'] is num) ? (map['qty'] as num).toDouble() : 0.0);
      final total = price * qty;
      return {'name': name, 'unit': unit, 'price': price, 'qty': qty, 'total': total};
    }).toList();

    final subtotal = (receiptJson['subtotal'] is num) ? (receiptJson['subtotal'] as num).toDouble() : items.fold(0.0, (s, it) => s + (it['total'] as double));
    final discountPercent = (receiptJson['discountPercent'] is num) ? (receiptJson['discountPercent'] as num).toDouble() : 0.0;
    final discountAmount = (receiptJson['discountAmount'] is num) ? (receiptJson['discountAmount'] as num).toDouble() : (discountPercent > 0 ? subtotal * discountPercent / 100 : 0.0);
    final subtotalAfterDiscount = subtotal - discountAmount;
    final vatPercent = (receiptJson['vatPercent'] is num) ? (receiptJson['vatPercent'] as num).toDouble() : 0.0;
    final vatAmount = (receiptJson['vatAmount'] is num) ? (receiptJson['vatAmount'] as num).toDouble() : (vatPercent > 0 ? subtotalAfterDiscount * vatPercent / 100 : 0.0);
    final finalAmount = (receiptJson['finalAmount'] is num) ? (receiptJson['finalAmount'] as num).toDouble() : subtotalAfterDiscount + vatAmount;

    // Logo: try fetch bytes if logoUrl present
    pw.MemoryImage? logoImage;
    final logoUrl = settings?['logoUrl']?.toString();
    if (logoUrl != null && logoUrl.isNotEmpty) {
      try {
        // attempt to fetch logo bytes (hostBase used by your app elsewhere)
        final logoUri = logoUrl.startsWith('http') ? Uri.parse(logoUrl) : Uri.parse('${AppConfig.hostBase}/${logoUrl}');
        final logoRes = await http.get(logoUri);
        if (logoRes.statusCode == 200) {
          logoImage = pw.MemoryImage(logoRes.bodyBytes);
        }
      } catch (_) {
        logoImage = null;
      }
    }

    // Build PDF page
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: base,
        build: (pw.Context ctx) {
          return [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(restaurantName, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                      if (address.isNotEmpty) pw.Text(address, style: pw.TextStyle(fontSize: 10)),
                      if (phone.isNotEmpty) pw.Text('Phone: $phone', style: pw.TextStyle(fontSize: 10)),
                      if (email.isNotEmpty) pw.Text('Email: $email', style: pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(height: 6),
                      if (vatNo.isNotEmpty) pw.Text('VAT: $vatNo', style: pw.TextStyle(fontSize: 10)),
                      if (panNo.isNotEmpty) pw.Text('PAN: $panNo', style: pw.TextStyle(fontSize: 10)),
                    ]),
                if (logoImage != null)
                  pw.Container(width: 80, height: 80, child: pw.Image(logoImage, fit: pw.BoxFit.contain))
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text('Invoice #: $invoiceNumber', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Table: ${receiptJson['tableName'] ?? orderJson['tableName'] ?? ''}', style: pw.TextStyle(fontSize: 10)),
                  pw.Text('Payment: ${paymentMethod.isNotEmpty ? paymentMethod : (receiptJson['paymentStatus'] ?? orderJson['paymentStatus'] ?? '')}', style: pw.TextStyle(fontSize: 10)),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('Receipt time: ${receiptPrintedStr}', style: pw.TextStyle(fontSize: 9)),
                  pw.Text('Invoice time: ${invoiceGeneratedAt}', style: pw.TextStyle(fontSize: 9)),
                ]),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: ['Item', 'Unit', 'Qty', 'Price', 'Total'],
              data: items.map((it) => [
                it['name'],
                it['unit'],
                (it['qty'] is double) ? (it['qty'] as double).toStringAsFixed(2) : it['qty'].toString(),
                (it['price'] as double).toStringAsFixed(2),
                (it['total'] as double).toStringAsFixed(2),
              ]).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              cellStyle: pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              headerDecoration: pw.BoxDecoration(color: PdfColors.grey200),
            ),
            pw.SizedBox(height: 8),
            pw.Container(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                    pw.Text('Subtotal: ', style: pw.TextStyle(fontSize: 10)),
                    pw.SizedBox(width: 8),
                    pw.Text('Rs ${subtotal.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10)),
                  ]),
                  if (discountAmount > 0)
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                      pw.Text('Discount (${discountPercent.toStringAsFixed(0)}%): ', style: pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 8),
                      pw.Text('- Rs ${discountAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10)),
                    ]),
                  if (vatAmount > 0)
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                      pw.Text('VAT (${vatPercent.toStringAsFixed(0)}%): ', style: pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 8),
                      pw.Text('Rs ${vatAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 10)),
                    ]),
                  pw.Divider(),
                  pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                    pw.Text('Total: ', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(width: 8),
                    pw.Text('Rs ${finalAmount.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(footerNote, style: pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 12),
            pw.Text('Powered by Flutter POS', style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
          ];
        },
      ),
    );

    return doc.save();
  }

  /// Preview invoice as a PDF-style screen using PdfPreview
  Future<void> _viewInvoice(Map<String, dynamic> orderJson) async {
    final orderId = (orderJson['_id'] ?? '').toString();
    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid order id')));
      return;
    }

    // fetch receipt
    final receiptJson = await _fetchReceiptJson(orderId);
    if (receiptJson == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved receipt found — generate receipt first')));
      return;
    }

    // fetch restaurant settings
    final settings = await _fetchRestaurantSettings();

    // navigate to preview screen
    if (!mounted) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice Preview'), backgroundColor: const Color(0xFFFF7043)),
        body: PdfPreview(
          build: (format) async {
            return _buildInvoicePdfBytes(orderJson, receiptJson, settings);
          },
          allowPrinting: true,
          allowSharing: true,
        ),
      );
    }));
  }

  /// Print invoice directly
  Future<void> _printInvoice(Map<String, dynamic> orderJson) async {
    final orderId = (orderJson['_id'] ?? '').toString();
    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid order id')));
      return;
    }

    // fetch receipt
    final receiptJson = await _fetchReceiptJson(orderId);
    if (receiptJson == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No saved receipt found — generate receipt first')));
      return;
    }

    final settings = await _fetchRestaurantSettings();
    try {
      final bytes = await _buildInvoicePdfBytes(orderJson, receiptJson, settings);
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invoice print failed: $e')));
    }
  }

  Widget _orderCard(Map<String, dynamic> o, int originalIndex, int totalLen) {
    final id = (o['_id'] ?? '').toString();
    final table = (o['table']?['name'] ?? '—').toString();
    final area = (o['area']?['name'] ?? '—').toString();
    final status = (o['paymentStatus'] ?? 'Paid').toString();
    final total = (o['totalAmount'] ?? 0.0).toString();
    final paid = (o['paidAmount'] ?? 0.0).toString();
    final due = (o['dueAmount'] ?? 0.0).toString();
    final isCheckedOut = (o['checkedOut'] ?? false) == true;
    final statusText = (o['status'] ?? '').toString().toLowerCase();
    final isCancelled = statusText == 'cancelled';



    final dynamicOrderId = o['orderId'];
    final clientNo = totalLen - originalIndex - 1;
    final orderNoText = (dynamicOrderId is num || dynamicOrderId is String)
        ? '#${dynamicOrderId.toString()}'
        : '#$clientNo';

    final chipColor = _statusColor(status);
    final selected = _selectedIds.contains(id);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: selected ? Colors.orange.shade50 : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () => _enterSelectMode(id),
        onTap: () {
          if (_selectMode) {
            _toggleSelected(id);
          } else {
            if (isCheckedOut || isCancelled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('This order is already checked out or cancelled and can’t be edited.'),
                ),
              );
              return;
            }

            Navigator.push<bool>(
              context,
              MaterialPageRoute(
                  builder: (_) => OrderScreen(isEdit: true, order: o)),
            ).then((changed) {
              if (changed == true && mounted) ref.refresh(ordersProvider);
            });
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$table • $area',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectMode)
                    Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelected(id),
                    )
                  else
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: chipColor.withOpacity(.1),
                      child: Icon(Icons.receipt_long,
                          color: chipColor, size: 24),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withOpacity(.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: Colors.blueGrey.withOpacity(.25)),
                            ),
                            child: Text(orderNoText,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipColor.withOpacity(.08),
                              borderRadius: BorderRadius.circular(999),
                              border:
                              Border.all(color: chipColor.withOpacity(.25)),
                            ),
                            child: Text(status,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: chipColor)),
                          ),
                          if (isCheckedOut) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: Colors.green.withOpacity(.25)),
                              ),
                              child: const Text('Checked out',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.green)),
                            ),
                          ],
                          if (isCancelled) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: Colors.red.withOpacity(.25)),
                              ),
                              child: const Text('cancelled',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.red)),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 6),
                        Text(
                          'Total: Rs $total • Paid: Rs $paid • Due: Rs $due',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13, color: Colors.brown.shade800),
                        ),
                      ],
                    ),
                  ),
                  if (!_selectMode)
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'set_payment') {
                          final pm = await _selectPaymentMethodDialog(o);
                          if (pm == null) return;
                          final id = (o['_id'] ?? '').toString();
                          try {
                            final r = await http.put(
                              Uri.parse('${AppConfig.apiBase}/orders/$id'),
                              headers: _headers(),
                              body: jsonEncode({
                                'paymentMethod': pm,
                                'paymentStatus': (pm['method']?.toString() == 'credit') ? 'Credit' : 'Paid',
                              }),
                            );
                            if (r.statusCode ~/ 100 != 2) {
                              throw Exception(_serverMsg('Set payment failed', r.statusCode, r.body));
                            }
                            if (mounted) {
                              ref.refresh(ordersProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Payment method saved: ${pm['method']}')),
                              );
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save payment failed: $e')));
                          }
                        }

                        if (v == 'edit') {
                          if (isCheckedOut || isCancelled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('This order is already checked out or cancelled and can’t be edited.')),
                            );
                            return;
                          }
                          final changed = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(builder: (_) => OrderScreen(isEdit: true, order: o)),
                          );
                          if (changed == true && mounted)
                            ref.refresh(ordersProvider);
                        }

                        if (v == 'print') await _printOrder(o);

                        if (v == 'checkout') {
                          if (isCancelled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Cancelled order cannot be checked out.')),
                            );
                            return;
                          }
                          await _checkoutOrder(o);
                        }

                        if (v == 'mark_paid') {
                          await _markPaid(o);
                          if (mounted) ref.refresh(ordersProvider);
                        }

                        if (v == 'cancel') {
                          if (isCancelled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Order is already cancelled.')),
                            );
                            return;
                          }
                          try {
                            await _cancelOrder(id);
                            if (mounted) {
                              ref.refresh(ordersProvider);
                              setState(() {}); // rebuild card to show Cancelled badge
                            }
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
                          }
                        }

                        if (v == 'delete') {
                          try {
                            await _deleteOrder(id);
                            if (mounted) ref.refresh(ordersProvider);
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                          }
                        }

                        if (v == 'view_invoice') await _viewInvoice(o);
                        if (v == 'print_invoice') await _printInvoice(o);
                      },
                      itemBuilder: (_) {
                        final items = <PopupMenuEntry<String>>[
                          const PopupMenuItem(value: 'set_payment', child: Text('Set Payment Method')),
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(value: 'print', child: Text('Print')),
                        ];

                        if (isCheckedOut) {
                          items.add(const PopupMenuItem(value: 'view_invoice', child: Text('View Invoice')));
                          items.add(const PopupMenuItem(value: 'print_invoice', child: Text('Print Invoice')));
                        }

                        if (!isCheckedOut && !isCancelled) items.add(const PopupMenuItem(value: 'checkout', child: Text('Checkout')));

                        if (_canManage && !isCheckedOut && !isCancelled)
                          items.add(const PopupMenuItem(
                            value: 'cancel',
                            child: Text('Cancel Order', style: TextStyle(color: Colors.red)),
                          ));

                        if (_canManage && status != 'Paid' && !isCheckedOut && !isCancelled)
                          items.add(const PopupMenuItem(value: 'mark_paid', child: Text('Mark Paid')));
                        if (_canManage) items.add(const PopupMenuItem(value: 'delete', child: Text('Delete')));
                        return items;
                      },
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
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(ordersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFF7043),
        actions: [
          if (_selectMode)
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print selected',
              onPressed: () => _printSelected(_currentFilteredOrders),
            ),
          if (_selectMode)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Mark selected as Paid',
              onPressed: () => _bulkMarkPaidSelected(),
            ),
          if (_selectMode)
            IconButton(
              icon: const Icon(Icons.shopping_cart_checkout),
              tooltip: 'Bulk Checkout',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Confirm Bulk Checkout'),
                    content: Text(
                        'Are you sure you want to checkout ${_selectedIds.length} orders?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Checkout')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await bulkCheckoutSelected(force: true);
                }
              },
            ),
          if (_selectMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectMode = false;
                _selectedIds.clear();
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          // Search + Nepali date filter
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
            child: Material(
              elevation: 1,
              borderRadius: BorderRadius.circular(14),
              color: Colors.brown.shade50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText: 'Search orders...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              BorderSide(color: Colors.brown.shade300, width: 1.5),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              BorderSide(color: Colors.brown.shade300, width: 1.5),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              BorderSide(color: Colors.brown.shade600, width: 1.8),
                            ),
                            filled: true,
                            fillColor: Colors.brown.shade50,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: BorderSide(color: Colors.brown.shade300),
                          backgroundColor: Colors.brown.shade50,
                        ),
                        icon: Icon(
                          Icons.calendar_today,
                          size: 18,
                          color: Colors.brown.shade700,
                        ),
                        label: Text(
                          _fromDate == null && _toDate == null
                              ? 'Select Date'
                              : '${_fromDate?.format("yyyy-MM-dd") ?? "—"} → ${_toDate?.format("yyyy-MM-dd") ?? "—"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.brown.shade800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: () async {
                          final pickedFrom = await showMaterialDatePicker(
                            context: context,
                            initialDate: _fromDate ?? NepaliDateTime.now(),
                            firstDate: NepaliDateTime(2000),
                            lastDate: NepaliDateTime(2100),
                          );
                          if (pickedFrom == null) return;

                          final pickedTo = await showMaterialDatePicker(
                            context: context,
                            initialDate: _toDate ?? pickedFrom,
                            firstDate: pickedFrom,
                            lastDate: NepaliDateTime(2100),
                          );
                          if (pickedTo == null) return;

                          setState(() {
                            _fromDate = pickedFrom;
                            _toDate = pickedTo;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 36,
                      width: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.clear, color: Colors.brown.shade700, size: 18),
                        tooltip: 'Clear date filters',
                        onPressed: () => setState(() {
                          _fromDate = null;
                          _toDate = null;
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ordersAsync.when(
              data: (orders) {
                _currentFilteredOrders = orders
                    .where((o) {
                  final t = (o['table']?['name'] ?? '').toString().toLowerCase();
                  final a = (o['area']?['name'] ?? '').toString().toLowerCase();
                  final s = (o['paymentStatus'] ?? '').toString().toLowerCase();
                  final textMatch = t.contains(_query) || a.contains(_query) || s.contains(_query);

                  if (_fromDate == null && _toDate == null) return textMatch;

                  final createdAt = DateTime.tryParse((o['createdAt'] ?? '').toString());
                  if (createdAt == null) return false;
                  final nepaliCreated = NepaliDateTime.fromDateTime(createdAt);

                  if (_fromDate != null && nepaliCreated.isBefore(_fromDate!)) return false;
                  if (_toDate != null && nepaliCreated.isAfter(_toDate!)) return false;
                  return textMatch;
                })
                    .toList();

                _currentFilteredIds = _currentFilteredOrders.map((o) => o['_id'].toString()).toList();

                if (_currentFilteredOrders.isEmpty) {
                  return const Center(child: Text('No orders found'));
                }

                final totalLen = _currentFilteredOrders.length;
                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(ordersProvider),
                  child: ListView.builder(
                    itemCount: _currentFilteredOrders.length,
                    itemBuilder: (_, i) => _orderCard(
                        _currentFilteredOrders[i], i, orders.length),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printSelected(List<Map<String, dynamic>> orders) async {
    for (final id in _selectedIds) {
      final order = orders.firstWhere((o) => o['_id'] == id);
      await _printOrder(order);
    }
    setState(() {
      _selectMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _printOrder(Map<String, dynamic> o) async {
    final orderId = (o['_id'] ?? '').toString();
    if (orderId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid order id')),
      );
      return;
    }

    try {
      final token = ref.read(authStateProvider)?.token ?? '';

      // Convert JSON receipt -> OrderModel safely
      OrderModel _orderModelFromReceipt(Map<String, dynamic> r) {
        final items = ((r['items'] as List?) ?? []).map((m) {
          final map = m as Map<String, dynamic>;
          final price = (map['price'] is num) ? (map['price'] as num).toDouble() : 0.0;
          final qty = (map['quantity'] is num) ? (map['quantity'] as num).toInt() : 0;
          return OrderItemModel(
            id: map['_id']?.toString() ?? '',
            name: map['name']?.toString() ?? '',
            unitName: map['unitName']?.toString() ?? '',
            price: price,
            quantity: qty,
          );
        }).toList();

        final totalAmount = items.fold(0.0, (sum, it) => sum + it.lineTotal);
        final discountPercent = (r['discountPercent'] is num) ? (r['discountPercent'] as num).toDouble() : 0.0;
        final discountAmount = (r['discountAmount'] is num)
            ? (r['discountAmount'] as num).toDouble()
            : (discountPercent > 0 ? totalAmount * discountPercent / 100 : 0.0);
        final subtotalAfterDiscount = totalAmount - discountAmount;
        final vatPercent = (r['vatPercent'] is num) ? (r['vatPercent'] as num).toDouble() : 0.0;
        final vatAmount = (r['vatAmount'] is num)
            ? (r['vatAmount'] as num).toDouble()
            : (vatPercent > 0 ? subtotalAfterDiscount * vatPercent / 100 : 0.0);
        final finalAmount = (r['finalAmount'] is num)
            ? (r['finalAmount'] as num).toDouble()
            : subtotalAfterDiscount + vatAmount;

        final createdAt = DateTime.tryParse(
          r['printedAt']?.toString() ?? r['createdAt']?.toString() ?? '',
        ) ??
            DateTime.now();

        return OrderModel(
          id: r['_id']?.toString() ?? '',
          tableName: r['tableName']?.toString() ?? '',
          area: r['areaName']?.toString() ?? '',
          items: items,
          paymentStatus: r['paymentStatus']?.toString() ?? 'Paid',
          paidAmount: (r['paidAmount'] is num) ? (r['paidAmount'] as num).toDouble() : 0.0,
          customerName: r['customerName']?.toString(),
          note: r['note']?.toString(),
          createdAt: createdAt,
          vatPercent: vatPercent,
          vatAmount: vatAmount,
          discountPercent: discountPercent,
          discountAmount: discountAmount,
          finalAmount: finalAmount,
          restaurantName: r['restaurantName']?.toString() ?? 'Deskgoo Cafe',
        );
      }

      // 1️⃣ Try fetching existing receipt
      final getRes = await http.get(
        Uri.parse('${AppConfig.apiBase}/receipts/$orderId'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (getRes.statusCode == 200) {
        final receiptJson = jsonDecode(getRes.body) as Map<String, dynamic>;
        final model = _orderModelFromReceipt(receiptJson);
        await PrintService.printOrderReceipt(
          model,
          context: context,
          vatAmount: model.vatAmount,
          discountAmount: model.discountAmount,
          finalAmount: model.finalAmount,
        );
        return;
      }

      // 2️⃣ Ask for VAT & Discount if no receipt exists
      final vatDiscount = await _askVatDiscountDialog(
        initialVat: (o['vatPercent'] is num) ? (o['vatPercent'] as num).toDouble() : 13.0,
        initialDiscount: (o['discountPercent'] is num) ? (o['discountPercent'] as num).toDouble() : 0.0,
      );
      if (vatDiscount == null) return;

      // 3️⃣ Save receipt
      final savePayload = {
        'orderId': orderId,
        'vatPercent': vatDiscount['vat'] ?? 0.0,
        'discountPercent': vatDiscount['discount'] ?? 0.0,
      };

      final postRes = await http.post(
        Uri.parse('${AppConfig.apiBase}/receipts'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(savePayload),
      );

      if (postRes.statusCode ~/ 100 != 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save receipt failed: ${postRes.statusCode} ${postRes.body}')),
        );
        return;
      }

      // 4️⃣ Print saved receipt
      final savedJson = jsonDecode(postRes.body) as Map<String, dynamic>;
      final model = _orderModelFromReceipt(savedJson);
      await PrintService.printOrderReceipt(
        model,
        context: context,
        vatAmount: model.vatAmount,
        discountAmount: model.discountAmount,
        finalAmount: model.finalAmount,
      );
    } catch (e, st) {
      debugPrint('Print error: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Print failed: $e')));
    }
  }

  Future<Map<String, double>?> _askVatDiscountDialog({
    double initialVat = 13.0,
    double initialDiscount = 0.0,
  }) async {
    final vatCtrl = TextEditingController(text: initialVat.toString());
    final discountCtrl = TextEditingController(text: initialDiscount.toString());

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Value'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: vatCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'VAT (%)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Discount (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Print')),
        ],
      ),
    );

    if (confirmed != true) return null;
    final vat = double.tryParse(vatCtrl.text.trim()) ?? 0.0;
    final discount = double.tryParse(discountCtrl.text.trim()) ?? 0.0;
    return {'vat': vat, 'discount': discount};
  }
}
