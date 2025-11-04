import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCgdkpblEyLpy544c4IOv8m7HLEHIbt_wM',
    appId: '1:15876375690:web:f6a29c9dd6d7e60a329973',
    messagingSenderId: '15876375690',
    projectId: 'smart-locker-project-63711',
    authDomain: 'smart-locker-project-63711.firebaseapp.com',
    databaseURL: 'https://smart-locker-project-63711-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'smart-locker-project-63711.firebasestorage.app',
  );

  
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCgdkpblEyLpy544c4IOv8m7HLEHIbt_wM',
    appId: '1:15876375690:android:ff51441d3ff1a9ad329973', 
    messagingSenderId: '15876375690',
    projectId: 'smart-locker-project-63711',
    databaseURL: 'https://smart-locker-project-63711-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'smart-locker-project-63711.firebasestorage.app', 
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCgdkpblEyLpy544c4IOv8m7HLEHIbt_wM',
    appId: '1:15876375690:ios:PLACEHOLDER329973', 
    messagingSenderId: '15876375690',
    projectId: 'smart-locker-project-63711',
    databaseURL: 'https://smart-locker-project-63711-default-rtdb.asia-southeast1.firebasedatabase.app',
    storageBucket: 'smart-locker-project-63711.firebasestorage.app',
  );
}