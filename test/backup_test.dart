import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:jale_app/backup_format.dart';
import 'package:jale_app/domain.dart';

void main() {
  final snapshot = BackupSnapshot(
    schemaVersion: 1,
    exportedAt: '2026-08-09T00:00:00Z',
    businessProfile: const BusinessProfile(
      id: 'business-1',
      name: 'Jale Demo',
      trade: 'Electricidad',
      phone: '5550000000',
      logoUri: null,
      iconKey: 'bolt',
      brandColor: '#215A8E',
      createdAt: '2026-08-09T00:00:00Z',
      updatedAt: '2026-08-09T00:00:00Z',
    ),
    clients: const [],
    quotes: const [],
    metadata: const {'next_quote_number': '4'},
    catalogItems: const [
      CatalogItem(
        id: 'catalog-1',
        concept: 'Pintura exterior',
        unitPriceCents: 8500,
        timesUsed: 3,
        createdAt: '2026-08-09T00:00:00Z',
        updatedAt: '2026-08-09T00:00:00Z',
      ),
    ],
  );
  test('cifra y descifra un respaldo versionado', () async {
    final encrypted = await encryptBackup(
      snapshot,
      'secreto-seguro',
      salt: Uint8List(16),
      nonce: Uint8List(12),
    );
    expect(encrypted, isNot(contains('next_quote_number')));
    final restored = await decryptBackup(encrypted, 'secreto-seguro');
    expect(restored.metadata, snapshot.metadata);
    expect(restored.businessProfile?.iconKey, 'bolt');
    expect(restored.catalogItems.single.unitPriceCents, 8500);
    expect(restored.catalogItems.single.timesUsed, 3);
  });
  test('rechaza una contrasena incorrecta', () async {
    final encrypted = await encryptBackup(snapshot, 'secreto-seguro');
    expect(decryptBackup(encrypted, 'otra-clave'), throwsA(isA<Exception>()));
  });
}
