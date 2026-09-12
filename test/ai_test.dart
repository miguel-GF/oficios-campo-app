import 'package:flutter_test/flutter_test.dart';
import 'package:jale_app/ai.dart';

void main() {
  test('convierte la respuesta estructurada de IA sin perder centavos', () {
    final quote = aiQuoteDraftFromJson({
      'client_name': 'Ana',
      'notes': 'Incluye material',
      'lines': [
        {
          'concept': 'Cambio de contacto',
          'quantity': 2,
          'unit_price_cents': 35000,
        },
      ],
    });
    expect(quote.clientName, 'Ana');
    expect(quote.lines.single.quantity, 2);
    expect(quote.lines.single.unitPriceCents, 35000);
  });

  test(
    'rechaza una respuesta de IA incompleta para dejar editar manualmente',
    () {
      expect(
        () => aiQuoteDraftFromJson({
          'client_name': 'Ana',
          'notes': '',
          'lines': [
            {'concept': '', 'quantity': 0, 'unit_price_cents': -1},
          ],
        }),
        throwsA(isA<AiApiException>()),
      );
    },
  );

  test('rechaza cantidades no finitas', () {
    expect(
      () => aiQuoteDraftFromJson({
        'lines': [
          {
            'concept': 'Servicio',
            'quantity': double.nan,
            'unit_price_cents': 100,
          },
        ],
      }),
      throwsA(isA<AiApiException>()),
    );
  });
}
