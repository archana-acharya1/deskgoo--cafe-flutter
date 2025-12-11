import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/order_model.dart';

class ReceiptGenerator {
  static Future<Uint8List> generateReceipt(
      OrderModel order, {
        required double vatAmount,
        required double discountAmount,
        required double finalAmount,
        double? vatPercent,
        double? discountPercent,
      }) async {
    final pdf = pw.Document();

    addReceiptPage(
      pdf,
      order,
      vatAmount: vatAmount,
      discountAmount: discountAmount,
      finalAmount: finalAmount,
      vatPercent: vatPercent ?? order.vatPercent,
      discountPercent: discountPercent ?? order.discountPercent,
    );

    return pdf.save();
  }

  static double _estimateReceiptHeightMm(OrderModel order) {
    double baseMm = 10 + 4 + 2 + 12;
    if ((order.customerName ?? '').isNotEmpty) baseMm += 4;
    if ((order.note ?? '').isNotEmpty) baseMm += 4;
    baseMm += 6 + 2;
    for (final it in order.items) {
      baseMm += 6;
      if (it.unitName.isNotEmpty) baseMm += 2;
    }
    baseMm += 25;
    return baseMm.clamp(80, 500);
  }

  static void addReceiptPage(
      pw.Document doc,
      OrderModel order, {
        required double vatAmount,
        required double discountAmount,
        required double finalAmount,
        double vatPercent = 0.0,
        double discountPercent = 0.0,
      }) {
    final subtotal = order.totalAmount;

    final heightMm = _estimateReceiptHeightMm(order) + 15;

    final pageFormat = PdfPageFormat(
      58 * PdfPageFormat.mm,
      heightMm * PdfPageFormat.mm,
      marginLeft: 5 * PdfPageFormat.mm,
      marginRight: 3 * PdfPageFormat.mm,
      marginTop: 3 * PdfPageFormat.mm,
      marginBottom: 3 * PdfPageFormat.mm,
    );

    final title = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final base = pw.TextStyle(fontSize: 7);
    final small = pw.TextStyle(fontSize: 6, color: PdfColors.grey700);
    final bold = pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold);

    pw.Widget dashedLine() => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Divider(color: PdfColors.grey600, thickness: 0.5),
    );

    pw.Widget kvLine(String l, String r, {bool strong = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(l, style: strong ? bold : base)),
          pw.Text(r, style: strong ? bold : base),
        ],
      ),
    );

    String money(num v) => v.toStringAsFixed(2);
    String fmtDate(DateTime d) =>
        "${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} "
            "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";

    final createdAt = order.createdAt;
    final tableName = order.tableName;
    final areaName = order.area;
    final customer = order.customerName ?? '';
    final note = order.note ?? '';
    final items = order.items;

    pw.Widget chip(String text) => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey700),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
      ),
    );

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (_) => pw.Center(
          child: pw.Container(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(order.restaurantName, style: title),
                      pw.SizedBox(height: 1),
                      pw.Text("Thank you for dining with us!", style: small),
                    ],
                  ),
                ),
                dashedLine(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Table: $tableName", style: base),
                    chip(order.paymentStatus),
                  ],
                ),
                pw.Text("Area: $areaName", style: base),
                pw.Text("Date: ${fmtDate(createdAt)}", style: small),
                if (customer.isNotEmpty)
                  pw.Text("Customer: $customer", style: small),
                if (note.isNotEmpty) pw.Text("Note: $note", style: small),
                dashedLine(),
                pw.Row(
                  children: [
                    pw.Expanded(flex: 6, child: pw.Text('Item', style: bold)),
                    pw.Expanded(
                        flex: 2,
                        child: pw.Text('Qty',
                            style: bold, textAlign: pw.TextAlign.right)),
                    pw.Expanded(
                        flex: 3,
                        child: pw.Text('Price',
                            style: bold, textAlign: pw.TextAlign.right)),
                    pw.Expanded(
                        flex: 3,
                        child: pw.Text('Total',
                            style: bold, textAlign: pw.TextAlign.right)),
                  ],
                ),
                dashedLine(),
                ...items.map((it) {
                  final lineTotal = it.price * it.quantity;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 1),
                    child: pw.Row(
                      children: [
                        pw.Expanded(
                          flex: 6,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(it.name, style: base),
                              if (it.unitName.isNotEmpty)
                                pw.Text("(${it.unitName})", style: small),
                            ],
                          ),
                        ),
                        pw.Expanded(
                          flex: 2,
                          child: pw.Text(it.quantity.toString(),
                              style: base, textAlign: pw.TextAlign.right),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(money(it.price),
                              style: base, textAlign: pw.TextAlign.right),
                        ),
                        pw.Expanded(
                          flex: 3,
                          child: pw.Text(money(lineTotal),
                              style: base, textAlign: pw.TextAlign.right),
                        ),
                      ],
                    ),
                  );
                }),
                dashedLine(),
                kvLine("Subtotal", "Rs ${money(subtotal)}"),
                if (discountAmount > 0)
                  kvLine("Discount (${discountPercent.toStringAsFixed(0)}%)",
                      "-Rs ${money(discountAmount)}"),
                if (vatAmount > 0)
                  kvLine("VAT (${vatPercent.toStringAsFixed(0)}%)",
                      "Rs ${money(vatAmount)}"),
                dashedLine(),
                kvLine("Final Amount", "Rs ${money(finalAmount)}", strong: true),
                pw.SizedBox(height: 4),
                pw.Center(child: pw.Text("Powered by Flutter POS", style: small)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
