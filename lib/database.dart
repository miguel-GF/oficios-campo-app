import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'domain.dart';

const schemaVersion = 7;
String now() => DateTime.now().toUtc().toIso8601String();
String newId() =>
    '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32).toRadixString(16)}';

Future<Database> openJaleDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return openJaleDatabaseAt(path.join(directory.path, 'jale.db'));
}

Future<Database> openJaleDatabaseAt(String databasePath) {
  return openDatabase(
    databasePath,
    version: schemaVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys=ON');
    },
    onCreate: (db, version) => _createSchema(db),
    onUpgrade: (db, oldVersion, version) async {
      if (oldVersion < 2) {
        await db.execute('ALTER TABLE quote_lines RENAME TO quote_lines_old');
        await _createQuoteLines(db);
        await db.execute(
          'INSERT INTO quote_lines SELECT * FROM quote_lines_old',
        );
        await db.execute('DROP TABLE quote_lines_old');
      }
      if (!await _hasColumn(db, 'business_profile', 'icon_key')) {
        await db.execute(
          'ALTER TABLE business_profile ADD COLUMN icon_key TEXT',
        );
      }
      if (!await _hasTable(db, 'catalog_items')) {
        await _createCatalogItems(db);
      }
      if (!await _hasColumn(db, 'quotes', 'origin')) {
        await db.execute(
          "ALTER TABLE quotes ADD COLUMN origin TEXT NOT NULL DEFAULT 'manual'",
        );
      }
      if (!await _hasColumn(db, 'quotes', 'client_phone')) {
        await db.execute(
          "ALTER TABLE quotes ADD COLUMN client_phone TEXT NOT NULL DEFAULT ''",
        );
      }
      if (!await _hasColumn(db, 'quotes', 'client_address')) {
        await db.execute(
          "ALTER TABLE quotes ADD COLUMN client_address TEXT NOT NULL DEFAULT ''",
        );
      }
      if (oldVersion < 7) await _createPaymentGuards(db);
    },
  );
}

Future<bool> _hasTable(Database db, String table) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [table],
  );
  return rows.isNotEmpty;
}

Future<bool> _hasColumn(Database db, String table, String column) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows.any((row) => row['name'] == column);
}

