import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Terms of Use | Coast Calendar",
  description: "Community terms for using Coast Calendar.",
};

const list = { paddingLeft: 20, listStyle: "disc" } as const;

export default function TermsPage() {
  return (
    <LegalShell eyebrow="Terms" title="Terms of Use" updated="19 November 2026">
      <p>Coast Calendar is a local community calendar and organisation directory for New Zealand, run by Atlas Digital. By using the Coast Calendar app or the website at coastcalendar.nz (“the Service”) you agree to these terms.</p>

      <H2>1. What the Service is</H2>
      <p>Anyone can browse listings and follow organisations. Organisations approved by Support and holding an active subscription can publish listings, polls and notices. Listings come from the community. We don’t create them or check every detail, so please confirm with the organiser before you go.</p>

      <H2>2. Your account</H2>
      <p>Give accurate details, keep your login safe, and let us know if you think someone else is using your account. You are responsible for what happens under your account.</p>

      <H2>3. What you post</H2>
      <p>You are responsible for what you post, and it must be accurate and lawful. Don’t post:</p>
      <ul style={list}>
        <li>spam, scams or misleading information</li>
        <li>anything harmful, hateful, unsafe, adult or illegal</li>
        <li>anything that uses someone else’s work, name or photos without permission</li>
      </ul>
      <p>You keep ownership of your content. You let us show it on the Service, and in links to and previews of it, for as long as it stays on the Service.</p>
      <p>Don’t try to break, overload or get unauthorised access to the Service, or use it to harm other people.</p>

      <H2>4. Moderation</H2>
      <p>Support may decline, edit the status of or remove content, and may suspend or close accounts, that break these terms or put the community at risk. A suspended organisation can’t publish until the suspension is lifted. We don’t review everything that is posted.</p>

      <H2>5. Subscriptions</H2>
      <ul style={list}>
        <li>Organisation plans are monthly subscriptions that renew automatically until you cancel.</li>
        <li>iPhone app: payment is charged to your Apple ID. Cancel at least 24 hours before the period ends in your iPhone Settings &gt; your name &gt; Subscriptions. Apple handles refunds at reportaproblem.apple.com.</li>
        <li>Website: payments are handled by Stripe. Cancel any time from Settings (Manage subscription). For refunds on website payments, email us.</li>
        <li>When you cancel, your plan keeps working until the end of the period you’ve paid for.</li>
        <li>When a subscription ends or a payment fails, you can’t create new listings, polls or notices until it is renewed. There is no grace period.</li>
        <li>Deleting your account does not cancel an Apple subscription. Cancel it in your iPhone Settings first.</li>
        <li>We’ll tell you before a price change affects you. A plan does not guarantee any number of views, bookings or sales.</li>
      </ul>

      <H2>6. Our responsibility</H2>
      <p>We work hard to keep the Service accurate and running, but we can’t promise it will always be available or error-free, or that every listing is correct.</p>
      <p>Nothing in these terms removes your rights under the Consumer Guarantees Act 1993, the Fair Trading Act 1986 or other New Zealand law that can’t be excluded. If you use the Service for business purposes, such as running an organisation page, you agree the Consumer Guarantees Act does not apply, as the law allows. Otherwise, to the extent the law allows, we are not liable for indirect loss, and our total liability to you is limited to what you paid us in the 12 months before the claim.</p>

      <H2>7. Deleting your account</H2>
      <p>You can request deletion in Settings or by emailing <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. What we delete and what we have to keep (such as tax records and an organisation’s business name) is explained in our <a href="/privacy">Privacy Policy</a>.</p>

      <H2>8. Changes</H2>
      <p>If we change these terms, we will update the date at the top. If a change is significant, we will let you know in the app or on the website before it applies.</p>

      <H2>9. New Zealand law</H2>
      <p>These terms are governed by New Zealand law, and New Zealand courts deal with any dispute. If you have a problem, please email us first at <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> and we’ll try to sort it out.</p>

      <H2>10. About these terms</H2>
      <p>This is our plain-language launch version. We have reviewed it carefully ourselves. It is not formal legal advice, and we intend to have it reviewed by a lawyer as Coast Calendar grows.</p>
    </LegalShell>
  );
}
