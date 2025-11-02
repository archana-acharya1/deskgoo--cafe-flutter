// lib/services/kot_printer.dart
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Thermal-friendly KOT printer — generates and prints a black & white PDF
/// compatible with thermal printers.
class KotPrinter {
  KotPrinter._();

  static Future<void> printKot(Map<String, dynamic> kot) async {
    try {
      final pdf = pw.Document();

      final type = (kot['type'] ?? 'NEW').toString().toUpperCase();
      final orderId = kot['orderId'] ?? kot['orderNumber'] ?? '';
      final table = kot['tableName'] ?? kot['table'] ?? '-';
      final items = (kot['items'] ?? []) as List<dynamic>;
      final timestamp = kot['timestamp'] ?? kot['time'] ?? DateTime.now().toString();

      String headerTitle;
      if (type == 'NEW') headerTitle = '*** NEW ORDER ***';
      else if (type == 'UPDATE') headerTitle = '*** ORDER UPDATED ***';
      else if (type == 'VOID') headerTitle = '*** ORDER VOIDED ***';
      else headerTitle = '*** ORDER ***';

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Padding(
              padding: pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Header
                  pw.Center(
                    child: pw.Text(
                      headerTitle,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('Table: $table', style: pw.TextStyle(fontSize: 12)),
                  if (orderId.toString().isNotEmpty)
                    pw.Text('Order ID: $orderId', style: pw.TextStyle(fontSize: 12)),
                  pw.Text('Time: $timestamp', style: pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 6),
                  pw.Text('----------------------------------------', style: pw.TextStyle(fontSize: 12)),
                  pw.Text('ITEMS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 4),

                  // Items list
                  ...items.map((raw) {
                    final item = raw is Map ? raw : <String, dynamic>{};
                    final name = (item['name'] ?? 'Unknown').toString();
                    final unit = (item['unitName'] ?? '').toString();
                    final qty = item['quantity'] ?? item['qty'] ?? 0;
                    final oldQty = item['oldQuantity'];
                    final voided = item['voided'] == true;

                    if (voided) {
                      return pw.Text(
                        '[VOIDED] $name (${unit.isEmpty ? "-" : unit}) x $qty',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          decoration: pw.TextDecoration.lineThrough,
                        ),
                      );
                    } else if (oldQty != null && oldQty != qty) {
                      return pw.Text(
                        'UPDATED: $name (${unit.isEmpty ? "-" : unit})  $oldQty -> $qty',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      );
                    } else {
                      return pw.Text(
                        '- $name (${unit.isEmpty ? "-" : unit}) x $qty',
                        style: pw.TextStyle(fontSize: 12),
                      );
                    }
                  }).toList(),

                  pw.SizedBox(height: 8),
                  pw.Text('----------------------------------------', style: pw.TextStyle(fontSize: 12)),
                  pw.Center(
                    child: pw.Text(
                      'KITCHEN ORDER TICKET',
                      style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Send PDF to print preview or thermal printer
      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e, st) {
      print('❌ KotPrinter.printKot error: $e\n$st');
    }
  }
}
