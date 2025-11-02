import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order_model.dart';

class OrdersNotifier extends StateNotifier<List<OrderModel>> {
  OrdersNotifier() : super([]);

  void setOrders(List<OrderModel> orders) => state = orders;

  void addOrder(OrderModel order) => state = [order, ...state];

  void updateOrder(OrderModel updatedOrder) {
    state = state.map((o) {
      if (o.tableName == updatedOrder.tableName &&
          o.createdAt == updatedOrder.createdAt) {
        return updatedOrder;
      }
      return o;
    }).toList();
  }

  void removeOrder(OrderModel order) {
    state = state
        .where((o) =>
    !(o.tableName == order.tableName &&
        o.createdAt == order.createdAt))
        .toList();
  }

  void removeOrderById(String orderId) {
    state = state.where((o) => o.tableName != orderId).toList();
  }
}

final ordersProvider =
StateNotifierProvider<OrdersNotifier, List<OrderModel>>(
      (ref) => OrdersNotifier(),
);
