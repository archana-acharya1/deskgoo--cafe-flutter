import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../state/auth.dart';

class AddDailyStockModal extends ConsumerStatefulWidget {
  const AddDailyStockModal({super.key});

  @override
  ConsumerState<AddDailyStockModal> createState() => _AddDailyStockModalState();
}

class _AddDailyStockModalState extends ConsumerState<AddDailyStockModal> {
  String? selectedItemId;
  final TextEditingController stockCtrl = TextEditingController();

  bool loadingItems = true;
  bool submitting = false;

  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    loadItems();
  }

  Future<void> loadItems() async {
    try {
      final token = ref.read(authStateProvider)?.token;
      final res = await ApiService.get('/items', token: token);

      items = (res.data['items'] as List).cast<Map<String, dynamic>>();
    } catch (e) {
      print("ITEM LOAD ERROR: $e");
    }

    setState(() => loadingItems = false);
  }

  Future<void> submit() async {
    if (selectedItemId == null || stockCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Fill all fields")));
      return;
    }

    setState(() => submitting = true);

    try {
      final token = ref.read(authStateProvider)?.token;

      final body = {
        "itemId": selectedItemId,
        "totalStock": double.parse(stockCtrl.text),
      };

      await ApiService.post("/daily-stock", body, token: token);

      Navigator.pop(context, true); // return success
    } catch (e) {
      print("CREATE DAILY STOCK ERROR: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: $e")));
    }

    setState(() => submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: loadingItems
            ? const Center(child: CircularProgressIndicator())
            : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Add Daily Stock",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),

            // ITEM DROPDOWN
            DropdownButtonFormField<String>(
              value: selectedItemId,
              decoration: const InputDecoration(
                labelText: "Select Item",
                border: OutlineInputBorder(),
              ),
              items: items.map<DropdownMenuItem<String>>((item) {
                return DropdownMenuItem<String>(
                  value: item['_id'].toString(), // force it to String
                  child: Text(item['name'].toString()),
                );
              }).toList(),
              onChanged: (v) => setState(() => selectedItemId = v),
            ),

            const SizedBox(height: 12),

            // TOTAL STOCK
            TextField(
              controller: stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: "Total Stock",
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: submitting ? null : submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.brown.shade700,
                minimumSize: const Size(double.infinity, 48),
              ),
              child: submitting
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Add Stock"),
            ),
          ],
        ),
      ),
    );
  }
}
