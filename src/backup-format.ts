import { gcm } from '@noble/ciphers/aes.js';
import { pbkdf2Async } from '@noble/hashes/pbkdf2.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { utf8ToBytes } from '@noble/hashes/utils.js';
import type { BackupSnapshot } from './domain';

const FORMAT_VERSION = 1;
// Noble runs PBKDF2 in JavaScript. This keeps password derivation deliberate
// without turning a manual backup into a multi-second UI freeze on low-end phones.
const KDF_ITERATIONS = 60_000;

type BackupEnvelope = {
  magic: 'JALE_BACKUP';
  formatVersion: 1;
  kdf: { name: 'PBKDF2-SHA256'; iterations: number; salt: string };
  cipher: { name: 'AES-256-GCM'; nonce: string; ciphertext: string };
};

function bytesToBase64(bytes: Uint8Array) {
  let binary = '';
  for (let offset = 0; offset < bytes.length; offset += 8192) binary += String.fromCharCode(...bytes.subarray(offset, offset + 8192));
  return btoa(binary);
}

function base64ToBytes(value: string) {
  const binary = atob(value); const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

function parseEnvelope(value: string): BackupEnvelope {
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { throw new Error('El archivo no es un respaldo válido de Jale.'); }
  const envelope = parsed as Partial<BackupEnvelope>;
  if (envelope.magic !== 'JALE_BACKUP' || envelope.formatVersion !== FORMAT_VERSION || envelope.kdf?.name !== 'PBKDF2-SHA256' || envelope.cipher?.name !== 'AES-256-GCM' || !envelope.kdf.salt || !envelope.cipher.nonce || !envelope.cipher.ciphertext || !Number.isInteger(envelope.kdf.iterations) || envelope.kdf.iterations < 10_000 || envelope.kdf.iterations > 1_000_000) throw new Error('El respaldo no es compatible con esta versión de Jale.');
  return envelope as BackupEnvelope;
}

export async function encryptBackup(snapshot: BackupSnapshot, password: string, salt: Uint8Array, nonce: Uint8Array) {
  if (password.length < 8) throw new Error('La contraseña debe tener al menos 8 caracteres.');
  if (salt.length !== 16 || nonce.length !== 12) throw new Error('No se pudo crear material criptográfico seguro.');
  const key = await pbkdf2Async(sha256, utf8ToBytes(password), salt, { c: KDF_ITERATIONS, dkLen: 32 });
  const plaintext = utf8ToBytes(JSON.stringify(snapshot));
  const ciphertext = gcm(key, nonce).encrypt(plaintext);
  const envelope: BackupEnvelope = { magic: 'JALE_BACKUP', formatVersion: FORMAT_VERSION, kdf: { name: 'PBKDF2-SHA256', iterations: KDF_ITERATIONS, salt: bytesToBase64(salt) }, cipher: { name: 'AES-256-GCM', nonce: bytesToBase64(nonce), ciphertext: bytesToBase64(ciphertext) } };
  return JSON.stringify(envelope);
}

export async function decryptBackup(value: string, password: string): Promise<BackupSnapshot> {
  const envelope = parseEnvelope(value);
  try {
    const salt = base64ToBytes(envelope.kdf.salt); const nonce = base64ToBytes(envelope.cipher.nonce);
    const key = await pbkdf2Async(sha256, utf8ToBytes(password), salt, { c: envelope.kdf.iterations, dkLen: 32 });
    const plaintext = gcm(key, nonce).decrypt(base64ToBytes(envelope.cipher.ciphertext));
    const snapshot = JSON.parse(new TextDecoder().decode(plaintext)) as BackupSnapshot;
    if (snapshot.schemaVersion !== 1 || !Array.isArray(snapshot.clients) || !Array.isArray(snapshot.quotes)) throw new Error('invalid');
    return snapshot;
  } catch { throw new Error('La contraseña es incorrecta o el respaldo está dañado.'); }
}
