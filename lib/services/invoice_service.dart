// import 'dart:typed_data';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:intl/intl.dart';
//
// import '../models/order_model.dart';
//
// class InvoiceService {
//   static Future<Uint8List> generateInvoicePdf({
//     required OrderModel order,
//     required Map<String, dynamic>? restaurantSettings,
//   }) async {
//     final pdf = pw.Document();
//     final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
//     final bool hasVat = (restaurantSettings?['vatNo'] ?? '').toString().isNotEmpty;
//     final bool hasPan = (restaurantSettings?['panNo'] ?? '').toString().isNotEmpty;
//
//     final logoUrl = restaurantSettings?['logoUrl'] ?? '';
//     pw.ImageProvider? logoImage;
//     if (logoUrl.isNotEmpty) {
//       try {
//         logoImage = pw.MemoryImage(await networkImage(logoUrl));
//       } catch (_) {}
//     }
//
//     final subtotal = order.totalAmount;
//     final discountAmount = order.discountPercent > 0
//         ? subtotal * order.discountPercent / 100
//         : 0.0;
//     final subtotalAfterDiscount = subtotal - discountAmount;
//     final vatAmount = order.vatPercent > 0
//         ? subtotalAfterDiscount * order.vatPercent / 100
//         : 0.0;
//     final finalAmount = subtotalAfterDiscount + vatAmount;
//
//     pdf.addPage(
//       pw.Page(
//         pageFormat: PdfPageFormat.roll80,
//         build: (pw.Context context) {
//           return pw.Column(
//             crossAxisAlignment: pw.CrossAxisAlignment.start,
//             children: [
//               if (logoImage != null)
//                 pw.Center(
//                   child: pw.Image(logoImage, height: 50),
//                 ),
//               pw.SizedBox(height: 8),
//               pw.Center(
//                 child: pw.Text(
//                   restaurantSettings?['name'] ?? 'Deskgoo Cafe',
//                   style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
//                 ),
//               ),
//               if (hasVat)
//                 pw.Center(
//                   child: pw.Text(
//                     'VAT No: ${restaurantSettings?['vatNo']}',
//                     style: const pw.TextStyle(fontSize: 10),
//                   ),
//                 ),
//               if (hasPan)
//                 pw.Center(
//                   child: pw.Text(
//                     'PAN No: ${restaurantSettings?['panNo']}',
//                     style: const pw.TextStyle(fontSize: 10),
//                   ),
//                 ),
//               pw.Divider(),
//               pw.Text('Invoice No: ${order.id ?? '-'}'),
//               pw.Text('Date: ${dateFormat.format(order.createdAt)}'),
//               pw.SizedBox(height: 6),
//               pw.Text('Table: ${order.tableName} (${order.area})'),
//               pw.Divider(),
//               pw.Row(
//                 mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                 children: const [
//                   pw.Text('Item', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
//                   pw.Text('Qty'),
//                   pw.Text('Price'),
//                 ],
//               ),
//               pw.Divider(),
//               ...order.items.map(
//                     (item) => pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Expanded(child: pw.Text(item.name)),
//                     pw.Text(item.quantity.toString()),
//                     pw.Text(item.total.toStringAsFixed(2)),
//                   ],
//                 ),
//               ),
//               pw.Divider(),
//               if (order.discountPercent > 0)
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text('Discount (${order.discountPercent}%)'),
//                     pw.Text('-${discountAmount.toStringAsFixed(2)}'),
//                   ],
//                 ),
//               if (order.vatPercent > 0)
//                 pw.Row(
//                   mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                   children: [
//                     pw.Text('VAT (${order.vatPercent}%)'),
//                     pw.Text(vatAmount.toStringAsFixed(2)),
//                   ],
//                 ),
//               pw.Divider(),
//               pw.Row(
//                 mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
//                 children: [
//                   pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
//                   pw.Text(finalAmount.toStringAsFixed(2),
//                       style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
//                 ],
//               ),
//               pw.SizedBox(height: 10),
//               pw.Center(
//                 child: pw.Text(
//                   'Thank you for dining with us!',
//                   style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic),
//                 ),
//               ),
//             ],
//           );
//         },
//       ),
//     );
//
//     return pdf.save();
//   }
// }
