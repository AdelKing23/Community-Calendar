import type { ReactNode } from "react";
import CommunityCalendarApp from "../CommunityCalendarApp";

export const CONTACT_EMAIL = "support@coastcalendar.nz";

// t262: legal and support pages render inside the app shell (side navigator, wallpaper, Settings)
// so the navigator never disappears. The page text is server-rendered as part of the page.
export default function LegalShell({ eyebrow, title, updated, children }: {
  eyebrow: string;
  title: string;
  updated?: string;
  children: ReactNode;
}) {
  return (
    <CommunityCalendarApp legalPage={{ eyebrow, title, updated }}>
      {children}
      <footer style={{ marginTop: 18, fontSize: "0.9rem", display: "flex", gap: 16, flexWrap: "wrap" }}>
        <span>Coast Calendar by Atlas Digital</span>
        <a href="/privacy">Privacy</a>
        <a href="/terms">Terms</a>
        <a href="/support">Support</a>
      </footer>
    </CommunityCalendarApp>
  );
}

export function H2({ children }: { children: ReactNode }) {
  return <h2 style={{ fontSize: "1.15rem", fontWeight: 700, marginTop: 10 }}>{children}</h2>;
}
