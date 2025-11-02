import 'dart:convert';
import 'package:http/http.dart' as http;

class ReceiptService {
  static const String baseUrl = "http://202.51.3.168:3000/api/v1/receipts";
  final String token;
  ReceiptService(this.token);

  Future<Map<String, dynamic>?> getReceipt(String orderId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/$orderId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      print("Receipt not found or error: ${response.body}");
      return null;
    }
  }

  Future<bool> saveReceipt(String orderId) async {
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: json.encode({'orderId': orderId}),
    );

    return response.statusCode == 200 || response.statusCode == 201;
  }
}
