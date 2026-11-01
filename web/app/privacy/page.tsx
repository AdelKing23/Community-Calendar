import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Privacy Policy | Coast Calendar",
  description: "How Coast Calendar collects, uses and protects your information.",
};

export default function PrivacyPage() {
  return (
    <LegalShell eyebrow="Privacy" title="Privacy Policy" updated="1 November 2026">
      <p>
        Coast Calendar is made by Atlas Digital in New Zealand. This policy covers the Coast Calendar iOS app and the website at coastcalendar.nz (“the Service”).
      </p>
      <p>
        This is a first-pass draft prepared for the current stage of the Service. It is not legal advice. A qualified New Zealand lawyer should review it before it is treated as final, especially against the Privacy Act 2020.
      </p>

      <H2>1. Who we are</H2>
      <p>
        Atlas Digital operates Coast Calendar. Contact: <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>

      <H2>2. What information we collect and store</H2>
      <p>To make the Service work we store:</p>
      <ul style={{ paddingLeft: 20, listStyle: "disc" }}>
        <li>your account email address and display name</li>
        <li>organisation details you provide</li>
        <li>photos you upload</li>
        <li>listings, polls and notices you create</li>
        <li>items you save to My Calendar</li>
        <li>your subscription or purchase status</li>
        <li>basic in-app usage such as listing views and saves (used for app features and simple analytics)</li>
      </ul>
      <p>Location is used only while you are using the app or site to pick an area. It is not stored and you are not tracked.</p>

      <H2>3. Public content</H2>
      <p>
        Listings and polls are public when published. Organisation pages, and the photos and details added to them, are also public once published.
      </p>

      <H2>4. What we do not do</H2>
      <p>We do not show ads. We do not sell your data. We do not track you across other apps or websites.</p>

      <H2>5. Payments</H2>
      <p>Payments are handled by Apple on iOS and by Stripe on the web. We do not see or store your full card details.</p>

      <H2>6. Service providers</H2>
      <p>
        Your data is stored with our hosting and database providers (Supabase and Cloudflare), who process it only to run the Service. We require them to handle data securely.
      </p>

      <H2>7. How long we keep information</H2>
      <p>
        We keep account and content information while your account is active or as needed to provide the Service. When you request account deletion we delete your personal information except where we are required to keep it by law (for example, certain financial or legal records).
      </p>

      <H2>8. Your rights</H2>
      <p>
        Under the New Zealand Privacy Act 2020 you can ask to access or correct personal information we hold about you, and you can make a complaint to the Privacy Commissioner. Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> to make a request.
      </p>

      <H2>9. Deleting your account</H2>
      <p>
        You can request account deletion from Settings in the app, or by emailing <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. We will delete your account and personal information except where we need to keep it by law.
      </p>

      <H2>10. Children’s privacy</H2>
      <p>The Service is not directed at children under 13. We do not knowingly collect personal information from children under 13.</p>

      <H2>11. Changes to this policy</H2>
      <p>
        We may update this policy from time to time. The “Last updated” date at the top will change. Continued use of the Service after an update means you accept the new policy.
      </p>

      <H2>12. Contact</H2>
      <p>
        Questions about privacy? Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.
      </p>
    </LegalShell>
  );
}
