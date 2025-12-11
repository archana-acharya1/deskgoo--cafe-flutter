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
        case 'UPDATE':
        case 'UPDATED':
          headerTitle = '*** ORDER UPDATED ***';
          break;
        case 'VOID':
        case 'VOIDED':
          headerTitle = '*** ORDER VOIDED ***';
          break;
        default:
          headerTitle = '*** ORDER ***';
      }

      final addedItems = items.where((i) => (i['changeType'] ?? i['action'] ?? 'ADDED').toString().toUpperCase() == 'ADDED').toList();
      final cancelledItems = items.where((i) => (i['changeType'] ?? i['action'] ?? '').toString().toUpperCase() == 'VOIDED' || (i['changeType'] ?? i['action'] ?? '').toString().toUpperCase() == 'CANCELLED').toList();
      final updatedItems = items.where((i) => (i['changeType'] ?? i['action'] ?? '').toString().toUpperCase() == 'UPDATED').toList();

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
                    child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                  ),

                  // Note
                  if (note.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('NOTE: $note', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                        pw.Center(
                          child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

                  // ADDED ITEMS
                  if (addedItems.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Center(
                          child: pw.Text(
                            'ADDED ITEMS',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        ...addedItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final unit = (item['unitName'] ?? '-').toString();
                          final qty = item['quantity'] ?? item['qty'] ?? 0;
                          return pw.Text('$name ($unit) x $qty', style: pw.TextStyle(fontSize: 12));
                        }).toList(),
                        pw.Center(
                          child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

// CANCELLED ITEMS
                  if (cancelledItems.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Center(
                          child: pw.Text(
                            'CANCELLED ITEMS',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        ...cancelledItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final unit = (item['unitName'] ?? '-').toString();
                          final qty = item['quantity'] ?? item['qty'] ?? 0;
                          return pw.Text(
                            '$name ($unit) x $qty',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.lineThrough),
                          );
                        }).toList(),
                        pw.Center(
                          child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),

// UPDATED ITEMS
                  if (updatedItems.isNotEmpty)
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Center(
                          child: pw.Text(
                            'UPDATED ITEMS',
                            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        ...updatedItems.map((item) {
                          final name = (item['name'] ?? 'Unknown').toString();
                          final unit = (item['unitName'] ?? '-').toString();
                          final oldQty = item['oldQuantity'] ?? 0;
                          final qty = item['quantity'] ?? item['qty'] ?? 0;
                          return pw.Text(' $name ($unit) $oldQty -> $qty', style: pw.TextStyle(fontSize: 12));
                        }).toList(),
                        pw.Center(
                          child: pw.Text('--------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),


                  pw.SizedBox(height: 8),
                  pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
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

      await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
    } catch (e, st) {
      print('❌ KotPrinter.printKot error: $e\n$st');
    }
  }
}
