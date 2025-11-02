import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../models/order_model.dart';
import 'receipt_generator.dart';
import 'receipt_service.dart';
import '../state/auth.dart';
import 'restaurant_settings_service.dart';

typedef VatDiscountDialogFn = Future<Map<String, double>?> Function({
double initialVat,
double initialDiscount,
bool showVat,
});

class PrintService {
  /// Prints receipt, respecting VAT/PAN settings
  static Future<void> printWithReceiptCheck(
      WidgetRef ref, {
        required BuildContext context,
        required Map<String, dynamic> orderData,
      }) async {
    try {
      final token = ref.read(authStateProvider)?.token ?? '';
      if (token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not authenticated')),
        );
        return;
      }

      // 1️⃣ Fetch restaurant settings
      final settingsService = RestaurantSettingsService(token);
      final settings = await settingsService.getSettings();
      final hasVat = settings?['vatNo'] != null &&
          settings!['vatNo'].toString().isNotEmpty;

      // 2️⃣ Prepare receipt service
      final receiptService = ReceiptService(token);
      final orderId = (orderData['_id'] ?? orderData['id'])?.toString() ?? '';
      if (orderId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid order ID')),
        );
        return;
      }

      OrderModel orderModel;
      double discountAmount = 0.0;
      double vatAmount = 0.0;
      double finalAmount = 0.0;

      // 3️⃣ Fetch saved receipt
      final existingReceipt = await receiptService.getReceipt(orderId);

      if (existingReceipt != null) {
        orderModel = OrderModel.fromJson(existingReceipt);

        discountAmount = orderModel.discountAmount;
        vatAmount = orderModel.vatAmount;
        finalAmount = orderModel.finalAmount;
      } else {
        // 4️⃣ Ask user for VAT & discount if no saved receipt
        final vatDiscount = await showVatDiscountDialog(
          context: context,
          initialVat: orderData['vatPercent'] is num
              ? (orderData['vatPercent'] as num).toDouble()
              : 13.0,
          initialDiscount: orderData['discountPercent'] is num
              ? (orderData['discountPercent'] as num).toDouble()
              : 0.0,
          showVat: hasVat,
        );

        if (vatDiscount == null) return;

        final merged = Map<String, dynamic>.from(orderData);
        merged['vatPercent'] = vatDiscount['vat'] ?? 0.0;
        merged['discountPercent'] = vatDiscount['discount'] ?? 0.0;

        // Map to OrderModel using proper _id and items ids
        orderModel = _mapServerOrderToModel(merged);

        // Calculate discount, VAT, final amount
        discountAmount = orderModel.discountPercent > 0
            ? orderModel.totalAmount * orderModel.discountPercent / 100
            : 0.0;

        final subtotalAfterDiscount = orderModel.totalAmount - discountAmount;

        vatAmount = orderModel.vatPercent > 0
            ? subtotalAfterDiscount * orderModel.vatPercent / 100
            : 0.0;

        finalAmount = subtotalAfterDiscount + vatAmount;

        // Update OrderModel with computed amounts (required parameters fixed)
        orderModel = OrderModel(
          id: orderModel.id,
          tableName: orderModel.tableName,
          area: orderModel.area,
          items: orderModel.items,
          paymentStatus: orderModel.paymentStatus,
          paidAmount: orderModel.paidAmount,
          customerName: orderModel.customerName,
          note: orderModel.note,
          createdAt: orderModel.createdAt,
          vatPercent: orderModel.vatPercent,
          discountPercent: orderModel.discountPercent,
          vatAmount: vatAmount,           // ✅ required
          discountAmount: discountAmount, // ✅ required
          finalAmount: finalAmount,       // ✅ required
          restaurantName: orderModel.restaurantName,
        );

        // Save receipt to backend
        final saved = await receiptService.saveReceipt(orderId);
        if (!saved) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Warning: failed to save receipt')),
          );
        }
      }

      // 5️⃣ Print PDF
      await printOrderReceipt(
        orderModel,
        vatAmount: vatAmount,
        discountAmount: discountAmount,
        finalAmount: finalAmount,
        context: context,
      );
    } catch (e, st) {
      debugPrint('PrintService error: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print error: $e')),
        );
      }
    }
  }

  /// PDF printing
  static Future<void> printOrderReceipt(
      OrderModel order, {
        required BuildContext context,
        required double vatAmount,
        required double discountAmount,
        required double finalAmount,
      }) async {
    try {
      final bytes = await ReceiptGenerator.generateReceipt(
        order,
        vatAmount: vatAmount,
        discountAmount: discountAmount,
        finalAmount: finalAmount,
        vatPercent: order.vatPercent,
        discountPercent: order.discountPercent,
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => bytes,
        name: 'Receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e, st) {
      debugPrint('PrintOrderReceipt failed: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print: $e')),
        );
      }
    }
  }
}

