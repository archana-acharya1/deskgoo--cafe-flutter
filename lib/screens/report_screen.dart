import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../state/auth.dart';

class SalesSummary {
  final String period;
  final double totalSales;
  final int totalOrders;

  SalesSummary({
    required this.period,
    required this.totalSales,
    required this.totalOrders,
  });

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

  TopItem({
    required this.name,
    required this.totalRevenue,
    required this.totalQuantity,
  });

  factory TopItem.fromJson(Map<String, dynamic> json) {
    return TopItem(
      name: json['name'] ?? '',
      totalRevenue: (json['totalRevenue'] ?? 0).toDouble(),
      totalQuantity: json['totalQuantity'] ?? 0,
    );
  }
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime? startDate;
  DateTime? endDate;
  bool newestFirst = true;
  bool sortByQuantity = true;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 6, vsync: this);
  }

  Future<Map<String, dynamic>> fetchDailyItemsReport() async {
    final auth = ref.read(authStateProvider);
    if (auth == null) throw Exception('Not authenticated');

    if (startDate == null && endDate == null) {
      return {};
    }

    Map<String, String> query = {};
    if (startDate != null) query['startDate'] = startDate!.toIso8601String();
    if (endDate != null) query['endDate'] = endDate!.toIso8601String();

    String url = '${AppConfig.apiBase}/reports/daily-items';
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

    final decoded = json.decode(response.body);
    return decoded is Map<String, dynamic> ? decoded : {};
  }

  Future<List<dynamic>> fetchReport(String endpoint) async {
    final auth = ref.read(authStateProvider);
    if (auth == null) throw Exception('Not authenticated');

    if (startDate == null && endDate == null) {
      return [];
    }

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

    if (endpoint == 'sales/summary') {
      data.sort((a, b) {
        DateTime dateA = DateTime.parse(a['_id']['period']);
        DateTime dateB = DateTime.parse(b['_id']['period']);
        return newestFirst ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
      });
    } else if (endpoint == 'sales/top-items') {
      data.sort((a, b) {
        if (sortByQuantity) {
          return (b['totalQuantity'] ?? 0).compareTo(a['totalQuantity'] ?? 0);
        } else {
          return (b['totalRevenue'] ?? 0).compareTo(a['totalRevenue'] ?? 0);
        }
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
        if (isStart) {
          startDate = date;
        } else {
          endDate = date;
        }
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

  void _toggleSortByMetric() {
    setState(() {
      sortByQuantity = !sortByQuantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF7043);
    const cream = Color(0xFFFDF6EC);

    return Scaffold(
      backgroundColor: cream,
      appBar: AppBar(
        backgroundColor: orange,
        title: const Text(
          'Sales Reports',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),

        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,

          tabs: const [
            Tab(text: 'Daily Items'),
            Tab(text: 'Summary'),
            Tab(text: 'Top Items'),
            Tab(text: 'By Category'),
            Tab(text: 'By Area'),
            Tab(text: 'By Table'),
          ],
        ),

        actions: [
          IconButton(
            icon: Icon(
              newestFirst ? Icons.arrow_upward : Icons.arrow_downward,
              color: Colors.white,
            ),
            onPressed: _toggleSort,
            tooltip: 'Sort by date',
          ),
          IconButton(
            icon: Icon(
              sortByQuantity ? Icons.format_list_numbered : Icons.attach_money,
              color: Colors.white,
            ),
            onPressed: _toggleSortByMetric,
            tooltip:
            sortByQuantity ? 'Sort by Revenue' : 'Sort by Quantity',
          ),
        ],
      ),

      body: Column(
        children: [
          _dateSelectorUI(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _dailyItemsTab(),

                reportListWidget(
                  'sales/summary',
                      (item) => _buildCard(
                    title: item['_id']['period'] ?? '',
                    subtitle: 'Orders: ${item['totalOrders']}',
                    trailing:
                    'Total: ${item['totalSales'].toStringAsFixed(2)}',
                  ),
                ),

                reportListWidget(
                  'sales/top-items',
                      (item) => _buildCard(
                    title: item['name'] ?? '',
                    subtitle: 'Qty Sold: ${item['totalQuantity']}',
                    trailing:
                    'Revenue: ${item['totalRevenue'].toStringAsFixed(2)}',
                  ),
                ),

                reportListWidget(
                  'sales/by-category',
                      (item) => _buildCard(
                    title: item['_id'] ?? '',
                    trailing:
                    'Total: ${item['totalSales'].toStringAsFixed(2)}',
                  ),
                ),

                reportListWidget(
                  'sales/by-area',
                      (item) => _buildCard(
                    title: item['_id'] ?? '',
                    trailing:
                    'Total: ${item['totalSales'].toStringAsFixed(2)}',
                  ),
                ),

                reportListWidget(
                  'sales/by-table',
                      (item) => _buildCard(
                    title: item['_id'] ?? '',
                    trailing:
                    'Total: ${item['totalSales'].toStringAsFixed(2)}',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dailyItemsTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: fetchDailyItemsReport(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              "Choose the date",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          );
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }

        return _buildDailyItemsList(snapshot.data!);
      },
    );
  }

  Widget _buildDailyItemsList(Map<String, dynamic> data) {
    final dates = data.keys.toList();

    return ListView.builder(
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final date = dates[index];
        final items = data[date] as List;

        return Card(
          margin: const EdgeInsets.all(10),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 3,
          child: ExpansionTile(
            title: Text(
              date,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            children: items.map((item) {
              return ListTile(
                title: Text(item['item']),
                subtitle: Text("Qty: ${item['quantity']}"),
                trailing: Text(
                  "Rs ${item['revenue']}",
                  style: const TextStyle(
                    color: Color(0xFFFF7043),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _dateSelectorUI() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _styledButton(
              label: startDate == null
                  ? 'Start Date'
                  : startDate!.toLocal().toString().split(' ')[0],
              onPressed: () => _pickDate(context, true),
            ),
            const SizedBox(width: 8),
            _styledButton(
              label: endDate == null
                  ? 'End Date'
                  : endDate!.toLocal().toString().split(' ')[0],
              onPressed: () => _pickDate(context, false),
            ),
            const SizedBox(width: 8),
            _styledButton(label: 'Last 7 Days', onPressed: _refreshLast7Days),
            const SizedBox(width: 8),
            _styledButton(label: 'Refresh', onPressed: () => setState(() {})),
            const SizedBox(width: 8),
            _styledButton(label: 'Clear', onPressed: _clearDates),
          ],
        ),
      ),
    );
  }

  Widget _styledButton({required String label, required VoidCallback onPressed}) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFFFF7043),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        elevation: 2,
      ),
      onPressed: onPressed,
      child: Text(label, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _buildCard({required String title, String? subtitle, String? trailing}) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing != null
            ? Text(
          trailing,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF7043),
          ),
        )
            : null,
      ),
    );
  }

  Widget reportListWidget(
      String endpoint, Widget Function(dynamic) itemBuilder) {
    return FutureBuilder<List<dynamic>>(
      future: fetchReport(endpoint),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(
            child: Text(
              'Choose the date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          );
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
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
