// File generated using information from google-services.json
// For production, consider using FlutterFire CLI: flutterfire configure

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Web configuration - You need to get the web app ID from Firebase Console
  // Steps:
  // 1. Go to https://console.firebase.google.com/
  // 2. Select your project "shunmugam-textile"
  // 3. Click on the gear icon > Project settings
  // 4. Scroll down to "Your apps" section
  // 5. If you don't have a web app, click "Add app" and select Web
  // 6. Copy the appId (it looks like: 1:550659683173:web:xxxxx)
  // 7. Replace 'YOUR_WEB_APP_ID' below with the actual web app ID
  // 
  // OR run: dart pub global activate flutterfire_cli
  // Then: flutterfire configure (this will auto-generate this file)
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB6h-z218hzFrtVwCL6gyrR-skLYSVIFNM',
    appId: '1:550659683173:web:39e60b0aae7172abd4e78c', // Replace with your web app ID
    messagingSenderId: '550659683173',
    projectId: 'shunmugam-textile',
    authDomain: 'shunmugam-textile.firebaseapp.com',
    storageBucket: 'shunmugam-textile.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyB6h-z218hzFrtVwCL6gyrR-skLYSVIFNM',
    appId: '1:550659683173:android:75a32c9dc4287cf8d4e78c',
    messagingSenderId: '550659683173',
    projectId: 'shunmugam-textile',
    storageBucket: 'shunmugam-textile.firebasestorage.app',
  );
}

