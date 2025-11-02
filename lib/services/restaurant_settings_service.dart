import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class RestaurantSettingsService {
  static const String baseUrl =
      "http://202.51.3.168:3000/api/restaurant-settings";

  final String token;
  RestaurantSettingsService(this.token);

  Future<Map<String, dynamic>?> getSettings() async {
    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      return json.decode(response.body)['settings'];
    } else {
      print("Error fetching settings: ${response.body}");
      return null;
    }
  }

  Future<bool> updateSettings({
    String? vatNo,
    String? panNo,
    String? email,
    String? phone,
    String? address,
    File? logoFile,
  }) async {
    final uri = Uri.parse(baseUrl);
    final request = http.MultipartRequest("PUT", uri);

    request.headers['Authorization'] = 'Bearer $token';

    if (vatNo != null) request.fields['vatNo'] = vatNo;
    if (panNo != null) request.fields['panNo'] = panNo;
    if (email != null) request.fields['email'] = email;
    if (phone != null) request.fields['phone'] = phone;
    if (address != null) request.fields['address'] = address;

    if (logoFile != null) {
      request.files.add(
        await http.MultipartFile.fromPath('logo', logoFile.path),
      );
    }

    final response = await request.send();
    return response.statusCode == 200;
  }
}
