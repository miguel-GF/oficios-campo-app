import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'domain.dart';

Map<String, dynamic> _profileJson(BusinessProfile value) => {
  'id': value.id,
  'name': value.name,
  'trade': value.trade,
  'phone': value.phone,
  'logoUri': value.logoUri,
  'iconKey': value.iconKey,
  'brandColor': value.brandColor,
  'createdAt': value.createdAt,
  'updatedAt': value.updatedAt,
};
Map<String, dynamic> _clientJson(Client value) => {
  'id': value.id,
  'name': value.name,
  'phone': value.phone,
  'address': value.address,
  'notes': value.notes,
  'createdAt': value.createdAt,
  'updatedAt': value.updatedAt,
};
Map<String, dynamic> _catalogItemJson(CatalogItem value) => {
  'id': value.id,
  'concept': value.concept,
  'unitPriceCents': value.unitPriceCents,
  'timesUsed': value.timesUsed,
  'createdAt': value.createdAt,
  'updatedAt': value.updatedAt,
};
Map<String, dynamic> _lineJson(QuoteLine value) => {
  'id': value.id,
  'concept': value.concept,
  'quantity': value.quantity,
  'unitPriceCents': value.unitPriceCents,
  'position': value.position,
};
Map<String, dynamic> _paymentJson(Payment value) => {
  'id': value.id,
  'quoteId': value.quoteId,
  'receiptNumber': value.receiptNumber,
  'method': value.method.name,
  'amountCents': value.amountCents,
  'paidAt': value.paidAt,
  'notes': value.notes,
  'voidedAt': value.voidedAt,
  'receiptFinalizedAt': value.receiptFinalizedAt,
  'quotaPeriod': value.quotaPeriod,
};
Map<String, dynamic> _quoteJson(Quote value) => {
  'id': value.id,
  'quoteNumber': value.quoteNumber,
  'clientId': value.clientId,
  'clientName': value.clientName,
  'clientPhone': value.clientPhone,
  'clientAddress': value.clientAddress,
  'status': value.status.name,
  'origin': value.origin.name,
  'issuedAt': value.issuedAt,
  'validUntil': value.validUntil,
  'notes': value.notes,
  'totalCents': value.totalCents,
  'finalizedAt': value.finalizedAt,
  'quotaPeriod': value.quotaPeriod,
  'createdAt': value.createdAt,
  'updatedAt': value.updatedAt,
  'lines': value.lines.map(_lineJson).toList(),
  'payments': value.payments.map(_paymentJson).toList(),
};

String _requiredString(Map<String, dynamic> value, String key) =>
    value[key] as String;
BusinessProfile _profileFromJson(Map<String, dynamic> value) => BusinessProfile(
  id: _requiredString(value, 'id'),
  name: _requiredString(value, 'name'),
  trade: _requiredString(value, 'trade'),
  phone: _requiredString(value, 'phone'),
  logoUri: value['logoUri'] as String?,
  iconKey: value['iconKey'] as String?,
  brandColor: _requiredString(value, 'brandColor'),
  createdAt: _requiredString(value, 'createdAt'),
  updatedAt: _requiredString(value, 'updatedAt'),
);
Client _clientFromJson(Map<String, dynamic> value) => Client(
  id: _requiredString(value, 'id'),
  name: _requiredString(value, 'name'),
  phone: _requiredString(value, 'phone'),
  address: _requiredString(value, 'address'),
  notes: _requiredString(value, 'notes'),
  createdAt: _requiredString(value, 'createdAt'),
  updatedAt: _requiredString(value, 'updatedAt'),
);
CatalogItem _catalogItemFromJson(Map<String, dynamic> value) => CatalogItem(
  id: _requiredString(value, 'id'),
  concept: _requiredString(value, 'concept'),
  unitPriceCents: value['unitPriceCents'] as int,
  timesUsed: value['timesUsed'] as int? ?? 0,
  createdAt: _requiredString(value, 'createdAt'),
  updatedAt: _requiredString(value, 'updatedAt'),
);
QuoteLine _lineFromJson(Map<String, dynamic> value) => QuoteLine(
  id: _requiredString(value, 'id'),
  concept: _requiredString(value, 'concept'),
  quantity: (value['quantity'] as num).toDouble(),
  unitPriceCents: value['unitPriceCents'] as int,
  position: value['position'] as int,
);
Payment _paymentFromJson(Map<String, dynamic> value) => Payment(
  id: _requiredString(value, 'id'),
  quoteId: _requiredString(value, 'quoteId'),
  receiptNumber: value['receiptNumber'] as int,
  method: paymentMethodFrom(_requiredString(value, 'method')),
  amountCents: value['amountCents'] as int,
  paidAt: _requiredString(value, 'paidAt'),
  notes: _requiredString(value, 'notes'),
  voidedAt: value['voidedAt'] as String?,
  receiptFinalizedAt: value['receiptFinalizedAt'] as String?,
  quotaPeriod: value['quotaPeriod'] as String?,
);
Quote _quoteFromJson(Map<String, dynamic> value) => Quote(
  id: _requiredString(value, 'id'),
  quoteNumber: value['quoteNumber'] as int,
  clientId: value['clientId'] as String?,
  clientName: _requiredString(value, 'clientName'),
  clientPhone: value['clientPhone'] as String? ?? '',
  clientAddress: value['clientAddress'] as String? ?? '',
  status: quoteStatusFrom(_requiredString(value, 'status')),
  origin: QuoteOrigin.values.firstWhere(
    (item) => item.name == (value['origin'] as String? ?? 'manual'),
    orElse: () => QuoteOrigin.manual,
  ),
  issuedAt: _requiredString(value, 'issuedAt'),
  validUntil: value['validUntil'] as String?,
  notes: _requiredString(value, 'notes'),
  totalCents: value['totalCents'] as int,
  finalizedAt: value['finalizedAt'] as String?,
  quotaPeriod: value['quotaPeriod'] as String?,
  createdAt: _requiredString(value, 'createdAt'),
  updatedAt: _requiredString(value, 'updatedAt'),
  lines: (value['lines'] as List)
      .map((item) => _lineFromJson(Map<String, dynamic>.from(item as Map)))
      .toList(),
  payments: (value['payments'] as List)
      .map((item) => _paymentFromJson(Map<String, dynamic>.from(item as Map)))
      .toList(),
);

