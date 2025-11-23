import '../services/api_service.dart';

class OrderService {
  static Future<bool> cancelOrder({
    required String orderId,
    required String reason,
    required String token,
  }) async {
    try {
      final res = await ApiService.put(
        "/orders/$orderId/cancel",
        {
          "cancelReason": reason,
        },
        token: token,
      );

      return res.statusCode == 200;
    } catch (e) {
      rethrow;
    }
  }
}
