// lib/services/api_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../config.dart';

class ApiService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBase,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );

  static Future<Response> get(
      String endpoint, {
        String? token,
        Map<String, dynamic>? params,
      }) async {
    return _dio.get(
      endpoint,
      queryParameters: params,
      options: Options(headers: _headers(token)),
    );
  }

  static Future<Response> post(
      String endpoint,
      dynamic data, {
        String? token,
      }) async {
    return _dio.post(
      endpoint,
      data: jsonEncode(data),
      options: Options(headers: _headers(token)),
    );
  }

  static Future<Response> put(
      String endpoint,
      dynamic data, {
        String? token,
      }) async {
    return _dio.put(
      endpoint,
      data: jsonEncode(data),
      options: Options(headers: _headers(token)),
    );
  }

  static Future<Response> delete(
      String endpoint, {
        String? token,
      }) async {
    return _dio.delete(
      endpoint,
      options: Options(headers: _headers(token)),
    );
  }

  static Map<String, String> _headers(String? token) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }
}
