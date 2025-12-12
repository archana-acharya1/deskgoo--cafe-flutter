import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class KotPrinter {
  KotPrinter._();

  static Future<void> printKot(Map<String, dynamic> kot) async {
    try {
      final pdf = pw.Document();

      final type = (kot['type'] ?? 'NEW').toString().toUpperCase();
      final orderId = kot['orderNumber'] ?? kot['orderId'] ?? '';
      final table = kot['tableName'] ?? kot['table'] ?? '-';
      final areaName = kot['areaName'] ?? '-';
      final items = (kot['items'] ?? []) as List<dynamic>;
      final timestamp = kot['timestamp'] ?? DateTime.now().toString();
      final note = (kot['note'] ?? '').toString().trim();

      String headerTitle;
      switch (type) {
        case 'NEW':
        case 'PLACED':
          headerTitle = '*** NEW ORDER ***';
          break;
        case 'VOID':
        case 'VOIDED':
          headerTitle = '*** ORDER VOIDED ***';
          break;
        default:
          headerTitle = '*** KITCHEN ORDER ***';
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (pw.Context context) {
            return pw.Padding(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Center(
                    child: pw.Text(
                      headerTitle,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: (type == 'NEW' || type == 'PLACED') ? PdfColors.red : PdfColors.black,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text('Table: $table', style: pw.TextStyle(fontSize: 12)),
                  pw.Text('Area: $areaName', style: pw.TextStyle(fontSize: 12)),
                  if (orderId.toString().isNotEmpty)
                    pw.Text('Order ID: $orderId', style: pw.TextStyle(fontSize: 12)),
                  pw.Text('Date & Time: $timestamp', style: pw.TextStyle(fontSize: 12)),
                  pw.SizedBox(height: 6),
                  pw.Center(
                    child: pw.Text('--------------------------------', style: pw.TextStyle(fontSize: 12)),
                  ),

                  // Note
                  if (note.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NOTE: $note', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Center(
                          child: pw.Text('--------------------------------', style: pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                  // Items
                  ...items.map((item) {
                    final name = (item['name'] ?? 'Unknown').toString();
                    final unit = (item['unitName'] ?? '-').toString();
                    final qty = item['quantity'] ?? item['qty'] ?? 0;
                    final oldQty = item['oldQuantity'] ?? 0;

                    // Determine change type robustly
                    String changeType = (item['changeType'] ?? item['action'] ?? 'ADDED').toString().toUpperCase();
                    if (changeType == 'UPDATED') {
                      if (qty > oldQty) changeType = 'INCREASED';
                      else if (qty < oldQty) changeType = 'REDUCED';
                      else changeType = 'UNCHANGED';
                    }

                    String label;
                    pw.TextStyle style = pw.TextStyle(fontSize: 12);

                    switch (changeType) {
                      case 'ADDED':
                        label = 'ADDED';
                        break;
                      case 'VOIDED':
                      case 'CANCELLED':
                        label = 'CANCELLED';
                        style = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.lineThrough);
                        break;
                      case 'REDUCED':
                        label = 'REDUCED';
                        break;
                      case 'INCREASED':
                        label = 'INCREASED';
                        break;
                      case 'UNCHANGED':
                        label = 'UNCHANGED';
                        break;
                      default:
                        label = 'UNKNOWN';
                    }

                    String line;
                    if (changeType == 'REDUCED') {
                      line = '$label : $name ($unit) ${oldQty - qty}';
                    } else if (changeType == 'INCREASED') {
                      line = '$label : $name ($unit) +${qty - oldQty}';
                    } else {
                      line = '$label : $name ($unit) x $qty';
                    }

                    return pw.Text(line, style: style);
                  }).toList(),

                  pw.SizedBox(height: 8),
                  pw.Center(child: pw.Text('--------------------------------', style: pw.TextStyle(fontSize: 12))),
                  pw.Center(child: pw.Text('KITCHEN ORDER TICKET', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                ],
              ),
            );
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e, st) {
      print('❌ KotPrinter.printKot error: $e\n$st');
    }
  }
}
