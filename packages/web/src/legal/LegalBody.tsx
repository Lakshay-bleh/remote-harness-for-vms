import { legalDocuments, legalLinks, POLICY_DATE } from './content';

/** The documents worth listing, in the website's order. ("legal" is the website's own index page.) */
export const LEGAL_LIST = legalLinks.filter(([key]) => key !== 'legal' && legalDocuments[key]).map(([key, label]) => ({ key: key as string, label: label as string }));

/** One legal document, read inside the app: its title and date, then each section. Plain text only, nothing is fetched. */
export function LegalBody({ docKey }: { docKey: string }) {
  const doc = legalDocuments[docKey];
  if (!doc) return <p className="text-sm text-muted">This document is not available.</p>;
  return (
    <article className="space-y-5 pb-4">
      <header>
        <h2 className="font-display text-2xl text-ink">{doc.title}</h2>
        <p className="mt-1 text-[14px] leading-relaxed text-muted">{doc.description}</p>
        <p className="mt-1 text-[12px] text-muted-soft">Version of {POLICY_DATE}. Stored in the app: it reads without a connection.</p>
      </header>
      {doc.sections.map((s) => (
        <section key={s.heading} className="space-y-2">
          <h3 className="text-[16px] font-semibold text-ink">{s.heading}</h3>
          {s.paragraphs.map((p, i) => <p key={i} className="text-[14.5px] leading-relaxed text-body-strong">{p}</p>)}
        </section>
      ))}
    </article>
  );
}
