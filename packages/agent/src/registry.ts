import { mkdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

export type RegistryEntry = {
  sessionId: string;
  cwd: string;
  title: string;
  createdAt: string;
  accountId: string;
};

export class SessionRegistry {
  private path: string;
  private entries = new Map<string, RegistryEntry>();

  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true });
    this.path = join(dataDir, 'sessions.json');
    if (existsSync(this.path)) {
      try {
        const raw = JSON.parse(readFileSync(this.path, 'utf-8')) as RegistryEntry[];
        for (const e of raw) this.entries.set(e.sessionId, e);
      } catch {
        // corrupt or empty file, start fresh
      }
    }
  }

  all(): RegistryEntry[] {
    return [...this.entries.values()];
  }

  get(sessionId: string): RegistryEntry | undefined {
    return this.entries.get(sessionId);
  }

  upsert(entry: RegistryEntry): void {
    this.entries.set(entry.sessionId, entry);
    this.persist();
  }

  private persist(): void {
    writeFileSync(this.path, JSON.stringify(this.all(), null, 2));
  }
}