/// VAT / Discount dialog
Future<Map<String, double>?> showVatDiscountDialog({
  required BuildContext context,
  required double initialVat,
  required double initialDiscount,
  required bool showVat,
}) async {
  final vatController = TextEditingController(text: initialVat.toString());
  final discountController =
  TextEditingController(text: initialDiscount.toString());

  return showDialog<Map<String, double>>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
      return AlertDialog(
        title: const Text('Enter Discount Details'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showVat)
              TextField(
                controller: vatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'VAT %'),
              ),
            TextField(
              controller: discountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Discount %'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final vat = double.tryParse(vatController.text) ?? 0.0;
              final discount = double.tryParse(discountController.text) ?? 0.0;
              Navigator.pop(context, {'vat': vat, 'discount': discount});
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}

/// Map server/orderData to OrderModel safely
OrderModel _mapServerOrderToModel(Map<String, dynamic> o) {
  String tableName() {
    final t = o['table'] ?? o['tableName'];
    if (t is Map && t['name'] is String) return t['name'] as String;
    if (t is String) return t;
    return 'Unknown Table';
  }

  String areaName() {
    final a = o['area'] ?? o['areaName'];
    if (a is Map && a['name'] is String) return a['name'] as String;
    if (a is String) return a;
    return 'Unknown Area';
  }

  final items = ((o['items'] as List?) ?? []).map((raw) {
    final m = raw as Map<String, dynamic>;
    final item = m['item'];
    final name = item is Map ? (item['name']?.toString() ?? 'Item') : 'Item';
    final unit = (m['unitName'] ?? '').toString();
    final price = (m['price'] as num?)?.toDouble() ?? 0.0;
    final qty = (m['quantity'] as num?)?.toInt() ?? 1;
    final itemId = m['_id']?.toString() ?? '';
    return OrderItemModel(
        id: itemId, name: name, unitName: unit, price: price, quantity: qty);
  }).toList();

  final paidAmount = (o['paidAmount'] as num?)?.toDouble() ?? 0.0;
  final status = (o['paymentStatus'] ?? 'Paid') as String;
  final cust = (o['customerName'] as String?);
  final createdAt = DateTime.tryParse((o['createdAt'] ?? '').toString()) ??
      DateTime.now();

  return OrderModel(
    id: o['_id']?.toString() ?? o['id']?.toString() ?? '',
    tableName: tableName(),
    area: areaName(),
    items: items,
    paymentStatus: status,
    paidAmount: paidAmount,
    customerName: cust,
    note: (o['note'] ?? '') as String?,
    createdAt: createdAt,
    restaurantName: o['restaurantName']?.toString() ?? 'Deskgoo Cafe',
    vatPercent: (o['vatPercent'] as num?)?.toDouble() ?? 0.0,
    vatAmount: (o['vatAmount'] as num?)?.toDouble() ?? 0.0,
    discountPercent: (o['discountPercent'] as num?)?.toDouble() ?? 0.0,
    discountAmount: (o['discountAmount'] as num?)?.toDouble() ?? 0.0,
    finalAmount: (o['finalAmount'] as num?)?.toDouble() ?? 0.0,
  );
}
