import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../constants/api_constants.dart';
import 'network_exceptions.dart';

/// A lightweight API Client using standard Dart [HttpClient].
class ApiClient {
  final HttpClient _httpClient;

  ApiClient({HttpClient? httpClient}) : _httpClient = httpClient ?? HttpClient();

  Future<Map<String, dynamic>> get(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final request = await _httpClient.getUrl(uri);

      ApiConstants.defaultHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      final response = await request.close().timeout(ApiConstants.connectTimeout);
      final responseBody = await response.transform(utf8.decoder).join();

      return _handleResponse(response.statusCode, responseBody);
    } catch (e) {
      throw NetworkException(e.toString());
    }
  }

  Future<Map<String, dynamic>> post(
    String endpoint, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl}$endpoint');
      final request = await _httpClient.postUrl(uri);

      ApiConstants.defaultHeaders.forEach((key, value) {
        request.headers.set(key, value);
      });
      headers?.forEach((key, value) {
        request.headers.set(key, value);
      });

      if (body != null) {
        request.write(jsonEncode(body));
      }

      final response = await request.close().timeout(ApiConstants.connectTimeout);
      final responseBody = await response.transform(utf8.decoder).join();

      return _handleResponse(response.statusCode, responseBody);
    } catch (e) {
      throw NetworkException(e.toString());
    }
  }

  Map<String, dynamic> _handleResponse(int statusCode, String body) {
    if (statusCode >= 200 && statusCode < 300) {
      if (body.isEmpty) return {};
      return jsonDecode(body) as Map<String, dynamic>;
    } else {
      throw ApiException(
        statusCode: statusCode,
        message: body,
      );
    }
  }
}
