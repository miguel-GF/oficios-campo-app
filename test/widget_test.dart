import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jale_app/app.dart';
import 'package:jale_app/theme.dart';

void main() {
  testWidgets('muestra una pantalla de error recuperable', (tester) async {
    var retried = false;
    var returnedHome = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AppErrorScreen(
          title: 'No pudimos cargar',
          message: 'Tus datos siguen protegidos.',
          retry: () => retried = true,
          home: () => returnedHome = true,
        ),
      ),
    );

    expect(find.text('No pudimos cargar'), findsOneWidget);
    await tester.tap(find.text('Intentar de nuevo'));
    await tester.tap(find.text('Volver al inicio'));
    expect(retried, isTrue);
    expect(returnedHome, isTrue);
  });

  testWidgets('onboarding muestra la captura del negocio', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Onboarding(save: (name, trade, phone, logoUri, iconKey) async {}),
      ),
    );

    expect(find.text('Primero, cuéntanos de tu negocio'), findsOneWidget);
    expect(find.text('NOMBRE DEL NEGOCIO *'), findsOneWidget);
    expect(find.text('OFICIO O ESPECIALIDAD'), findsOneWidget);
  });

  test('ofrece varias paletas visuales', () {
    expect(jalePalettes.length, greaterThanOrEqualTo(6));
    expect(jalePalettes.map((palette) => palette.id).toSet().length, 6);
    expect(jalePalettes.first.id, 'cobalto');
  });

  test('ofrece un catálogo inicial amplio de oficios', () {
    expect(commonTrades.length, 15);
    expect(commonTrades, contains('Electricidad'));
    expect(commonTrades, contains('Instalación de gas'));
  });

  test('traduce errores técnicos a mensajes accionables', () {
    expect(
      friendlyErrorMessage(Exception('AI_LIMIT_REACHED')),
      contains('cotizaciones con IA'),
    );
    expect(
      friendlyErrorMessage(Exception('RATE_LIMITED')),
      contains('Espera un momento'),
    );
  });

  test('permite elegir un icono manual o volver al icono del oficio', () {
    expect(jaleIconChoices.length, greaterThanOrEqualTo(20));
    expect(iconFromKey('bolt'), Icons.bolt_rounded);
    expect(iconFromKey('ai'), Icons.auto_awesome_rounded);
    expect(iconFromKey(null), isNull);
    expect(iconFromKey('unknown'), isNull);
  });

  testWidgets('el selector de icono permite cambiar y volver a Auto', (
    tester,
  ) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BusinessIconPicker(
            value: selected,
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('IA'));
    expect(selected, 'ai');
    await tester.tap(find.text('Rayo'));
    expect(selected, 'bolt');
    await tester.tap(find.text('Auto'));
    expect(selected, isNull);
  });

  testWidgets('la demo de voz muestra el resultado esperado', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: VoiceAiDemoPage()));

    expect(find.text('DEMO'), findsOneWidget);
    final play = find.ancestor(
      of: find.text('Reproducir demo completa'),
      matching: find.byType(FilledButton),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pump();
    await tester.tap(play);
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pump(const Duration(milliseconds: 1400));
    await tester.pumpAndSettle();
    expect(find.text('Miguel González'), findsOneWidget);
    expect(find.text('Cambio de chapa'), findsOneWidget);
  });
}
