import { Laptop, PencilSimple, Plus, Trash } from '@phosphor-icons/react';
import { useState } from 'react';
import { DogState } from '../dog/DogState';
import { OverflowMenu } from '../Menu';
import { dropCache } from '../cache';
import { ConfirmSheet } from '../settings/parts';
import { forgetChats } from './chatStore';
import { Button, ScreenHeader } from '../ui';
import { displayName, forgetComputerPrefs, setComputerPrefs, useComputerPrefs } from './computerPrefs';
import RenameSheet from './RenameSheet';
import ComputerDetail from './ComputerDetail';
import PairSheet from './PairSheet';
import { loadComputers, removeComputer, saveComputer } from './storage';
import type { PairedComputer } from './lib/client';

/** One computer in the list: its name, how it was paired, and its own menu. */
function Card({ c, onOpen, onRemove }: { c: PairedComputer; onOpen: () => void; onRemove: () => void }) {
  const prefs = useComputerPrefs(c.id);
  const [sheet, setSheet] = useState<'rename' | 'remove' | null>(null);
  const name = displayName(c, prefs);
  return (
    <li className="flex items-center rounded-xl border border-hairline bg-surface-card pr-1 transition hover:border-primary/40">
      <button onClick={onOpen} className="flex min-w-0 flex-1 items-center gap-3 p-4 text-left">
        <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-canvas text-muted"><Laptop size={22} /></span>
        <span className="min-w-0"><span className="block truncate text-[15px] font-medium text-ink">{name}</span><span className="block text-[12px] text-muted">Paired {new Date(c.pairedAt).toLocaleDateString()}{c.agentId ? ' · works away from home' : ' · on your Wi-Fi'}</span></span>
      </button>
      <OverflowMenu label={`Options for ${name}`} items={[{ label: 'Open', onClick: onOpen }, { label: 'Rename', icon: <PencilSimple size={18} />, onClick: () => setSheet('rename') }, { label: 'Forget this computer', icon: <Trash size={18} />, danger: true, divider: true, onClick: () => setSheet('remove') }]} />
      {sheet === 'rename' && <RenameSheet current={prefs.alias} original={c.name} onSave={(alias) => setComputerPrefs(c.id, { alias })} onClose={() => setSheet(null)} />}
      {sheet === 'remove' && <ConfirmSheet title={`Forget ${name}?`} body="This phone will no longer control it. You can pair it again any time with a new code." action="Forget" onConfirm={() => (forgetComputerPrefs(c.id), forgetChats(c.id), dropCache(`computer:${c.id}:`), onRemove())} onClose={() => setSheet(null)} />}
    </li>
  );
}

/** Your own computers running Escanor Desktop: pair one, then watch and control it from here. */
export default function ComputersView() {
  const [computers, setComputers] = useState<PairedComputer[]>(loadComputers);
  const [openId, setOpenId] = useState<string | null>(null);
  const [pairing, setPairing] = useState(false);
  const open = computers.find((c) => c.id === openId);

  if (open) return <ComputerDetail computer={open} onBack={() => setOpenId(null)} onRemove={() => (setComputers(removeComputer(open.id)), setOpenId(null))} />;

  return (
    <div className="flex h-full min-h-0 flex-col">
      <ScreenHeader title="Computers"><Button onClick={() => setPairing(true)} className="inline-flex items-center gap-1.5 whitespace-nowrap !px-4"><Plus size={16} weight="bold" /> Add</Button></ScreenHeader>
      <div className="min-h-0 flex-1 overflow-y-auto px-4 pb-6">
        {computers.length === 0 ? (
          <DogState
            scene="sleep"
            title="Waiting for your computer"
            text="Install Escanor Desktop on your computer and pair it here. Everything runs on that computer’s own hardware, so there is nothing extra to pay for. You just see the results and approve what matters."
            action={<Button onClick={() => setPairing(true)}>Add your computer</Button>}
          />
        ) : (
          <ul className="space-y-2 pt-2">
            {computers.map((c) => <Card key={c.id} c={c} onOpen={() => setOpenId(c.id)} onRemove={() => setComputers(removeComputer(c.id))} />)}
          </ul>
        )}
      </div>
      {pairing && <PairSheet onClose={() => setPairing(false)} onPaired={(c) => (setComputers(saveComputer(c)), setPairing(false), setOpenId(c.id))} />}
    </div>
  );
}
