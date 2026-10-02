import { createCipheriv, createDecipheriv, hkdfSync, randomBytes } from 'node:crypto';

// AES-256-GCM for secrets the hub must be able to read back (the MCP bearer token it pushes to VMs).
// This protects the SQLite file (backups, copies, SQL-level reads) — not a process that has the key.
const PREFIX = 'enc:v1:';

export function deriveKey(secret: string): Buffer {
  return Buffer.from(hkdfSync('sha256', secret, 'remote-harness-hub', 'secretbox-v1', 32));
}

export const isSealed = (v: string): boolean => v.startsWith(PREFIX);

export function seal(key: Buffer, plaintext: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  return `${PREFIX}${iv.toString('base64')}:${cipher.getAuthTag().toString('base64')}:${ct.toString('base64')}`;
}

export function open(key: Buffer, boxed: string): string {
  if (!isSealed(boxed)) throw new Error('not a sealed value');
  const [iv, tag, ct] = boxed.slice(PREFIX.length).split(':').map((p) => Buffer.from(p, 'base64'));
  const decipher = createDecipheriv('aes-256-gcm', key, iv);
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ct), decipher.final()]).toString('utf8');
}
