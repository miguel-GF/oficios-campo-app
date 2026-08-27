import * as Crypto from 'expo-crypto';
import * as DocumentPicker from 'expo-document-picker';
import { Directory, File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import type { SQLiteDatabase } from 'expo-sqlite';
import { decryptBackup, encryptBackup } from './backup-format';
import { exportSnapshot, importSnapshot } from './database';

const brandingDirectory = new Directory(Paths.document, 'branding');
const businessLogo = () => new File(brandingDirectory, 'business-logo');

export function clearBusinessLogo() {
  const logo = businessLogo();
  if (logo.exists) logo.delete();
}

export async function persistBusinessLogo(sourceUri: string) {
  brandingDirectory.create({ intermediates: true, idempotent: true });
  const destination = businessLogo();
  await new File(sourceUri).copy(destination, { overwrite: true });
  return destination.uri;
}

async function addLogoToSnapshot(snapshot: Awaited<ReturnType<typeof exportSnapshot>>) {
  const uri = snapshot.businessProfile?.logoUri;
  if (uri) {
    const logo = new File(uri);
    if (logo.exists) snapshot.logoBase64 = await logo.base64();
  }
  return snapshot;
}

export async function exportEncryptedBackup(db: SQLiteDatabase, password: string) {
  const snapshot = await addLogoToSnapshot(await exportSnapshot(db));
  const value = await encryptBackup(snapshot, password, Crypto.getRandomBytes(16), Crypto.getRandomBytes(12));
  const backup = new File(Paths.cache, `jale-backup-${Date.now()}.jale-backup`);
  backup.create({ intermediates: true, overwrite: true });
  backup.write(value);
  if (!(await Sharing.isAvailableAsync())) throw new Error('No se puede compartir archivos en este dispositivo.');
  await Sharing.shareAsync(backup.uri, { mimeType: 'application/octet-stream', dialogTitle: 'Guardar respaldo cifrado de Jale' });
  return backup.uri;
}

export async function importEncryptedBackup(db: SQLiteDatabase, password: string) {
  const selection = await DocumentPicker.getDocumentAsync({ type: '*/*', copyToCacheDirectory: true, multiple: false });
  if (selection.canceled) return null;
  const asset = selection.assets[0];
  if (!asset) return null;
  const value = await new File(asset.uri).text();
  const snapshot = await decryptBackup(value, password);
  if (snapshot.logoBase64 && snapshot.businessProfile) {
    brandingDirectory.create({ intermediates: true, idempotent: true });
    const logo = businessLogo();
    logo.create({ intermediates: true, overwrite: true });
    logo.write(snapshot.logoBase64, { encoding: 'base64' });
    snapshot.businessProfile.logoUri = logo.uri;
  }
  await importSnapshot(db, snapshot);
  return snapshot;
}
