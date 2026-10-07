import '../config/app_config.dart';

/// API and Server URL constants.
class ApiConstants {
  ApiConstants._();

  /// Dynamic Base URL sourced from [AppConfig]
  static String get baseUrl => AppConfig.instance.baseUrl;

  /// Dynamic Socket URL sourced from [AppConfig]
  static String get socketUrl => AppConfig.instance.socketUrl;

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Authentication Endpoints
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String refreshToken = '/auth/refresh';
  static const String profile = '/auth/profile';

  // Chat Endpoints
  static const String rooms = '/chat/rooms';
  static const String messages = '/chat/messages';
  static const String sendMessage = '/chat/send';

  // Headers
  static const String contentTypeHeader = 'Content-Type';
  static const String jsonContentType = 'application/json';
  static const String authorizationHeader = 'Authorization';

  static Map<String, String> get defaultHeaders => {
        contentTypeHeader: jsonContentType,
      };
}
