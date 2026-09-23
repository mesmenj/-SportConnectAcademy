// Public Firebase client configuration for SportA. No service account credentials.
import 'package:firebase_core/firebase_core.dart';

class SportAFirebaseOptions {
  static const web = FirebaseOptions(
    apiKey: 'AIzaSyDCMUGy06QiXwqlM4p_vYUO-Ipju3dxcGA',
    appId: '1:748675195464:web:b3707efa61f1bdb4a42e7d',
    messagingSenderId: '748675195464',
    projectId: 'sporta-hub-2026',
    authDomain: 'sporta-hub-2026.firebaseapp.com',
    storageBucket: 'sporta-hub-2026.firebasestorage.app',
  );
  static const android = FirebaseOptions(
    apiKey: 'AIzaSyD3_aRk72kPs_agwvguWSM88O22MFR1oWg',
    appId: '1:748675195464:android:2030db6ffac8e07da42e7d',
    messagingSenderId: '748675195464',
    projectId: 'sporta-hub-2026',
    storageBucket: 'sporta-hub-2026.firebasestorage.app',
  );
  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyCKtnuOm9kjzvXx8866jvzz77EkFy1pUT0',
    appId: '1:748675195464:ios:43670326f3e97135a42e7d',
    messagingSenderId: '748675195464',
    projectId: 'sporta-hub-2026',
    storageBucket: 'sporta-hub-2026.firebasestorage.app',
    iosBundleId: 'com.sporta.app',
  );
}
