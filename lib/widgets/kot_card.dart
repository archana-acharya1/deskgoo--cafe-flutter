import 'package:flutter/material.dart';

class KotCard extends StatelessWidget {
  final Map<String, dynamic> kot;

  const KotCard({Key? key, required this.kot}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final type = kot["type"] ?? "UNKNOWN";

    final color = type == "NEW"
        ? Colors.green[700]
        : type == "UPDATE"
        ? Colors.orange[700]
        : type == "VOID"
        ? Colors.red[700]
        : Colors.grey[700];

    final icon = type == "NEW"
        ? Icons.add_circle
        : type == "UPDATE"
        ? Icons.sync
        : type == "VOID"
        ? Icons.cancel
        : Icons.info;

    final items = List<Map<String, dynamic>>.from(kot["items"] ?? []);

    return Card(
      elevation: 4,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + table + type
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  "Table: ${kot["table"] ?? "Unknown"}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: color,
                  ),
                ),
                const Spacer(),
                Text(
                  type,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ],
            ),

            const Divider(height: 20, thickness: 1),

            // Items list
            ...items.map((item) {
              final name = item["name"] ?? "Unnamed Item";
              final unit = item["unitName"] ?? "";
              final qty = item["quantity"];
              final oldQty = item["oldQuantity"];
              final isVoided = type == "VOID";

              String itemText;

              if (oldQty != null && oldQty != qty) {
                // Show changed quantities (like 2 → 3)
                itemText = "• $name ($unit)  $oldQty → $qty";
              } else {
                itemText = "• $name ($unit) x$qty";
              }

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Text(
                  itemText,
                  style: TextStyle(
                    fontSize: 16,
                    color: isVoided ? Colors.red[800] : Colors.black,
                    decoration:
                    isVoided ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
              );
            }).toList(),

            const SizedBox(height: 10),

            // Footer info (time & orderId)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  kot["time"]?.toString().split(".").first ?? "",
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                if (kot["orderId"] != null && kot["orderId"].toString().isNotEmpty)
                  Text(
                    "Order: ${kot["orderId"]}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
