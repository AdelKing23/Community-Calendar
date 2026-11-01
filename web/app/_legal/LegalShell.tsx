import type { ReactNode } from "react";

export const CONTACT_EMAIL = "support@coastcalendar.nz";

export default function LegalShell({ eyebrow, title, updated, children }: {
  eyebrow: string;
  title: string;
  updated?: string;
  children: ReactNode;
}) {
  return (
    <main style={{ maxWidth: 760, margin: "0 auto", padding: "32px 20px 64px", lineHeight: 1.6 }}>
      <p style={{ marginBottom: 24 }}>
        <a href="/" style={{ fontWeight: 600, textDecoration: "none" }}>← Coast Calendar</a>
      </p>
      <section className="section">
        <div className="section__header">
          <p className="eyebrow">{eyebrow}</p>
          <h1 style={{ fontSize: "2rem", fontWeight: 700, margin: "4px 0 8px" }}>{title}</h1>
          {updated ? <p style={{ opacity: 0.7, fontSize: "0.9rem" }}>Last updated {updated}</p> : null}
        </div>
        <div className="panel legal-page" style={{ display: "grid", gap: 14 }}>
          {children}
        </div>
      </section>
      <footer style={{ marginTop: 32, fontSize: "0.9rem", opacity: 0.8, display: "flex", gap: 16, flexWrap: "wrap" }}>
        <span>Coast Calendar by Atlas Digital</span>
        <a href="/privacy">Privacy</a>
        <a href="/terms">Terms</a>
        <a href="/support">Support</a>
      </footer>
    </main>
  );
}

export function H2({ children }: { children: ReactNode }) {
  return <h2 style={{ fontSize: "1.15rem", fontWeight: 700, marginTop: 10 }}>{children}</h2>;
}
