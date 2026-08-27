import test from 'node:test';
import assert from 'node:assert/strict';
import { decryptBackup, encryptBackup } from '../src/backup-format';
import type { BackupSnapshot } from '../src/domain';

const snapshot: BackupSnapshot = { schemaVersion: 1, exportedAt: '2026-08-09T00:00:00Z', businessProfile: null, clients: [], quotes: [], metadata: { next_quote_number: '4' } };
const salt = new Uint8Array(16).fill(7); const nonce = new Uint8Array(12).fill(9);

test('cifra y descifra un respaldo versionado', async () => {
  const encrypted = await encryptBackup(snapshot, 'secreto-seguro', salt, nonce);
  assert.equal(encrypted.includes('next_quote_number'), false);
  assert.deepEqual(await decryptBackup(encrypted, 'secreto-seguro'), snapshot);
});

test('rechaza contraseña incorrecta y archivos manipulados', async () => {
  const encrypted = await encryptBackup(snapshot, 'secreto-seguro', salt, nonce);
  await assert.rejects(() => decryptBackup(encrypted, 'otra-clave'), /incorrecta|dañado/);
  const parsed = JSON.parse(encrypted); parsed.cipher.ciphertext = `${parsed.cipher.ciphertext.slice(0, -3)}AAA`;
  await assert.rejects(() => decryptBackup(JSON.stringify(parsed), 'secreto-seguro'), /incorrecta|dañado/);
});
