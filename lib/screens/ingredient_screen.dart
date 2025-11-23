import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../state/auth.dart';
import '../config.dart';

class IngredientScreen extends ConsumerStatefulWidget {
  const IngredientScreen({super.key});

  @override
  ConsumerState<IngredientScreen> createState() => _IngredientScreenState();
}

class _IngredientScreenState extends ConsumerState<IngredientScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController unitController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  bool loading = false;
  List ingredients = [];

  @override
  void initState() {
    super.initState();
    fetchIngredients();
  }

  Future<void> fetchIngredients() async {
    try {
      final token = ref.read(authStateProvider)?.token;
      final url = Uri.parse('${AppConfig.apiBase}/ingredients');

      final res = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => ingredients = data["ingredients"]);
      } else {
        print("Fetch failed: ${res.body}");
      }
    } catch (e) {
      print("Error: $e");
    }
  }

  Future<void> createIngredient() async {
    final name = nameController.text.trim();
    final unit = unitController.text.trim();
    final quantity = double.tryParse(quantityController.text.trim());
    final price = double.tryParse(priceController.text.trim());

    if (name.isEmpty || unit.isEmpty || quantity == null || price == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields correctly")),
      );
      return;
    }

    setState(() => loading = true);

    try {
      final token = ref.read(authStateProvider)?.token;
      final url = Uri.parse('${AppConfig.apiBase}/ingredients');

      final res = await http.post(
        url,
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "name": name,
          "unit": unit,
          "quantity": quantity,
          "pricePerUnit": price,
        }),
      );

      setState(() => loading = false);

      if (res.statusCode == 201) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ingredient Added")),
        );

        nameController.clear();
        unitController.clear();
        quantityController.clear();
        priceController.clear();

        fetchIngredients();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${res.body}")),
        );
      }
    } catch (e) {
      setState(() => loading = false);
      print("Error: $e");
    }
  }

  Future<void> deleteIngredient(String id) async {
    final token = ref.read(authStateProvider)?.token;
    final url = Uri.parse('${AppConfig.apiBase}/ingredients/$id');

    final res = await http.delete(
      url,
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ingredient Deleted")),
      );
      fetchIngredients();
    } else {
      print("Delete failed: ${res.body}");
    }
  }

  Future<void> editIngredient(Map ing) async {
    final nameCtrl = TextEditingController(text: ing["name"]);
    final unitCtrl = TextEditingController(text: ing["unit"]);
    final qtyCtrl = TextEditingController(text: ing["quantity"].toString());
    final priceCtrl = TextEditingController(text: ing["pricePerUnit"].toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Edit Ingredient"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: "Name")),
              TextField(controller: unitCtrl, decoration: const InputDecoration(labelText: "Unit")),
              TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantity")),
              TextField(controller: priceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Price Per Unit")),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final token = ref.read(authStateProvider)?.token;
                final url = Uri.parse('${AppConfig.apiBase}/ingredients/${ing["_id"]}');

                final res = await http.put(
                  url,
                  headers: {
                    "Authorization": "Bearer $token",
                    "Content-Type": "application/json",
                  },
                  body: jsonEncode({
                    "name": nameCtrl.text.trim(),
                    "unit": unitCtrl.text.trim(),
                    "quantity": double.tryParse(qtyCtrl.text.trim()),
                    "pricePerUnit": double.tryParse(priceCtrl.text.trim()),
                  }),
                );

                if (res.statusCode == 200) {
                  Navigator.pop(context);
                  fetchIngredients();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Ingredient Updated")),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Update Failed: ${res.body}")),
                  );
                }
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Ingredients")),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.grey.shade200,
              ),
              child: Column(
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: "Ingredient Name")),
                  TextField(controller: unitController, decoration: const InputDecoration(labelText: "Unit (kg, g, L, ml etc.)")),
                  TextField(controller: quantityController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Quantity")),
                  TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Price Per Unit")),

                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: loading ? null : createIngredient,
                    child: loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text("Add Ingredient"),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ingredients.length,
              itemBuilder: (context, index) {
                final ing = ingredients[index];

                return Card(
                  child: ListTile(
                    title: Text(
                      ing["name"].toString().toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      "Qty: ${ing["quantity"]} ${ing["unit"]}\n"
                          "Price: ${ing["pricePerUnit"]}\n"
                          "Total Cost: ${ing["totalCost"]}",
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => editIngredient(ing),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => deleteIngredient(ing["_id"]),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
