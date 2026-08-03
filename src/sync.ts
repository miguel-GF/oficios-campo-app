import type { SQLiteDatabase } from 'expo-sqlite';
import * as FileSystem from 'expo-file-system/legacy';
import { applyRemoteSnapshot, listQueue, markQueueDone, markQueueFailed, setAttachmentRemotePath } from './database';

export type SyncResult = { configured: boolean; sent: number; failed: number };

/**
 * Sends the durable local outbox to one Supabase Edge Function. The function is
 * deliberately the only server contract: service-role credentials never ship
 * in the application and the local-first app remains usable without env vars.
 */
export async function syncPending(db: SQLiteDatabase, accessToken?: string): Promise<SyncResult> {
  const url = process.env.EXPO_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey || !accessToken) return { configured: false, sent: 0, failed: 0 };
  const queue = await listQueue(db); let sent = 0; let failed = 0;
  for (const item of queue) {
    try {
      const payload = JSON.parse(item.payload);
      if (item.tableName === 'attachments' && payload.localUri && !payload.remotePath) {
        const ticket = await fetch(`${url}/functions/v1/evidence-upload`, { method: 'POST', headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ orderId: payload.orderId, attachmentId: payload.id, contentType: 'image/jpeg' }) });
        if (!ticket.ok) throw new Error(`No se pudo preparar evidencia: ${ticket.status}`);
        const { signedUrl, path } = await ticket.json();
        const upload = await FileSystem.uploadAsync(signedUrl, payload.localUri, { httpMethod: 'PUT', uploadType: FileSystem.FileSystemUploadType.BINARY_CONTENT, headers: { 'Content-Type': 'image/jpeg' } });
        if (upload.status < 200 || upload.status >= 300) throw new Error(`No se pudo subir evidencia: ${upload.status}`);
        payload.remotePath = path; delete payload.localUri; await setAttachmentRemotePath(db, payload.id, path);
      }
      const response = await fetch(`${url}/functions/v1/sync`, {
        method: 'POST',
        headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ idempotencyKey: item.id, table: item.tableName, entityId: item.entityId, operation: item.operation, payload }),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}: ${(await response.text()).slice(0, 200)}`);
      await markQueueDone(db, item.id); sent += 1;
    } catch (error) {
      await markQueueFailed(db, item.id, error instanceof Error ? error.message : String(error)); failed += 1;
    }
  }
  if (failed === 0) {
    try {
      const response = await fetch(`${url}/functions/v1/pull`, { headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` } });
      if (!response.ok) throw new Error(`Pull HTTP ${response.status}`); const body = await response.json();
      await applyRemoteSnapshot(db, body.snapshot, body.pulledAt);
    } catch (error) { failed += 1; }
  }
  return { configured: true, sent, failed };
}
