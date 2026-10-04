import { Archive, Tray, DotsThree, MagnifyingGlass, PencilSimple, PushPin, PushPinSlash, Trash, X } from '@phosphor-icons/react';
import { useEffect, useMemo, useState } from 'react';
import { organise, prune, rename, toggleArchived, togglePinned, updateMeta, useChatMeta, type ChatItem, type ChatRow } from './chatMeta';
import { haptic } from './settings/prefs';
import { Button, Sheet } from './ui';

interface Props {
  chats: ChatItem[];
  activeId: string | null;
  onOpen: (id: string) => void;
  onDelete: (id: string, name: string) => void;
  /** When false (the narrow icon rail) nothing is drawn. */
  visible?: boolean;
  /** Show the empty-state hint. */
  hint?: boolean;
}

/** Your assistant chats, organised like any chat app: search, pinned on top, then by recency, with a menu on each. */
export default function ChatList({ chats, activeId, onOpen, onDelete, hint }: Props) {
  const meta = useChatMeta();
  const [query, setQuery] = useState('');
  const [showArchived, setShowArchived] = useState(false);
  const [menu, setMenu] = useState<ChatRow | null>(null);
  const [renaming, setRenaming] = useState<ChatRow | null>(null);
  const [name, setName] = useState('');

  // Forget organisation for chats that no longer exist; wait for a real list so a failed load does not wipe it.
  useEffect(() => {
    if (chats.length > 0) updateMeta((m) => prune(m, chats.map((c) => c.id)));
  }, [chats]);

  const sections = useMemo(() => organise(chats, meta, { query, showArchived }), [chats, meta, query, showArchived]);
  const archivedCount = meta.archived.filter((id) => chats.some((c) => c.id === id)).length;
  const searching = query.trim().length > 0;

  const act = (fn: () => void) => () => { haptic(); fn(); setMenu(null); };

  return (
    <>
      {chats.length > 3 && (
        <div className="px-3 pb-2">
          <label className="flex items-center gap-2 rounded-pill border border-line-strong bg-surface-dark-soft px-3 py-2 focus-within:border-primary/60">
            <MagnifyingGlass size={16} className="shrink-0 text-muted" aria-hidden />
            <input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search chats" aria-label="Search chats" autoCapitalize="none" autoCorrect="off" spellCheck={false} className="min-w-0 flex-1 bg-transparent text-[14px] text-ink outline-none placeholder:text-muted-soft" />
            {query && <button type="button" onClick={() => setQuery('')} aria-label="Clear search" className="shrink-0 text-muted hover:text-ink"><X size={14} /></button>}
          </label>
        </div>
      )}

      <div className="min-h-0 flex-1 overflow-y-auto px-3">
        {chats.length === 0 && hint && <p className="px-3.5 py-2 text-sm text-muted">Your chats will show up here.</p>}
        {searching && sections.length === 0 && <p className="px-3.5 py-3 text-sm text-muted">No chats match “{query.trim()}”.</p>}
        {sections.map((s) => (
          <section key={s.key} aria-label={s.label} className="pb-1.5">
            <h2 className="flex items-center gap-1.5 px-3.5 pb-1 pt-2 text-[12px] font-medium text-muted">{s.key === 'pinned' && <PushPin size={12} weight="fill" aria-hidden />}{s.label}</h2>
            <ul className="space-y-0.5">
              {s.rows.map((c) => {
                const active = c.id === activeId;
                return (
                  <li key={c.id} className={`group relative rounded-pill transition ${active ? 'bg-surface-card' : 'hover:bg-surface-card/60'}`}>
                    <button onClick={() => onOpen(c.id)} className={`block w-full truncate rounded-pill py-2.5 pl-3.5 pr-11 text-left text-[14px] outline-none focus-visible:ring-2 focus-visible:ring-primary/50 ${active ? 'text-ink' : 'text-body group-hover:text-ink'}`}>{c.name}</button>
                    <button onClick={() => setMenu(c)} aria-label={`Options for ${c.name}`} aria-haspopup="dialog" className="absolute right-1 top-1/2 flex h-9 w-9 -translate-y-1/2 items-center justify-center rounded-full text-muted transition hover:bg-surface-strong hover:text-ink md:opacity-0 md:group-hover:opacity-100 md:focus-visible:opacity-100"><DotsThree size={20} weight="bold" /></button>
                  </li>
                );
              })}
            </ul>
          </section>
        ))}
        {!searching && archivedCount > 0 && (
          <button onClick={() => setShowArchived((v) => !v)} className="mb-2 flex w-full items-center gap-2 rounded-pill px-3.5 py-2 text-[13px] text-muted transition hover:bg-surface-card/60 hover:text-ink"><Tray size={16} aria-hidden />{showArchived ? 'Hide archived' : `Archived (${archivedCount})`}</button>
        )}
      </div>

      {menu && (
        <Sheet title={menu.name.length > 40 ? `${menu.name.slice(0, 40)}…` : menu.name} onClose={() => setMenu(null)}>
          <ul className="-mx-1 divide-y divide-hairline">
            <MenuItem icon={menu.pinned ? <PushPinSlash size={20} /> : <PushPin size={20} />} label={menu.pinned ? 'Unpin' : 'Pin to the top'} onClick={act(() => updateMeta((m) => togglePinned(m, menu.id)))} disabled={menu.archived} />
            <MenuItem icon={<PencilSimple size={20} />} label="Rename" onClick={() => { setName(menu.name); setRenaming(menu); setMenu(null); }} />
            <MenuItem icon={menu.archived ? <Tray size={20} /> : <Archive size={20} />} label={menu.archived ? 'Move back to chats' : 'Archive'} onClick={act(() => updateMeta((m) => toggleArchived(m, menu.id)))} />
            <MenuItem icon={<Trash size={20} />} label="Delete" danger onClick={act(() => onDelete(menu.id, menu.name))} />
          </ul>
        </Sheet>
      )}
      {renaming && (
        <Sheet title="Rename chat" onClose={() => setRenaming(null)}>
          <form className="space-y-3" onSubmit={(e) => { e.preventDefault(); updateMeta((m) => rename(m, renaming.id, name)); setRenaming(null); }}>
            <input value={name} onChange={(e) => setName(e.target.value)} maxLength={80} autoFocus aria-label="Chat name" placeholder={renaming.title} className="w-full rounded-md border border-line-strong bg-surface-card px-3 py-3 text-[15px] text-ink outline-none focus:border-primary focus:ring-4 focus:ring-primary/15" />
            <p className="text-[12px] text-muted">Leave it empty to go back to the name Escanor gave it. Names are saved on this phone.</p>
            <Button type="submit" className="w-full">Save</Button>
          </form>
        </Sheet>
      )}
    </>
  );
}

function MenuItem({ icon, label, onClick, danger, disabled }: { icon: React.ReactNode; label: string; onClick: () => void; danger?: boolean; disabled?: boolean }) {
  return (
    <li>
      <button type="button" onClick={onClick} disabled={disabled} className={`flex w-full items-center gap-3 px-1 py-3.5 text-left text-[15px] transition active:bg-surface-card disabled:opacity-40 ${danger ? 'text-error' : 'text-ink'}`}>
        <span className={danger ? '' : 'text-body'}>{icon}</span>{label}
      </button>
    </li>
  );
}
