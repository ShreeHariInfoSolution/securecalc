import 'environment.dart';

/// Application configuration management for different environments.
class AppConfig {
  final String appName;
  final String baseUrl;
  final String socketUrl;
  final Environment environment;

  static late final AppConfig _instance;

  AppConfig._({
    required this.appName,
    required this.baseUrl,
    required this.socketUrl,
    required this.environment,
  });

  static AppConfig get instance => _instance;

  /// Initializes the application configuration based on the target [Environment].
  static void initialize(Environment env) {
    switch (env) {
      case Environment.dev:
        _instance = AppConfig._(
          appName: 'SynqChat (Dev)',
          baseUrl: 'http://10.0.2.2:3000/api/v1',
          socketUrl: 'ws://10.0.2.2:3000',
          environment: Environment.dev,
        );
        break;
      case Environment.staging:
        _instance = AppConfig._(
          appName: 'SynqChat (Staging)',
          baseUrl: 'https://staging-api.synqchat.com/api/v1',
          socketUrl: 'wss://staging-api.synqchat.com',
          environment: Environment.staging,
        );
        break;
      case Environment.prod:
        _instance = AppConfig._(
          appName: 'SynqChat',
          baseUrl: 'https://api.synqchat.com/api/v1',
          socketUrl: 'wss://api.synqchat.com',
          environment: Environment.prod,
        );
        break;
    }
  }
}
