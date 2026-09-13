import 'dart:io';

import 'package:jale_app/database.dart';
import 'package:jale_app/domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openJaleDatabaseAt(inMemoryDatabasePath);
  });

  tearDown(() => db.close());

  Future<Quote> completeDraft({
    QuoteOrigin origin = QuoteOrigin.manual,
    String client = 'María López',
    int price = 125000,
  }) async {
    final id = await createQuote(db, null, origin);
    final draft = (await getQuote(db, id))!;
    return draft.copyWith(
      clientName: client,
      clientPhone: '5551234567',
      clientAddress: 'Calle 1',
      lines: [
        draft.lines.first.copyWith(
          concept: 'Instalación eléctrica',
          quantity: 1,
          unitPriceCents: price,
        ),
      ],
    );
  }

  test('las cotizaciones manuales son ilimitadas', () async {
    for (var index = 0; index < 6; index++) {
      await finalizeQuote(
        db,
        await completeDraft(client: 'Cliente $index'),
        false,
      );
    }

    final extra = await finalizeQuote(db, await completeDraft(), false);
    expect(extra?.finalizedAt, isNotNull);

    final aiQuote = await finalizeQuote(
      db,
      await completeDraft(origin: QuoteOrigin.ai),
      false,
    );
    expect(aiQuote?.origin, QuoteOrigin.ai);
    expect((await getDocumentUsage(db)).used, 7);
  });

  test(
    'el origen queda fijo después de finalizar para no liberar cuota',
    () async {
      final quote = await finalizeQuote(db, await completeDraft(), false);
      expect(quote?.origin, QuoteOrigin.manual);
      final editedWithAi = quote!.copyWith(
        origin: QuoteOrigin.ai,
        notes: 'Mejorada con IA',
      );
      await saveQuoteDraft(db, editedWithAi);
      final saved = await getQuote(db, quote.id);
      expect(saved?.origin, QuoteOrigin.manual);
      expect((await getDocumentUsage(db)).used, 1);
    },
  );

  test('un recibo no consume cuota y un pago protege la cotización', () async {
    final first = await finalizeQuote(db, await completeDraft(), false);
    final accepted = await setQuoteStatus(db, first!.id, QuoteStatus.accepted);
    final payment = await recordPayment(
      db,
      accepted!,
      PaymentMethod.transfer,
      25000,
      'Anticipo',
    );

    for (var index = 1; index < 4; index++) {
      await finalizeQuote(
        db,
        await completeDraft(client: 'Cliente $index'),
        false,
      );
    }

    final receipt = await finalizeReceipt(db, payment!.id, false);
    expect(receipt.receiptFinalizedAt, isNotNull);
    final stillAccepted = await setQuoteStatus(db, first.id, QuoteStatus.sent);
    expect(stillAccepted?.status, QuoteStatus.accepted);
    expect(
      () => setQuoteStatus(db, first.id, QuoteStatus.rejected),
      throwsA(isA<Exception>()),
    );
    expect(
      () => saveQuoteDraft(db, accepted.copyWith(clientName: 'Otra persona')),
      throwsA(isA<Exception>()),
    );
  });

  test('el catálogo conserva precio y ordena lo más usado', () async {
    await saveCatalogItem(db, concept: 'Pintura de muro', unitPriceCents: 4500);
    await saveCatalogItem(
      db,
      concept: 'Cambio de contacto',
      unitPriceCents: 30000,
    );
    await markCatalogItemsUsed(db, [
      const QuoteLine(
        id: '1',
        concept: 'Pintura de muro',
        quantity: 1,
        unitPriceCents: 4500,
        position: 0,
      ),
      const QuoteLine(
        id: '2',
        concept: 'Pintura de muro',
        quantity: 1,
        unitPriceCents: 4500,
        position: 1,
      ),
    ]);

    final items = await listCatalogItems(db);
    expect(items.first.concept, 'Pintura de muro');
    expect(items.first.timesUsed, 2);
    expect(items.first.unitPriceCents, 4500);
  });

  test('la base impide sobrepagos concurrentes', () async {
    final finalized = await finalizeQuote(
      db,
      await completeDraft(price: 10000),
      false,
    );
    final accepted = (await setQuoteStatus(
      db,
      finalized!.id,
      QuoteStatus.accepted,
    ))!;

    final attempts = await Future.wait(
      [
        recordPayment(db, accepted, PaymentMethod.cash, 7500, 'Primero'),
        recordPayment(db, accepted, PaymentMethod.cash, 7500, 'Segundo'),
      ].map((attempt) async {
        try {
          await attempt;
          return true;
        } catch (_) {
          return false;
        }
      }),
    );

    expect(attempts.where((value) => value), hasLength(1));
    final saved = (await getQuote(db, accepted.id))!;
    expect(paymentSummary(saved.totalCents, saved.payments).paidCents, 7500);
  });

  test('el respaldo incluye más de cien clientes', () async {
    for (var index = 0; index < 105; index++) {
      await saveClient(db, name: 'Cliente $index');
    }
    final snapshot = await exportSnapshot(db);
    expect(snapshot.clients, hasLength(105));
  });

  test(
    'el catalogo actualiza un concepto parecido en vez de duplicarlo',
    () async {
      await saveCatalogItem(
        db,
        concept: 'Pintura de muro',
        unitPriceCents: 4500,
      );
      await saveCatalogItem(db, concept: 'pintura muro', unitPriceCents: 5000);
      final items = await listCatalogItems(db);
      expect(items, hasLength(1));
      expect(items.single.unitPriceCents, 5000);
    },
  );

  test('migra una base v2 existente sin perder sus datos', () async {
    final legacyPath =
        '${Directory.systemTemp.path}/jale-legacy-${DateTime.now().microsecondsSinceEpoch}.db';
    final legacy = await openDatabase(
      legacyPath,
      version: 2,
      onCreate: (tx, _) async {
        await tx.execute(
          'CREATE TABLE business_profile (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, trade TEXT NOT NULL, phone TEXT NOT NULL, logo_uri TEXT, brand_color TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await tx.execute(
          'CREATE TABLE clients (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, phone TEXT NOT NULL, address TEXT NOT NULL, notes TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await tx.execute(
          'CREATE TABLE quotes (id TEXT PRIMARY KEY NOT NULL, quote_number INTEGER NOT NULL UNIQUE, client_id TEXT, client_name TEXT NOT NULL, status TEXT NOT NULL, issued_at TEXT NOT NULL, valid_until TEXT, notes TEXT NOT NULL, total_cents INTEGER NOT NULL, finalized_at TEXT, quota_period TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await tx.execute(
          'CREATE TABLE quote_lines (id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, concept TEXT NOT NULL, quantity REAL NOT NULL, unit_price_cents INTEGER NOT NULL, position INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await tx.execute(
          'CREATE TABLE payments (id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, receipt_number INTEGER NOT NULL UNIQUE, method TEXT NOT NULL, amount_cents INTEGER NOT NULL, paid_at TEXT NOT NULL, notes TEXT NOT NULL, voided_at TEXT, receipt_finalized_at TEXT, quota_period TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)',
        );
        await tx.execute(
          'CREATE TABLE app_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
        );
        await tx.insert('app_metadata', {
          'key': 'next_quote_number',
          'value': '2',
        });
        await tx.insert('app_metadata', {
          'key': 'next_receipt_number',
          'value': '1',
        });
        await tx.insert('business_profile', {
          'id': 'legacy-business',
          'name': 'Taller legado',
          'trade': 'Electricidad',
          'phone': '5550000000',
          'brand_color': '#0E5E4A',
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        });
        await tx.insert('quotes', {
          'id': 'legacy-quote',
          'quote_number': 1,
          'client_name': 'Cliente legado',
          'status': 'draft',
          'issued_at': '2026-01-01',
          'notes': '',
          'total_cents': 100,
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        });
        await tx.insert('quote_lines', {
          'id': 'legacy-line',
          'quote_id': 'legacy-quote',
          'concept': 'Revisión eléctrica',
          'quantity': 1,
          'unit_price_cents': 100,
          'position': 0,
          'created_at': '2026-01-01',
          'updated_at': '2026-01-01',
        });
      },
    );
    await legacy.close();

    final upgraded = await openJaleDatabaseAt(legacyPath);
    addTearDown(() async {
      await upgraded.close();
      await File(legacyPath).delete();
    });
    expect((await getBusinessProfile(upgraded))?.name, 'Taller legado');
    final quote = (await getQuote(upgraded, 'legacy-quote'))!;
    expect(quote.lines.single.concept, 'Revisión eléctrica');
    await saveQuoteDraft(
      upgraded,
      quote.copyWith(notes: 'Migrada correctamente'),
    );
    await saveCatalogItem(
      upgraded,
      concept: 'Revisión eléctrica',
      unitPriceCents: 100,
    );
    expect(
      (await listCatalogItems(upgraded)).single.concept,
      'Revisión eléctrica',
    );
  });
}
