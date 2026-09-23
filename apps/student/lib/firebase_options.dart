import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options_sporta.dart';

class DefaultFirebaseOptions {
  static const useEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: true,
  );
  static const emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '127.0.0.1',
  );
  static FirebaseOptions get currentPlatform {
    if (!useEmulators) {
      if (kIsWeb) return SportAFirebaseOptions.web;
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => SportAFirebaseOptions.android,
        TargetPlatform.iOS => SportAFirebaseOptions.ios,
        _ => throw UnsupportedError(
          'Firebase SportA est configuré pour Android, iOS et Web.',
        ),
      };
    }
    const projectId = String.fromEnvironment(
      'FIREBASE_PROJECT_ID',
      defaultValue: 'demo-sporta',
    );
    if (projectId == 'classcard-79419' ||
        (useEmulators && !projectId.startsWith('demo-'))) {
      throw StateError(
        'SportA exige un projet indépendant ; utiliser demo-sporta avec les émulateurs.',
      );
    }
    const apiKey = String.fromEnvironment(
      'FIREBASE_API_KEY',
      defaultValue: 'demo-key',
    );
    const appId = String.fromEnvironment(
      'FIREBASE_APP_ID',
      defaultValue: 'demo-app',
    );
    if (!useEmulators &&
        (projectId.startsWith('demo-') ||
            apiKey == 'demo-key' ||
            appId == 'demo-app')) {
      throw StateError(
        'Configurer Firebase SportA avant de désactiver les émulateurs.',
      );
    }
    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
        defaultValue: '000000000000',
      ),
      projectId: projectId,
      authDomain: kIsWeb ? '$projectId.firebaseapp.com' : null,
      storageBucket: const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    );
  }
}
