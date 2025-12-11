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
      final timestamp = kot['timestamp'] ?? DateTime.now().toString();
      final note = (kot['note'] ?? '').toString().trim();
      final items = (kot['items'] ?? []) as List<dynamic>;

      String headerTitle;
      switch (type) {
        case 'NEW':
        case 'PLACED':
          headerTitle = 'NEW ORDER';
          break;
        case 'UPDATE':
        case 'UPDATED':
          headerTitle = 'ORDER UPDATED';
          break;
        case 'VOID':
        case 'VOIDED':
          headerTitle = 'ORDER VOIDED';
          break;
        default:
          headerTitle = 'ORDER';
      }

      final addedItems = items.where((i) => (i['action'] ?? '').toString().toUpperCase() == 'ADDED').toList();
      final updatedItems = items.where((i) => (i['action'] ?? '').toString().toUpperCase() == 'UPDATED').toList();
      final reducedItems = items.where((i) => (i['action'] ?? '').toString().toUpperCase() == 'REDUCED').toList();
      final cancelledItems = items.where((i) => (i['action'] ?? '').toString().toUpperCase() == 'CANCELLED').toList();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          build: (context) => pw.Padding(
            padding: const pw.EdgeInsets.all(8),
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
                      color: (type == 'NEW' || type == 'PLACED') ? PdfColors.red : PdfColors.black,
                    ),
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text('Table: $table', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Area: $areaName', style: pw.TextStyle(fontSize: 12)),
                if (orderId.isNotEmpty)
                  pw.Text('Order ID: $orderId', style: pw.TextStyle(fontSize: 12)),
                pw.Text('Date & Time: $timestamp', style: pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 6),
                pw.Center(
                  child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                ),

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

                if (addedItems.isNotEmpty)
                  _buildItemSection('ADDED ITEMS', addedItems, (item) {
                    final name = item['name'] ?? 'Unknown';
                    final unit = item['unitName'] ?? '-';
                    final qty = item['quantity'] ?? item['qty'] ?? 0;
                    return '$name ($unit) x $qty';
                  }),

                if (updatedItems.isNotEmpty)
                  _buildItemSection('UPDATED ITEMS', updatedItems, (item) {
                    final name = item['name'] ?? 'Unknown';
                    final unit = item['unitName'] ?? '-';
                    final oldQty = item['oldQuantity'] ?? 0;
                    final qty = item['quantity'] ?? item['qty'] ?? 0;
                    return '$name ($unit) $oldQty -> $qty';
                  }),

                if (reducedItems.isNotEmpty)
                  _buildItemSection('REDUCED ITEMS', reducedItems, (item) {
                    final name = item['name'] ?? 'Unknown';
                    final unit = item['unitName'] ?? '-';
                    final oldQty = item['oldQuantity'] ?? 0;
                    final qty = item['quantity'] ?? item['qty'] ?? 0;
                    return '$name ($unit) $oldQty -> $qty';
                  }),

                if (cancelledItems.isNotEmpty)
                  _buildItemSection('CANCELLED ITEMS', cancelledItems, (item) {
                    final name = item['name'] ?? 'Unknown';
                    final unit = item['unitName'] ?? '-';
                    final qty = item['quantity'] ?? 0;
                    return '$name ($unit) x $qty';
                  }, lineThrough: true),

                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12)),
                ),
                pw.Center(
                  child: pw.Text(
                    'KITCHEN ORDER TICKET',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      await Printing.layoutPdf(onLayout: (format) async => pdf.save());
    } catch (e, st) {
      print('❌ KotPrinter.printKot error: $e\n$st');
    }
  }

  static pw.Widget _buildItemSection(
      String title, List items, String Function(Map<String, dynamic>) lineBuilder,
      {bool lineThrough = false}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
        ...items.map((item) => pw.Text(
          lineBuilder(item),
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: lineThrough ? pw.FontWeight.bold : pw.FontWeight.normal,
            decoration: lineThrough ? pw.TextDecoration.lineThrough : null,
          ),
        )),
        pw.Center(
            child: pw.Text('---------------------------------------------', style: pw.TextStyle(fontSize: 12))),
      ],
    );
  }
}
