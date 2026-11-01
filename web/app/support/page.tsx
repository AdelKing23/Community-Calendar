import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Support | Coast Calendar",
  description: "Get help with Coast Calendar.",
};

export default function SupportPage() {
  return (
    <LegalShell eyebrow="Support" title="Support">
      <p>Need help with Coast Calendar, your organisation page, a listing or a subscription? We’re happy to help.</p>

      <H2>Email</H2>
      <p><a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a></p>
      <p>(Replies currently come from the Atlas Digital team.)</p>

      <H2>In-app Support</H2>
      <p>
        Signed in? Send us a message from Support in the app or on <a href="/">coastcalendar.nz</a> and you’ll see our replies there.
      </p>

      <H2>Common questions</H2>
      <p>
        <strong>How do I cancel a subscription?</strong>
        <br />
        On iOS, open Settings → your name → Subscriptions. On the web, use Manage subscription in Settings (opens Stripe).
      </p>
      <p>
        <strong>How do I report a listing?</strong>
        <br />
        Use the Report option on the listing, or email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>
      <p>
        <strong>How do I delete my account?</strong>
        <br />
        Request deletion from Settings in the app, or email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. Support completes the deletion.
      </p>
      <p>
        <strong>How long does a reply take?</strong>
        <br />
        We aim to reply within a few business days. Urgent issues about live listings or accounts are prioritised.
      </p>
      <p>
        <strong>Where are the Terms and Privacy Policy?</strong>
        <br />
        <a href="/terms">Terms of Use</a>
        {" · "}
        <a href="/privacy">Privacy Policy</a>
      </p>
    </LegalShell>
  );
}