Map<String, dynamic> snapshotJson(BackupSnapshot value) => {
  'schemaVersion': value.schemaVersion,
  'exportedAt': value.exportedAt,
  'businessProfile': value.businessProfile == null
      ? null
      : _profileJson(value.businessProfile!),
  'clients': value.clients.map(_clientJson).toList(),
  'quotes': value.quotes.map(_quoteJson).toList(),
  'metadata': value.metadata,
  'catalogItems': value.catalogItems.map(_catalogItemJson).toList(),
  if (value.logoBase64 != null) 'logoBase64': value.logoBase64,
};
BackupSnapshot snapshotFromJson(Map<String, dynamic> value) => BackupSnapshot(
  schemaVersion: value['schemaVersion'] as int,
  exportedAt: _requiredString(value, 'exportedAt'),
  businessProfile: value['businessProfile'] == null
      ? null
      : _profileFromJson(
          Map<String, dynamic>.from(value['businessProfile'] as Map),
        ),
  clients: (value['clients'] as List)
      .map((item) => _clientFromJson(Map<String, dynamic>.from(item as Map)))
      .toList(),
  quotes: (value['quotes'] as List)
      .map((item) => _quoteFromJson(Map<String, dynamic>.from(item as Map)))
      .toList(),
  metadata: Map<String, String>.from(value['metadata'] as Map),
  logoBase64: value['logoBase64'] as String?,
  catalogItems: (value['catalogItems'] as List? ?? const [])
      .map(
        (item) => _catalogItemFromJson(Map<String, dynamic>.from(item as Map)),
      )
      .toList(),
);

const _iterations = 60000;
String _b64(List<int> value) => base64Encode(value);
List<int> _unb64(String value) => base64Decode(value);

Future<String> encryptBackup(
  BackupSnapshot snapshot,
  String password, {
  List<int>? salt,
  List<int>? nonce,
}) async {
  if (password.length < 8) {
    throw Exception('La contraseña debe tener al menos 8 caracteres.');
  }
  final random = Random.secure();
  final actualSalt = salt ?? List<int>.generate(16, (_) => random.nextInt(256));
  final actualNonce =
      nonce ?? List<int>.generate(12, (_) => random.nextInt(256));
  if (actualSalt.length != 16 || actualNonce.length != 12) {
    throw Exception('No se pudo crear material criptográfico seguro.');
  }
  final kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: 256,
  );
  final key = await kdf.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: actualSalt,
  );
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(jsonEncode(snapshotJson(snapshot))),
    secretKey: key,
    nonce: actualNonce,
  );
  return jsonEncode({
    'magic': 'JALE_BACKUP',
    'formatVersion': 1,
    'kdf': {
      'name': 'PBKDF2-SHA256',
      'iterations': _iterations,
      'salt': _b64(actualSalt),
    },
    'cipher': {
      'name': 'AES-256-GCM',
      'nonce': _b64(actualNonce),
      'ciphertext': _b64([...box.cipherText, ...box.mac.bytes]),
    },
  });
}

Future<BackupSnapshot> decryptBackup(String value, String password) async {
  try {
    if (value.length > 70 * 1024 * 1024) throw Exception('invalid');
    final envelope = jsonDecode(value) as Map<String, dynamic>;
    final kdf = envelope['kdf'] as Map<String, dynamic>,
        cipher = envelope['cipher'] as Map<String, dynamic>;
    if (envelope['magic'] != 'JALE_BACKUP' ||
        envelope['formatVersion'] != 1 ||
        kdf['name'] != 'PBKDF2-SHA256' ||
        cipher['name'] != 'AES-256-GCM') {
      throw Exception('invalid');
    }
    final iterations = kdf['iterations'] as int;
    if (iterations < 10000 || iterations > 1000000) throw Exception('invalid');
    final salt = _unb64(kdf['salt'] as String),
        nonce = _unb64(cipher['nonce'] as String),
        combined = _unb64(cipher['ciphertext'] as String);
    if (salt.length != 16 || nonce.length != 12 || combined.length < 16) {
      throw Exception('invalid');
    }
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        combined.sublist(0, combined.length - 16),
        nonce: nonce,
        mac: Mac(combined.sublist(combined.length - 16)),
      ),
      secretKey: key,
    );
    final snapshot = snapshotFromJson(
      jsonDecode(utf8.decode(plain)) as Map<String, dynamic>,
    );
    if (snapshot.schemaVersion != 1) throw Exception('invalid');
    return snapshot;
  } catch (_) {
    throw Exception('La contraseña es incorrecta o el respaldo está dañado.');
  }
}
