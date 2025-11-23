import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/AddDailyStockModal.dart';
import '../services/api_service.dart';
import '../state/auth.dart';

final dailyStocksProvider = FutureProvider((ref) async {
  final token = ref.read(authStateProvider)?.token;
  final res = await ApiService.get('/daily-stock', token: token);
  return res.data['stocks'];
});

class DailyStockScreen extends ConsumerWidget {
  const DailyStockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stocksAsync = ref.watch(dailyStocksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daily Stock"),
        backgroundColor: Colors.brown.shade700,
      ),

      body: stocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Error: $e")),
        data: (stocks) {
          if (stocks.isEmpty) {
            return const Center(child: Text("No Daily Stock yet"));
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.refresh(dailyStocksProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: stocks.length,
              itemBuilder: (_, i) {
                final s = stocks[i];
                final name = s['item']['name'];
                final total = s['totalStock'];
                final remaining = s['remainingStock'];

                return Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(name),
                    subtitle: Text("Remaining: $remaining / $total"),
                  ),
                );
              },
            ),
          );
        },
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.brown.shade700,
        child: const Icon(Icons.add),
        onPressed: () async {
          final added = await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => const AddDailyStockModal(),
          );

          if (added == true) {
            ref.refresh(dailyStocksProvider);
          }
        },
      ),
    );
  }
}
