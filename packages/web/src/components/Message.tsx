import { useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import rehypeHighlight from 'rehype-highlight';
import type { DisplayItem, Block } from '../groupMessages';
import { useStore } from '../store';

function summarizeTool(name: string, input: Record<string, unknown>): string {
  if (typeof input?.command === 'string') return input.command;
  if (typeof input?.file_path === 'string') return input.file_path as string;
  if (typeof input?.pattern === 'string') return input.pattern as string;
  if (typeof input?.description === 'string') return input.description as string;
  if (typeof input?.prompt === 'string') return (input.prompt as string).slice(0, 80);
  const first = Object.values(input ?? {})[0];
  return typeof first === 'string' ? first.slice(0, 80) : name;
}

function ToolUseCard({ block }: { block: Block }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="my-1.5 overflow-hidden rounded-xl border border-white/8 bg-base-800/60">
      <button onClick={() => setOpen((o) => !o)} className="flex w-full items-center gap-2 px-3 py-2 text-left">
        <span className="rounded-md bg-accent/15 px-1.5 py-0.5 font-mono text-[11px] font-medium text-accent">{block.name}</span>
        <span className="flex-1 truncate font-mono text-[12px] text-white/50">{summarizeTool(block.name, block.input)}</span>
        <svg className={`h-3 w-3 shrink-0 text-white/30 transition-transform ${open ? 'rotate-90' : ''}`} viewBox="0 0 24 24" fill="none">
          <path d="M9 6l6 6-6 6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open && (
        <pre className="border-t border-white/5 bg-base-950/60 px-3 py-2 font-mono text-[11px] text-white/60">
          {JSON.stringify(block.input, null, 2)}
        </pre>
      )}
    </div>
  );
}

function Thinking({ text }: { text: string }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="my-1.5">
      <button onClick={() => setOpen((o) => !o)} className="text-[12px] italic text-white/30 hover:text-white/50">
        {open ? 'Hide thinking' : 'Show thinking'}
      </button>
      {open && <p className="mt-1 whitespace-pre-wrap text-[12px] italic leading-relaxed text-white/40">{text}</p>}
    </div>
  );
}

function Markdown({ text }: { text: string }) {
  return (
    <div className="markdown text-[14px] leading-relaxed text-white/90">
      <ReactMarkdown remarkPlugins={[remarkGfm]} rehypePlugins={[rehypeHighlight]}>
        {text}
      </ReactMarkdown>
    </div>
  );
}

function ImageBlock({ block }: { block: Block }) {
  const src = block.source?.data ? `data:${block.source.media_type};base64,${block.source.data}` : undefined;
  if (!src) return null;
  return <img src={src} className="mt-1.5 max-h-64 rounded-xl border border-white/10 object-cover" />;
}

function Blocks({ blocks }: { blocks: Block[] }) {
  return (
    <>
      {blocks.map((b, i) => {
        if (b.type === 'text') return <Markdown key={i} text={b.text} />;
        if (b.type === 'thinking') return <Thinking key={i} text={b.thinking} />;
        if (b.type === 'tool_use') return <ToolUseCard key={i} block={b} />;
        if (b.type === 'image') return <ImageBlock key={i} block={b} />;
        return null;
      })}
    </>
  );
}

function toolResultText(block: Block): string {
  if (typeof block.content === 'string') return block.content;
  if (Array.isArray(block.content)) {
    return block.content
      .map((c: Block) => (c.type === 'text' ? c.text : JSON.stringify(c)))
      .join('\n');
  }
  return '';
}

function PermissionRequest({ vmId, sessionId, data, resolved }: { vmId: string; sessionId: string; data: any; resolved: boolean }) {
  const { actions } = useStore();
  const [busy, setBusy] = useState<'allow' | 'deny' | null>(null);

  async function respond(behavior: 'allow' | 'deny') {
    setBusy(behavior);
    await actions.resolvePermission(vmId, sessionId, data.requestId, behavior);
  }

  return (
    <div className="my-1.5 max-w-[85%] rounded-xl border border-amber-400/25 bg-amber-400/[0.06] px-3.5 py-3">
      <p className="text-[13px] font-medium text-amber-300">Permission requested</p>
      <p className="mt-0.5 font-mono text-[12px] text-white/60">
        {data.toolName} — {summarizeTool(data.toolName, data.input)}
      </p>
      {!resolved ? (
        <div className="mt-2.5 flex gap-2">
          <button
            disabled={busy !== null}
            onClick={() => respond('allow')}
            className="rounded-lg bg-amber-400 px-3 py-1.5 text-[12px] font-medium text-base-950 transition hover:bg-amber-300 disabled:opacity-40"
          >
            Allow
          </button>
          <button
            disabled={busy !== null}
            onClick={() => respond('deny')}
            className="rounded-lg border border-white/10 px-3 py-1.5 text-[12px] font-medium text-white/70 transition hover:bg-white/5 disabled:opacity-40"
          >
            Deny
          </button>
        </div>
      ) : (
        <p className="mt-2 text-[12px] text-white/30">Resolved</p>
      )}
    </div>
  );
}

export default function Message({ item, vmId, sessionId }: { item: DisplayItem; vmId: string; sessionId: string }) {
  const { state } = useStore();

  if (item.kind === 'user') {
    return (
      <div className="flex justify-end">
        <div className="max-w-[85%] rounded-2xl rounded-tr-sm bg-accent px-3.5 py-2.5 text-[14px] leading-relaxed text-base-950">
          {item.blocks.map((b, i) =>
            b.type === 'text' ? <p key={i} className="whitespace-pre-wrap">{b.text}</p> : <ImageBlock key={i} block={b} />,
          )}
        </div>
      </div>
    );
  }

  if (item.kind === 'assistant') {
    return (
      <div className="flex justify-start">
        <div className="max-w-[85%] rounded-2xl rounded-tl-sm bg-base-800 px-3.5 py-2.5">
          <Blocks blocks={item.blocks} />
        </div>
      </div>
    );
  }

  if (item.kind === 'tool_result') {
    const text = item.blocks.map(toolResultText).join('\n').trim();
    if (!text) return null;
    return (
      <div className="flex justify-start">
        <details className="max-w-[85%] rounded-xl border border-white/8 bg-base-900/60 px-3 py-2 text-[12px] text-white/40">
          <summary className="cursor-pointer select-none text-white/40">Tool output</summary>
          <pre className="mt-1.5 whitespace-pre-wrap font-mono text-[11px] text-white/50">{text.slice(0, 4000)}</pre>
        </details>
      </div>
    );
  }

  if (item.kind === 'permission_request') {
    return (
      <div className="flex justify-start">
        <PermissionRequest vmId={vmId} sessionId={sessionId} data={item.data} resolved={state.resolvedPermissionIds.has(item.data.requestId)} />
      </div>
    );
  }

  if (item.kind === 'system_init') {
    return (
      <p className="py-1 text-center text-[11px] text-white/25">
        Session started · {item.data.model} · {item.data.cwd}
      </p>
    );
  }

  if (item.kind === 'result') {
    const d = item.data;
    if (d.subtype !== 'success') {
      return <p className="py-1 text-center text-[11px] text-red-400/70">Turn ended with an error</p>;
    }
    return null;
  }

  if (item.kind === 'error') {
    return (
      <div className="flex justify-start">
        <div className="max-w-[85%] rounded-2xl border border-red-400/25 bg-red-400/[0.06] px-3.5 py-2.5 text-[13px] text-red-300">
          {item.text}
        </div>
      </div>
    );
  }

  return null;
}
