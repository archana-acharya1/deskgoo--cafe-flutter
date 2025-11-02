import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';
import 'orders_provider.dart';
import 'socket_provider.dart';

void setupSocketListeners(WidgetRef ref) {
  final socket = ref.read(socketProvider).instance;

  // --- KOT NEW ---
  socket.on('kot:new', (data) {
    final order = OrderModel(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      tableName: data['table'] is Map ? data['table']['name']?.toString() ?? '' : data['table']?.toString() ?? '',
      area: data['area'] is Map ? data['area']['name']?.toString() ?? '' : data['area']?.toString() ?? '',
      items: (data['items'] as List? ?? []).map((it) {
        final itemMap = it['item'] as Map<String, dynamic>? ?? {};
        return OrderItemModel(
          id: it['_id']?.toString() ?? '',
          name: it['name']?.toString() ?? itemMap['name']?.toString() ?? '',
          unitName: it['unitName']?.toString() ?? it['unit']?.toString() ?? '',
          price: (it['price'] ?? it['unitPrice'] ?? 0).toDouble(),
          quantity: (it['quantity'] ?? 1).toInt(),
        );
      }).toList(),
      paymentStatus: 'Pending',
      paidAmount: 0.0,
      customerName: data['customerName']?.toString(),
      note: data['note']?.toString(),
      createdAt: DateTime.tryParse(
        data['createdAt']?.toString() ?? DateTime.now().toIso8601String(),
      ) ??
          DateTime.now(),
      vatPercent: (data['vatPercent'] ?? 0).toDouble(),
      discountPercent: (data['discountPercent'] ?? 0).toDouble(),
      vatAmount: (data['vatAmount'] ?? 0).toDouble(),
      discountAmount: (data['discountAmount'] ?? 0).toDouble(),
      finalAmount: (data['finalAmount'] ?? 0).toDouble(),
      restaurantName: data['restaurantName']?.toString() ?? 'Deskgoo Cafe',
    );

    ref.read(ordersProvider.notifier).addOrder(order);
  });

  // --- KOT UPDATE ---
  socket.on('kot:update', (data) {
    final updatedOrder = OrderModel(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      tableName: data['table'] is Map ? data['table']['name']?.toString() ?? '' : data['table']?.toString() ?? '',
      area: data['area'] is Map ? data['area']['name']?.toString() ?? '' : data['area']?.toString() ?? '',
      items: (data['items'] as List? ?? []).map((it) {
        final itemMap = it['item'] as Map<String, dynamic>? ?? {};
        return OrderItemModel(
          id: it['_id']?.toString() ?? '',
          name: it['name']?.toString() ?? itemMap['name']?.toString() ?? '',
          unitName: it['unitName']?.toString() ?? it['unit']?.toString() ?? '',
          price: (it['price'] ?? it['unitPrice'] ?? 0).toDouble(),
          quantity: (it['quantity'] ?? 1).toInt(),
        );
      }).toList(),
      paymentStatus: 'Updated',
      paidAmount: 0.0,
      customerName: data['customerName']?.toString(),
      note: data['note']?.toString(),
      createdAt: DateTime.tryParse(
        data['updatedAt']?.toString() ?? DateTime.now().toIso8601String(),
      ) ??
          DateTime.now(),
      vatPercent: (data['vatPercent'] ?? 0).toDouble(),
      discountPercent: (data['discountPercent'] ?? 0).toDouble(),
      vatAmount: (data['vatAmount'] ?? 0).toDouble(),
      discountAmount: (data['discountAmount'] ?? 0).toDouble(),
      finalAmount: (data['finalAmount'] ?? 0).toDouble(),
      restaurantName: data['restaurantName']?.toString() ?? 'Deskgoo Cafe',
    );

    ref.read(ordersProvider.notifier).updateOrder(updatedOrder);
  });

  // --- KOT VOID ---
  socket.on('kot:void', (data) {
    final voidedOrder = OrderModel(
      id: data['_id']?.toString() ?? data['id']?.toString() ?? '',
      tableName: '',
      area: '',
      items: [],
      paymentStatus: 'VOID',
      paidAmount: 0.0,
      customerName: data['customerName']?.toString(),
      note: data['note']?.toString(),
      createdAt: DateTime.tryParse(
        data['deletedAt']?.toString() ?? DateTime.now().toIso8601String(),
      ) ??
          DateTime.now(),
      vatPercent: 0.0,
      discountPercent: 0.0,
      vatAmount: 0.0,
      discountAmount: 0.0,
      finalAmount: 0.0,
      restaurantName: data['restaurantName']?.toString() ?? 'Deskgoo Cafe',
    );

    ref.read(ordersProvider.notifier).removeOrder(voidedOrder);
  });
}
