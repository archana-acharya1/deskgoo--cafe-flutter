import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order_model.dart';
import 'receipt_generator.dart';

class MultiReceiptGenerator {
  /// Prints multiple orders as separate receipt pages.
  static Future<void> printMany(List<OrderModel> orders) async {
    if (orders.isEmpty) return;

    final doc = pw.Document();

    for (final o in orders) {
      ReceiptGenerator.addReceiptPage(
        doc,
        o,
        vatPercent: o.vatPercent,
        discountPercent: o.discountPercent,
        vatAmount: o.vatAmount,
        discountAmount: o.discountAmount,
        finalAmount: o.finalAmount, // ✅ Pass finalAmount here
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => doc.save(),
      name: 'Receipts_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }
}
