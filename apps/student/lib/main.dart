import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'sporta_app.dart';
import 'design/design_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const designPreview = bool.fromEnvironment(
    'DESIGN_PREVIEW',
    defaultValue: true,
  );
  if (designPreview) {
    runApp(const SportADesignApp());
    return;
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (DefaultFirebaseOptions.useEmulators) {
    final host = DefaultFirebaseOptions.emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
    FirebaseFunctions.instanceFor(
      region: 'europe-west1',
    ).useFunctionsEmulator(host, 5001);
  }
  if (!DefaultFirebaseOptions.useEmulators) {
    const siteKey = String.fromEnvironment('FIREBASE_APPCHECK_SITE_KEY');
    if (kIsWeb && siteKey.isEmpty) {
      throw StateError(
        'Configurer FIREBASE_APPCHECK_SITE_KEY pour Flutter Web SportA.',
      );
    }
    await FirebaseAppCheck.instance.activate(
      providerWeb: kIsWeb ? ReCaptchaV3Provider(siteKey) : null,
    );
  }
  runApp(const SportATenantApp());
}
