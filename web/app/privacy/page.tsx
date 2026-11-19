import type { Metadata } from "next";
import LegalShell, { CONTACT_EMAIL, H2 } from "../_legal/LegalShell";

export const metadata: Metadata = {
  title: "Privacy Policy | Coast Calendar",
  description: "How Coast Calendar collects, uses, keeps and protects your information.",
};

const list = { paddingLeft: 20, listStyle: "disc" } as const;

export default function PrivacyPage() {
  return (
    <LegalShell eyebrow="Privacy" title="Privacy Policy" updated="19 November 2026">
      <p>Coast Calendar is run by Atlas Digital in New Zealand. This policy explains what information the Coast Calendar app and the website at coastcalendar.nz (“the Service”) collect, why, and what you can do about it. It is written to meet the New Zealand Privacy Act 2020.</p>

      <H2>1. Who to contact</H2>
      <p>Atlas Digital is responsible for your information. Our privacy officer can be reached at <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>.</p>

      <H2>2. What we collect</H2>
      <ul style={list}>
        <li>your email address, display name and sign-in records</li>
        <li>organisation details you give us, such as business name, contact name, email, phone, website and description</li>
        <li>photos you upload (we remove location and camera details before they are stored)</li>
        <li>listings, polls, notices and poll answers</li>
        <li>organisations you follow and items you save</li>
        <li>notifications we send you and whether you have read them</li>
        <li>a push notification token for your device, if you turn notifications on</li>
        <li>messages you send to Support and reports you make about listings</li>
        <li>your subscription status and purchase reference numbers from Apple or Stripe</li>
        <li>simple usage counts, such as listing views and saves, used to run app features and show organisations how their listings are doing</li>
      </ul>
      <p>If you let the app use your location, it is used once to suggest your nearest area. It is not stored and is not used to track you.</p>

      <H2>3. How we use it</H2>
      <p>Only to run the Service: to sign you in, show and manage listings, send the notifications you ask for, provide your organisation’s plan, answer Support messages and keep the Service safe. We do not show ads, sell your information or track you across other apps or websites.</p>

      <H2>4. What is public</H2>
      <p>Published listings, polls and approved organisation pages (including their photos and contact details you choose to show) are public. Private organisation calendar items and unpublished content are visible only to that organisation’s account and to Support.</p>

      <H2>5. Who we share it with</H2>
      <p>We use these providers to run the Service. They process information for us and for no other purpose:</p>
      <ul style={list}>
        <li>Supabase: database, sign-in and photo storage, hosted in Sydney, Australia</li>
        <li>Cloudflare: website hosting</li>
        <li>Apple: purchases in the iPhone app and push notifications</li>
        <li>Stripe: payments made on the website (we never see your full card details)</li>
      </ul>
      <p>Australia’s privacy law gives protection comparable to New Zealand’s. We only share information with others if the law requires it.</p>

      <H2>6. How we protect it</H2>
      <p>Information is encrypted in transit. Each account can only see and change its own information, and only an organisation’s own account can change what that organisation publishes. Support can access information only to run and moderate the Service. If a privacy breach is likely to cause serious harm, we will tell you and the Privacy Commissioner.</p>

      <H2>7. How long we keep it</H2>
      <p>We keep your information while your account is open. When your account is deleted:</p>
      <ul style={list}>
        <li>your login, profile, photos, notification tokens, follows, saved items, notifications and poll answers are deleted</li>
        <li>your organisation’s public page, contact details, photos, listings and notices are removed; its business name is kept for invoice and tax records</li>
        <li>subscription and payment records are kept for 7 years for New Zealand tax law, with your name, email and account removed</li>
        <li>a short record that we completed your request is kept, with no account linked to it</li>
      </ul>
      <p>Our hosting provider may keep encrypted backups for a limited time before they are overwritten.</p>

      <H2>8. Deleting your account</H2>
      <p>Request deletion in Settings, or email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a>. A person on our team checks and completes each request. We aim to finish within 30 days, and usually much sooner. Deleting your account cancels a website (Stripe) subscription. It does not cancel an Apple subscription. Cancel that yourself in your iPhone Settings &gt; your name &gt; Subscriptions.</p>

      <H2>9. Your rights</H2>
      <p>You can ask for a copy of your information or ask us to correct it. Email <a href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</a> from your account email address. We will reply within 20 working days and can give you your information as a file. If you are unhappy with how we handle your information, you can complain to the Privacy Commissioner at privacy.org.nz.</p>

      <H2>10. Children</H2>
      <p>Coast Calendar is not intended for children under 13, and we do not knowingly collect their information. If we learn we hold information from a child under 13, we will delete it.</p>

      <H2>11. Changes</H2>
      <p>If we change this policy, we will update the date at the top. If a change is significant, we will also let you know in the app or on the website.</p>

      <H2>12. About this policy</H2>
      <p>This is our plain-language launch version. We have reviewed it carefully ourselves. It is not formal legal advice, and we intend to have it reviewed by a lawyer as Coast Calendar grows.</p>
    </LegalShell>
  );
}
