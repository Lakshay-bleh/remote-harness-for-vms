import { copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export type RegistryEntry = {
  sessionId: string;
  cwd: string;
  title: string;
  createdAt: string;
  accountId: string;
  /** 'terminal' = a Claude Code session started outside the agent and imported by TerminalSessionSync. */
  source?: 'terminal';
  /** Last transcript message the hub has, so a session continued in the terminal only sends what is new. */
  syncedUuid?: string;
  /** Transcript mtime at the last sync; an unchanged file is not re-read. */
  syncedMtime?: number;
};

const isEntry = (e: unknown): e is RegistryEntry =>
  typeof e === 'object' && e !== null &&
  ['sessionId', 'cwd', 'title', 'createdAt', 'accountId'].every((k) => typeof (e as Record<string, unknown>)[k] === 'string');

function readEntries(path: string): RegistryEntry[] {
  const raw = JSON.parse(readFileSync(path, 'utf-8'));
  if (!Array.isArray(raw)) throw new Error('registry is not an array');
  return raw.filter(isEntry);
}

export class SessionRegistry {
  private path: string;
  private entries = new Map<string, RegistryEntry>();

  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true });
    this.path = join(dataDir, 'sessions.json');
    for (const e of this.load()) this.entries.set(e.sessionId, e);
  }

  // A corrupt registry used to be treated as empty, which silently turned "resume" into a brand-new
  // conversation with no history. Fall back to the previous good copy, and never discard a file we
  // couldn't read: quarantine it so it can be recovered by hand.
  private load(): RegistryEntry[] {
    const bak = `${this.path}.bak`;
    if (existsSync(this.path)) {
      try {
        return readEntries(this.path);
      } catch (err) {
        console.error(`[registry] ${this.path} unreadable (${err instanceof Error ? err.message : err})`);
        if (existsSync(bak)) {
          try {
            const recovered = readEntries(bak);
            console.error('[registry] recovered sessions from backup');
            this.quarantine();
            return recovered;
          } catch {
            // fall through to quarantine
          }
        }
        this.quarantine();
        return [];
      }
    }
    if (existsSync(bak)) {
      try {
        return readEntries(bak);
      } catch {
        return [];
      }
    }
    return [];
  }

  private quarantine(): void {
    const dest = `${this.path}.corrupt-${Date.now()}`;
    try {
      renameSync(this.path, dest);
      console.error(`[registry] kept unreadable file as ${dest}`);
    } catch {
      // already gone
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

  // Write to a temp file and rename, so a crash mid-write can never leave a truncated sessions.json.
  private persist(): void {
    const tmp = `${this.path}.tmp`;
    writeFileSync(tmp, JSON.stringify(this.all(), null, 2), { mode: 0o600 });
    if (existsSync(this.path)) copyFileSync(this.path, `${this.path}.bak`);
    renameSync(tmp, this.path);
  }
}
