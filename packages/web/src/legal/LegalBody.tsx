import type { ReactNode } from 'react';
import { legalDocuments, legalLinks, POLICY_DATE } from './content';

const SITE = 'https://www.escanor.in';

/** The documents worth listing, in the website's order. ("legal" and "about" are website pages.) */
export const LEGAL_LIST = legalLinks.filter(([key]) => key !== 'legal' && legalDocuments[key]).map(([key, label]) => ({ key: key as string, label: label as string }));

/** The two inline marks the policies use: [label](href) and **bold**. Site paths open on the website. */
function Rich({ text }: { text: string }) {
  const parts: ReactNode[] = [];
  let last = 0;
  for (const m of text.matchAll(/\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*/g)) {
    const at = m.index ?? 0;
    if (at > last) parts.push(text.slice(last, at));
    if (m[3]) parts.push(<strong key={at} className="font-semibold text-ink">{m[3]}</strong>);
    else {
      const href = m[2].startsWith('/') ? `${SITE}${m[2]}` : m[2];
      parts.push(/^https:\/\//.test(href) ? <a key={at} href={href} target="_blank" rel="noopener noreferrer" className="underline">{m[1]}</a> : m[1]);
    }
    last = at + m[0].length;
  }
  if (last < text.length) parts.push(text.slice(last));
  return <>{parts}</>;
}

/** One legal document, read inside the app: its title and date, then each section. Nothing is fetched. */
export function LegalBody({ docKey }: { docKey: string }) {
  const doc = legalDocuments[docKey];
  if (!doc) return <p className="text-sm text-muted">This document is not available.</p>;
  return (
    <article className="space-y-5 pb-4">
      <header>
        <h2 className="font-display text-2xl text-ink">{doc.title}</h2>
        <p className="mt-1 text-[14px] leading-relaxed text-muted">{doc.description}</p>
        <p className="mt-1 text-[12px] text-muted-soft">Last updated {POLICY_DATE}</p>
      </header>
      {doc.sections.map((s) => (
        <section key={s.heading} className="space-y-2">
          <h3 className="text-[16px] font-semibold text-ink">{s.heading}</h3>
          {s.paragraphs?.map((p, i) => <p key={i} className="text-[14.5px] leading-relaxed text-body-strong"><Rich text={p} /></p>)}
          {s.items && (
            <ul className="list-disc space-y-1.5 pl-5 text-[14.5px] leading-relaxed text-body-strong">
              {s.items.map((item, i) => <li key={i}><Rich text={item} /></li>)}
            </ul>
          )}
        </section>
      ))}
    </article>
  );
}
