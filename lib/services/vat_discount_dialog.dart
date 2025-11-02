import 'package:flutter/material.dart';

class VatDiscountDialog extends StatefulWidget {
  final double initialVat;
  final double initialDiscount;

  const VatDiscountDialog({
    super.key,
    this.initialVat = 13.0,
    this.initialDiscount = 0.0,
  });

  @override
  State<VatDiscountDialog> createState() => _VatDiscountDialogState();
}

class _VatDiscountDialogState extends State<VatDiscountDialog> {
  late TextEditingController vatController;
  late TextEditingController discountController;

  @override
  void initState() {
    super.initState();
    vatController = TextEditingController(text: widget.initialVat.toString());
    discountController =
        TextEditingController(text: widget.initialDiscount.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add the value'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: vatController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'VAT (%)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: discountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Discount (%)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final vat = double.tryParse(vatController.text.trim()) ?? 0.0;
            final discount =
                double.tryParse(discountController.text.trim()) ?? 0.0;
            Navigator.pop(context, {'vat': vat, 'discount': discount});
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
