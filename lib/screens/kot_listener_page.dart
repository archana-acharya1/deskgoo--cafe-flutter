import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../services/kot_printer.dart';

class KotListenerPage extends StatefulWidget {
  final String restaurantId;
  const KotListenerPage({super.key, required this.restaurantId});

  @override
  State<KotListenerPage> createState() => _KotListenerPageState();
}

class _KotListenerPageState extends State<KotListenerPage> {
  late IO.Socket socket;
  List<Map<String, dynamic>> kotList = [];

  @override
  void initState() {
    super.initState();
    _connectToSocket();
  }

  void _connectToSocket() {
    const serverUrl = 'http://202.51.3.168:3000';
    socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket.connect();

    socket.onConnect((_) {
      print('✅ Connected to Socket.IO server');
      socket.emit('joinRestaurant', widget.restaurantId);
    });

    // Debug all events — helps confirm what backend emits
    socket.onAny((event, data) {
      print('📡 Socket Event: $event — Data: $data');
    });

    // Listen for KOT-specific events
    socket.on('kot:new', (data) => _handleKotEvent('NEW', data));
    socket.on('kot:update', (data) => _handleKotEvent('UPDATE', data));
    socket.on('kot:void', (data) => _handleKotEvent('VOID', data));

    socket.onDisconnect((_) => print('❌ Disconnected from socket.io'));
    socket.onError((err) => print('Socket error: $err'));
  }

  void _handleKotEvent(String type, dynamic data) {
    print('📥 Received KOT [$type]: $data');

    final kotData = {
      'type': type,
      'orderId': data['orderId'] ?? '',
      'table': data['table'] ?? data['tableName'] ?? 'Unknown',
      'orderNumber': data['orderNumber'] ?? '',
      'timestamp': DateTime.now().toString(),
      'items': data['items'] ?? [],
    };

    // Add to list (newest on top)
    setState(() {
      kotList.insert(0, kotData);
    });

    // Print KOT (type-aware)
    KotPrinter.printKot(kotData);
  }

  @override
  void dispose() {
    socket.dispose();
    super.dispose();
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'NEW':
        return Colors.green[700]!;
      case 'UPDATE':
        return Colors.orange[700]!;
      case 'VOID':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'NEW':
        return 'NEW ORDER';
      case 'UPDATE':
        return 'ORDER UPDATED';
      case 'VOID':
        return 'ORDER VOIDED';
      default:
        return 'ORDER';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KOT Listener'),
        centerTitle: true,
      ),
      body: kotList.isEmpty
          ? const Center(child: Text('Waiting for KOT events...'))
          : ListView.builder(
        itemCount: kotList.length,
        itemBuilder: (context, i) {
          final kot = kotList[i];
          final type = kot['type'];
          final color = _typeColor(type);
          final label = _typeLabel(type);

          return Card(
            margin: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        type == 'NEW'
                            ? Icons.add_circle
                            : type == 'UPDATE'
                            ? Icons.sync
                            : Icons.cancel,
                        color: color,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Table: ${kot["table"]}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const Divider(),
                  ...List.generate((kot["items"] as List).length, (i) {
                    final item = kot["items"][i];
                    final itemName = item["name"] ?? "Unknown Item";
                    final qty = item["quantity"] ?? 0;
                    final unit = item["unitName"] ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        "• $itemName ($unit) × $qty",
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                  Text(
                    kot["timestamp"]
                        .toString()
                        .split(".")
                        .first
                        .replaceAll("T", " "),
                    style: TextStyle(
                        color: Colors.grey[600], fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
