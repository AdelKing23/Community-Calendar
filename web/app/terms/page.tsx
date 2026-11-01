import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Terms of Use | Coast Calendar",
  description: "Community terms for using Coast Calendar.",
};

export default function TermsPage() {
  return (
    <LegalShell eyebrow="Terms" title="Terms of Use" updated="1 November 2026">
      <p>
        Coast Calendar is a community calendar and organisation directory for the Coast and surrounding areas of New Zealand, made by Atlas Digital. By using the Coast Calendar iOS app or the website at coastcalendar.nz (“the Service”), you agree to these Terms of Use.
      </p>
      <p>
        These Terms are a first-pass draft prepared for the current stage of the Service. They are not legal advice. A qualified New Zealand lawyer should review them before they are treated as final.
      </p>

      <H2>1. The Service</H2>
      <p>
        The Service lets people browse local what’s-on listings, follow organisations, and (for approved organisations with an active subscription) publish listings, polls and notices. Content is submitted by the community. We do not create or verify the accuracy of listings.
      </p>

      <H2>2. Accounts</H2>
      <p>
        You may need an account to publish content or manage an organisation. You are responsible for keeping your login details secure and for activity under your account. You must provide accurate information when you register.
      </p>

      <H2>3. Listings, polls, notices and organisation content</H2>
      <p>
        Organisations and users are responsible for the accuracy, legality and appropriateness of the content they post. Keep listings and organisation details accurate and up to date.
      </p>
      <p>You must not post:</p>
      <ul style={{ paddingLeft: 20, listStyle: "disc" }}>
        <li>spam, scams, or misleading content</li>
        <li>content that is harmful, unsafe, illegal, or inappropriate</li>
        <li>content that infringes someone else’s rights</li>
      </ul>

      <H2>4. Acceptable Use</H2>
      <p>
        You agree not to misuse the Service, including by attempting to disrupt it, access it without permission, or use it in a way that harms other users or the community.
      </p>

      <H2>5. User-generated content and licence</H2>
      <p>
        You keep ownership of the content you post. By posting content on the Service you grant Atlas Digital a non-exclusive, royalty-free licence to host, display, and distribute that content as part of the Service (including on the app and website) for as long as it remains on the Service. You can remove your own content; we may also remove content as described below.
      </p>

      <H2>6. Moderation and removal</H2>
      <p>
        Support may review, change the status of, or remove listings, polls, notices, photos or accounts that break these Terms or that we reasonably consider harmful to the community or the Service. We do not promise to review all content.
      </p>

      <H2>7. Subscriptions and payments</H2>
      <p>Paid organisation plans are monthly subscriptions that renew automatically until cancelled. You can cancel anytime:</p>
      <ul style={{ paddingLeft: 20, listStyle: "disc" }}>
        <li>on iOS, through your Apple ID subscription settings</li>
        <li>on the web, through Stripe (Manage subscription in Settings)</li>
      </ul>
      <p>Cancelling stops future renewals. Your plan stays active until the end of the current paid period.</p>
      <p>
        On iOS, payment is charged to your Apple ID and Apple’s standard terms apply. On the web, payments are processed by Stripe. We do not see or store your full card details.
      </p>

      <H2>8. Intellectual property</H2>
      <p>
        The Coast Calendar name, branding, app, and website are owned by Atlas Digital. You may not copy or reuse them without permission, except for normal personal use of the Service.
      </p>

      <H2>9. Disclaimer and limitation of liability</H2>
      <p>
        The Service is provided “as is.” Event details come from the community, so always check with the organiser before you go. We work to keep the Service running, but we do not guarantee that it will be uninterrupted, error-free, or that any particular listing is accurate.
      </p>
      <p>
        To the extent permitted by New Zealand law, Atlas Digital is not liable for any loss or damage arising from your use of the Service or from reliance on community-submitted content. Nothing in these Terms limits rights that cannot be limited under the Consumer Guarantees Act 1993 or other New Zealand law.
      </p>

      <H2>10. Account deletion and termination</H2>
      <p>
        You can request deletion of your account from Settings in the app or by emailing <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. We will delete your account and personal information except where we need to keep it by law.
      </p>
      <p>We may suspend or close accounts that break these Terms.</p>

      <H2>11. Changes to these Terms</H2>
      <p>
        We may update these Terms from time to time. The “Last updated” date at the top will change. Continued use of the Service after an update means you accept the new Terms.
      </p>

      <H2>12. Governing law</H2>
      <p>These Terms are governed by the laws of New Zealand. Any disputes will be subject to the courts of New Zealand.</p>

      <H2>13. Contact</H2>
      <p>
        Questions about these Terms? Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>
    </LegalShell>
  );
}
