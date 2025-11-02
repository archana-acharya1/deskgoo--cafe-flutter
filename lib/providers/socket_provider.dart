import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/order_model.dart';
import '../state/auth.dart';
import 'orders_provider.dart';

final socketProvider = Provider<SocketService>((ref) {
  final authState = ref.watch(authStateProvider);
  return SocketService(ref, authState);
});

class SocketService {
  final Ref ref;
  final dynamic authState;
  late final IO.Socket socket;

  SocketService(this.ref, this.authState) {
    socket = IO.io(
      "http://202.51.3.168:3000",
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );
    _initSocketListeners();
  }

  void _initSocketListeners() {
    socket.onConnect((_) {
      print('✅ Socket connected: ${socket.id}');
      // Join restaurant room
      if (authState?.restaurantId != null) {
        socket.emit('joinRestaurant', authState!.restaurantId);
        print("🏠 Joined restaurant room: ${authState!.restaurantId}");
      }
    });

    // --- ORDER CREATED ---
    socket.on('order_created', (data) {
      print('🆕 Order Created: $data');
      try {
        final order = OrderModel.fromJson(Map<String, dynamic>.from(data));
        ref.read(ordersProvider.notifier).addOrder(order);
      } catch (e) {
        print("❌ Failed to parse order_created event: $e");
      }
    });

    // --- ORDER UPDATED ---
    socket.on('order_updated', (data) {
      print('🔁 Order Updated: $data');
      try {
        final order = OrderModel.fromJson(Map<String, dynamic>.from(data));
        ref.read(ordersProvider.notifier).updateOrder(order);
      } catch (e) {
        print("❌ Failed to parse order_updated event: $e");
      }
    });

    // --- ORDER DELETED ---
    socket.on('order_deleted', (data) {
      print('🗑️ Order Deleted: $data');
      try {
        final orderId = data['orderId'] ?? data['_id'];
        if (orderId != null) {
          ref.read(ordersProvider.notifier).removeOrderById(orderId);
        }
      } catch (e) {
        print("❌ Failed to handle order_deleted event: $e");
      }
    });

    socket.onDisconnect((_) {
      print('⚠️ Socket disconnected');
    });

    socket.onError((err) {
      print('🚨 Socket error: $err');
    });
  }

  IO.Socket get instance => socket;

  void dispose() {
    socket.dispose();
  }
}
