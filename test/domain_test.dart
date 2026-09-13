import 'package:test/test.dart';
import 'package:jale_app/domain.dart';

Payment payment(int amount, [String? voidedAt]) => Payment(
  id: '$amount',
  quoteId: 'q',
  receiptNumber: amount,
  method: PaymentMethod.cash,
  amountCents: amount,
  paidAt: '2026-08-03T00:00:00Z',
  notes: '',
  voidedAt: voidedAt,
  receiptFinalizedAt: null,
  quotaPeriod: null,
);
QuoteLine line(double quantity, int price, [String concept = 'Servicio']) =>
    QuoteLine(
      id: concept,
      concept: concept,
      quantity: quantity,
      unitPriceCents: price,
      position: 0,
    );

void main() {
  test(
    'calcula totales con cantidades decimales',
    () => expect(quoteTotal([line(1.5, 1099), line(2, 500)]), 2649),
  );
  test('agrega conceptos de IA sin duplicar los que ya existen', () {
    final existing = [line(1, 8500, 'Pintura de muro')];
    final additions = [
      line(2, 8500, 'pintura muro'),
      line(1, 12000, 'Impermeabilizacion de techo'),
    ];
    final merged = appendUniqueQuoteLines(existing, additions);
    expect(merged, hasLength(2));
    expect(merged.first.quantity, 1);
    expect(merged.last.concept, 'Impermeabilizacion de techo');
    expect(findSimilarQuoteLineIndex('pintura muro', existing), 0);
  });
  test('sugiere un concepto parecido del catálogo sin cambiarlo a ciegas', () {
    final item = CatalogItem(
      id: 'cat-1',
      concept: 'Pintura de muro',
      unitPriceCents: 8500,
      timesUsed: 2,
      createdAt: '2026-01-01',
      updatedAt: '2026-01-01',
    );
    final suggestion = suggestCatalogItem('pintura muro', [item]);
    expect(suggestion?.item.id, 'cat-1');
    expect(suggestion!.score, greaterThanOrEqualTo(0.55));
    expect(suggestCatalogItem('impermeabilización', [item]), isNull);
  });
  test('deriva pagos e ignora anulaciones', () {
    expect(paymentSummary(10000, []).paidCents, 0);
    expect(paymentSummary(10000, [payment(3000)]).balanceCents, 7000);
    expect(
      paymentSummary(10000, [
        payment(11000),
        payment(1000, '2026-08-04'),
      ]).status,
      PaymentStatus.paid,
    );
  });
  test('presenta aceptación y cobro como una sola etapa comprensible', () {
    expect(
      quoteStage(QuoteStatus.accepted, PaymentStatus.pending),
      QuoteStage.accepted,
    );
    expect(
      quoteStage(QuoteStatus.accepted, PaymentStatus.partial),
      QuoteStage.partial,
    );
    expect(
      quoteStage(QuoteStatus.accepted, PaymentStatus.paid),
      QuoteStage.paid,
    );
    expect(quoteStageLabel(QuoteStage.paid), 'PAGADA');
  });
  test('valida una cotizacion antes de finalizar', () {
    expect(
      validateQuoteForFinalization(clientName: '', lines: [line(1, 100)]),
      isNotNull,
    );
    expect(
      validateQuoteForFinalization(
        clientName: 'Ana',
        lines: [line(1, 100, '')],
      ),
      isNotNull,
    );
    expect(
      validateQuoteForFinalization(clientName: 'Ana', lines: [line(1, 100)]),
      isNull,
    );
    expect(
      validateQuoteForFinalization(
        clientName: 'Ana',
        lines: [line(1, 100)],
        validUntil: '2026-02-31',
      ),
      contains('válida'),
    );
  });
  test('calcula periodo, cuota, folios e importes', () {
    expect(quotaPeriod(DateTime(2026, 1, 15)), '2026-01');
    expect(usageSummary(2, '2026-01').used, 2);
    expect(formatFolio('COT', 42), 'COT-000042');
    expect(parseMoneyToCents(r'$ 1,250'), 125000);
    expect(parseMoneyToCents('1.250,50'), 125050);
    expect(parseMoneyToCents('invalido'), 0);
  });
  test('normaliza colores institucionales', () {
    expect(normalizeBrandColor('#215a8e'), '#215A8E');
    expect(normalizeBrandColor('red; color: black'), defaultBrandColor);
  });
  test('resume actividad de semana y estados de cobro', () {
    QuoteSummary summary({required PaymentStatus payment, int paid = 0}) =>
        QuoteSummary(
          id: '$payment',
          quoteNumber: 1,
          clientName: 'Ana',
          status: QuoteStatus.accepted,
          issuedAt: '2026-09-02T12:00:00',
          totalCents: 10000,
          updatedAt: '2026-09-02T12:00:00',
          paidCents: paid,
          balanceCents: 10000 - paid,
          paymentStatus: payment,
        );
    final value = dashboardSummary(
      [
        summary(payment: PaymentStatus.partial, paid: 4000),
        summary(payment: PaymentStatus.paid, paid: 10000),
      ],
      DashboardRange.week,
      clock: DateTime(2026, 9, 3),
    );
    expect(value.created, 2);
    expect(value.partial, 1);
    expect(value.paid, 1);
    expect(value.collectedCents, 14000);
    expect(value.pendingCents, 6000);
  });
}
