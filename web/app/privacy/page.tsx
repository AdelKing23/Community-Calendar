import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Privacy Policy | Coast Calendar",
  description: "How Coast Calendar collects, uses, keeps and protects your information.",
};

export default function PrivacyPage() {
  return (
    <LegalShell eyebrow="Privacy" title="Privacy Policy" updated="18 November 2026">
      <p>Coast Calendar is made by Atlas Digital in New Zealand. This policy covers the Coast Calendar apps for iPhone and Android and the website at coastcalendar.nz (“the Service”).</p>
      <p>This is a first-pass draft prepared for the current stage of the Service. It is not legal advice. A qualified New Zealand lawyer should review it before it is treated as final, especially against the Privacy Act 2020.</p>

      <H2>1. Who we are</H2>
      <p>Atlas Digital operates Coast Calendar and is responsible for the personal information described here. Contact: <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.</p>

      <H2>2. What information we collect and store</H2>
      <p>To make the Service work we store:</p>
      <ul style={{ paddingLeft: 20, listStyle: "disc" }}>
        <li>your account email address, display name and sign-in records</li>
        <li>organisation details you provide, such as business name, contact name, contact email, phone number, website and description</li>
        <li>photos you upload (we remove location and camera details from photos before they are stored)</li>
        <li>listings, polls, poll answers and notices you create</li>
        <li>organisations you follow and items you save to My Calendar</li>
        <li>notifications we send you, and whether you have read them</li>
        <li>a push notification token for your device, if you allow notifications, so alerts reach only your signed-in account</li>
        <li>messages you send to Support and reports you make about listings</li>
        <li>your subscription or purchase status, including Apple or Stripe reference numbers</li>
        <li>basic in-app usage such as listing views and saves (used for app features and simple analytics)</li>
      </ul>
      <p>Location is used only while you are using the app or site to pick an area. It is not stored and you are not tracked.</p>

      <H2>3. Public content</H2>
      <p>Listings and polls are public when published. Organisation pages, and the photos and details added to them, are also public once published and approved by Support. Private organisation calendar items and unpublished content are visible only to the organisation’s account and Support.</p>

      <H2>4. What we do not do</H2>
      <p>We do not show ads. We do not sell your data. We do not track you across other apps or websites.</p>

      <H2>5. Payments</H2>
      <p>Payments are handled by Apple in the iPhone app and by Stripe on the website. We do not see or store your full card details. We keep a record of each subscription and payment so we can provide your plan and meet our tax obligations.</p>

      <H2>6. Service providers and where your data is stored</H2>
      <p>We use trusted providers who process information only to run the Service: Supabase (database, sign-in and photo storage, hosted in Sydney, Australia), Cloudflare (website hosting), Apple (iPhone purchases and push notifications) and Stripe (website payments). Australia has privacy protections comparable to New Zealand’s. We require our providers to handle data securely.</p>

      <H2>7. How we protect your information</H2>
      <p>Information is encrypted in transit. Each account can see and change only its own information, and only an organisation’s own account can change what that organisation publishes. Support staff can access information only to run and moderate the Service. If a privacy breach is likely to cause serious harm, we will tell you and the Privacy Commissioner as the Privacy Act requires.</p>

      <H2>8. How long we keep information</H2>
      <p>We keep account and content information while your account is active. When your account is deleted:</p>
      <ul style={{ paddingLeft: 20, listStyle: "disc" }}>
        <li>your login, profile, photos, push notification tokens, follows, saved items, notifications and poll answers are deleted</li>
        <li>your organisation is archived: its public page, contact details and photos are removed, its listings and notices are taken down, and its business name is kept for invoice and tax records</li>
        <li>subscription and payment records are kept for 7 years, as New Zealand tax law requires, with your name, email and account removed from them</li>
        <li>the text of your deletion request is kept as a record that we acted on it, with no account linked to it</li>
      </ul>

      <H2>9. Your rights</H2>
      <p>Under the New Zealand Privacy Act 2020 you can ask for a copy of the personal information we hold about you, and ask us to correct it. Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> from your account email address. We will respond within 20 working days, and we can provide your information as a file you can keep. You can also make a complaint to the Privacy Commissioner (privacy.org.nz).</p>

      <H2>10. Deleting your account</H2>
      <p>You can request account deletion from Settings in the app, or by emailing <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. We aim to complete deletion within 30 days. Deleting your account cancels any website (Stripe) subscription. If you subscribed in the iPhone app, cancel the subscription in your Apple ID subscription settings, because only you can cancel an Apple subscription.</p>

      <H2>11. Children’s privacy</H2>
      <p>The Service is not directed at children under 13. We do not knowingly collect personal information from children under 13.</p>

      <H2>12. Changes to this policy</H2>
      <p>We may update this policy from time to time. The “Last updated” date at the top will change. Continued use of the Service after an update means you accept the new policy.</p>

      <H2>13. Contact</H2>
      <p>Questions about privacy? Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.</p>
    </LegalShell>
  );
}
