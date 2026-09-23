import 'package:classcard_student/core/localization/app_language.dart';
import 'package:classcard_student/features/auth/onboarding_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    AppLanguageController.setLanguage(AppLanguage.french);
  });

  testWidgets('refreshes onboarding immediately after a language change', (
    tester,
  ) async {
    await tester.pumpWidget(const _LocalizedOnboarding());
    await tester.pumpAndSettle();
    expect(find.text('Chaque point raconte une histoire.'), findsOneWidget);
    expect(find.text('Continuer'), findsOneWidget);

    AppLanguageController.setLanguage(AppLanguage.english);
    await tester.pumpAndSettle();

    expect(find.text('Every point tells a story.'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('refreshes form labels without reopening the screen', (
    tester,
  ) async {
    await tester.pumpWidget(const _LocalizedFormLabel());
    expect(find.text('Nom'), findsOneWidget);

    AppLanguageController.setLanguage(AppLanguage.english);
    await tester.pump();

    expect(find.text('Last name'), findsOneWidget);
    expect(find.text('Nom'), findsNothing);
  });
}

class _LocalizedFormLabel extends StatelessWidget {
  const _LocalizedFormLabel();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageController.language,
    builder: (_, __, ___) => MaterialApp(
      home: Scaffold(
        body: TextField(decoration: InputDecoration(labelText: tr('Nom'))),
      ),
    ),
  );
}

class _LocalizedOnboarding extends StatelessWidget {
  const _LocalizedOnboarding();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AppLanguage>(
    valueListenable: AppLanguageController.language,
    builder: (_, language, __) => MaterialApp(
      locale: Locale(language == AppLanguage.english ? 'en' : 'fr'),
      home: const OnboardingScreen(),
    ),
  );
}
