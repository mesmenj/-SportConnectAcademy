import 'package:classcard_student/design/design_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('all primary screens render on a small phone without Firebase', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SportADesignApp());
    await tester.pumpAndSettle();
    expect(find.text('Bonjour, Sophie.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    for (final label in [
      'Réserver',
      'Planning',
      'Tournois',
      'Profil',
      'Accueil',
    ]) {
      await tester.tap(find.widgetWithText(NavigationDestination, label));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
  });

  testWidgets('a reservation goes through all three steps into the calendar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SportADesignApp());
    await tester.tap(find.widgetWithText(NavigationDestination, 'Réserver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tennis').first);
    await tester.pumpAndSettle();
    expect(find.text('La bonne formule.'), findsOneWidget);
    await tester.ensureVisible(find.text('Continuer'));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Le bon moment.'), findsOneWidget);
    await tester.ensureVisible(find.text('Continuer'));
    await tester.tap(find.text('Continuer'));
    await tester.pumpAndSettle();
    expect(find.text('Tout est prêt.'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirmer dans l’aperçu'));
    await tester.tap(find.text('Confirmer dans l’aperçu'));
    await tester.pumpAndSettle();
    expect(find.text('Votre planning.'), findsOneWidget);
    expect(find.text('Tennis · Cours privé'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop uses the navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SportADesignApp());
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
