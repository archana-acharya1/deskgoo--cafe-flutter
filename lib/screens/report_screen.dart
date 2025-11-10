import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../state/auth.dart';

// ----------------------
// Models
// ----------------------
class SalesSummary {
  final String period;
  final double totalSales;
  final int totalOrders;

  SalesSummary({required this.period, required this.totalSales, required this.totalOrders});

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    return SalesSummary(
      period: json['_id']['period'] ?? '',
      totalSales: (json['totalSales'] ?? 0).toDouble(),
      totalOrders: json['totalOrders'] ?? 0,
    );
  }
}

class TopItem {
  final String name;
  final double totalRevenue;
  final int totalQuantity;

  TopItem({required this.name, required this.totalRevenue, required this.totalQuantity});

  factory TopItem.fromJson(Map<String, dynamic> json) {
    return TopItem(
      name: json['name'] ?? '',
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      totalQuantity: json['totalQuantity'] ?? 0,
    );
  }
}

// ----------------------
// Reports Screen
// ----------------------
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? startDate;
  DateTime? endDate;
  bool newestFirst = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  Future<List<dynamic>> fetchReport(String endpoint) async {
    final auth = ref.read(authStateProvider);
    if (auth == null) throw Exception('Not authenticated');

    Map<String, String> query = {};
    if (startDate != null) query['startDate'] = startDate!.toIso8601String();
    if (endDate != null) query['endDate'] = endDate!.toIso8601String();

    String url = '${AppConfig.apiBase}/reports/$endpoint';
    if (query.isNotEmpty) {
      url += '?' + query.entries.map((e) => '${e.key}=${e.value}').join('&');
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer ${auth.token}'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to load report');
    }

    List<dynamic> data = json.decode(response.body);
    // Sort by date if Summary or Top Items
    if (endpoint == 'sales/summary' || endpoint == 'sales/top-items') {
      data.sort((a, b) {
        DateTime dateA = endpoint == 'sales/summary'
            ? DateTime.parse(a['_id']['period'])
            : DateTime.now();
        DateTime dateB = endpoint == 'sales/summary'
            ? DateTime.parse(b['_id']['period'])
            : DateTime.now();
        return newestFirst ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });
    }
    return data;
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    DateTime? date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
    );
    if (date != null) {
      setState(() {
        if (isStart) startDate = date;
        else endDate = date;
      });
    }
  }

  void _refreshLast7Days() {
    setState(() {
      endDate = DateTime.now();
      startDate = endDate!.subtract(const Duration(days: 6));
    });
  }

  void _clearDates() {
    setState(() {
      startDate = null;
      endDate = null;
    });
  }

  void _toggleSort() {
    setState(() {
      newestFirst = !newestFirst;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Reports'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Top Items'),
            Tab(text: 'By Category'),
            Tab(text: 'By Area'),
            Tab(text: 'By Table'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(newestFirst ? Icons.arrow_downward : Icons.arrow_upward),
            onPressed: _toggleSort,
            tooltip: 'Sort by date',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: () => _pickDate(context, true),
                  child: Text(startDate == null ? 'Start Date' : startDate!.toLocal().toString().split(' ')[0]),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _pickDate(context, false),
                  child: Text(endDate == null ? 'End Date' : endDate!.toLocal().toString().split(' ')[0]),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _refreshLast7Days,
                  child: const Text('Last 7 Days'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => setState(() {}), // refresh
                  child: const Text('Refresh'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _clearDates,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                reportListWidget('sales/summary', (item) => ListTile(
                  title: Text(item['_id']['period'] ?? ''),
                  subtitle: Text('Orders: ${item['totalOrders']}'),
                  trailing: Text('Total: ${item['totalSales'].toStringAsFixed(2)}'),
                )),
                reportListWidget('sales/top-items', (item) => ListTile(
                  title: Text(item['name'] ?? ''),
                  subtitle: Text('Qty Sold: ${item['totalQuantity']}'),
                  trailing: Text('Revenue: ${item['totalRevenue'].toStringAsFixed(2)}'),
                )),
                reportListWidget('sales/by-category', (item) => ListTile(
                  title: Text(item['_id'] ?? ''),
                  trailing: Text('Total: ${item['totalSales'].toStringAsFixed(2)}'),
                )),
                reportListWidget('sales/by-area', (item) => ListTile(
                  title: Text(item['_id'] ?? ''),
                  trailing: Text('Total: ${item['totalSales'].toStringAsFixed(2)}'),
                )),
                reportListWidget('sales/by-table', (item) => ListTile(
                  title: Text(item['_id'] ?? ''),
                  trailing: Text('Total: ${item['totalSales'].toStringAsFixed(2)}'),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget reportListWidget(String endpoint, Widget Function(dynamic) itemBuilder) {
    return FutureBuilder<List<dynamic>>(
      future: fetchReport(endpoint),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No data available'));
        }

        final data = snapshot.data!;
        return ListView.builder(
          itemCount: data.length,
          itemBuilder: (context, index) => itemBuilder(data[index]),
        );
      },
    );
  }
}