Future<void> _createSchema(Database db) async {
  await db.transaction((tx) async {
    await tx.execute(
      '''CREATE TABLE business_profile (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, trade TEXT NOT NULL DEFAULT '', phone TEXT NOT NULL DEFAULT '', logo_uri TEXT, icon_key TEXT, brand_color TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    );
    await tx.execute(
      '''CREATE TABLE clients (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, phone TEXT NOT NULL DEFAULT '', address TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    );
    await tx.execute(
      '''CREATE TABLE quotes (id TEXT PRIMARY KEY NOT NULL, quote_number INTEGER NOT NULL UNIQUE, client_id TEXT, client_name TEXT NOT NULL DEFAULT '', client_phone TEXT NOT NULL DEFAULT '', client_address TEXT NOT NULL DEFAULT '', status TEXT NOT NULL, origin TEXT NOT NULL DEFAULT 'manual', issued_at TEXT NOT NULL, valid_until TEXT, notes TEXT NOT NULL DEFAULT '', total_cents INTEGER NOT NULL DEFAULT 0, finalized_at TEXT, quota_period TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(client_id) REFERENCES clients(id))''',
    );
    await _createQuoteLines(tx);
    await tx.execute(
      '''CREATE TABLE payments (id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, receipt_number INTEGER NOT NULL UNIQUE, method TEXT NOT NULL, amount_cents INTEGER NOT NULL, paid_at TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '', voided_at TEXT, receipt_finalized_at TEXT, quota_period TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(quote_id) REFERENCES quotes(id))''',
    );
    await tx.execute(
      'CREATE TABLE app_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)',
    );
    await _createCatalogItems(tx);
    await tx.execute('CREATE INDEX idx_clients_name ON clients(name)');
    await tx.execute(
      'CREATE INDEX idx_quotes_updated ON quotes(updated_at DESC)',
    );
    await tx.execute('CREATE INDEX idx_quotes_client ON quotes(client_id)');
    await tx.execute(
      'CREATE INDEX idx_payments_quote ON payments(quote_id, paid_at)',
    );
    await _createPaymentGuards(tx);
    await tx.insert('app_metadata', {'key': 'next_quote_number', 'value': '1'});
    await tx.insert('app_metadata', {
      'key': 'next_receipt_number',
      'value': '1',
    });
  });
}

Future<void> _createPaymentGuards(DatabaseExecutor db) async {
  await db.execute('DROP TRIGGER IF EXISTS payments_guard_insert');
  await db.execute('DROP TRIGGER IF EXISTS payments_guard_update');
  await db.execute('''
    CREATE TRIGGER payments_guard_insert BEFORE INSERT ON payments
    WHEN NEW.voided_at IS NULL
    BEGIN
      SELECT CASE WHEN NEW.amount_cents <= 0
        THEN RAISE(ABORT, 'PAYMENT_AMOUNT_INVALID') END;
      SELECT CASE WHEN COALESCE((SELECT status FROM quotes WHERE id=NEW.quote_id), '') <> 'accepted'
        THEN RAISE(ABORT, 'PAYMENT_QUOTE_NOT_ACCEPTED') END;
      SELECT CASE WHEN NEW.amount_cents + COALESCE((SELECT SUM(amount_cents) FROM payments WHERE quote_id=NEW.quote_id AND voided_at IS NULL), 0) >
        COALESCE((SELECT total_cents FROM quotes WHERE id=NEW.quote_id), -1)
        THEN RAISE(ABORT, 'PAYMENT_EXCEEDS_BALANCE') END;
    END
  ''');
  await db.execute('''
    CREATE TRIGGER payments_guard_update BEFORE UPDATE ON payments
    WHEN NEW.voided_at IS NULL
    BEGIN
      SELECT CASE WHEN NEW.amount_cents <= 0
        THEN RAISE(ABORT, 'PAYMENT_AMOUNT_INVALID') END;
      SELECT CASE WHEN COALESCE((SELECT status FROM quotes WHERE id=NEW.quote_id), '') <> 'accepted'
        THEN RAISE(ABORT, 'PAYMENT_QUOTE_NOT_ACCEPTED') END;
      SELECT CASE WHEN NEW.amount_cents + COALESCE((SELECT SUM(amount_cents) FROM payments WHERE quote_id=NEW.quote_id AND voided_at IS NULL AND id<>OLD.id), 0) >
        COALESCE((SELECT total_cents FROM quotes WHERE id=NEW.quote_id), -1)
        THEN RAISE(ABORT, 'PAYMENT_EXCEEDS_BALANCE') END;
    END
  ''');
}

Future<void> _createCatalogItems(DatabaseExecutor db) async {
  await db.execute(
    '''CREATE TABLE IF NOT EXISTS catalog_items (id TEXT PRIMARY KEY NOT NULL, concept TEXT NOT NULL COLLATE NOCASE UNIQUE, unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0), times_used INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_catalog_usage ON catalog_items(times_used DESC, updated_at DESC)',
  );
}

Future<void> _createQuoteLines(DatabaseExecutor db) => db.execute(
  '''CREATE TABLE quote_lines (id TEXT PRIMARY KEY NOT NULL, quote_id TEXT NOT NULL, concept TEXT NOT NULL, quantity REAL NOT NULL CHECK(quantity >= 0), unit_price_cents INTEGER NOT NULL CHECK(unit_price_cents >= 0), position INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(quote_id) REFERENCES quotes(id) ON DELETE CASCADE)''',
);

BusinessProfile? profileFromRow(Map<String, Object?>? row) => row == null
    ? null
    : BusinessProfile(
        id: row['id']! as String,
        name: row['name']! as String,
        trade: row['trade']! as String,
        phone: row['phone']! as String,
        logoUri: row['logo_uri'] as String?,
        iconKey: row['icon_key'] as String?,
        brandColor: row['brand_color']! as String,
        createdAt: row['created_at']! as String,
        updatedAt: row['updated_at']! as String,
      );
Client clientFromRow(Map<String, Object?> row) => Client(
  id: row['id']! as String,
  name: row['name']! as String,
  phone: row['phone']! as String,
  address: row['address']! as String,
  notes: row['notes']! as String,
  createdAt: row['created_at']! as String,
  updatedAt: row['updated_at']! as String,
);
CatalogItem catalogItemFromRow(Map<String, Object?> row) => CatalogItem(
  id: row['id']! as String,
  concept: row['concept']! as String,
  unitPriceCents: row['unit_price_cents']! as int,
  timesUsed: row['times_used']! as int,
  createdAt: row['created_at']! as String,
  updatedAt: row['updated_at']! as String,
);
QuoteLine lineFromRow(Map<String, Object?> row) => QuoteLine(
  id: row['id']! as String,
  concept: row['concept']! as String,
  quantity: (row['quantity']! as num).toDouble(),
  unitPriceCents: row['unit_price_cents']! as int,
  position: row['position']! as int,
);
Payment paymentFromRow(Map<String, Object?> row) => Payment(
  id: row['id']! as String,
  quoteId: row['quote_id']! as String,
  receiptNumber: row['receipt_number']! as int,
  method: paymentMethodFrom(row['method']! as String),
  amountCents: row['amount_cents']! as int,
  paidAt: row['paid_at']! as String,
  notes: row['notes']! as String,
  voidedAt: row['voided_at'] as String?,
  receiptFinalizedAt: row['receipt_finalized_at'] as String?,
  quotaPeriod: row['quota_period'] as String?,
);

Future<BusinessProfile?> getBusinessProfile(Database db) async =>
    profileFromRow((await db.query('business_profile', limit: 1)).firstOrNull);

Future<BusinessProfile> saveBusinessProfile(
  Database db, {
  required String name,
  required String trade,
  required String phone,
  String? logoUri,
  String? iconKey,
  required String brandColor,
}) async {
  if (name.trim().isEmpty) throw Exception('Escribe el nombre de tu negocio.');
  final current = await getBusinessProfile(db), stamp = now();
  final profile = BusinessProfile(
    id: current?.id ?? newId(),
    name: name.trim(),
    trade: trade.trim(),
    phone: phone.trim(),
    logoUri: logoUri,
    iconKey: iconKey,
    brandColor: normalizeBrandColor(brandColor),
    createdAt: current?.createdAt ?? stamp,
    updatedAt: stamp,
  );
  await db.insert('business_profile', {
    'id': profile.id,
    'name': profile.name,
    'trade': profile.trade,
    'phone': profile.phone,
    'logo_uri': profile.logoUri,
    'icon_key': profile.iconKey,
    'brand_color': profile.brandColor,
    'created_at': profile.createdAt,
    'updated_at': profile.updatedAt,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return profile;
}

Future<List<Client>> listClients(Database db, [String query = '']) async {
  final like = '%${query.trim()}%';
  final rows = await db.query(
    'clients',
    where: 'name LIKE ? OR phone LIKE ? OR address LIKE ?',
    whereArgs: [like, like, like],
    orderBy: 'updated_at DESC, name',
  );
  return rows.map(clientFromRow).toList();
}

Future<Client> saveClient(
  Database db, {
  String? id,
  required String name,
  String phone = '',
  String address = '',
  String notes = '',
  String? createdAt,
}) async {
  if (name.trim().isEmpty) throw Exception('Escribe el nombre del cliente.');
  final stamp = now(), clientId = id ?? newId();
  await db.insert('clients', {
    'id': clientId,
    'name': name.trim(),
    'phone': phone.trim(),
    'address': address.trim(),
    'notes': notes.trim(),
    'created_at': createdAt ?? stamp,
    'updated_at': stamp,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return clientFromRow(
    (await db.query('clients', where: 'id=?', whereArgs: [clientId])).first,
  );
}

Future<List<CatalogItem>> listCatalogItems(
  Database db, [
  String query = '',
]) async {
  final rows = await db.query(
    'catalog_items',
    where: 'concept LIKE ?',
    whereArgs: ['%${query.trim()}%'],
    orderBy: 'times_used DESC, updated_at DESC',
  );
  return rows.map(catalogItemFromRow).toList();
}

Future<CatalogItem> saveCatalogItem(
  Database db, {
  required String concept,
  required int unitPriceCents,
}) async {
  final clean = concept.trim();
  if (clean.isEmpty) throw Exception('Escribe el nombre del concepto.');
  if (unitPriceCents < 0) throw Exception('El precio no es válido.');
  final stamp = now();
  final similar = suggestCatalogItem(clean, await listCatalogItems(db));
  if (similar != null && similar.score >= 0.62) {
    await db.update(
      'catalog_items',
      {'unit_price_cents': unitPriceCents, 'updated_at': stamp},
      where: 'id=?',
      whereArgs: [similar.item.id],
    );
    return catalogItemFromRow(
      (await db.query(
        'catalog_items',
        where: 'id=?',
        whereArgs: [similar.item.id],
        limit: 1,
      )).first,
    );
  }
  await db.rawInsert(
    '''INSERT INTO catalog_items (id, concept, unit_price_cents, times_used, created_at, updated_at)
       VALUES (?, ?, ?, 0, ?, ?)
       ON CONFLICT(concept) DO UPDATE SET unit_price_cents=excluded.unit_price_cents, updated_at=excluded.updated_at''',
    [newId(), clean, unitPriceCents, stamp, stamp],
  );
  return catalogItemFromRow(
    (await db.query(
      'catalog_items',
      where: 'concept = ? COLLATE NOCASE',
      whereArgs: [clean],
      limit: 1,
    )).first,
  );
}

Future<void> markCatalogItemsUsed(
  Database db,
  Iterable<QuoteLine> lines,
) async {
  final stamp = now();
  await db.transaction((tx) async {
    for (final line in lines) {
      await tx.rawUpdate(
        '''UPDATE catalog_items SET times_used=times_used+1, updated_at=?
           WHERE concept=? COLLATE NOCASE''',
        [stamp, line.concept.trim()],
      );
    }
  });
}

Future<int> _nextNumber(DatabaseExecutor db, String key) async {
  final rows = await db.query(
    'app_metadata',
    columns: ['value'],
    where: 'key=?',
    whereArgs: [key],
    limit: 1,
  );
  final value = max(
    1,
    int.tryParse((rows.firstOrNull?['value'] as String?) ?? '') ?? 1,
  );
  await db.insert('app_metadata', {
    'key': key,
    'value': '${value + 1}',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  return value;
}

Future<String> createQuote(
  Database db, [
  Client? client,
  QuoteOrigin origin = QuoteOrigin.manual,
]) async {
  final id = newId(), stamp = now();
  await db.transaction((tx) async {
    final number = await _nextNumber(tx, 'next_quote_number');
    await tx.insert('quotes', {
      'id': id,
      'quote_number': number,
      'client_id': client?.id,
      'client_name': client?.name ?? '',
      'client_phone': client?.phone ?? '',
      'client_address': client?.address ?? '',
      'status': 'draft',
      'origin': origin.name,
      'issued_at': stamp,
      'notes': '',
      'total_cents': 0,
      'created_at': stamp,
      'updated_at': stamp,
    });
    await tx.insert('quote_lines', {
      'id': newId(),
      'quote_id': id,
      'concept': '',
      'quantity': 1,
      'unit_price_cents': 0,
      'position': 0,
      'created_at': stamp,
      'updated_at': stamp,
    });
  });
  return id;
}

Future<Quote?> getQuote(DatabaseExecutor db, String id) async {
  final rows = await db.query(
    'quotes',
    where: 'id=?',
    whereArgs: [id],
    limit: 1,
  );
  if (rows.isEmpty) return null;
  final row = rows.first;
  final lines = (await db.query(
    'quote_lines',
    where: 'quote_id=?',
    whereArgs: [id],
    orderBy: 'position,id',
  )).map(lineFromRow).toList();
  final payments = (await db.query(
    'payments',
    where: 'quote_id=?',
    whereArgs: [id],
    orderBy: 'paid_at,receipt_number',
  )).map(paymentFromRow).toList();
  return Quote(
    id: id,
    quoteNumber: row['quote_number']! as int,
    clientId: row['client_id'] as String?,
    clientName: row['client_name']! as String,
    clientPhone: row['client_phone'] as String? ?? '',
    clientAddress: row['client_address'] as String? ?? '',
    status: quoteStatusFrom(row['status']! as String),
    issuedAt: row['issued_at']! as String,
    validUntil: row['valid_until'] as String?,
    notes: row['notes']! as String,
    totalCents: row['total_cents']! as int,
    finalizedAt: row['finalized_at'] as String?,
    quotaPeriod: row['quota_period'] as String?,
    createdAt: row['created_at']! as String,
    updatedAt: row['updated_at']! as String,
    lines: lines,
    payments: payments,
    origin: QuoteOrigin.values.firstWhere(
      (value) => value.name == (row['origin'] as String? ?? 'manual'),
      orElse: () => QuoteOrigin.manual,
    ),
  );
}

Future<void> saveQuoteDraft(Database db, Quote quote) async {
  final stamp = now(), total = quoteTotal(quote.lines);
  final current = await getQuote(db, quote.id);
  // Once a quote is finalized, its origin is immutable so editing it with
  // the assistant cannot retroactively release a manual quota credit.
  final origin = current?.finalizedAt != null ? current!.origin : quote.origin;
  final paid = current == null
      ? 0
      : paymentSummary(current.totalCents, current.payments).paidCents;
  if (paid > 0 &&
      (total != current!.totalCents ||
          quote.clientName.trim() != current.clientName.trim() ||
          quote.clientPhone.trim() != current.clientPhone.trim() ||
          quote.clientAddress.trim() != current.clientAddress.trim())) {
    throw Exception(
      'No puedes cambiar cliente ni total después de registrar un pago.',
    );
  }
  await db.transaction((tx) async {
    await tx.update(
      'quotes',
      {
        'client_id': quote.clientId,
        'client_name': quote.clientName.trim(),
        'client_phone': quote.clientPhone.trim(),
        'client_address': quote.clientAddress.trim(),
        'origin': origin.name,
        'issued_at': quote.issuedAt,
        'valid_until': quote.validUntil,
        'notes': quote.notes,
        'total_cents': total,
        'updated_at': stamp,
      },
      where: 'id=?',
      whereArgs: [quote.id],
    );
    await tx.delete('quote_lines', where: 'quote_id=?', whereArgs: [quote.id]);
    for (var index = 0; index < quote.lines.length; index++) {
      final line = quote.lines[index];
      await tx.insert('quote_lines', {
        'id': line.id,
        'quote_id': quote.id,
        'concept': line.concept.trim(),
        'quantity': line.quantity,
        'unit_price_cents': line.unitPriceCents,
        'position': index,
        'created_at': stamp,
        'updated_at': stamp,
      });
    }
  });
}

Future<List<QuoteSummary>> listQuotes(Database db, [String query = '']) async {
  final like = '%${query.trim()}%';
  final rows = await db.rawQuery(
    '''SELECT q.*, COALESCE(SUM(CASE WHEN p.voided_at IS NULL THEN p.amount_cents ELSE 0 END),0) AS paid_cents FROM quotes q LEFT JOIN payments p ON p.quote_id=q.id WHERE q.client_name LIKE ? OR CAST(q.quote_number AS TEXT) LIKE ? GROUP BY q.id ORDER BY q.updated_at DESC''',
    [like, like],
  );
  return rows.map((row) {
    final summary = paymentSummary(row['total_cents']! as int, [
      Payment(
        id: '',
        quoteId: '',
        receiptNumber: 0,
        method: PaymentMethod.other,
        amountCents: row['paid_cents']! as int,
        paidAt: '',
        notes: '',
        voidedAt: null,
        receiptFinalizedAt: null,
        quotaPeriod: null,
      ),
    ]);
    return QuoteSummary(
      id: row['id']! as String,
      quoteNumber: row['quote_number']! as int,
      clientName: row['client_name']! as String,
      status: quoteStatusFrom(row['status']! as String),
      issuedAt: row['issued_at']! as String,
      totalCents: row['total_cents']! as int,
      updatedAt: row['updated_at']! as String,
      paidCents: summary.paidCents,
      balanceCents: summary.balanceCents,
      paymentStatus: summary.status,
      origin: QuoteOrigin.values.firstWhere(
        (value) => value.name == (row['origin'] as String? ?? 'manual'),
        orElse: () => QuoteOrigin.manual,
      ),
    );
  }).toList();
}

Future<UsageSummary> getDocumentUsage(Database db, {String? period}) async {
  final value = period ?? quotaPeriod();
  final quotes =
      Sqflite.firstIntValue(
        await db.rawQuery(
          "SELECT COUNT(*) FROM quotes WHERE quota_period=? AND origin='manual'",
          [value],
        ),
      ) ??
      0;
  return usageSummary(quotes, value);
}

Future<Quote?> finalizeQuote(Database db, Quote quote, bool _) async {
  final validation = validateQuoteForFinalization(
    clientName: quote.clientName,
    lines: quote.lines,
    validUntil: quote.validUntil,
  );
  if (validation != null) throw Exception(validation);
  await saveQuoteDraft(db, quote);
  if (quote.finalizedAt != null) return getQuote(db, quote.id);
  final stamp = now();
  await db.update(
    'quotes',
    {
      'status': 'finalized',
      'finalized_at': stamp,
      'quota_period': quotaPeriod(),
      'updated_at': stamp,
    },
    where: 'id=?',
    whereArgs: [quote.id],
  );
  return getQuote(db, quote.id);
}

Future<Quote?> setQuoteStatus(
  Database db,
  String id,
  QuoteStatus status,
) async {
  final current = await getQuote(db, id);
  if (current == null) throw Exception('No se encontró la cotización.');
  if (current.status == QuoteStatus.draft) {
    throw Exception('Finaliza la cotización antes de cambiar su estado.');
  }
  final hasPayments = current.payments.any((item) => item.voidedAt == null);
  if (status == QuoteStatus.rejected && hasPayments) {
    throw Exception(
      'No puedes marcar como no aceptada una cotización con pagos.',
    );
  }
  if (status == QuoteStatus.draft) {
    throw Exception('Una cotización finalizada no puede volver a borrador.');
  }
  if (status == QuoteStatus.sent &&
      (current.status == QuoteStatus.accepted ||
          current.status == QuoteStatus.rejected)) {
    // Compartir de nuevo un PDF no debe borrar una respuesta del cliente.
    return current;
  }
  await db.update(
    'quotes',
    {'status': status.name, 'updated_at': now()},
    where: 'id=?',
    whereArgs: [id],
  );
  return getQuote(db, id);
}

Future<Payment?> recordPayment(
  Database db,
  Quote quote,
  PaymentMethod method,
  int amountCents,
  String notes,
) async {
  if (amountCents <= 0) throw Exception('El abono debe ser mayor a cero.');
  final current = await getQuote(db, quote.id);
  if (current == null) throw Exception('No se encontró la cotización.');
  if (current.status != QuoteStatus.accepted) {
    throw Exception(
      'Solo se pueden registrar pagos de una cotización aceptada.',
    );
  }
  if (amountCents >
      paymentSummary(current.totalCents, current.payments).balanceCents) {
    throw Exception('El abono supera el saldo pendiente.');
  }
  final id = newId(), stamp = now();
  await db.transaction((tx) async {
    final number = await _nextNumber(tx, 'next_receipt_number');
    await tx.insert('payments', {
      'id': id,
      'quote_id': quote.id,
      'receipt_number': number,
      'method': method.name,
      'amount_cents': amountCents,
      'paid_at': stamp,
      'notes': notes.trim(),
      'created_at': stamp,
      'updated_at': stamp,
    });
  });
  final latest = await getQuote(db, quote.id);
  return latest?.payments.where((item) => item.id == id).firstOrNull;
}

Future<void> voidPayment(Database db, String id) => db
    .update('payments', {
      'voided_at': now(),
      'updated_at': now(),
    }, where: 'id=? AND voided_at IS NULL')
    .then((_) {});

Future<Payment> finalizeReceipt(Database db, String id, bool _) async {
  final rows = await db.rawQuery(
    'SELECT p.*, q.status AS quote_status FROM payments p JOIN quotes q ON q.id=p.quote_id WHERE p.id=?',
    [id],
  );
  if (rows.isEmpty) throw Exception('No se encontró el pago.');
  final row = rows.first;
  if (row['quote_status'] != 'accepted') {
    throw Exception(
      'Solo se pueden emitir recibos de una cotización aceptada.',
    );
  }
  if (row['voided_at'] != null) {
    throw Exception('No se puede generar un recibo para un pago anulado.');
  }
  if (row['receipt_finalized_at'] == null) {
    final stamp = now();
    final period = quotaPeriod();
    await db.update(
      'payments',
      {
        'receipt_finalized_at': stamp,
        'quota_period': period,
        'updated_at': stamp,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }
  final saved = await db.query(
    'payments',
    where: 'id=?',
    whereArgs: [id],
    limit: 1,
  );
  return paymentFromRow(saved.first);
}

Future<void> deleteAllLocalData(Database db) async {
  await db.transaction((tx) async {
    await tx.delete('payments');
    await tx.delete('quote_lines');
    await tx.delete('quotes');
    await tx.delete('clients');
    await tx.delete('business_profile');
    await tx.delete('catalog_items');
    await tx.update(
      'app_metadata',
      {'value': '1'},
      where: 'key IN (?,?)',
      whereArgs: ['next_quote_number', 'next_receipt_number'],
    );
  });
}

Future<BackupSnapshot> exportSnapshot(Database db) async {
  final data = await db.transaction((tx) async {
    final quotes = <Quote>[];
    for (final row in await tx.query('quotes', orderBy: 'quote_number')) {
      final quote = await getQuote(tx, row['id']! as String);
      if (quote != null) quotes.add(quote);
    }
    return (
      metadata: {
        for (final row in await tx.query('app_metadata'))
          row['key']! as String: row['value']! as String,
      },
      quotes: quotes,
      profile: profileFromRow(
        (await tx.query('business_profile', limit: 1)).firstOrNull,
      ),
      clients: (await tx.query(
        'clients',
        orderBy: 'updated_at DESC, name',
      )).map(clientFromRow).toList(),
      catalog: (await tx.query(
        'catalog_items',
        orderBy: 'times_used DESC, updated_at DESC',
      )).map(catalogItemFromRow).toList(),
    );
  });
  final profile = data.profile;
  String? logoBase64;
  final logoPath = profile?.logoUri;
  if (logoPath != null && logoPath.isNotEmpty) {
    try {
      final bytes = await File(logoPath).readAsBytes();
      if (bytes.length <= 5 * 1024 * 1024) logoBase64 = base64Encode(bytes);
    } catch (_) {
      // A missing optional logo must not prevent the user's data backup.
    }
  }
  return BackupSnapshot(
    schemaVersion: 1,
    exportedAt: now(),
    businessProfile: profile,
    clients: data.clients,
    quotes: data.quotes,
    metadata: data.metadata,
    logoBase64: logoBase64,
    catalogItems: data.catalog,
  );
}

Future<void> importSnapshot(Database db, BackupSnapshot snapshot) async {
  _validateSnapshot(snapshot);
  String? restoredLogoPath;
  if (snapshot.logoBase64 != null) {
    try {
      final bytes = base64Decode(snapshot.logoBase64!);
      if (bytes.length > 5 * 1024 * 1024) throw const FormatException();
      final directory = await getApplicationDocumentsDirectory();
      final branding = Directory(path.join(directory.path, 'branding'));
      await branding.create(recursive: true);
      restoredLogoPath = path.join(branding.path, 'restored-${newId()}.jpg');
      await File(restoredLogoPath).writeAsBytes(bytes, flush: true);
    } catch (_) {
      throw Exception('El logotipo del respaldo está dañado.');
    }
  }
  try {
    await db.transaction((tx) async {
      await tx.delete('payments');
      await tx.delete('quote_lines');
      await tx.delete('quotes');
      await tx.delete('clients');
      await tx.delete('business_profile');
      await tx.delete('catalog_items');
      await tx.delete('app_metadata');
      final profile = snapshot.businessProfile;
      if (profile != null) {
        await tx.insert('business_profile', {
          'id': profile.id,
          'name': profile.name,
          'trade': profile.trade,
          'phone': profile.phone,
          'logo_uri': restoredLogoPath,
          'icon_key': profile.iconKey,
          'brand_color': profile.brandColor,
          'created_at': profile.createdAt,
          'updated_at': profile.updatedAt,
        });
      }
      for (final client in snapshot.clients) {
        await tx.insert('clients', {
          'id': client.id,
          'name': client.name,
          'phone': client.phone,
          'address': client.address,
          'notes': client.notes,
          'created_at': client.createdAt,
          'updated_at': client.updatedAt,
        });
      }
      for (final quote in snapshot.quotes) {
        await tx.insert('quotes', {
          'id': quote.id,
          'quote_number': quote.quoteNumber,
          'client_id': quote.clientId,
          'client_name': quote.clientName,
          'client_phone': quote.clientPhone,
          'client_address': quote.clientAddress,
          'status': quote.status.name,
          'origin': quote.origin.name,
          'issued_at': quote.issuedAt,
          'valid_until': quote.validUntil,
          'notes': quote.notes,
          'total_cents': quote.totalCents,
          'finalized_at': quote.finalizedAt,
          'quota_period': quote.quotaPeriod,
          'created_at': quote.createdAt,
          'updated_at': quote.updatedAt,
        });
        for (final line in quote.lines) {
          await tx.insert('quote_lines', {
            'id': line.id,
            'quote_id': quote.id,
            'concept': line.concept,
            'quantity': line.quantity,
            'unit_price_cents': line.unitPriceCents,
            'position': line.position,
            'created_at': quote.createdAt,
            'updated_at': quote.updatedAt,
          });
        }
        for (final payment in quote.payments) {
          await tx.insert('payments', {
            'id': payment.id,
            'quote_id': quote.id,
            'receipt_number': payment.receiptNumber,
            'method': payment.method.name,
            'amount_cents': payment.amountCents,
            'paid_at': payment.paidAt,
            'notes': payment.notes,
            'voided_at': payment.voidedAt,
            'receipt_finalized_at': payment.receiptFinalizedAt,
            'quota_period': payment.quotaPeriod,
            'created_at': quote.createdAt,
            'updated_at': quote.updatedAt,
          });
        }
      }
      for (final entry in snapshot.metadata.entries.where(
        (entry) =>
            entry.key != 'next_quote_number' &&
            entry.key != 'next_receipt_number',
      )) {
        await tx.insert('app_metadata', {
          'key': entry.key,
          'value': entry.value,
        });
      }
      for (final item in snapshot.catalogItems) {
        await tx.insert('catalog_items', {
          'id': item.id,
          'concept': item.concept,
          'unit_price_cents': item.unitPriceCents,
          'times_used': item.timesUsed,
          'created_at': item.createdAt,
          'updated_at': item.updatedAt,
        });
      }
      final nextQuote = snapshot.quotes.fold<int>(
        1,
        (value, quote) => max(value, quote.quoteNumber + 1),
      );
      final nextReceipt = snapshot.quotes
          .expand((quote) => quote.payments)
          .fold<int>(
            1,
            (value, payment) => max(value, payment.receiptNumber + 1),
          );
      await tx.insert('app_metadata', {
        'key': 'next_quote_number',
        'value': '$nextQuote',
      });
      await tx.insert('app_metadata', {
        'key': 'next_receipt_number',
        'value': '$nextReceipt',
      });
    });
  } catch (_) {
    if (restoredLogoPath != null) {
      try {
        await File(restoredLogoPath).delete();
      } catch (_) {
        // Best effort cleanup; the database transaction has already rolled back.
      }
    }
    rethrow;
  }
}

void _validateSnapshot(BackupSnapshot snapshot) {
  if (snapshot.schemaVersion != 1) {
    throw Exception('El respaldo no es compatible.');
  }
  if (snapshot.clients.length > 100000 ||
      snapshot.quotes.length > 100000 ||
      snapshot.catalogItems.length > 100000) {
    throw Exception('El respaldo excede el tamaño permitido.');
  }
  final clientIds = <String>{};
  for (final client in snapshot.clients) {
    if (client.id.isEmpty ||
        client.name.trim().isEmpty ||
        !clientIds.add(client.id)) {
      throw Exception('El respaldo contiene clientes inválidos o duplicados.');
    }
  }
  final quoteIds = <String>{};
  final quoteNumbers = <int>{};
  final paymentIds = <String>{};
  final receiptNumbers = <int>{};
  final lineIds = <String>{};
  for (final quote in snapshot.quotes) {
    if (quote.id.isEmpty ||
        quote.quoteNumber <= 0 ||
        !quoteIds.add(quote.id) ||
        !quoteNumbers.add(quote.quoteNumber) ||
        (quote.clientId != null && !clientIds.contains(quote.clientId))) {
      throw Exception('El respaldo contiene cotizaciones inválidas.');
    }
    if (quoteTotal(quote.lines) != quote.totalCents || quote.totalCents < 0) {
      throw Exception(
        'El total de una cotización no coincide con sus conceptos.',
      );
    }
    for (final line in quote.lines) {
      if (line.id.isEmpty ||
          !lineIds.add(line.id) ||
          (quote.status != QuoteStatus.draft && line.concept.trim().isEmpty) ||
          !line.quantity.isFinite ||
          line.quantity <= 0 ||
          line.unitPriceCents < 0) {
        throw Exception('El respaldo contiene conceptos inválidos.');
      }
    }
    var paid = 0;
    for (final payment in quote.payments) {
      if (payment.id.isEmpty ||
          payment.quoteId != quote.id ||
          payment.receiptNumber <= 0 ||
          payment.amountCents <= 0 ||
          !paymentIds.add(payment.id) ||
          !receiptNumbers.add(payment.receiptNumber)) {
        throw Exception('El respaldo contiene pagos inválidos.');
      }
      if (payment.voidedAt == null) paid += payment.amountCents;
    }
    if (paid > quote.totalCents ||
        (paid > 0 && quote.status != QuoteStatus.accepted)) {
      throw Exception('Los pagos del respaldo no coinciden con la cotización.');
    }
  }
  final catalogIds = <String>{};
  final concepts = <String>{};
  for (final item in snapshot.catalogItems) {
    if (item.id.isEmpty ||
        item.concept.trim().isEmpty ||
        item.unitPriceCents < 0 ||
        item.timesUsed < 0 ||
        !catalogIds.add(item.id) ||
        !concepts.add(item.concept.trim().toLowerCase())) {
      throw Exception('El respaldo contiene conceptos de catálogo inválidos.');
    }
  }
}
