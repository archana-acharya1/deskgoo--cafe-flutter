import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/auth.dart';
import '../services/api_service.dart';
import '../config.dart';

class StockDetailScreen extends ConsumerStatefulWidget {
  final String stockId;
  const StockDetailScreen({super.key, required this.stockId});

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  Map<String, dynamic>? stock;
  bool isLoading = false;
  bool isUpdating = false;

  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchStockDetail();
  }

  Future<void> fetchStockDetail() async {
    setState(() => isLoading = true);
    try {
      final token = ref.read(authStateProvider)?.token;
      final res = await ApiService.get('/stocks/${widget.stockId}', token: token);

      // ✅ Merge history into stock so UI can use it
      final stockData = res.data['stock'];
      stockData['history'] = res.data['history'] ?? [];

      setState(() => stock = stockData);
    } catch (e) {
      debugPrint('Error fetching stock detail: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load stock details')),
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> addPurchase() async {
    final qty = double.tryParse(_quantityController.text.trim()) ?? 0;
    final price = double.tryParse(_priceController.text.trim()) ?? 0;

    if (qty <= 0 || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid quantity and price')),
      );
      return;
    }

    setState(() => isUpdating = true);
    try {
      final token = ref.read(authStateProvider)?.token;

      // ✅ Call the correct purchase endpoint
      await ApiService.post(
        '/stocks/purchase/${widget.stockId}',
        {'quantity': qty, 'price': price},
        token: token,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase added successfully')),
        );
        _quantityController.clear();
        _priceController.clear();

        // ✅ Reload data to show updated history
        await fetchStockDetail();
      }
    } catch (e) {
      debugPrint('Error adding purchase: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to add purchase')),
      );
    } finally {
      setState(() => isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = stock?['name'] ?? '';
    final unit = stock?['unit'] ?? '';
    final qty = (stock?['quantity'] as num?)?.toDouble() ?? 0.0;
    final alert = (stock?['alertThreshold'] as num?)?.toDouble() ?? 0.0;
    final auto = stock?['autoDecrement'] ?? false;
    final isLow = qty <= alert && alert > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'Stock Detail' : name),
        backgroundColor: Colors.brown.shade700,
        foregroundColor: Colors.white,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : stock == null
          ? const Center(child: Text('Stock not found'))
          : RefreshIndicator(
        onRefresh: fetchStockDetail,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Stock Overview Card
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF3E8), Color(0xFFFFE6D6)],
                  ),
                  border: Border.all(color: const Color(0x1A000000)),
                ),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6A3B13),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(.08),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.green.withOpacity(.22)),
                          ),
                          child: Text(
                            unit,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Remaining: ${qty.toStringAsFixed(2)} $unit',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: isLow ? Colors.redAccent : Colors.brown.shade800,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Spacer(),
                        if (isLow)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Low Stock',
                              style: TextStyle(fontSize: 11, color: Colors.redAccent),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Alert at: ${alert.toStringAsFixed(0)}',
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    if (auto)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF7043).withOpacity(.08),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFFF7043).withOpacity(.22)),
                        ),
                        child: const Text(
                          'Auto Decrement Enabled',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFFF7043),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Add Purchase Section
              Text(
                'Add Purchase',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.brown.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Price',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.brown.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 45),
                ),
                onPressed: isUpdating ? null : addPurchase,
                icon: isUpdating
                    ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
                    : const Icon(Icons.add),
                label: const Text('Add Purchase'),
              ),
              const SizedBox(height: 24),

              // Stock History Section
              Text(
                'Stock History',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.brown.shade800,
                ),
              ),
              const SizedBox(height: 8),
              if (stock?['history'] == null || (stock!['history'] as List).isEmpty)
                const Text('No history available.')
              else
                ...List.generate(
                  (stock!['history'] as List).length,
                      (i) {
                    final h = stock!['history'][i];
                    final q = (h['quantityAdded'] ?? h['quantity'] ?? 0).toDouble();
                    final p = (h['pricePerUnit'] ?? h['price'] ?? 0).toDouble();
                    final date = DateTime.tryParse(h['createdAt'] ?? '')?.toLocal();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.history, color: Colors.brown),
                        title: Text(
                          '+${q.toStringAsFixed(2)} $unit',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          'Rs.${p.toStringAsFixed(2)} | ${date != null ? date.toString().substring(0, 16) : ''}',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
