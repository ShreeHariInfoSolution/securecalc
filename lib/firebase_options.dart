// File generated for FirebaseOptions configuration
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCc8g0GR0g1P8RzORFkoJgc993Tyx0yjGo',
    appId: '1:82967236601:android:c802cf8b6a2015b152f728',
    messagingSenderId: '82967236601',
    projectId: 'synq-chat-de4c1',
    storageBucket: 'synq-chat-de4c1.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBJwbWsZuUn_PIiwJWs8p0bRdpmrjcReDk',
    appId: '1:82967236601:ios:4d8364362933502752f728',
    messagingSenderId: '82967236601',
    projectId: 'synq-chat-de4c1',
    storageBucket: 'synq-chat-de4c1.firebasestorage.app',
    iosBundleId: 'com.shis.securecalc',
  );
}
