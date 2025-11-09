import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/order_model.dart';
import '../state/auth.dart';
import 'orders_provider.dart';
import '../config.dart';

final socketProvider = Provider<SocketService>((ref) {
  final authState = ref.watch(authStateProvider);
  return SocketService(ref, authState);
});

class SocketService {
  final Ref ref;
  final dynamic authState;
  late final IO.Socket socket;

  SocketService(this.ref, this.authState) {
    final token = authState?.token ?? '';
    socket = IO.io(
      AppConfig.hostBase,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setQuery({'token': token})
          .disableAutoConnect()
          .build(),
    );

    if (token.isNotEmpty) {
      print('Lu hai connect bhayo,,');
      socket.connect();
    }

    _initSocketListeners();
  }

  void _initSocketListeners() {
    socket.onConnect((_) {
      print(' Socket connected: ${socket.id}');
      final restaurantId = authState?.restaurantId;
      if (restaurantId != null && restaurantId.isNotEmpty) {
        socket.emit('joinRestaurant', restaurantId);
        print(" Joined restaurant room: $restaurantId");
        socket.on('itemCreated', (items) {
          print('item listened after string: itemCreated is: , ${items}');
        });
      }
    });

    socket.onReconnect((_) {
      print(' Socket reconnected');
      final restaurantId = authState?.restaurantId;
      if (restaurantId != null && restaurantId.isNotEmpty) {
        socket.emit('joinRestaurant', restaurantId);
        print("Rejoined restaurant room: $restaurantId");
      }
    });

    socket.on('order_created', (data) {
      print(' Order Created: $data');
      try {
        final order = OrderModel.fromJson(Map<String, dynamic>.from(data));
        ref.read(ordersProvider.notifier).addOrder(order);
      } catch (e) {
        print(" Failed to parse order_created event: $e");
      }
    });

    socket.on('order_updated', (data) {
      print(' Order Updated: $data');
      try {
        final order = OrderModel.fromJson(Map<String, dynamic>.from(data));
        ref.read(ordersProvider.notifier).updateOrder(order);
      } catch (e) {
        print(" Failed to parse order_updated event: $e");
      }
    });

    socket.on('order_deleted', (data) {
      print(' Order Deleted: $data');
      try {
        final orderId = data['orderId'] ?? data['_id'];
        if (orderId != null) {
          ref.read(ordersProvider.notifier).removeOrderById(orderId);
        }
      } catch (e) {
        print("Failed to handle order_deleted event: $e");
      }
    });

    socket.onDisconnect((_) {
      print('Socket disconnected');
    });

    socket.onError((err) {
      print('Socket error: $err');
    });
  }

  IO.Socket get instance => socket;

  void disconnect() {
    try {
      final restaurantId = authState?.restaurantId;
      if (restaurantId != null && restaurantId.isNotEmpty) {
        socket.emit('leaveRestaurant', restaurantId);
      }
    } catch (_) {}

    try {
      if (socket.connected) {
        socket.disconnect();
      }
    } catch (_) {}

    try {
      socket.dispose();
    } catch (_) {}

    print('SocketService: disconnected and disposed');
  }

  void dispose() {
    socket.dispose();
  }
}
