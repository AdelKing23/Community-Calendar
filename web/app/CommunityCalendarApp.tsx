"use client";

import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from "react";
import type { KeyboardEvent as ReactKeyboardEvent, PointerEvent as ReactPointerEvent } from "react";
import { applyTheme, applyThemeForUser, cardTints, readTheme, saveTheme, wallpapers } from "./theme";

const supabaseUrl =
  process.env.NEXT_PUBLIC_SUPABASE_URL ?? "https://fujngeynyosnplviyvbg.supabase.co";
const supabaseKey =
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "sb_publishable_YsW8_4ahQtnqyDzVgMRsSg_jfgtVfMx";

const TEMP_SUPPORT_OVERRIDE = false; // TEMP: remove before launch — bypasses Support approval/subscription gates for testing (search TEMP_SUPPORT_OVERRIDE)
// TEMP_BRIDGE: client-side stand-ins for backend pieces missing in Supabase. Remove each when the backend lands.
//   report_via_support: submit_event_report RPC and event_reports table are absent (probed 15 Oct 2026),
//   so listing reports are sent through submit_support_request with topic "Listing report".
//   HOW TO SWITCH TO submit_event_report (once the backend exists):
//     1. In Supabase, confirm public.submit_event_report(p_event_id uuid, p_category text, p_details text)
//        exists and authenticated has EXECUTE (iOS calls it with exactly these params).
//     2. Set report_via_support: false below — ReportListing then calls submit_event_report directly.
//     3. Later, delete the TEMP_BRIDGE branch in ReportListing and this const (search TEMP_BRIDGE).
const TEMP_BRIDGES = { report_via_support: true } as const;

// Polls run from creation time (start_at) for at most this many days (end_at). After end_at the poll
// is shown as closed and voting/withdraw lock. Change this number to change the limit for new polls.
const POLL_MAX_DAYS = 14;
const POLL_MAX_MS = POLL_MAX_DAYS * 24 * 60 * 60 * 1000;
// iOS PollDetails.maxOptions / minimum (EventModels.swift, CreateListingScreen.swift).
const POLL_MAX_OPTIONS = 10;
const POLL_MIN_OPTIONS = 2;

// Mirrors iOS normalizeOptions(): at least 2 boxes, one trailing empty box while there is room,
// and no more than one empty box at the end.
function normalizePollOptions(options: string[]) {
  const next = [...options];
  while (next.length < POLL_MIN_OPTIONS) next.push("");
  while (next.length > POLL_MIN_OPTIONS && !next[next.length - 1].trim() && !next[next.length - 2].trim()) next.pop();
  if (next.length < POLL_MAX_OPTIONS && next[next.length - 1].trim()) next.push("");
  return next.slice(0, POLL_MAX_OPTIONS);
}

const sessionKey = "community_calendar_web_session";
const launchAreas = ["Pohutukawa Coast", "Beachlands", "Maraetai", "Franklin"];
const homeScopeKey = "communityCalendar.home.locationScope";
const webInstallKey = "communityCalendar.web.installationID";
const webOpenSessionKey = "communityCalendar.web.openRecorded";

const defaultHomeScope = "pohutukawa-coast";

type LocationScopeRecord = {
  id: string;
  slug: string;
  name: string;
  scope_type: string;
};

type LocationEdgeRecord = {
  child_slug: string;
  parent_slug: string;
  relationship_type: string;
  sort_order: number;
};

function parentSlugOf(slug: string, edges: LocationEdgeRecord[]): string | undefined {
  return edges.find((edge) => edge.child_slug === slug)?.parent_slug;
}

function ancestorScopesOf(slug: string, scopes: LocationScopeRecord[], edges: LocationEdgeRecord[], limit = 4): LocationScopeRecord[] {
  const bySlug = new Map(scopes.map((scope) => [scope.slug, scope]));
  const out: LocationScopeRecord[] = [];
  let current = parentSlugOf(slug, edges);
  while (current && out.length < limit) {
    const scope = bySlug.get(current);
    if (!scope || scope.scope_type === "country" || scope.slug === "new-zealand") break;
    out.push(scope);
    current = parentSlugOf(current, edges);
  }
  return out;
}

// fb2: viewer scope plus every wider scope (including New Zealand) — a poll whose coverage is any of these is visible.
function coverageSlugsFor(slug: string, edges: LocationEdgeRecord[]): Set<string> {
  const out = new Set<string>([slug, "new-zealand"]);
  let current = parentSlugOf(slug, edges);
  let guard = 0;
  while (current && guard++ < 12) { out.add(current); current = parentSlugOf(current, edges); }
  return out;
}

function childScopesOf(parent: string, scopes: LocationScopeRecord[], edges: LocationEdgeRecord[]): LocationScopeRecord[] {
  const bySlug = new Map(scopes.map((scope) => [scope.slug, scope]));
  return edges
    .filter((edge) => edge.parent_slug === parent)
    .map((edge) => bySlug.get(edge.child_slug))
    .filter((scope): scope is LocationScopeRecord => Boolean(scope));
}

function siblingScopesOf(slug: string, scopes: LocationScopeRecord[], edges: LocationEdgeRecord[], limit = 6): LocationScopeRecord[] {
  const parent = parentSlugOf(slug, edges);
  if (!parent) return [];
  const ancestorNames = new Set(ancestorScopesOf(slug, scopes, edges).map((scope) => scope.name.toLowerCase()));
  return childScopesOf(parent, scopes, edges)
    .filter((scope) => scope.slug !== slug)
    .filter((scope) => !ancestorNames.has(scope.name.toLowerCase()))
    .slice(0, limit);
}

function primaryChipsOf(slug: string, scopes: LocationScopeRecord[], edges: LocationEdgeRecord[], limit = 6): LocationScopeRecord[] {
  const selected = scopes.find((scope) => scope.slug === slug);
  if (!selected || selected.scope_type === "place") {
    return siblingScopesOf(slug, scopes, edges, limit);
  }
  return childScopesOf(slug, scopes, edges).slice(0, limit);
}

function searchScopes(query: string, scopes: LocationScopeRecord[], limit = 8): LocationScopeRecord[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];
  const matches = scopes.filter((scope) =>
    scope.name.toLowerCase().includes(normalized) || scope.slug.includes(normalized)
  );
  const prefix = matches.filter((scope) => scope.name.toLowerCase().startsWith(normalized) || scope.slug.startsWith(normalized));
  const restHits = matches.filter((scope) => !prefix.some((hit) => hit.slug === scope.slug));
  return [...prefix, ...restHits].slice(0, limit);
}

const categories = ["Live Music", "Food & Drink", "Markets", "Kids & Family", "Sport", "Community", "Fundraisers", "Classes & Workshops", "Seniors", "Church / Marae / Cultural", "Nightlife", "Public Notices"];
const topicFilters = [
  { slug: "Community", label: "Community" },
  { slug: "Public Notices", label: "Notices" },
  { slug: "Live Music", label: "Live Music" },
  { slug: "Food & Drink", label: "Food" },
  { slug: "Fundraisers", label: "Fundraisers" },
  { slug: "Nightlife", label: "Nightlife" },
  { slug: "Church / Marae / Cultural", label: "Culture" },
  { slug: "Classes & Workshops", label: "Workshops" },
  { slug: "Sport", label: "Sport" },
  { slug: "Kids & Family", label: "Family" },
  { slug: "Markets", label: "Markets" },
  { slug: "Seniors", label: "Seniors" },
] as const;


type SessionUser = {
  id: string;
  email?: string;
};

type AuthSession = {
  access_token: string;
  refresh_token?: string;
  expires_at?: number;
  user: SessionUser;
};

type AuthPayload = Partial<AuthSession> & {
  session?: AuthSession | null;
  user?: SessionUser | null;
};

type EventRecord = {
  id: string;
  title: string;
  category: string;
  topics?: string[];
  venue: string;
  start_at: string;
  end_at: string;
  price_label: string | null;
  short_description: string;
  long_description: string | null;
  location_display_name: string | null;
  town: string;
  status: string;
  listing_kind?: string | null;
  poll_question?: string | null;
  poll_options?: string[] | null;
  poll_allows_custom_answer?: boolean | null;
  organisation_name?: string | null;
  business_profile_id?: string | null;
  is_free?: boolean | null;
  image_url?: string | null;
};

type HostRecord = {
  id: string;
  owner_user_id?: string;
  display_name?: string | null;
  business_name: string;
  bio?: string | null;
  public_website?: string | null;
  public_location_text?: string | null;
  avatar_image_path?: string | null;
  hero_image_path?: string | null;
  contact_name: string | null;
  contact_email: string;
  phone: string | null;
  area_scope_id: string;
  about: string | null;
  website: string | null;
  selected_plan_id: string | null;
  status: string;
  rejection_reason: string | null;
  suspension_reason: string | null;
  support_note: string | null;
  avatar_image_url: string | null;
  hero_image_url: string | null;
  avatar_image_position_x: number | null;
  avatar_image_position_y: number | null;
  hero_image_position_x: number | null;
  hero_image_position_y: number | null;
  created_at: string;
};

type SubscriptionRecord = {
  id: string;
  business_profile_id: string;
  plan_id: string;
  product_id: string;
  status: string;
  active_listing_limit: number;
  placement_rank: number;
  current_period_end: string | null;
  provider?: string | null; // 'apple' | 'stripe'
};

type EngagementRecord = {
  id: string;
  event_id: string;
  engagement_type: "saved" | "interested" | "going";
  events?: EventRecord;
};

type UserProfile = {
  user_id: string;
  display_name: string | null;
  public_role: string | null;
  organisation_name: string | null;
  phone: string | null;
  website: string | null;
  preferred_contact_email: string | null;
  avatar_image_url: string | null;
  contact_visibility: "anonymous" | "name_and_email" | "public_profile";
};

type SupportRequest = {
  id: string;
  topic: string;
  listing_reference: string | null;
  message: string;
  status: "open" | "in_review" | "closed";
  support_note: string | null;
  created_at: string;
  updated_at?: string | null;
  submitted_by?: string | null;
};

type ChangeRequest = {
  id: string;
  change_type: string;
  status: string;
  requester_note: string | null;
  support_note: string | null;
  created_at: string;
  events?: EventRecord;
  event_id?: string;
  requested_by?: string;
  review_reason?: string | null;
  proposed_changes?: Record<string, unknown> | null;
};

type UserNotification = {
  id: string;
  user_id: string;
  title: string;
  body: string;
  notification_type: string;
  related_table: string | null;
  related_id: string | null;
  read_at: string | null;
  push_status?: "queued" | "sending" | "sent" | "failed" | "skipped";
  push_attempts?: number;
  push_last_attempt_at?: string | null;
  push_sent_at?: string | null;
  push_error?: string | null;
  created_at: string;
};

type MemberFollowRecord = {
  id: string;
  user_id: string;
  business_profile_id: string;
  notification_level: "all" | "important";
  created_at: string;
};

type MemberNoticeRecord = {
  id: string;
  business_profile_id: string;
  owner_user_id: string;
  title: string;
  summary: string | null;
  body: string | null;
  template_style: "weekly_letter" | "photo_update" | "notice_board";
  status: "draft" | "published" | "archived";
  hero_image_url: string | null;
  image_urls: string[];
  published_at: string | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
};

type SupportAuditEvent = {
  id: string;
  actor_user_id: string | null;
  action: string;
  entity_table: string;
  entity_id: string;
  before_data: Record<string, unknown> | null;
  after_data: Record<string, unknown> | null;
  reason: string | null;
  created_at: string;
};

type Notice = { kind: "good" | "warn"; text: string } | null;

type MemberDraft = {
  business_name: string;
  contact_name: string;
  contact_email: string;
  phone: string;
  website: string;
  about: string;
  area_scope_id: string;
  selected_plan_id: string;
  avatar_image_url: string;
  hero_image_url: string;
  avatar_image_position_x: number;
  avatar_image_position_y: number;
  hero_image_position_x: number;
  hero_image_position_y: number;
};

type NoticeDraft = {
  title: string;
  summary: string;
  body: string;
  template_style: MemberNoticeRecord["template_style"];
  hero_image_url: string;
  status: "draft" | "published";
};

function authHeaders(accessToken?: string) {
  const bearer = accessToken ?? supabaseKey;
  return {
    apikey: supabaseKey,
    Authorization: `Bearer ${bearer}`,
    "Content-Type": "application/json",
  };
}

function userFacingServiceMessage(raw: string, status?: number) {
  const trimmed = raw.trim();
  let code = "";
  let combined = trimmed;

  try {
    const parsed = JSON.parse(trimmed) as {
      code?: string;
      message?: string;
      error?: string;
      error_description?: string;
      details?: string;
      hint?: string;
    };
    code = parsed.code ?? "";
    combined = [parsed.message, parsed.error_description, parsed.error, parsed.details, parsed.hint]
      .filter(Boolean)
      .join(" ");
  } catch {
    // Plain text responses are handled by the same pattern matcher below.
  }

  const message = combined.toLowerCase();

  if (code === "42501" || message.includes("row-level security") || message.includes("permission denied") || message.includes("not authorized")) {
    if (message.includes("events")) {
      return "We couldn’t confirm your publishing access. Refresh your member status and try again. Your listing is still here.";
    }
    if (message.includes("member_notices") || message.includes("notices")) {
      return "This Notice can’t be published yet. Publishing Notices needs approved membership and an active subscription. Save it as a draft or ask Support to check your member status.";
    }
    if (message.includes("business_profiles")) {
      return "This member profile could not be saved with this account. Sign in again, verify your email, then check required member details. If it still fails, Support should review it.";
    }
    return "This account does not have access to complete that action yet. Check sign-in, email verification, membership approval and subscription state.";
  }

  if (code === "23502" || message.includes("null value") || message.includes("required")) {
    return "A required field is missing. Check the form and try again.";
  }
  if (code === "23503") {
    return "This item is linked to something the app can’t find anymore. Refresh the page and try again.";
  }
  if (code === "23505" || message.includes("duplicate") || message.includes("already exists")) {
    return "This already exists. Check whether it was saved earlier, then refresh and try again.";
  }
  if (code === "23514" || message.includes("check constraint") || message.includes("invalid input")) {
    return "One field has a value the app cannot accept. Check dates, category, price, contact details and membership options.";
  }
  if (["22P02", "22007", "22008", "22023"].includes(code)) {
    return "One of the fields is not in the right format. Check dates, times, email, website and phone details.";
  }
  if (code === "22001") {
    return "One of the fields is too long. Shorten the title, summary, contact details or Notice text and try again.";
  }
  if (["PGRST301", "PGRST302"].includes(code) || message.includes("jwt") || message.includes("token") || message.includes("expired")) {
    return "Your sign-in session has expired. Please sign in again.";
  }
  if (["PGRST106", "PGRST108", "PGRST118", "PGRST200", "PGRST201", "PGRST202", "42P01", "42703", "42883"].includes(code)) {
    return "That didn’t work, and it isn’t something you can fix in the form. Please try again shortly, or contact Support.";
  }
  if (message.includes("invalid login credentials")) {
    return "Sign in failed. Check your email and password, then try again.";
  }
  if (message.includes("email not confirmed")) {
    return "Check your email to confirm your account, then sign in again.";
  }
  if (message.includes("user already registered")) {
    return "That email already has an account. Sign in instead, or use Forgot password.";
  }
  if (message.includes("invalid email")) {
    return "Use a real email address, then try again.";
  }
  if (message.includes("too large") || message.includes("payload") || message.includes("file size")) {
    return "That file is too large. Try a smaller image.";
  }
  if (message.includes("mime") || message.includes("unsupported") || message.includes("content type")) {
    return "That file type is not supported. Use a JPG, PNG or HEIC image.";
  }

  if (status === 400 || status === 422) return "Something in the form needs fixing. Check required fields, dates, contact details and image sizes.";
  if (status === 401) return "Your sign-in session has expired. Please sign in again.";
  if (status === 403) return "This account does not have access to do that yet. Check email verification, membership approval and subscription state.";
  if (status === 404) return "That item could not be found. It may have been changed, archived or removed.";
  if (status === 409) return "This looks like a duplicate or conflict. Refresh the page and try again.";
  if (status === 413) return "That file is too large. Try a smaller image.";
  if (status === 415) return "That file type is not supported. Use a JPG, PNG or HEIC image.";
  if (status === 429) return "Too many tries in a short time. Wait a moment, then try again.";
  if (status && status >= 500) return "The service hit a problem. Please try again shortly. If it keeps happening, Support should check it.";

  return "Something went wrong. Try again shortly, and contact Support if it keeps happening.";
}

function messageFromError(error: unknown) {
  if (!(error instanceof Error)) {
    return "Something went wrong. Try again shortly.";
  }

  const message = error.message.trim();
  if (message.startsWith("{") || message.includes("\"code\"") || message.includes("row-level security")) {
    return userFacingServiceMessage(message);
  }

  return message || "Something went wrong. Try again shortly.";
}


async function signedStorageImageUrl(bucket: string, storagePath: string, accessToken?: string): Promise<string | null> {
  const response = await fetch(`${supabaseUrl}/storage/v1/object/sign/${bucket}/${storagePath}`, {
    method: "POST",
    headers: {
      ...authHeaders(accessToken),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ expiresIn: 3600 }),
  });
  if (!response.ok) {
    console.error(`${bucket} sign`, response.status, await response.text());
    return null;
  }
  const payload = await response.json() as { signedURL?: string; signedUrl?: string };
  const signed = payload.signedURL ?? payload.signedUrl;
  if (!signed) return null;
  if (signed.startsWith("http")) {
    const url = new URL(signed);
    if (url.pathname.startsWith("/object/")) {
      url.pathname = `/storage/v1${url.pathname}`;
    }
    return url.toString();
  }
  if (signed.startsWith("/storage/v1/object/")) return `${supabaseUrl}${signed}`;
  if (signed.startsWith("storage/v1/object/")) return `${supabaseUrl}/${signed}`;
  if (signed.startsWith("/object/")) return `${supabaseUrl}/storage/v1${signed}`;
  if (signed.startsWith("object/")) return `${supabaseUrl}/storage/v1/${signed}`;
  if (signed.startsWith("/")) return `${supabaseUrl}${signed}`;
  return `${supabaseUrl}/storage/v1/${signed}`;
}

const memberImagePublicPrefix = "/storage/v1/object/public/member-images/";

function memberImagePath(value: string | null | undefined): string | null {
  if (!value) return null;
  const at = value.indexOf(memberImagePublicPrefix);
  if (at >= 0) return value.slice(at + memberImagePublicPrefix.length).split("?")[0];
  if (/^https?:/i.test(value) || value.startsWith("blob:") || value.startsWith("data:")) return null;
  return value.replace(/^\/+/, "");
}

// Accepts a member-images storage path, a public member-images URL (re-signed) or any other full URL (used as-is).
async function resolveMemberImage(value: string | null | undefined, accessToken?: string): Promise<string | null> {
  if (!value) return null;
  const path = memberImagePath(value);
  if (!path) return value;
  return (await signedStorageImageUrl("member-images", path, accessToken)) ?? null;
}

async function signedListingImageUrl(storagePath: string, accessToken?: string): Promise<string | null> {
  return signedStorageImageUrl("listing-images", storagePath, accessToken);
}

async function rest<T>(path: string, options: RequestInit = {}, accessToken?: string): Promise<T> {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    ...options,
    headers: {
      ...authHeaders(accessToken),
      ...(options.headers ?? {}),
    },
  });

  if (!response.ok) {
    throw new Error(userFacingServiceMessage(await response.text(), response.status));
  }

  if (response.status === 204) {
    return undefined as T;
  }

  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

async function rpc<T>(name: string, body: Record<string, unknown>, accessToken?: string): Promise<T> {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: authHeaders(accessToken),
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(userFacingServiceMessage(await response.text(), response.status));
  }

  const text = await response.text();
  return (text ? JSON.parse(text) : undefined) as T;
}

async function signIn(email: string, password: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify({ email, password }),
  });

  if (!response.ok) {
    throw new Error(userFacingServiceMessage(await response.text(), response.status));
  }

  const payload = await response.json() as AuthPayload;
  const session = authSessionFromPayload(payload);
  if (!session) {
    throw new Error("Sign in did not return an active session. Check your email confirmation, then try again.");
  }
  return session;
}

async function signUp(email: string, password: string, fullName = "") {
  const name = fullName.trim();
  const response = await fetch(`${supabaseUrl}/auth/v1/signup`, {
    method: "POST",
    headers: authHeaders(),
    body: JSON.stringify(name ? { email: email.trim(), password, data: { full_name: name } } : { email: email.trim(), password }),
  });

  if (!response.ok) {
    throw new Error(userFacingServiceMessage(await response.text(), response.status));
  }

  const payload = await response.json() as AuthPayload;
  return authSessionFromPayload(payload);
}

// iOS resendVerificationEmail / sendPasswordResetEmail
async function resendVerificationEmail(email: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/resend`, { method: "POST", headers: authHeaders(), body: JSON.stringify({ type: "signup", email: email.trim() }) });
  if (!response.ok) throw new Error(userFacingServiceMessage(await response.text(), response.status));
}
async function sendPasswordResetEmail(email: string) {
  const response = await fetch(`${supabaseUrl}/auth/v1/recover`, { method: "POST", headers: authHeaders(), body: JSON.stringify({ email: email.trim() }) });
  if (!response.ok) throw new Error(userFacingServiceMessage(await response.text(), response.status));
}

// stripe1: Stripe Checkout live (create-checkout-session + stripe-webhook deployed). Set false to fall back to "Activate in the iPhone app".
const STRIPE_ENABLED = true;
async function startCheckout(planId: string, profileId: string, token: string) {
  if (!STRIPE_ENABLED) throw new Error("Card payments on web coming soon. Activate in the iPhone app for now.");
  const response = await fetch(`${supabaseUrl}/functions/v1/create-checkout-session`, {
    method: "POST",
    headers: { ...authHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({ plan_id: planId, business_profile_id: profileId, return_url: window.location.origin }),
  });
  if (!response.ok) {
    // stripe3: show the edge function's own { error } text (e.g. a Stripe message) rather than the generic service message.
    const raw = await response.text();
    let detail = "";
    try { detail = String((JSON.parse(raw) as { error?: unknown }).error ?? ""); } catch { /* not JSON */ }
    throw new Error(detail ? `Checkout failed: ${detail}` : userFacingServiceMessage(raw, response.status));
  }
  const body = await response.json() as { url?: string };
  if (!body.url) throw new Error("Checkout could not be started. Please try again.");
  window.location.href = body.url;
}

// iOS BusinessSubscriptionPlan (Models/BusinessCommerce.swift)
const iosPlans = [
  { id: "local_business", title: "Local Member", price: "$19.99/month", allowance: "1 active listing or poll at a time", blurb: "New local publishers" },
  { id: "growth", title: "Growth Member", price: "$49.99/month", allowance: "Up to 4 active listings or polls", blurb: "Regular local publishers" },
  { id: "sponsor", title: "Community Partner", price: "$149.99/month", allowance: "Up to 8 active listings or polls", blurb: "High-activity community publishers" },
] as const;

// iOS BusinessOrganisationType
const organisationTypes = [
  ["business", "Business"], ["school_ece", "School/ECE"], ["sports_club", "Sports club"], ["community_group", "Community group"],
  ["charity_non_profit", "Charity/non-profit"], ["marae_cultural_organisation", "Marae/cultural organisation"],
  ["church_faith_community", "Church/faith community"], ["market", "Market"], ["hospitality_venue", "Hospitality/venue"],
  ["instructor_activity_provider", "Instructor/activity provider"], ["council_public_service", "Council/public service"],
  ["other_organisation", "Other organisation"],
] as const;

function authSessionFromPayload(payload: AuthPayload): AuthSession | null {
  if (payload.session?.access_token && payload.session.user) {
    return payload.session;
  }
  if (payload.access_token && payload.user) {
    return {
      access_token: payload.access_token,
      refresh_token: payload.refresh_token,
      expires_at: payload.expires_at,
      user: payload.user,
    };
  }
  return null;
}

function sessionExpirySeconds(current: AuthSession): number | null {
  if (typeof current.expires_at === "number") return current.expires_at;
  try {
    const payload = JSON.parse(atob(current.access_token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))) as { exp?: number };
    return typeof payload.exp === "number" ? payload.exp : null;
  } catch {
    return null;
  }
}

let sessionRefreshInFlight: Promise<AuthSession | null> | null = null;

// Returns the same session if still fresh, a new session if refreshed, or null if the refresh failed.
async function refreshSessionIfNeeded(current: AuthSession): Promise<AuthSession | null> {
  const expiresAt = sessionExpirySeconds(current);
  if (expiresAt === null || expiresAt - Date.now() / 1000 > 60) return current;
  if (!current.refresh_token) return null;
  if (!sessionRefreshInFlight) {
    sessionRefreshInFlight = (async () => {
      try {
        const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
          method: "POST",
          headers: { apikey: supabaseKey, "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: current.refresh_token }),
        });
        if (!response.ok) return null;
        return authSessionFromPayload(await response.json() as AuthPayload);
      } catch {
        return null;
      } finally {
        sessionRefreshInFlight = null;
      }
    })();
  }
  return sessionRefreshInFlight;
}

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-NZ", {
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function DateText({ value }: { value: string }) {
  const [label, setLabel] = useState(value);
  useEffect(() => {
    setLabel(
      new Intl.DateTimeFormat("en-NZ", {
        timeZone: "Pacific/Auckland",
        weekday: "short",
        day: "numeric",
        month: "short",
        hour: "numeric",
        minute: "2-digit",
      }).format(new Date(value)),
    );
  }, [value]);
  return <>{label}</>;
}

function areaLabel(value: string) {
  return value.replaceAll("-", " ");
}

function canPublish(profile: HostRecord | null, subscriptions: SubscriptionRecord[]) {
  if (TEMP_SUPPORT_OVERRIDE && profile) return true; // TEMP_SUPPORT_OVERRIDE
  return profile?.status === "approved" && subscriptions.some((sub) => {
    const stillCurrent = !sub.current_period_end || new Date(sub.current_period_end).getTime() > Date.now();
    return ["active", "trialing"].includes(sub.status) && stillCurrent;
  });
}

// renew1: bold "renews on / ends on" line from the latest current business_subscriptions row (Apple or Stripe).
function SubscriptionEndLine({ subscriptions }: { subscriptions: SubscriptionRecord[] }) {
  const now = Date.now();
  const current = subscriptions
    .filter((sub) => ["active", "trialing", "past_due", "grace_period", "cancelled"].includes(sub.status) && (!sub.current_period_end || new Date(sub.current_period_end).getTime() > now))
    .sort((a, b) => new Date(b.current_period_end ?? 0).getTime() - new Date(a.current_period_end ?? 0).getTime())[0];
  if (!current) return <p className="subscription-end"><strong>No active subscription</strong></p>;
  const title = iosPlans.find((p) => p.id === current.plan_id)?.title ?? current.plan_id;
  const date = current.current_period_end
    ? new Date(current.current_period_end).toLocaleDateString("en-NZ", { day: "numeric", month: "long", year: "numeric", timeZone: "Pacific/Auckland" })
    : null;
  const ending = current.status === "cancelled";
  return (
    <p className="subscription-end">
      <strong>{date ? `Your ${title} subscription ${ending ? "ends" : "renews"} on ${date}` : `Your ${title} subscription is active`}</strong>
    </p>
  );
}

// launch1: current subscription row (same rule as SubscriptionEndLine).
function currentSubscription(subscriptions: SubscriptionRecord[]) {
  const now = Date.now();
  return subscriptions
    .filter((sub) => ["active", "trialing", "past_due", "grace_period"].includes(sub.status) && (!sub.current_period_end || new Date(sub.current_period_end).getTime() > now))
    .sort((a, b) => new Date(b.current_period_end ?? 0).getTime() - new Date(a.current_period_end ?? 0).getTime())[0] ?? null;
}

// settings1: Stripe Billing Portal (cancel, card, invoices) via create-portal-session.
async function openBillingPortal(session: AuthSession, profileId: string) {
  const response = await fetch(`${supabaseUrl}/functions/v1/create-portal-session`, {
    method: "POST",
    headers: { ...authHeaders(session.access_token), "Content-Type": "application/json" },
    body: JSON.stringify({ business_profile_id: profileId, return_url: window.location.origin }),
  });
  const raw = await response.text();
  let body: { url?: string; error?: string } = {};
  try { body = JSON.parse(raw); } catch { /* not JSON */ }
  if (!response.ok || !body.url) throw new Error(body.error || userFacingServiceMessage(raw, response.status));
  window.location.href = body.url;
}

// settings1 TEMP_BRIDGE: notification preferences live in localStorage (iOS has no server-side preference store yet).
type NotifyPrefs = { orgPosts: boolean; reminders: boolean; pollResults: boolean; notices: boolean; supportReplies: boolean; autoCalendar: boolean; planPanel: boolean };
const defaultNotifyPrefs: NotifyPrefs = { orgPosts: true, reminders: true, pollResults: true, notices: true, supportReplies: true, autoCalendar: false, planPanel: true };
function readNotifyPrefs(userId?: string | null): NotifyPrefs {
  try { return { ...defaultNotifyPrefs, ...JSON.parse(window.localStorage.getItem(`cc-notify-prefs-v1:${userId ?? "anon"}`) || "{}") }; } catch { return defaultNotifyPrefs; }
}
function writeNotifyPrefs(userId: string | null | undefined, prefs: NotifyPrefs) {
  try { window.localStorage.setItem(`cc-notify-prefs-v1:${userId ?? "anon"}`, JSON.stringify(prefs)); } catch { /* ignore */ }
}
function ToggleRow({ title, detail, on, onChange }: { title: string; detail?: string; on: boolean; onChange: (next: boolean) => void }) {
  return (
    <label className="toggle-row">
      <span><strong>{title}</strong>{detail ? <small>{detail}</small> : null}</span>
      <input type="checkbox" role="switch" checked={on} aria-checked={on} onChange={(e) => onChange(e.target.checked)} />
    </label>
  );
}

// launch1: clear, easy cancel. Stripe → Billing Portal (create-portal-session); Apple → App Store subscriptions.
function CancelPlanControl({ subscriptions, session, profileId }: { subscriptions: SubscriptionRecord[]; session: AuthSession | null; profileId: string | null | undefined }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const current = currentSubscription(subscriptions);
  if (!current) return null;
  if (current.provider !== "stripe") {
    return (
      <div className="cancel-plan">
        <p className="panel-note"><strong>Your plan is billed by Apple.</strong> Cancel it in your Apple ID subscriptions.</p>
        <a className="button button--danger" href="https://apps.apple.com/account/subscriptions" target="_blank" rel="noreferrer">Manage subscription</a>
      </div>
    );
  }
  async function openPortal() {
    if (!session || !profileId || busy) return;
    setBusy(true); setError("");
    try {
      await openBillingPortal(session, profileId);
    } catch (e) {
      setBusy(false);
      setError(e instanceof Error ? e.message : "Could not open billing.");
    }
  }
  return (
    <div className="cancel-plan">
      <button type="button" className="button button--danger" disabled={busy} aria-busy={busy} onClick={() => void openPortal()}>{busy ? "Opening…" : "Manage subscription"}</button>
      <p className="panel-note">Opens secure Stripe billing, where you can cancel or update your card. Your plan stays active until the end of the paid period.</p>
      {error ? <p className="panel-note" role="alert">{error}</p> : null}
    </div>
  );
}

// launch1: first-visit tips overlay. Seen state in localStorage; reopen via the "cc-show-tour" window event.
const TOUR_KEY = "cc-tour-seen-v1";

// welcome1: Support's welcome listing is pinned first on Home / What's On (client-side; no owner or table needed).
const WELCOME_EVENT_ID = "e1188df3-816b-449e-973c-36133bc13bb2";
const WELCOME_EXTRA = "This is where everyone shares their events and you hand pick what you want to fill your own personal calendar up (see inside the Settings menu for My Calendar and start adding things to do).";
const WELCOME_RESURFACE_KEY = "cc-welcome-last-shown";
const WELCOME_RESURFACE_DAYS = 10;
function withWelcomeExtra(event: EventRecord): EventRecord {
  const add = (text: string | null | undefined) => {
    const base = (text ?? "").trim();
    if (!base || base.includes(WELCOME_EXTRA)) return base || WELCOME_EXTRA;
    const sign = "Ngā mihi nui.";
    return base.endsWith(sign) ? `${base.slice(0, -sign.length).trimEnd()} ${WELCOME_EXTRA} ${sign}` : `${base} ${WELCOME_EXTRA}`;
  };
  return { ...event, short_description: add(event.short_description), long_description: add(event.long_description) };
}
function WelcomeResurface({ welcome, onOpen }: { welcome: EventRecord | null; onOpen: (event: EventRecord) => void }) {
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!welcome) return;
    try {
      const now = Date.now();
      const last = Number(window.localStorage.getItem(WELCOME_RESURFACE_KEY) || 0);
      const tourShowing = !window.localStorage.getItem(TOUR_KEY);
      if (!last || tourShowing) { window.localStorage.setItem(WELCOME_RESURFACE_KEY, String(now)); return; }
      if (now - last >= WELCOME_RESURFACE_DAYS * 86400000) { window.localStorage.setItem(WELCOME_RESURFACE_KEY, String(now)); setOpen(true); }
    } catch { /* ignore */ }
  }, [welcome]);
  if (!open || !welcome) return null;
  return (
    <div className="tour-overlay" role="dialog" aria-modal="true" aria-label="Welcome to Coast Calendar" onClick={() => setOpen(false)}>
      <div className="tour-card pcc-card welcome-sheet" onClick={(e) => e.stopPropagation()}>
        <p className="tour-step">From Coast Calendar</p>
        <h3>{welcome.title}</h3>
        <p>{welcome.long_description || welcome.short_description}</p>
        <div className="action-row">
          <button type="button" className="button" onClick={() => setOpen(false)}>Close</button>
          <button type="button" className="button button--primary" onClick={() => { setOpen(false); onOpen(welcome); }}>Open</button>
        </div>
      </div>
    </div>
  );
}
const tourCards = [
  { title: "What's On", text: "See listings and polls near you. Set your area to widen or narrow what you see." },
  { title: "Create", text: "Organisations can list events and run polls. Create an account, then apply for your organisation in Settings." },
  { title: "Polls", text: "Vote on local questions and see what your community thinks. You can change or withdraw your answer while a poll is open." },
  { title: "My Calendar", text: "Save, mark Interested or Going, and add events to your phone's calendar." },
  { title: "Make it yours", text: "Use Settings to change card colours and add a wallpaper." },
  { title: "Support", text: "Questions, feedback or problems? Send us a Support message any time." },
];
function QuickTour() {
  const [open, setOpen] = useState(false);
  const [index, setIndex] = useState(0);
  useEffect(() => {
    try { if (!window.localStorage.getItem(TOUR_KEY)) setOpen(true); } catch { /* ignore */ }
    const show = () => { setIndex(0); setOpen(true); };
    window.addEventListener("cc-show-tour", show);
    return () => window.removeEventListener("cc-show-tour", show);
  }, []);
  if (!open) return null;
  const close = () => { try { window.localStorage.setItem(TOUR_KEY, "1"); } catch { /* ignore */ } setOpen(false); };
  const card = tourCards[index];
  const last = index === tourCards.length - 1;
  return (
    <div className="tour-overlay" role="dialog" aria-modal="true" aria-label="Quick tour" onClick={close}>
      <div className="tour-card pcc-card" onClick={(e) => e.stopPropagation()}>
        <p className="tour-step">{index + 1} of {tourCards.length}</p>
        <h3>{card.title}</h3>
        <p>{card.text}</p>
        <div className="tour-dots" aria-hidden="true">{tourCards.map((_, i) => <span key={i} className={i === index ? "is-on" : ""} />)}</div>
        <div className="action-row">
          <button type="button" className="button" onClick={close}>Skip</button>
          {index > 0 ? <button type="button" className="button" onClick={() => setIndex(index - 1)}>Back</button> : null}
          <button type="button" className="button button--primary" onClick={() => (last ? close() : setIndex(index + 1))}>{last ? "Got it" : "Next"}</button>
        </div>
      </div>
    </div>
  );
}

function memberDraftFromProfile(profile: HostRecord | null, email?: string): MemberDraft {
  return {
    business_name: profile?.business_name ?? "",
    contact_name: profile?.contact_name ?? "",
    contact_email: profile?.contact_email ?? email ?? "",
    phone: profile?.phone ?? "",
    website: profile?.website ?? "",
    about: profile?.about ?? "",
    area_scope_id: profile?.area_scope_id ?? "pohutukawa-coast",
    selected_plan_id: profile?.selected_plan_id ?? "local_business",
    avatar_image_url: profile?.avatar_image_url ?? "",
    hero_image_url: profile?.hero_image_url ?? "",
    avatar_image_position_x: profile?.avatar_image_position_x ?? 50,
    avatar_image_position_y: profile?.avatar_image_position_y ?? 50,
    hero_image_position_x: profile?.hero_image_position_x ?? 50,
    hero_image_position_y: profile?.hero_image_position_y ?? 50,
  };
}

function objectPosition(x: number, y: number) {
  return `${x}% ${y}%`;
}

function emptyNoticeDraft(): NoticeDraft {
  return {
    title: "",
    summary: "",
    body: "",
    template_style: "weekly_letter",
    hero_image_url: "",
    status: "draft",
  };
}

type AppView = "home" | "whatsOn" | "hosts" | "create" | "account" | "support" | "privacy" | "terms" | "contact" | "settings";


function SettingsRow({
  title,
  detail,
  action,
  onClick,
}: {
  title: string;
  detail: string;
  action: string;
  onClick: () => void;
}) {
  return (
    <button type="button" className="settings-row" onClick={onClick}>
      <span>
        <strong>{title}</strong>
        <em>{detail}</em>
      </span>
      <b>{action}</b>
    </button>
  );
}


function dateWindow(scope: "today" | "week" | "month" | "upcoming") {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const end = new Date(start);
  if (scope === "today") end.setHours(23, 59, 59, 999);
  else if (scope === "week") end.setDate(end.getDate() + 7);
  else if (scope === "month") end.setDate(end.getDate() + 30);
  else end.setDate(end.getDate() + 90);
  return { start, end };
}

function eventOverlapsWindow(event: EventRecord, scope: "today" | "week" | "month" | "upcoming") {
  const { start, end } = dateWindow(scope);
  const from = new Date(event.start_at);
  const to = new Date(event.end_at || event.start_at);
  return from <= end && to >= start;
}

type OrgCardDraft = {
  business_name: string;
  about: string;
  website: string;
  contact_name: string;
  contact_email: string;
  phone: string;
  public_location_text: string;
};

const PUBLIC_PROFILE_SELECT = "id,public_slug,display_name,area_scope_id,bio,public_contact_name,public_contact_email,public_phone,public_location_text,public_address,public_website,avatar_image_path,hero_image_path,avatar_image_position_x,avatar_image_position_y,hero_image_position_x,hero_image_position_y,published_at,public_contact_revision,public_contact_confirmed_revision,public_contact_confirmed_at";
type PublicProfileDraft = Record<string, string | number | null | undefined>;

const orgCardFields: { key: keyof OrgCardDraft; label: string; placeholder: string; multiline?: boolean }[] = [
  { key: "business_name", label: "Organisation name", placeholder: "e.g. Beachlands Community Hall" },
  { key: "about", label: "About", placeholder: "Tell people who you are, what you run and who it's for.", multiline: true },
  { key: "website", label: "Website", placeholder: "https://" },
  { key: "contact_name", label: "Contact name", placeholder: "Who people should ask for" },
  { key: "contact_email", label: "Contact email", placeholder: "hello@yourorg.nz" },
  { key: "phone", label: "Phone", placeholder: "Optional" },
];

type OrgImageDraft = {
  avatar_image_url: string;
  hero_image_url: string;
  avatar_image_position_x: number;
  avatar_image_position_y: number;
  hero_image_position_x: number;
  hero_image_position_y: number;
};

function InlineField({ value, placeholder, multiline, onChange, className, type = "text" }: {
  value: string;
  placeholder: string;
  multiline?: boolean;
  onChange: (value: string) => void;
  className?: string;
  type?: string;
}) {
  const [open, setOpen] = useState(false);
  if (open) {
    return multiline ? (
      <textarea autoFocus className={`inline-field__input ${className ?? ""}`} value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} onBlur={() => setOpen(false)} />
    ) : (
      <input autoFocus type={type} className={`inline-field__input ${className ?? ""}`} value={value} placeholder={placeholder} onChange={(e) => onChange(e.target.value)} onBlur={() => setOpen(false)} onKeyDown={(e) => { if (e.key === "Enter") setOpen(false); }} />
    );
  }
  return (
    <button type="button" className={`inline-field ${value ? "" : "is-empty"} ${className ?? ""}`} onClick={(e) => { e.stopPropagation(); setOpen(true); }} title="Tap to edit">
      {value || placeholder}
    </button>
  );
}

const memberPlans = [
  ["local_business", "Local Member", "Best for a school, club, venue, class, group or local business starting out."],
  ["growth", "Growth Member", "Best for regular listings, campaigns and a wider local push."],
  ["sponsor", "Community Partner", "Best for members who want strongest placement and more active listings."],
] as const;

function MembershipPlanSection({ selectedPlan, onSelect, disabled, approvedAndPaid }: {
  selectedPlan: string | null;
  onSelect?: (plan: string) => void;
  disabled: boolean;
  approvedAndPaid: boolean;
}) {
  return (
    <>
      <section className="notice-composer">
        <div className="section-mini-header">
          <p className="eyebrow">Plan first</p>
          <h3>Choose what you are applying for</h3>
          <p className="panel-note">Payment only happens after Support approval. Choosing now means you know the reward before filling in the member page.</p>
        </div>
        <div className="template-grid" role="radiogroup" aria-label="Member plan">
          {memberPlans.map(([value, title, text]) => (
            <button
              type="button"
              className={selectedPlan === value ? "template-card template-card--active" : "template-card"}
              key={value}
              onClick={() => onSelect?.(value)}
              disabled={disabled}
            >
              <strong>{title}</strong>
              <span>{text}</span>
            </button>
          ))}
        </div>
      </section>
      <div className="payment-note">
        <strong>Payments</strong>
        <span>{approvedAndPaid ? "Active subscription found. Web listing creation is available." : "After Support approval, finish subscription inside the iPhone app so Apple handles billing and cancellation."}</span>
      </div>
    </>
  );
}

// Renders a photo exactly like the card: object-fit cover, object-position x/y, then zoom about that same point.
function FramedPhoto({ src, x, y, zoom, onLoad }: { src: string; x: number; y: number; zoom: number; onLoad?: (img: HTMLImageElement) => void }) {
  return (
    <img
      className="framed-photo"
      alt=""
      draggable={false}
      src={src}
      onLoad={(e) => onLoad?.(e.currentTarget)}
      style={{ objectPosition: `${x}% ${y}%`, transform: zoom !== 1 ? `scale(${zoom})` : undefined, transformOrigin: `${x}% ${y}%` }}
    />
  );
}

function PhotoAdjustModal({ kind, src, x, y, zoom, onCancel, onOk }: {
  kind: "avatar" | "hero";
  src: string | null;
  x: number;
  y: number;
  zoom: number;
  onCancel: () => void;
  onOk: (x: number, y: number, zoom: number) => void;
}) {
  const [pos, setPos] = useState({ x, y });
  const [scale, setScale] = useState(zoom);
  const [natural, setNatural] = useState<{ w: number; h: number } | null>(null);
  const [dragging, setDragging] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);
  const dragRef = useRef<{ id: number; lastX: number; lastY: number } | null>(null);
  const clamp = (n: number) => Math.max(0, Math.min(100, n));

  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    dialogRef.current?.querySelector<HTMLElement>(".photo-modal__frame")?.focus();
    return () => previous?.focus?.();
  }, []);

  function onKeyDown(event: ReactKeyboardEvent<HTMLDivElement>) {
    if (event.key === "Escape") { event.preventDefault(); onCancel(); return; }
    if (event.key !== "Tab" || !dialogRef.current) return;
    const items = Array.from(dialogRef.current.querySelectorAll<HTMLElement>("button, input, [tabindex='0']")).filter((el) => !el.hasAttribute("disabled"));
    if (!items.length) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  }

  // 1:1 drag. With cover width W (frame F) and zoom z about the object-position point,
  // the image moves (z*W - F) px per 100% of position, so dp = -dx / (z*W - F) * 100.
  function move(dx: number, dy: number, frame: DOMRect) {
    if (!natural) return;
    const cover = Math.max(frame.width / natural.w, frame.height / natural.h);
    const spanX = scale * natural.w * cover - frame.width;
    const spanY = scale * natural.h * cover - frame.height;
    setPos((current) => ({
      x: spanX > 0.5 ? clamp(current.x - (dx / spanX) * 100) : current.x,
      y: spanY > 0.5 ? clamp(current.y - (dy / spanY) * 100) : current.y,
    }));
  }

  return (
    <div className="photo-modal__backdrop" onMouseDown={(e) => { if (e.target === e.currentTarget) onCancel(); }}>
      <div ref={dialogRef} className="photo-modal" role="dialog" aria-modal="true" aria-label={kind === "hero" ? "Adjust cover photo" : "Adjust profile photo"} onKeyDown={onKeyDown}>
        <h3>{kind === "hero" ? "Adjust cover photo" : "Adjust profile photo"}</h3>
        <p className="panel-note">Press and drag the photo to position it.</p>
        <div
          className={`photo-modal__frame photo-modal__frame--${kind}${dragging ? " is-dragging" : ""}`}
          tabIndex={0}
          aria-label="Photo. Press and drag to move."
          onPointerDown={(e) => { e.preventDefault(); e.currentTarget.setPointerCapture(e.pointerId); dragRef.current = { id: e.pointerId, lastX: e.clientX, lastY: e.clientY }; setDragging(true); }}
          onPointerMove={(e) => {
            const drag = dragRef.current;
            if (!drag || drag.id !== e.pointerId) return;
            const dx = e.clientX - drag.lastX;
            const dy = e.clientY - drag.lastY;
            drag.lastX = e.clientX;
            drag.lastY = e.clientY;
            move(dx, dy, e.currentTarget.getBoundingClientRect());
          }}
          onPointerUp={() => { dragRef.current = null; setDragging(false); }}
          onPointerCancel={() => { dragRef.current = null; setDragging(false); }}
        >
          {src ? <FramedPhoto src={src} x={pos.x} y={pos.y} zoom={scale} onLoad={(img) => setNatural({ w: img.naturalWidth, h: img.naturalHeight })} /> : <span>Loading photo…</span>}
        </div>
        <label className="photo-modal__zoom">
          <span>Zoom</span>
          <input type="range" min={1} max={3} step={0.01} value={scale} onChange={(e) => setScale(Number(e.target.value))} />
          <span>{scale.toFixed(1)}×</span>
        </label>
        <p className="panel-note photo-modal__note">Zoom is only a preview. Position is saved; zoom is not saved yet.</p>
        <div className="photo-modal__actions">
          <button type="button" className="button button--secondary" onClick={onCancel}>Cancel</button>
          <button type="button" className="button button--primary" onClick={() => onOk(Math.round(pos.x), Math.round(pos.y), scale)}>OK</button>
        </div>
      </div>
    </div>
  );
}

function OrgCardPane({ profile, busy, onBack, onUpload, accessToken, subscriptions = [], onReload, onSupport }: {
  accessToken?: string;
  profile: HostRecord;
  busy: boolean;
  onBack: () => void;
  onUpload?: (file: File, kind: "avatar" | "hero") => Promise<string>;
  subscriptions?: SubscriptionRecord[];
  onReload?: () => Promise<void> | void;
  onSupport?: () => void;
}) {
  // iOS parity: the public org card lives in public_member_profiles and is saved via
  // save_member_public_profile_with_images (SupabaseEventService.swift). business_profiles is not patched.
  const [pub, setPub] = useState<PublicProfileDraft | null>(null);
  const str = (v: unknown, fallback: unknown = "") => String(v ?? fallback ?? "");
  const num = (v: unknown, fallback: unknown) => (typeof v === "number" ? v : typeof fallback === "number" ? fallback : 50);
  const initial: OrgCardDraft = {
    business_name: str(pub?.display_name, profile.business_name),
    about: str(pub?.bio, profile.about),
    website: str(pub?.public_website, profile.website),
    contact_name: str(pub?.public_contact_name, profile.contact_name),
    contact_email: str(pub?.public_contact_email, profile.contact_email),
    phone: str(pub?.public_phone, profile.phone),
    public_location_text: str(pub?.public_location_text),
  };
  const initialImages: OrgImageDraft = {
    avatar_image_url: str(pub?.avatar_image_path, profile.avatar_image_url),
    hero_image_url: str(pub?.hero_image_path, profile.hero_image_url),
    avatar_image_position_x: num(pub?.avatar_image_position_x, profile.avatar_image_position_x),
    avatar_image_position_y: num(pub?.avatar_image_position_y, profile.avatar_image_position_y),
    hero_image_position_x: num(pub?.hero_image_position_x, profile.hero_image_position_x),
    hero_image_position_y: num(pub?.hero_image_position_y, profile.hero_image_position_y),
  };
  const loadPub = useCallback(async () => {
    if (!accessToken) return null;
    try {
      const rows = await rest<PublicProfileDraft[]>(`public_member_profiles?select=${PUBLIC_PROFILE_SELECT}&id=eq.${profile.id}&limit=1`, {}, accessToken);
      const row = rows?.[0] ?? null;
      setPub(row);
      return row;
    } catch { return null; }
  }, [accessToken, profile.id]);
  const [draft, setDraft] = useState<OrgCardDraft>(initial);
  // Set once the owner edits anything; the saved-card load then won't overwrite their typing.
  const touchedRef = useRef(false);
  const [images, setImages] = useState<OrgImageDraft>(initialImages);
  const editDraft = (next: OrgCardDraft) => { touchedRef.current = true; setDraft(next); };
  const editImages = (next: OrgImageDraft) => { touchedRef.current = true; setImages(next); };
  const [uploading, setUploading] = useState<"" | "avatar" | "hero">("");
  const [saved, setSaved] = useState("");
  const [reloading, setReloading] = useState(false);
  useEffect(() => {
    void loadPub().then((row) => {
      if (!row || touchedRef.current) return;
      setDraft({
        business_name: str(row.display_name, profile.business_name),
        about: str(row.bio, profile.about),
        website: str(row.public_website, profile.website),
        contact_name: str(row.public_contact_name, profile.contact_name),
        contact_email: str(row.public_contact_email, profile.contact_email),
        phone: str(row.public_phone, profile.phone),
        public_location_text: str(row.public_location_text),
      });
      setImages({
        avatar_image_url: str(row.avatar_image_path, profile.avatar_image_url),
        hero_image_url: str(row.hero_image_path, profile.hero_image_url),
        avatar_image_position_x: num(row.avatar_image_position_x, profile.avatar_image_position_x),
        avatar_image_position_y: num(row.avatar_image_position_y, profile.avatar_image_position_y),
        hero_image_position_x: num(row.hero_image_position_x, profile.hero_image_position_x),
        hero_image_position_y: num(row.hero_image_position_y, profile.hero_image_position_y),
      });
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [loadPub]);
  const changed = (Object.keys(initial) as (keyof OrgCardDraft)[]).filter((key) => draft[key].trim() !== initial[key].trim());
  const changedImages = (Object.keys(initialImages) as (keyof OrgImageDraft)[]).filter((key) => images[key] !== initialImages[key]);
  const dirty = changed.length + changedImages.length > 0;
  const editing = true;
  const [display, setDisplay] = useState<{ avatar: string | null; hero: string | null }>({ avatar: null, hero: null });
  useEffect(() => {
    let cancelled = false;
    void Promise.all([resolveMemberImage(images.avatar_image_url, accessToken), resolveMemberImage(images.hero_image_url, accessToken)])
      .then(([avatar, hero]) => { if (!cancelled) setDisplay({ avatar, hero }); });
    return () => { cancelled = true; };
  }, [images.avatar_image_url, images.hero_image_url, accessToken]);
  const [menu, setMenu] = useState<"" | "avatar" | "hero">("");
  const [adjust, setAdjust] = useState<"" | "avatar" | "hero">("");
  // Session-only zoom: NOT SAVED. business_profiles has no zoom/scale column, so this resets on reload.
  const [zoom, setZoom] = useState<{ avatar: number; hero: number }>({ avatar: 1, hero: 1 });
  const fileInputs = { avatar: useRef<HTMLInputElement>(null), hero: useRef<HTMLInputElement>(null) };

  async function pick(kind: "avatar" | "hero", file: File | undefined) {
    if (!file || !onUpload) return;
    setUploading(kind);
    setSaved("");
    try {
      const url = await onUpload(file, kind);
      // Store the storage path (same form the Hosts signer accepts), not the public URL.
      setImages((current) => ({ ...current, [`${kind}_image_url`]: memberImagePath(url) ?? url }));
      setAdjust(kind);
    } catch (error) {
      setSaved(`Not saved: ${error instanceof Error ? error.message : "Upload failed."}`);
    } finally {
      setUploading("");
    }
  }

  function tapImage(kind: "avatar" | "hero") {
    if (!editing || adjust) return;
    if (!images[`${kind}_image_url`]) {
      fileInputs[kind].current?.click();
      return;
    }
    setMenu(menu === kind ? "" : kind);
  }

  const imageMenu = (kind: "avatar" | "hero") => menu === kind ? (
    <div className={`org-preview__menu org-preview__menu--${kind}`} role="menu">
      <button type="button" onClick={() => { setMenu(""); fileInputs[kind].current?.click(); }}>Change photo</button>
      <button type="button" onClick={() => { setMenu(""); setAdjust(kind); }}>Adjust position</button>
      <button type="button" className="is-danger" onClick={() => { setMenu(""); editImages({ ...images, [`${kind}_image_url`]: "" }); }}>Remove</button>
      <button type="button" onClick={() => setMenu("")}>Cancel</button>
    </div>
  ) : null;

  function save() {
    if (!dirty) return;
    if (!draft.business_name.trim()) { setSaved("Not saved: organisation name can't be empty."); return; }
    if (!draft.contact_email.trim()) { setSaved("Not saved: contact email can't be empty."); return; }
    if (!accessToken) { setSaved("Not saved: sign in again."); return; }
    const t = (v: string) => v.trim() || null;
    const asPath = (v: string) => (v ? memberImagePath(v) ?? v : null);
    setSaved("Saving…");
    void rpc<unknown>("save_member_public_profile_with_images", {
      p_business_profile_id: profile.id,
      p_display_name: draft.business_name.trim(),
      p_area_scope_id: (pub?.area_scope_id as string | null | undefined) ?? profile.area_scope_id ?? null,
      p_bio: t(draft.about),
      p_public_contact_name: t(draft.contact_name),
      p_public_contact_email: t(draft.contact_email),
      p_public_phone: t(draft.phone),
      p_public_location_text: t(draft.public_location_text),
      p_public_address: (pub?.public_address as string | null | undefined) ?? null,
      p_public_website: t(draft.website),
      p_avatar_image_path: asPath(images.avatar_image_url),
      p_hero_image_path: asPath(images.hero_image_url),
      p_avatar_image_position_x: images.avatar_image_position_x,
      p_avatar_image_position_y: images.avatar_image_position_y,
      p_hero_image_position_x: images.hero_image_position_x,
      p_hero_image_position_y: images.hero_image_position_y,
    }, accessToken).then(async (result) => {
      const row = Array.isArray(result) ? result[0] : result;
      if (result == null || (Array.isArray(result) && result.length === 0)) {
        setSaved("Not saved: the server returned no row (check RLS / function grants for save_member_public_profile_with_images).");
        return;
      }
      if (row && typeof row === "object") setPub(row as PublicProfileDraft); else await loadPub();
      setSaved("Saved ✓");
      void onReload?.();
    }).catch((error: unknown) => {
      const msg = messageFromError(error);
      setSaved(`Not saved: ${msg}`);
    });
  }

  const activeSub = subscriptions.find((item) => item.business_profile_id === profile.id && ["active", "trialing"].includes(item.status));
  const statusTitle: Record<string, string> = { approved: "Approved", pending_review: "Pending review", rejected: "Needs changes", suspended: "Suspended" };

  return (
    <section className="account-panel org-manage">
      <button type="button" className="text-link" onClick={onBack}>← Back to Settings</button>
      <p className="eyebrow">Manage my organisation</p>
      <p className="panel-note">This is your public card. Tap the cover, the circle or any text to change it.</p>

      <article className="host-card org-manage__card">
        <div
          className="host-card__hero org-manage__hero"
          onClick={() => tapImage("hero")}
        >
          {display.hero ? <FramedPhoto src={display.hero} x={images.hero_image_position_x} y={images.hero_image_position_y} zoom={zoom.hero} /> : null}
          {!images.hero_image_url ? <span className="org-manage__hint">＋ Add cover photo</span> : null}
        </div>
        {imageMenu("hero")}
        <div
          className="host-card__avatar org-manage__avatar"
          onClick={() => tapImage("avatar")}
        >
          {display.avatar ? <FramedPhoto src={display.avatar} x={images.avatar_image_position_x} y={images.avatar_image_position_y} zoom={zoom.avatar} /> : null}
          {images.avatar_image_url ? null : (draft.business_name || "+").slice(0, 1)}
        </div>
        {imageMenu("avatar")}
        <div className="host-card__body">
          <p className="event-card__meta">{areaLabel(profile.area_scope_id)}</p>
          <h3><InlineField value={draft.business_name} placeholder="Organisation name" onChange={(v) => editDraft({ ...draft, business_name: v })} /></h3>
          <p><InlineField multiline value={draft.about} placeholder="A verified local member sharing listings with the community." onChange={(v) => editDraft({ ...draft, about: v })} /></p>
          <div className="action-row">
            <span className="chip">Belong</span>
            <span className="chip"><InlineField type="url" value={draft.website} placeholder="Add website" onChange={(v) => editDraft({ ...draft, website: v })} /></span>
          </div>
          <div className="org-manage__contact">
            <span>Contact</span>
            <InlineField value={draft.contact_name} placeholder="Contact name" onChange={(v) => editDraft({ ...draft, contact_name: v })} />
            <InlineField type="email" value={draft.contact_email} placeholder="Contact email" onChange={(v) => editDraft({ ...draft, contact_email: v })} />
            <InlineField value={draft.phone} placeholder="Phone (optional)" onChange={(v) => editDraft({ ...draft, phone: v })} />
          </div>
          <div className="org-manage__contact">
            <span>Location</span>
            <LocationTypeahead value={draft.public_location_text} placeholder="Town or area shown on your card" onChange={(v) => editDraft({ ...draft, public_location_text: v })} />
          </div>
        </div>
      </article>

      <input ref={fileInputs.hero} hidden type="file" accept="image/*" onChange={(e) => { void pick("hero", e.target.files?.[0]); e.target.value = ""; }} />
      <input ref={fileInputs.avatar} hidden type="file" accept="image/*" onChange={(e) => { void pick("avatar", e.target.files?.[0]); e.target.value = ""; }} />
      {uploading ? <p className="panel-note">Uploading photo…</p> : null}
      {adjust ? (
        <PhotoAdjustModal
          kind={adjust}
          src={adjust === "hero" ? display.hero : display.avatar}
          x={images[`${adjust}_image_position_x`] as number}
          y={images[`${adjust}_image_position_y`] as number}
          onCancel={() => setAdjust("")}
          zoom={zoom[adjust]}
          onOk={(x, y, z) => { setImages((current) => ({ ...current, [`${adjust}_image_position_x`]: x, [`${adjust}_image_position_y`]: y })); setZoom((current) => ({ ...current, [adjust]: z })); setAdjust(""); }}
        />
      ) : null}
      {saved && !dirty ? <p className={saved.startsWith("Not saved") ? "org-card__error" : "org-card__toast"} role="status">{saved}</p> : null}

      <div className="org-manage__section">
        <p className="eyebrow">Membership</p>
        <p className="status-pill">Status: {statusTitle[profile.status] ?? profile.status.replaceAll("_", " ")}{activeSub ? ` · ${iosPlans.find((plan) => plan.id === activeSub.plan_id)?.title ?? "Member"} ${activeSub.status}` : " · no active subscription"}</p>
        <MembershipPlanSection selectedPlan={profile.selected_plan_id} disabled approvedAndPaid={canPublish(profile, subscriptions)} />
        <p className="panel-note">Subscriptions are purchased in the Coast Calendar iOS app. Reload after subscribing.</p>
        {onReload ? (
          <button type="button" className="button button--secondary" aria-busy={reloading} disabled={reloading} onClick={() => { setReloading(true); void Promise.resolve(onReload()).finally(() => setReloading(false)); }}>
            {reloading ? "Reloading…" : "Reload status"}
          </button>
        ) : null}
      </div>

      <div className="org-manage__danger">
        <p className="eyebrow">Danger zone</p>
        <div className="org-manage__danger-row">
          <div>
            <strong>Cancel subscription</strong>
            <p className="panel-note">Apple plans are cancelled in your <a href="https://apps.apple.com/account/subscriptions" target="_blank" rel="noreferrer">Apple ID</a>. Card plans are managed in Settings. Your plan stays active until the end of the paid period.</p>
          </div>
        </div>
        <div className="org-manage__danger-row">
          <div>
            <strong>Shut down my organisation</strong>
            <p className="panel-note">There's no self-serve shutdown yet. Support closes organisations and archives their listings.</p>
          </div>
          <button type="button" className="button button--secondary" onClick={onSupport} disabled={!onSupport}>Ask Support to close your organisation</button>
        </div>
      </div>

      {dirty ? (
        <div className="org-savebar" role="region" aria-label="Unsaved changes">
          <span>{saved.startsWith("Not saved") ? <span className="org-card__error">{saved}</span> : "Unsaved changes"}</span>
          <div>
            <button type="button" className="text-link" onClick={() => { setDraft(initial); setImages(initialImages); setZoom({ avatar: 1, hero: 1 }); setSaved(""); setAdjust(""); }}>Discard</button>
            <button type="button" className="button button--primary" aria-busy={busy} disabled={busy || Boolean(uploading)} onClick={save}>{busy ? "Saving…" : "Save"}</button>
          </div>
        </div>
      ) : null}
    </section>
  );
}

function InfoRow({ title, detail }: { title: string; detail: string }) {
  return (
    <div className="settings-row settings-row--static">
      <span>
        <strong>{title}</strong>
        <em>{detail}</em>
      </span>
    </div>
  );
}

function SettingsHub({
  session,
  onAccount,
  onSignOut,
  onSupport,
  onRequestDelete,
  onOpenListing,
  engagements,
  boardEvents,
  busy,
  onToggleEngagement,
  memberProfile,
  onPrivacy,
  subscriptions = [],
  onTerms,
  onUploadImage,
  onMembership,
  onAccountSection,
  onReload,
  onReviewQueue,
  initialPane,
  onInitialPaneUsed,
  onPreviewOrg,
  onRegisterOrg,
  userProfile = null,
  onSaveProfile,
  notifications = [],
  onMarkNotificationRead,
  memberFollows = [],
  hosts = [],
  onToggleBelong,
}: {
  userProfile?: UserProfile | null;
  onSaveProfile?: (profile: UserProfile) => void;
  notifications?: UserNotification[];
  onMarkNotificationRead?: (id: string) => void;
  memberFollows?: MemberFollowRecord[];
  hosts?: HostRecord[];
  onToggleBelong?: (host: HostRecord) => void;
  session: AuthSession | null;
  onAccount: () => void;
  onSignOut: () => void;
  onSupport: () => void;
  onRequestDelete: () => void;
  onOpenListing: (event: EventRecord) => void;
  engagements: EngagementRecord[];
  boardEvents: EventRecord[];
  busy: boolean;
  onToggleEngagement: (eventID: string, type: EngagementRecord["engagement_type"]) => void;
  memberProfile: HostRecord | null;
  onPrivacy: () => void;
  subscriptions?: SubscriptionRecord[];
  onUploadImage?: (file: File, kind: "avatar" | "hero") => Promise<string>;
  onTerms?: () => void;
  onMembership?: () => void;
  onAccountSection?: (section: "account" | "saved" | "notifications" | "membership") => void;
  onReload?: () => Promise<void> | void;
  onReviewQueue?: () => void;
  initialPane?: "org" | "setup" | null;
  onRegisterOrg?: (draft: OrgRegistrationDraft) => Promise<boolean>;
  onInitialPaneUsed?: () => void;
  onPreviewOrg?: () => void;
}) {
  const [pane, setPane] = useState<"hub" | "wallpaper" | "card" | "listings" | "activity" | "calendar" | "org-calendar" | "account" | "org" | "reminders" | "setup" | "interactions" | "notifications" | "membership" | "subscription">(initialPane ?? "hub");
  const [interactionTab, setInteractionTab] = useState<"interested" | "going" | "belong" | "reminders" | "saved" | "shared">("interested");
  const [prefs, setPrefs] = useState<NotifyPrefs>(() => readNotifyPrefs(session?.user.id));
  const [billingBusy, setBillingBusy] = useState(false);
  const [billingError, setBillingError] = useState("");
  const [usedListings, setUsedListings] = useState<number | null>(null);
  const [deleteBlocked, setDeleteBlocked] = useState(false);
  useEffect(() => { setPrefs(readNotifyPrefs(session?.user.id)); }, [session?.user.id]);
  const updatePrefs = (patch: Partial<NotifyPrefs>) => { const next = { ...prefs, ...patch }; setPrefs(next); writeNotifyPrefs(session?.user.id, next); };
  useEffect(() => {
    if (pane !== "subscription" || !session || !memberProfile) return;
    rest<{ id: string }[]>(`events?select=id&business_profile_id=eq.${memberProfile.id}&status=eq.published`, {}, session.access_token)
      .then((rows) => setUsedListings(rows.length)).catch(() => setUsedListings(null));
  }, [pane, session, memberProfile]);
  const back = <button type="button" className="text-link" onClick={() => setPane("hub")}>← Back to Settings</button>;
  async function manageBilling() {
    if (!session || !memberProfile || billingBusy) return;
    setBillingBusy(true); setBillingError("");
    try { await openBillingPortal(session, memberProfile.id); } catch (e) { setBillingBusy(false); setBillingError(e instanceof Error ? e.message : "Could not open billing."); }
  }
  useEffect(() => {
    if (initialPane) { setPane(initialPane); onInitialPaneUsed?.(); }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialPane]);

  if (pane === "setup") {
    return (
      <GetSetUpGuide
        session={session}
        profile={memberProfile}
        subscriptions={subscriptions}
        busy={busy}
        onBack={() => setPane("hub")}
        onSignIn={onAccount}
        onRegister={onRegisterOrg}
        onUploadImage={onUploadImage}
        onReload={onReload}
        onManageOrg={() => setPane("org")}
      />
    );
  }

  if (pane === "reminders") {
    return (
      <section className="panel account-panel">
        <button type="button" className="text-link" onClick={() => setPane("hub")}>← Back to Settings</button>
        <p className="eyebrow">Organisation management</p>
        <h2>Engagement and reminders</h2>
        <div className="settings-group settings-group--pad">
          <ToggleRow title="Show 'Plan this' when I tap Going" detail="Add to calendar, Not going and a reminder note." on={prefs.planPanel} onChange={(v) => updatePrefs({ planPanel: v })} />
          <ToggleRow title="Add reminders to my phone calendar" detail="Download a calendar file with a 1-hour alert when you tap Going." on={prefs.autoCalendar} onChange={(v) => updatePrefs({ autoCalendar: v })} />
          <ToggleRow title="Reminder notifications" on={prefs.reminders} onChange={(v) => updatePrefs({ reminders: v })} />
        </div>
        <p className="panel-note">Push reminders come from the iPhone app. The website doesn't send reminder emails.</p>
      </section>
    );
  }

  if (pane === "org" && session && memberProfile) {
    return (
      <OrgCardPane
        key={memberProfile.id}
        profile={memberProfile}
        busy={busy}
        onBack={() => setPane("hub")}
        onUpload={onUploadImage}
        accessToken={session.access_token}
        subscriptions={subscriptions}
        onReload={onReload}
        onSupport={onSupport}
      />
    );
  }

  if (pane === "account") {
    const current = currentSubscription(subscriptions);
    return (
      <section className="panel account-panel">
        {back}
        <p className="eyebrow">Account</p>
        <h2>Account details</h2>
        {!session ? (
          <button type="button" className="button button--primary" onClick={onAccount}>Sign in</button>
        ) : (
          <>
            <form className="settings-form" onSubmit={(event) => {
              event.preventDefault();
              if (!onSaveProfile) return;
              const data = new FormData(event.currentTarget);
              onSaveProfile({
                user_id: session.user.id,
                display_name: String(data.get("display_name") ?? ""),
                public_role: userProfile?.public_role ?? "",
                organisation_name: userProfile?.organisation_name ?? "",
                phone: String(data.get("phone") ?? ""),
                website: userProfile?.website ?? "",
                preferred_contact_email: userProfile?.preferred_contact_email ?? session.user.email ?? "",
                avatar_image_url: userProfile?.avatar_image_url ?? "",
                contact_visibility: userProfile?.contact_visibility ?? "name_and_email",
              });
            }}>
              <label>Name<input name="display_name" defaultValue={userProfile?.display_name ?? ""} autoComplete="name" /></label>
              <label>Email<input value={session.user.email ?? ""} readOnly aria-readonly="true" /><small>Your sign-in email. Contact Support to change it.</small></label>
              <label>Phone<input name="phone" defaultValue={userProfile?.phone ?? ""} inputMode="tel" autoComplete="tel" /></label>
              <label>Address <em>Optional</em><input disabled placeholder="Coming soon" /><small>Personal addresses aren't stored yet.</small></label>
              <div className="action-row"><button className="button button--primary" disabled={busy} aria-busy={busy}>{busy ? "Saving…" : "Save"}</button></div>
            </form>

            <p className="eyebrow">Payment details</p>
            <div className="settings-group settings-group--pad">
              {!current ? <p className="panel-note">No payment details on file.</p>
                : current.provider === "stripe" ? (
                  <>
                    <p className="panel-note">Card payments by Stripe for your organisation plan.</p>
                    <button type="button" className="button" disabled={billingBusy} onClick={() => void manageBilling()}>{billingBusy ? "Opening…" : "View card and invoices"}</button>
                    {billingError ? <p className="panel-note" role="alert">{billingError}</p> : null}
                  </>
                ) : <p className="panel-note">Your plan is billed by Apple. <a href="https://apps.apple.com/account/subscriptions" target="_blank" rel="noreferrer">Manage in Apple ID</a></p>}
            </div>

            <div className="danger-zone">
              <button type="button" className="button button--danger" onClick={() => (memberProfile ? setDeleteBlocked(true) : onRequestDelete())}>Request account deletion</button>
              {deleteBlocked && memberProfile ? (
                <div className="status-card" role="alert">
                  <strong>Transfer ownership or delete your organisation first</strong>
                  <p>You own {memberProfile.business_name}. Support can transfer it to someone else or close it and archive its listings.</p>
                  <button type="button" className="button button--primary" onClick={onSupport}>Contact Support</button>
                </div>
              ) : null}
            </div>
          </>
        )}
      </section>
    );
  }

  if (pane === "interactions") {
    const boardByID = new Map(boardEvents.map((event) => [event.id, event]));
    const byType = (type: EngagementRecord["engagement_type"]) => engagements
      .filter((row) => row.engagement_type === type)
      .map((row) => ({ row, event: boardByID.get(row.event_id) ?? row.events }))
      .filter((item): item is { row: EngagementRecord; event: EventRecord } => Boolean(item.event));
    const tabs: [typeof interactionTab, string][] = [["interested", "Liked / Interested"], ["going", "Going"], ["belong", "Belong"], ["reminders", "Reminders"], ["saved", "Saved"], ["shared", "Shared"]];
    const listFor = (type: EngagementRecord["engagement_type"], removeLabel: string) => {
      const items = byType(type);
      if (!items.length) return <p className="panel-note">Nothing here yet.</p>;
      return (
        <ul className="interaction-list">
          {items.map(({ row, event }) => (
            <li key={row.id}>
              <button type="button" className="interaction-list__title" onClick={() => onOpenListing(event)}>
                {event.listing_kind === "poll" ? <span className="poll-chip">POLL</span> : null}{event.title}
                <small><DateText value={event.start_at} /></small>
              </button>
              <button type="button" className="button button--small" disabled={busy} onClick={() => onToggleEngagement(event.id, type)}>{removeLabel}</button>
            </li>
          ))}
        </ul>
      );
    };
    const hostByID = new Map(hosts.map((host) => [host.id, host]));
    return (
      <section className="panel account-panel">
        {back}
        <p className="eyebrow">Account</p>
        <h2>My interactions</h2>
        {!session ? <button type="button" className="button button--primary" onClick={onAccount}>Sign in</button> : (
          <>
            <div className="chip-row" role="tablist">
              {tabs.map(([id, label]) => <button key={id} type="button" role="tab" aria-selected={interactionTab === id} className={interactionTab === id ? "chip chip--active" : "chip"} onClick={() => setInteractionTab(id)}>{label}</button>)}
            </div>
            {interactionTab === "interested" ? listFor("interested", "Remove") : null}
            {interactionTab === "going" ? listFor("going", "Not going") : null}
            {interactionTab === "saved" ? listFor("saved", "Unsave") : null}
            {interactionTab === "reminders" ? (
              <>
                <p className="panel-note">Reminders come from listings you're Going to. Add one to your phone calendar for a 1-hour alert.</p>
                {byType("going").length ? (
                  <ul className="interaction-list">
                    {byType("going").map(({ row, event }) => (
                      <li key={row.id}>
                        <button type="button" className="interaction-list__title" onClick={() => onOpenListing(event)}>{event.title}<small><DateText value={event.start_at} /></small></button>
                        <button type="button" className="button button--small" onClick={() => downloadEventIcs(event)}>Add to calendar</button>
                      </li>
                    ))}
                  </ul>
                ) : <p className="panel-note">Nothing here yet.</p>}
              </>
            ) : null}
            {interactionTab === "belong" ? (
              memberFollows.length ? (
                <ul className="interaction-list">
                  {memberFollows.map((follow) => {
                    const host = hostByID.get(follow.business_profile_id);
                    return (
                      <li key={follow.id}>
                        <span className="interaction-list__title">{host?.business_name ?? "Organisation"}<small>Belonging since <DateText value={follow.created_at} /></small></span>
                        {host && onToggleBelong ? <button type="button" className="button button--small" disabled={busy} onClick={() => onToggleBelong(host)}>Leave</button> : null}
                      </li>
                    );
                  })}
                </ul>
              ) : <p className="panel-note">You don't Belong to any organisations yet. Open a host page and tap Belong.</p>
            ) : null}
            {interactionTab === "shared" ? <p className="panel-note">Shares aren't saved to your account yet, so there's nothing to list here.</p> : null}
          </>
        )}
      </section>
    );
  }

  if (pane === "notifications") {
    const unread = notifications.filter((n) => !n.read_at);
    return (
      <section className="panel account-panel">
        {back}
        <p className="eyebrow">Account</p>
        <h2>Notifications</h2>
        <div className="settings-group settings-group--pad">
          <ToggleRow title="New posts from organisations you Belong to" on={prefs.orgPosts} onChange={(v) => updatePrefs({ orgPosts: v })} />
          <ToggleRow title="Reminders" detail="For listings you're Going to." on={prefs.reminders} onChange={(v) => updatePrefs({ reminders: v })} />
          <ToggleRow title="Poll results" on={prefs.pollResults} onChange={(v) => updatePrefs({ pollResults: v })} />
          <ToggleRow title="Notices" on={prefs.notices} onChange={(v) => updatePrefs({ notices: v })} />
          <ToggleRow title="Support replies" on={prefs.supportReplies} onChange={(v) => updatePrefs({ supportReplies: v })} />
          <ToggleRow title="Add reminders to my phone calendar" detail="When you tap Going, download a calendar file with a 1-hour alert." on={prefs.autoCalendar} onChange={(v) => updatePrefs({ autoCalendar: v })} />
        </div>
        <p className="panel-note">These choices are saved on this device. Push alerts come from the iPhone app.</p>
        <p className="eyebrow">Recent updates{unread.length ? ` · ${unread.length} unread` : ""}</p>
        {notifications.length ? (
          <ul className="interaction-list">
            {notifications.slice(0, 30).map((n) => (
              <li key={n.id} className={n.read_at ? "" : "is-unread"}>
                <span className="interaction-list__title">{n.title}<small>{n.body}</small></span>
                {!n.read_at && onMarkNotificationRead ? <button type="button" className="button button--small" onClick={() => onMarkNotificationRead(n.id)}>Mark read</button> : null}
              </li>
            ))}
          </ul>
        ) : <p className="panel-note">No updates yet.</p>}
      </section>
    );
  }

  if (pane === "membership") {
    const hostByID = new Map(hosts.map((host) => [host.id, host]));
    return (
      <section className="panel account-panel">
        {back}
        <p className="eyebrow">Account</p>
        <h2>Membership</h2>
        {!session ? <button type="button" className="button button--primary" onClick={onAccount}>Sign in</button> : (
          <ul className="interaction-list">
            {memberProfile ? (
              <li>
                <span className="interaction-list__title">{memberProfile.business_name}<small>Owner · {memberProfile.status.replaceAll("_", " ")}</small></span>
                <small className="panel-note">Owners can't leave. Ask Support to transfer ownership.</small>
              </li>
            ) : null}
            {memberFollows.map((follow) => {
              const host = hostByID.get(follow.business_profile_id);
              return (
                <li key={follow.id}>
                  <span className="interaction-list__title">{host?.business_name ?? "Organisation"}<small>Member (Belong)</small></span>
                  {host && onToggleBelong ? <button type="button" className="button button--small" disabled={busy} onClick={() => onToggleBelong(host)}>Leave</button> : null}
                </li>
              );
            })}
            {!memberProfile && !memberFollows.length ? <li><span className="panel-note">You don't own or Belong to any organisations yet.</span></li> : null}
          </ul>
        )}
      </section>
    );
  }

  if (pane === "subscription") {
    const current = currentSubscription(subscriptions);
    const title = current ? iosPlans.find((p) => p.id === current.plan_id)?.title ?? current.plan_id : null;
    return (
      <section className="panel account-panel">
        {back}
        <p className="eyebrow">Organisation management</p>
        <h2>Organisation subscription</h2>
        {!session || !memberProfile ? (
          <button type="button" className="button button--primary" onClick={() => setPane("setup")}>Get set up</button>
        ) : !current ? (
          <>
            <SubscriptionEndLine subscriptions={subscriptions} />
            <button type="button" className="button button--primary" onClick={() => setPane("setup")}>Choose a plan</button>
          </>
        ) : (
          <>
            <p className="status-pill">{title}</p>
            <SubscriptionEndLine subscriptions={subscriptions} />
            <div className="settings-group settings-group--pad">
              <InfoRow title="Active listings and polls" detail={`${usedListings ?? "–"} used of ${current.active_listing_limit} · ${usedListings == null ? "" : Math.max(0, current.active_listing_limit - usedListings) + " remaining"}`} />
              <InfoRow title="Placement" detail="Placement follows your plan." />
              <InfoRow title="Billed by" detail={current.provider === "stripe" ? "Card (Stripe)" : "Apple"} />
            </div>
            {current.provider === "stripe" ? (
              <>
                <button type="button" className="button" disabled={billingBusy} onClick={() => void manageBilling()}>{billingBusy ? "Opening…" : "Billing details and invoice PDFs"}</button>
                <p className="panel-note">Opens Stripe billing, where you can update your card and download invoices.</p>
                {billingError ? <p className="panel-note" role="alert">{billingError}</p> : null}
              </>
            ) : null}
            <div className="danger-zone"><CancelPlanControl subscriptions={subscriptions} session={session} profileId={memberProfile.id} /></div>
          </>
        )}
      </section>
    );
  }
  const orgApproved = Boolean(session && memberProfile && (TEMP_SUPPORT_OVERRIDE || memberProfile.status === "approved")); // TEMP_SUPPORT_OVERRIDE

  if (pane === "org-calendar" && session && memberProfile && orgApproved) {
    return <OrgCalendarPane session={session} profile={memberProfile} onBack={() => setPane("hub")} onOpen={onOpenListing} />;
  }
  const theme = readTheme(session?.user.id);

  if (pane === "calendar") {
    return (
      <MyCalendarPane
        session={session}
        engagements={engagements}
        boardEvents={boardEvents}
        busy={busy}
        onBack={() => setPane("hub")}
        onSignIn={onAccount}
        onOpen={onOpenListing}
        onToggle={onToggleEngagement}
      />
    );
  }

  if (pane === "activity") {
    const boardByID = new Map(boardEvents.map((event) => [event.id, event]));
    const grouped = new Map<string, { event: EventRecord; active: Set<string> }>();
    for (const engagement of engagements) {
      const event = boardByID.get(engagement.event_id) ?? engagement.events;
      if (!event) continue;
      const entry = grouped.get(engagement.event_id) ?? { event, active: new Set<string>() };
      entry.active.add(engagement.engagement_type);
      grouped.set(engagement.event_id, entry);
    }
    const items = Array.from(grouped.values());
    return (
      <section className="panel account-panel">
        <button type="button" className="text-link" onClick={() => setPane("hub")}>← Back to Settings</button>
        <p className="eyebrow">My activity</p>
        <h2>My engagements</h2>
        <p className="panel-note">Listings you mark Interested, Going, or Save appear here.</p>
        {!session ? (
          <button type="button" className="button button--primary" onClick={onAccount}>Sign in</button>
        ) : items.length === 0 ? (
          <div className="panel-note">
            <strong>Nothing saved yet</strong>
            <p>Tap Save, Interested, or Going on a listing to keep it here.</p>
          </div>
        ) : (
          items.map(({ event, active }) => (
            <EventCard
              key={event.id}
              event={event}
              active={active}
              busy={busy}
              onToggle={onToggleEngagement}
              onOpen={onOpenListing}
            />
          ))
        )}
      </section>
    );
  }

  if (pane === "wallpaper") {
    return (
      <section className="panel account-panel">
        <button type="button" className="text-link" onClick={() => setPane("hub")}>← Back to Settings</button>
        <p className="eyebrow">Appearance</p>
        <h2>App wallpaper</h2>
        <div className="settings-grid">
          {wallpapers.map((item) => (
            <button type="button" key={item.id} className="settings-swatch" onClick={() => { saveTheme({ wallpaper: item.id }, session?.user.id); setPane("hub"); }}>
              <span className="settings-swatch__preview" style={item.file ? { backgroundImage: `url(${item.file})` } : { background: "var(--pcc-cream)" }} />
              <span>{item.title}</span>
            </button>
          ))}
        </div>
      </section>
    );
  }


  if (pane === "listings") {
    return (
      <MyListingsPane
        session={session}
        onBack={() => setPane("hub")}
        onOpen={onOpenListing}
        onSignIn={onAccount}
      />
    );
  }

  if (pane === "card") {
    return (
      <section className="panel account-panel">
        <button type="button" className="text-link" onClick={() => setPane("hub")}>← Back to Settings</button>
        <p className="eyebrow">Appearance</p>
        <h2>Card colour</h2>
        <p className="panel-note">Pick a readable card surface for your wallpaper.</p>
        <div className="settings-grid">
          {cardTints.map((item) => (
            <button type="button" key={item.id} className="settings-swatch" onClick={() => { saveTheme({ card: item.id }, session?.user.id); setPane("hub"); }}>
              <span className="settings-swatch__preview" data-card={item.id} />
              <span>{item.title}</span>
            </button>
          ))}
        </div>
      </section>
    );
  }

  const activeSub = memberProfile ? subscriptions.find((item) => item.business_profile_id === memberProfile.id && ["active", "trialing"].includes(item.status)) : undefined;
  const memberStatusTitle: Record<string, string> = { approved: "Approved", pending_review: "Pending review", pending: "Pending review", rejected: "Needs changes", suspended: "Suspended" };
  const memberPageDetail = !session ? "Apply" : !memberProfile ? "Set up" : activeSub ? "Preview" : (memberStatusTitle[memberProfile.status] ?? memberProfile.status);
  const publicName = memberProfile?.contact_name || memberProfile?.business_name || "";
  return (
    <section className="account-panel settings-ios">
      <div className="panel settings-header">
        <p className="eyebrow">YOUR SPACE</p>
        <h2>Settings</h2>
        <p className="panel-note">Account, membership, saved activity and reminders.</p>
      </div>

      <p className="eyebrow">Account</p>
      <div className="settings-group">
        {session ? (
          <>
            <SettingsRow title="Account details" detail={publicName ? `${publicName} · ${session.user.email ?? ""}` : session.user.email ?? "Name, email, phone and payment"} action="Open" onClick={() => setPane("account")} />
            <SettingsRow title="My interactions" detail="Liked, Going, Belong, Reminders, Saved and Shared." action="Open" onClick={() => setPane("interactions")} />
            <SettingsRow title="Notifications" detail={notifications.some((n) => !n.read_at) ? `${notifications.filter((n) => !n.read_at).length} unread · choose what you hear about` : "Choose what you hear about."} action="Open" onClick={() => setPane("notifications")} />
            <SettingsRow title="Membership" detail="Organisations you own or Belong to." action="Open" onClick={() => setPane("membership")} />
            <SettingsRow title="My Calendar" detail="Your Going dates and organisations you Belong to." action="Open" onClick={() => setPane("calendar")} />
          </>
        ) : (
          <SettingsRow title="Create account or sign in" detail="Create a free account to save listings, set reminders, and Belong to organisations." action="Open" onClick={onAccount} />
        )}
      </div>

      <p className="eyebrow">Organisation management</p>
      <div className="settings-group">
        <SettingsRow
          title="Organisation home page"
          detail={memberProfile ? "Your public organisation card. Edit it in place." : "Register your organisation to get a public page."}
          action={memberPageDetail}
          onClick={() => (session && memberProfile && memberProfile.status === "approved" ? setPane("org") : setPane("setup"))}
        />
        <SettingsRow title="Organisation subscription" detail={memberProfile ? "Plan, renewal, usage, billing and cancel." : "Choose a plan after approval."} action="Open" onClick={() => setPane(session && memberProfile ? "subscription" : "setup")} />
        <SettingsRow title="Engagement and reminders" detail="Going, Plan this and calendar reminders." action="Open" onClick={() => setPane("reminders")} />
        <SettingsRow title="Get set up" detail="Account, organisation, approval, plan and payment — step by step." action="Open" onClick={() => setPane("setup")} />
        {session && memberProfile && onPreviewOrg ? (
          <SettingsRow title="Preview my public page" detail="See your organisation card and listings as the public sees them." action="Open" onClick={onPreviewOrg} />
        ) : null}
        {session ? (
          <SettingsRow title="My listings" detail="Review, edit, remove, and follow Support feedback." action="Open" onClick={() => setPane("listings")} />
        ) : null}
        {orgApproved ? (
          <SettingsRow title="Org Calendar" detail="Add and manage dates for your organisation." action="Open" onClick={() => setPane("org-calendar")} />
        ) : null}
      </div>

      <p className="eyebrow">Appearance</p>
      <div className="settings-group">
        <SettingsRow title="App wallpaper" detail={wallpapers.find((item) => item.id === theme.wallpaper)?.title ?? "Original"} action="Change" onClick={() => setPane("wallpaper")} />
        <SettingsRow title="Card colour" detail={cardTints.find((item) => item.id === theme.card)?.title ?? "Clean white"} action="Change" onClick={() => setPane("card")} />
        <SettingsRow title="Show tips again" detail="A quick tour of What's On, Create, polls, My Calendar, colours and Support." action="Show" onClick={() => window.dispatchEvent(new Event("cc-show-tour"))} />
      </div>

      <p className="eyebrow">Support</p>
      <div className="settings-group">
        <SettingsRow title="Contact Coast Calendar Support" detail="Send a private support request." action="Open" onClick={onSupport} />
      </div>

      {onReviewQueue ? (
        <div className="settings-group">
          <SettingsRow title="Review queue" detail="Membership, listing, Notice and support queues." action="Open" onClick={onReviewQueue} />
        </div>
      ) : null}
    </section>
  );
}

type OwnListing = EventRecord & { submitted_by: string; listing_source: string | null; audience?: string | null; contact_name?: string | null; contact_email?: string | null; contact_phone?: string | null };

function listingChip(status: string) {
  if (status === "published") return "Live";
  if (status === "pending_review") return "Pending";
  if (status === "rejected") return "Action needed";
  if (status === "archived") return "Archived";
  if (status === "approved_awaiting_payment") return "Awaiting payment";
  return status.replaceAll("_", " ");
}

// Lets poll cards anywhere (board, lists) vote inline like iOS PollFeedCard, without prop-drilling.
const CompactCardsContext = createContext(false);
const PollCardContext = createContext<{ session: AuthSession | null; ownerProfileId: string | null; onSignIn: () => void; noticeTools?: { busy: boolean; canPublish: boolean; onUploadImage: (file: File, kind: "notice") => Promise<string>; onCreateNotice: (draft: NoticeDraft) => Promise<boolean> } } | null>(null);

// A poll is ended once its end_at has passed (polls get end_at = creation + POLL_MAX_DAYS).
function pollEnded(event: { listing_kind?: string | null; end_at?: string | null }, nowMs = Date.now()) {
  if (event.listing_kind !== "poll" || !event.end_at) return false;
  const end = new Date(event.end_at).getTime();
  return !Number.isNaN(end) && nowMs > end;
}

async function archiveOwnListing(eventID: string, token: string) {
  const response = await fetch(`${supabaseUrl}/rest/v1/rpc/owner_archive_own_listing`, {
    method: "POST",
    headers: { ...authHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({ p_event_id: eventID }),
  });
  if (!response.ok) throw new Error(await response.text());
}
const editTowns = ["Omana", "Whitford", "Maraetai", "Beachlands", "Clevedon", "Kawakawa Bay", "Orere Point", "Hunua", "Ardmore"];

type ListingEditDraft = {
  title: string; category: string; town: string; venue: string; date: string; time: string;
  priceLabel: string; audience: string; shortDescription: string; longDescription: string;
  contactName: string; contactEmail: string; contactPhone: string;
};

function pad2(value: number) { return String(value).padStart(2, "0"); }

function draftFromListing(row: OwnListing): ListingEditDraft {
  const start = new Date(row.start_at);
  const valid = !Number.isNaN(start.getTime());
  return {
    title: row.title ?? "",
    category: row.category ?? categories[0],
    town: row.town ?? editTowns[0],
    venue: row.venue ?? "",
    date: valid ? `${start.getFullYear()}-${pad2(start.getMonth() + 1)}-${pad2(start.getDate())}` : "",
    time: valid ? `${pad2(start.getHours())}:${pad2(start.getMinutes())}` : "",
    priceLabel: row.price_label ?? "",
    audience: row.audience ?? "",
    shortDescription: row.short_description ?? "",
    longDescription: row.long_description ?? "",
    contactName: row.contact_name ?? "",
    contactEmail: row.contact_email ?? "",
    contactPhone: row.contact_phone ?? "",
  };
}

// Mirrors iOS ListingEditDraft.proposedChanges.
function proposedChangesFromDraft(draft: ListingEditDraft): Record<string, unknown> {
  const start = new Date(`${draft.date}T${draft.time || "00:00"}`);
  const end = new Date(start.getTime() + 2 * 60 * 60 * 1000);
  const price = draft.priceLabel.trim();
  const resolvedPrice = price === "" ? "Free" : price;
  const shortText = draft.shortDescription.trim();
  const longText = draft.longDescription.trim();
  const audience = draft.audience.trim();
  return {
    title: draft.title.trim(),
    category: draft.category,
    town: draft.town,
    venue: draft.venue.trim(),
    start_at: start.toISOString(),
    end_at: end.toISOString(),
    price_label: resolvedPrice,
    is_free: resolvedPrice.toLowerCase().includes("free"),
    audience: audience === "" ? "Everyone" : audience,
    short_description: shortText,
    long_description: longText === "" ? shortText : longText,
    contact_name: draft.contactName.trim(),
    contact_email: draft.contactEmail.trim(),
    contact_phone: draft.contactPhone.trim(),
  };
}

function ListingEditForm({ listing, busy, onCancel, onSubmit }: {
  listing: OwnListing;
  busy: boolean;
  onCancel: () => void;
  onSubmit: (draft: ListingEditDraft, note: string) => void;
}) {
  const [draft, setDraft] = useState<ListingEditDraft>(() => draftFromListing(listing));
  const [note, setNote] = useState("");
  const set = (key: keyof ListingEditDraft) => (event: { target: { value: string } }) => setDraft((current) => ({ ...current, [key]: event.target.value }));
  const canSend = draft.title.trim() !== "" && draft.date !== "" && !busy;
  return (
    <section className="panel account-panel">
      <button type="button" className="text-link" onClick={onCancel}>Back</button>
      <p className="eyebrow">My listings</p>
      <h2>Request an edit</h2>
      <p className="panel-note">Your public listing will not change until Support reviews this request.</p>
      <form className="form-grid" onSubmit={(event) => { event.preventDefault(); if (canSend) onSubmit(draft, note); }}>
        <label>Title<input value={draft.title} onChange={set("title")} required /></label>
        <label>Category<select value={draft.category} onChange={set("category")}>{(categories.includes(draft.category) ? categories : [draft.category, ...categories]).map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
        <label>Town<select value={draft.town} onChange={set("town")}>{(editTowns.includes(draft.town) ? editTowns : [draft.town, ...editTowns]).map((item) => <option key={item} value={item}>{item}</option>)}</select></label>
        <label className="typeahead-field">Venue
          <LocationTypeahead
            value={draft.venue}
            onChange={(venue) => setDraft((current) => ({ ...current, venue }))}
            onPick={(hit) => { const town = editTowns.find((item) => hit.label.toLowerCase().includes(item.toLowerCase()) || hit.place.toLowerCase() === item.toLowerCase()); if (town) setDraft((current) => ({ ...current, town })); }}
          />
        </label>
        <label>Date<input type="date" value={draft.date} onChange={set("date")} required /></label>
        <label>Time<input type="time" value={draft.time} onChange={set("time")} /></label>
        <label>Price<input value={draft.priceLabel} onChange={set("priceLabel")} placeholder="Free" /></label>
        <label>Audience<input value={draft.audience} onChange={set("audience")} placeholder="Everyone" /></label>
        <label>Short description<textarea value={draft.shortDescription} onChange={set("shortDescription")} rows={3} /></label>
        <label>Long description<textarea value={draft.longDescription} onChange={set("longDescription")} rows={5} /></label>
        <label>Contact name<input value={draft.contactName} onChange={set("contactName")} /></label>
        <label>Contact email<input type="email" value={draft.contactEmail} onChange={set("contactEmail")} /></label>
        <label>Contact phone<input value={draft.contactPhone} onChange={set("contactPhone")} /></label>
        <label>Note to Support (optional)<textarea value={note} onChange={(event) => setNote(event.target.value)} rows={3} /></label>
        <div className="action-row">
          <button type="submit" className="button button--primary" disabled={!canSend}>{busy ? "Sending…" : "Send request"}</button>
          <button type="button" className="button button--secondary" onClick={onCancel} disabled={busy}>Cancel</button>
        </div>
      </form>
    </section>
  );
}

async function attachOwnerImages<T extends EventRecord>(rows: T[], accessToken: string): Promise<T[]> {
  if (!rows.length) return rows;
  try {
    const ids = rows.map((row) => row.id).join(",");
    const images = await rest<{ event_id: string; storage_path: string; position: number }[]>(
      `event_images?select=event_id,storage_path,position&event_id=in.(${ids})&order=position.asc`, {}, accessToken);
    const firstByEvent = new Map<string, string>();
    for (const image of images ?? []) {
      if (!firstByEvent.has(image.event_id)) firstByEvent.set(image.event_id, image.storage_path);
    }
    const signedEntries = await Promise.all(Array.from(firstByEvent.entries()).map(async ([eventId, storagePath]) => {
      try {
        return [eventId, await signedListingImageUrl(storagePath, accessToken)] as const;
      } catch {
        return [eventId, null] as const;
      }
    }));
    const signedByEvent = new Map(signedEntries.filter((entry): entry is readonly [string, string] => Boolean(entry[1])));
    return rows.map((row) => ({ ...row, image_url: row.image_url ?? signedByEvent.get(row.id) ?? null }));
  } catch (error) {
    console.error("attachOwnerImages", error);
    return rows;
  }
}

function localDayKey(value: Date) {
  return `${value.getFullYear()}-${pad2(value.getMonth() + 1)}-${pad2(value.getDate())}`;
}

function MyCalendarPane({ session, engagements, boardEvents, busy, onBack, onSignIn, onOpen, onToggle }: {
  session: AuthSession | null;
  engagements: EngagementRecord[];
  boardEvents: EventRecord[];
  busy: boolean;
  onBack: () => void;
  onSignIn: () => void;
  onOpen: (event: EventRecord) => void;
  onToggle: (eventID: string, type: EngagementRecord["engagement_type"]) => void;
}) {
  const [items, setItems] = useState<EventRecord[]>([]);
  const [note, setNote] = useState("");
  const [loading, setLoading] = useState(false);
  const [month, setMonth] = useState(() => { const now = new Date(); return new Date(now.getFullYear(), now.getMonth(), 1); });
  const [selectedDay, setSelectedDay] = useState(() => localDayKey(new Date()));

  useEffect(() => {
    if (!session) return;
    let cancelled = false;
    (async () => {
      setLoading(true);
      setNote("");
      try {
        const notes = await rest<EventRecord[]>("rpc/fetch_my_calendar_listings", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: "{}",
        }, session.access_token);
        const boardByID = new Map(boardEvents.map((event) => [event.id, event]));
        const going = engagements
          .filter((engagement) => engagement.engagement_type === "going")
          .map((engagement) => boardByID.get(engagement.event_id) ?? engagement.events)
          .filter((event): event is EventRecord => Boolean(event));
        const seen = new Set<string>();
        const merged: EventRecord[] = [];
        for (const item of [...(notes ?? []), ...going]) {
          if (seen.has(item.id)) continue;
          seen.add(item.id);
          merged.push(boardByID.get(item.id)?.image_url ? { ...item, image_url: boardByID.get(item.id)?.image_url } : item);
        }
        const withImages = await attachOwnerImages(merged, session.access_token);
        if (!cancelled) setItems(withImages);
      } catch (error) {
        if (!cancelled) setNote(error instanceof Error ? error.message : "My Calendar could not be loaded. Please try again soon.");
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session?.access_token, engagements]);

  const markedDays = new Set(items.map((item) => localDayKey(new Date(item.start_at))));
  const daysItems = items.filter((item) => localDayKey(new Date(item.start_at)) === selectedDay);
  const firstWeekday = (month.getDay() + 6) % 7; // Monday first
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const cells: (Date | null)[] = [
    ...Array.from({ length: firstWeekday }, () => null),
    ...Array.from({ length: daysInMonth }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index + 1)),
  ];
  const todayKey = localDayKey(new Date());
  const selectedDate = new Date(`${selectedDay}T00:00`);

  return (
    <section className="panel account-panel">
      <button type="button" className="text-link" onClick={onBack}>← Back to Settings</button>
      <p className="eyebrow">My Calendar</p>
      <h2>My Calendar</h2>
      <p className="panel-note">Dates from organisations you belong to, plus events you are going to.</p>
      {!session ? (
        <button type="button" className="button button--primary" onClick={onSignIn}>Sign in</button>
      ) : (
        <>
          {note ? <p className="panel-note">{note}</p> : null}
          <div className="settings-group" style={{ padding: 12 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
              <button type="button" className="text-link" style={{ padding: 0 }} onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))} aria-label="Previous month">‹ Prev</button>
              <strong>{month.toLocaleDateString(undefined, { month: "long", year: "numeric" })}</strong>
              <button type="button" className="text-link" style={{ padding: 0 }} onClick={() => setMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))} aria-label="Next month">Next ›</button>
            </div>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, textAlign: "center" }}>
              {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label) => (
                <span key={label} style={{ fontSize: 12, opacity: 0.6, fontWeight: 700 }}>{label}</span>
              ))}
              {cells.map((day, index) => {
                if (!day) return <span key={`blank-${index}`} />;
                const key = localDayKey(day);
                const isSelected = key === selectedDay;
                return (
                  <button
                    type="button"
                    key={key}
                    onClick={() => setSelectedDay(key)}
                    aria-pressed={isSelected}
                    aria-label={`${day.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}${markedDays.has(key) ? ", has events" : ""}`}
                    className={`cal-day${key === todayKey ? " is-today" : ""}${isSelected ? " is-selected" : ""}${markedDays.has(key) ? " has-events" : ""}`}
                  >
                    <span className="cal-day__num">{day.getDate()}</span>
                    <span className="cal-day__dot" aria-hidden="true" />
                  </button>
                );
              })}
            </div>
          </div>
          <h3>{selectedDate.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}</h3>
          {loading ? (
            <p className="panel-note">Loading your calendar…</p>
          ) : daysItems.length === 0 ? (
            <p className="panel-note">Nothing on this day from organisations you belong to.</p>
          ) : (
            daysItems.map((item) => {
              const active = new Set(engagements.filter((engagement) => engagement.event_id === item.id).map((engagement) => engagement.engagement_type));
              return (
                <EventCard key={item.id} event={item} active={active} busy={busy} onToggle={onToggle} onOpen={onOpen} />
              );
            })
          )}
        </>
      )}
    </section>
  );
}

function OrgMonthGrid({ month, onMonth, selectedDay, onSelect, markedDays }: {
  month: Date;
  onMonth: (value: Date) => void;
  selectedDay: string;
  onSelect: (key: string) => void;
  markedDays: Set<string>;
}) {
  const firstWeekday = (month.getDay() + 6) % 7;
  const daysInMonth = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const cells: (Date | null)[] = [
    ...Array.from({ length: firstWeekday }, () => null),
    ...Array.from({ length: daysInMonth }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index + 1)),
  ];
  const todayKey = localDayKey(new Date());
  return (
    <div className="settings-group" style={{ padding: 12 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 8 }}>
        <button type="button" className="text-link" style={{ padding: 0 }} onClick={() => onMonth(new Date(month.getFullYear(), month.getMonth() - 1, 1))} aria-label="Previous month">‹ Prev</button>
        <strong>{month.toLocaleDateString(undefined, { month: "long", year: "numeric" })}</strong>
        <button type="button" className="text-link" style={{ padding: 0 }} onClick={() => onMonth(new Date(month.getFullYear(), month.getMonth() + 1, 1))} aria-label="Next month">Next ›</button>
      </div>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(7, 1fr)", gap: 4, textAlign: "center" }}>
        {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label) => (
          <span key={label} style={{ fontSize: 12, opacity: 0.6, fontWeight: 700 }}>{label}</span>
        ))}
        {cells.map((day, index) => {
          if (!day) return <span key={`blank-${index}`} />;
          const key = localDayKey(day);
          const isSelected = key === selectedDay;
          return (
            <button type="button" key={key} onClick={() => onSelect(key)} aria-pressed={isSelected}
              aria-label={`${day.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}${markedDays.has(key) ? ", has events" : ""}`}
              className={`cal-day${key === todayKey ? " is-today" : ""}${isSelected ? " is-selected" : ""}${markedDays.has(key) ? " has-events" : ""}`}>
              <span className="cal-day__num">{day.getDate()}</span>
              <span className="cal-day__dot" aria-hidden="true" />
            </button>
          );
        })}
      </div>
    </div>
  );
}

type OrgCalendarDraft = { editingID: string | null; words: string; venue: string; time: string; details: string; isPublic: boolean };
const emptyOrgDraft: OrgCalendarDraft = { editingID: null, words: "", venue: "", time: "12:00", details: "", isPublic: true };

function OrgCalendarPane({ session, profile, onBack, onOpen }: {
  session: AuthSession;
  profile: HostRecord;
  onBack: () => void;
  onOpen: (event: EventRecord) => void;
}) {
  const [items, setItems] = useState<EventRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const [note, setNote] = useState("");
  const [month, setMonth] = useState(() => { const now = new Date(); return new Date(now.getFullYear(), now.getMonth(), 1); });
  const [selectedDay, setSelectedDay] = useState(() => localDayKey(new Date()));
  const [draft, setDraft] = useState<OrgCalendarDraft>(emptyOrgDraft);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState("");

  async function load() {
    setLoading(true);
    setNote("");
    try {
      const rows = await rest<EventRecord[]>("rpc/fetch_org_calendar_listings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ p_profile_id: profile.id }),
      }, session.access_token);
      setItems(await attachOwnerImages(rows ?? [], session.access_token));
    } catch (error) {
      setNote(error instanceof Error ? error.message : "Org Calendar could not be loaded. Please try again soon.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { void load(); // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session.access_token, profile.id]);

  const markedDays = new Set(items.map((item) => localDayKey(new Date(item.start_at))));
  const daysItems = items.filter((item) => localDayKey(new Date(item.start_at)) === selectedDay);
  const selectedDate = new Date(`${selectedDay}T00:00`);
  const canSave = draft.words.trim().length >= 2 && !saving;

  function startEdit(item: EventRecord) {
    const start = new Date(item.start_at);
    const visibility = (item as EventRecord & { visibility?: string | null }).visibility;
    setSelectedDay(localDayKey(start));
    setDraft({
      editingID: item.id,
      words: item.title ?? "",
      venue: item.location_display_name ?? item.venue ?? "",
      time: `${pad2(start.getHours())}:${pad2(start.getMinutes())}`,
      details: item.long_description ?? item.short_description ?? "",
      isPublic: visibility ? visibility === "public" : true,
    });
    setSaveError("");
  }

  async function save() {
    const title = draft.words.trim();
    if (title.length < 2) return;
    setSaving(true);
    setSaveError("");
    try {
      if (draft.editingID) {
        // iOS updateOrgCalendarListing: selected day + chosen time
        const combined = new Date(`${selectedDay}T${draft.time || "12:00"}`);
        await rest("rpc/owner_update_org_calendar_listing", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            p_event_id: draft.editingID,
            p_title: title,
            p_venue: draft.venue,
            p_details: draft.details,
            p_start_at: combined.toISOString(),
            p_visibility: draft.isPublic ? "public" : "private",
          }),
        }, session.access_token);
      } else {
        // iOS insertOrgCalendarListing: noon on the selected day, 2h long, town Beachlands
        const start = new Date(`${selectedDay}T12:00`);
        await rest("rpc/owner_insert_org_calendar_listing", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            p_profile_id: profile.id,
            p_title: title,
            p_start_at: start.toISOString(),
            p_end_at: new Date(start.getTime() + 7200 * 1000).toISOString(),
            p_visibility: draft.isPublic ? "public" : "private",
            p_town: "Beachlands",
            p_location_scope_id: "",
            p_location_display_name: draft.venue,
            p_details: draft.details,
          }),
        }, session.access_token);
      }
      setDraft(emptyOrgDraft);
      await load();
    } catch (error) {
      setSaveError(error instanceof Error ? error.message : "Could not save. Please try again.");
    } finally {
      setSaving(false);
    }
  }

  return (
    <section className="panel account-panel">
      <button type="button" className="text-link" onClick={onBack}>← Back to Settings</button>
      <p className="eyebrow">Org Calendar</p>
      <h2>{profile.business_name || "Organisation"}</h2>
      <p className="panel-note">Add dates for people who belong to your organisation.</p>
      {note ? <p className="panel-note">{note}</p> : null}
      <OrgMonthGrid month={month} onMonth={setMonth} selectedDay={selectedDay} onSelect={setSelectedDay} markedDays={markedDays} />
      <h3>{selectedDate.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}</h3>
      <div className="settings-group" style={{ padding: 16, display: "grid", gap: 8 }}>
        <strong>{draft.editingID ? "Edit date" : "Create on this day"}</strong>
        <label>What&apos;s on<input value={draft.words} onChange={(e) => setDraft({ ...draft, words: e.target.value })} placeholder="Working bee" /></label>
        <label className="typeahead-field">Where
          <LocationTypeahead value={draft.venue} onChange={(venue) => setDraft((current) => ({ ...current, venue }))} placeholder="Clubrooms" />
        </label>
        {draft.editingID ? (
          <label>Time<input type="time" value={draft.time} onChange={(e) => setDraft({ ...draft, time: e.target.value })} /></label>
        ) : null}
        <label>Details<textarea rows={3} value={draft.details} onChange={(e) => setDraft({ ...draft, details: e.target.value })} placeholder="Julie is bringing lunch" /></label>
        <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <input type="checkbox" checked={draft.isPublic} onChange={(e) => setDraft({ ...draft, isPublic: e.target.checked })} /> Public listing
        </label>
        <p className="panel-note">People who Belong to this organisation can see this date. It is not on the public board.</p>
        <div style={{ display: "flex", gap: 8 }}>
          <button type="button" className="button button--primary" disabled={!canSave} onClick={() => void save()}>{saving ? "Saving" : draft.editingID ? "Save" : "Create on this day"}</button>
          {draft.editingID ? <button type="button" className="button" onClick={() => setDraft(emptyOrgDraft)}>Cancel edit</button> : null}
        </div>
        {saveError ? <p className="panel-note" style={{ color: "var(--pcc-red, #b3261e)" }}>{saveError}</p> : null}
      </div>
      {loading ? (
        <p className="panel-note">Loading your calendar…</p>
      ) : daysItems.length === 0 ? (
        <p className="panel-note">Nothing on this day yet.</p>
      ) : (
        daysItems.map((item) => (
          <div key={item.id}>
            <EventCard event={item} active={new Set()} busy={saving} onToggle={() => undefined} onOpen={onOpen} />
            <button type="button" className="text-link" onClick={() => startEdit(item)}>Edit</button>
            <button type="button" className="text-link org-cal__remove" disabled={saving} onClick={() => {
              if (!window.confirm("Remove this date?\n\nIt leaves the org calendar. Support can still see the archive.")) return;
              setSaving(true); setSaveError("");
              archiveOwnListing(item.id, session.access_token)
                .then(() => load())
                .catch((error) => setSaveError(error instanceof Error ? error.message : "Could not remove. Please try again."))
                .finally(() => setSaving(false));
            }}>Remove from calendar</button>
          </div>
        ))
      )}
    </section>
  );
}

function MyListingsPane({ session, onBack, onSignIn, onOpen }: { session: { access_token: string; user: { id: string } } | null; onBack: () => void; onSignIn: () => void; onOpen: (event: EventRecord) => void }) {
  const [rows, setRows] = useState<OwnListing[]>([]);
  const [requests, setRequests] = useState<ChangeRequest[]>([]);
  const [editing, setEditing] = useState<OwnListing | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  async function load() {
    if (!session) return;
    const data = await rest<OwnListing[]>(`events?select=id,title,category,venue,start_at,end_at,price_label,short_description,long_description,location_display_name,town,status,listing_kind,poll_question,submitted_by,listing_source,audience,contact_name,contact_email,contact_phone&submitted_by=eq.${session.user.id}&listing_source=eq.create&order=created_at.desc`, {}, session.access_token);
    const owned = (data ?? []).filter((row) => row.submitted_by === session.user.id && row.listing_source !== "org_calendar");
    setRows(owned);
    if (owned.length) {
      try {
        const ids = owned.map((row) => row.id).join(",");
        const images = await rest<{ event_id: string; storage_path: string; position: number }[]>(
          `event_images?select=event_id,storage_path,position&event_id=in.(${ids})&order=position.asc`, {}, session.access_token);
        const firstByEvent = new Map<string, string>();
        for (const image of images ?? []) {
          if (!firstByEvent.has(image.event_id)) firstByEvent.set(image.event_id, image.storage_path);
        }
        const signedEntries = await Promise.all(Array.from(firstByEvent.entries()).map(async ([eventId, storagePath]) => {
          try {
            return [eventId, await signedListingImageUrl(storagePath, session.access_token)] as const;
          } catch {
            return [eventId, null] as const;
          }
        }));
        const signedByEvent = new Map(signedEntries.filter((entry): entry is readonly [string, string] => Boolean(entry[1])));
        setRows(owned.map((row) => ({ ...row, image_url: signedByEvent.get(row.id) ?? null })));
      } catch (error) {
        console.error("my listings event_images", error);
      }
    }
    const changeRows = await rest<ChangeRequest[]>(`event_change_requests?select=*&requested_by=eq.${session.user.id}&order=created_at.desc`, {}, session.access_token);
    setRequests(changeRows ?? []);
  }
  useEffect(() => { void load().catch((error) => setNote(error instanceof Error ? error.message : "Could not load your listings.")); }, [session?.user.id, session?.access_token]);
  function requestFor(eventID: string) {
    const forListing = requests.filter((request) => request.event_id === eventID && request.change_type === "edit_request");
    return forListing.find((request) => request.status === "pending") ?? forListing[0];
  }
  async function archive(id: string) {
    if (!session || !window.confirm("Remove this listing?\n\nIt will come off the public board. Support can restore it if this was a mistake. Poll answers and listing history stay on file.")) return;
    setBusy(true);
    try {
      await archiveOwnListing(id, session.access_token);
      await load();
      setNote("Archived.");
    } catch (error) {
      setNote(error instanceof Error ? error.message : "Could not archive that listing.");
    } finally {
      setBusy(false);
    }
  }
  async function submitEditRequest(listing: OwnListing, draft: ListingEditDraft, requesterNote: string) {
    if (!session) return;
    setBusy(true);
    try {
      await rest<void>("event_change_requests", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({
          event_id: listing.id,
          requested_by: session.user.id,
          change_type: "edit_request",
          status: "pending",
          proposed_changes: proposedChangesFromDraft(draft),
          requester_note: requesterNote.trim() === "" ? null : requesterNote.trim(),
        }),
      }, session.access_token);
      setEditing(null);
      await load();
      setNote("Edit request sent to Support.");
    } catch (error) {
      setNote(error instanceof Error ? error.message : "Could not send that edit request.");
    } finally {
      setBusy(false);
    }
  }
  if (editing) {
    return (
      <>
        {note ? <p className="panel-note">{note}</p> : null}
        <ListingEditForm listing={editing} busy={busy} onCancel={() => setEditing(null)} onSubmit={(draft, requesterNote) => void submitEditRequest(editing, draft, requesterNote)} />
      </>
    );
  }
  return (
    <section className="panel account-panel">
      <button type="button" className="text-link" onClick={onBack}>← Back to Settings</button>
      <p className="eyebrow">Organisations</p>
      <h2>My listings</h2>
      {!session ? <EmptyState title="Sign in to see your listings" text="Sign in here to see submitted, pending, approved and archived listings."><button type="button" className="button button--primary" onClick={onSignIn}>Sign in</button></EmptyState> : null}
      {note ? <p className="panel-note">{note}</p> : null}
      {session && !note && rows.length === 0 ? <EmptyState title="No listings yet" text="Listings you can manage will appear here after they are sent for review." /> : null}
      {(() => {
        // Display-only grouping: ended polls (end_at passed) are shown as Archived; their status is not written.
        const isArchived = (row: OwnListing) => row.status === "archived" || pollEnded(row);
        const active = rows.filter((row) => !isArchived(row));
        const archived = rows.filter(isArchived);
        const card = (row: OwnListing, archivedView: boolean) => (
          <EventCard
            key={row.id}
            event={row}
            busy={busy}
            onToggle={() => undefined}
            onOpen={onOpen}
            ownerStatus={archivedView ? "archived" : row.status}
            onRemove={(id) => void archive(id)}
            ownerRequest={requestFor(row.id)}
            onRequestEdit={() => { setNote(""); setEditing(row); }}
          />
        );
        return (
          <>
            {active.map((row) => card(row, false))}
            {session && rows.length && !active.length ? <p className="panel-note">No active listings.</p> : null}
            {archived.length ? (
              <>
                <p className="eyebrow">Archived</p>
                <p className="panel-note">Archived listings and ended polls. Open a poll to see its final results.</p>
                {archived.map((row) => card(row, true))}
              </>
            ) : null}
          </>
        );
      })()}
    </section>
  );
}

export default function CommunityCalendarApp() {
  useEffect(() => {
    applyThemeForUser(null);
  }, []);

  const [session, setSession] = useState<AuthSession | null>(() => {
    if (typeof window === "undefined") {
      return null;
    }
    const saved = window.localStorage.getItem(sessionKey);
    return saved ? JSON.parse(saved) as AuthSession : null;
  });
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
  }, []);
  const [selectedHost, setSelectedHost] = useState<HostRecord | null>(null);
  const [selectedEvent, setSelectedEvent] = useState<EventRecord | null>(null);
  const [events, setEvents] = useState<EventRecord[]>([]);
  const [view, setView] = useState<AppView>("home");
  const [hosts, setHosts] = useState<HostRecord[]>([]);
  const [engagements, setEngagements] = useState<EngagementRecord[]>([]);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [memberProfile, setMemberProfile] = useState<HostRecord | null>(null);
  const [subscriptions, setSubscriptions] = useState<SubscriptionRecord[]>([]);
  const [supportRequests, setSupportRequests] = useState<SupportRequest[]>([]);
  const [supportInboxRequests, setSupportInboxRequests] = useState<SupportRequest[]>([]);
  const [notifications, setNotifications] = useState<UserNotification[]>([]);
  const [memberFollows, setMemberFollows] = useState<MemberFollowRecord[]>([]);
  const [memberNotices, setMemberNotices] = useState<MemberNoticeRecord[]>([]);
  const [isSupportUser, setIsSupportUser] = useState(false);
  const [accountSection, setAccountSection] = useState<AccountHubSection>(null);
  const [settingsInitialPane, setSettingsInitialPane] = useState<"org" | "setup" | null>(null);
  // stripe1: handle the Stripe Checkout return (?checkout=success|cancelled) — open Get set up and strip the param.
  useEffect(() => {
    if (typeof window === "undefined") return;
    const url = new URL(window.location.href);
    const result = url.searchParams.get("checkout");
    if (result !== "success" && result !== "cancelled") return;
    try { window.sessionStorage.setItem("cc-checkout", result); } catch { /* ignore */ }
    url.searchParams.delete("checkout");
    window.history.replaceState(null, "", url.pathname + url.search + url.hash);
    setSettingsInitialPane("setup");
    setView("settings");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const [pendingVerifyEmail, setPendingVerifyEmail] = useState<string | null>(null);
  const [supportView, setSupportView] = useState<"operator" | "public">("public");
  const [supportProfiles, setSupportProfiles] = useState<HostRecord[]>([]);
  const [supportSubscriptions, setSupportSubscriptions] = useState<SubscriptionRecord[]>([]);
  const [supportListings, setSupportListings] = useState<EventRecord[]>([]);
  const [supportMemberNotices, setSupportMemberNotices] = useState<MemberNoticeRecord[]>([]);
  const [supportNotifications, setSupportNotifications] = useState<UserNotification[]>([]);
  const [supportAuditEvents, setSupportAuditEvents] = useState<SupportAuditEvent[]>([]);
  const [changeRequests, setChangeRequests] = useState<ChangeRequest[]>([]);
  const [notice, setNotice] = useState<Notice>(null);

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(() => setNotice(null), 5000);
    return () => window.clearTimeout(timer);
  }, [notice]);

  const [busy, setBusy] = useState(false);
  const [dateScope, setDateScope] = useState<"today" | "week" | "month" | "upcoming">("today");
  const [selectedTopics, setSelectedTopics] = useState<string[]>([]);
  const [locationScopes, setLocationScopes] = useState<LocationScopeRecord[]>([]);
  const [locationEdges, setLocationEdges] = useState<LocationEdgeRecord[]>([]);
  const [homeScope, setHomeScope] = useState(defaultHomeScope);
  const [homeEventIDs, setHomeEventIDs] = useState<string[] | null>(null);
  const [widerPollIDs, setWiderPollIDs] = useState<Set<string>>(new Set());
  const [showFinder, setShowFinder] = useState(false);
  const [weeklyViews, setWeeklyViews] = useState<number | null>(null);
  const [finderQuery, setFinderQuery] = useState("");
  const [hostQuery, setHostQuery] = useState("");
  function toggleTopic(slug: string) {
    setSelectedTopics((current) => current.includes(slug)
      ? current.filter((item) => item !== slug)
      : [...current, slug]);
  }
  const topicChipStyle = (active: boolean): React.CSSProperties => active
    ? { background: "var(--pcc-orange)", color: "#fff", border: "1px solid var(--pcc-orange)" }
    : { background: "var(--pcc-card)", color: "var(--pcc-green)", border: "1px solid var(--pcc-green)" };


  const eventHost = useMemo(() => new Map(hosts.map((host) => [host.owner_user_id, host])), [hosts]);
  const visibleEvents = useMemo(() => {
    const topicFiltered = selectedTopics.length === 0
      ? events
      : events.filter((event) => {
          const slugs = event.topics ?? [];
          const fallback = (event.category ?? "").toLowerCase().replace(/\s+/g, "_");
          return selectedTopics.some((topic) => slugs.includes(topic) || fallback === topic || fallback.replace("-", "_") === topic);
        });
    const dated = view === "whatsOn"
      ? topicFiltered.filter((event) => eventOverlapsWindow(event, dateScope))
      : topicFiltered;
    if (view !== "home" && view !== "whatsOn") return dated;
    const welcomeRow = events.find((event) => event.id === WELCOME_EVENT_ID);
    const allowed = new Set(homeEventIDs ?? []);
    const covering = coverageSlugsFor(homeScope, locationEdges);
    const slugById = new Map(locationScopes.map((scope) => [scope.id, scope.slug]));
    const filteredOut = dated.filter((event) => {
      if (event.listing_kind === "poll") {
        // Polls show only where the viewer's area sits inside the poll's coverage scope.
        const cov = slugById.get(String((event as EventRecord & { primary_location_scope_id?: string | null }).primary_location_scope_id ?? ""));
        // Polls: visible only if the poll's primary coverage scope is the viewer's area or wider (ancestor rows don't count).
        return cov ? covering.has(cov) : widerPollIDs.has(event.id);
      }
      return homeEventIDs === null ? true : allowed.has(event.id);
    }).filter((event) => event.id !== WELCOME_EVENT_ID);
    // welcome1: pinned first, regardless of date, topic or area.
    return welcomeRow ? [withWelcomeExtra(welcomeRow), ...filteredOut] : filteredOut;
  }, [events, selectedTopics, view, homeEventIDs, widerPollIDs, dateScope, homeScope, locationEdges, locationScopes]);

  useEffect(() => {
    if (selectedEvent) recordEventAnalytics(selectedEvent.id, "detail_view", "event_detail", session?.access_token);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedEvent?.id]);

  const engagedByEvent = useMemo(() => {
    const map = new Map<string, Set<string>>();
    engagements.forEach((row) => {
      const set = map.get(row.event_id) ?? new Set<string>();
      set.add(row.engagement_type);
      map.set(row.event_id, set);
    });
    return map;
  }, [engagements]);

  useEffect(() => {
    const stored = window.localStorage.getItem(homeScopeKey);
    if (stored) setHomeScope(stored);
    void loadLocationCatalog();
    void loadPublicData();
    void recordWebOpen();
  }, []);

  useEffect(() => {
    window.localStorage.setItem(homeScopeKey, homeScope);
    void loadHomeTargets(homeScope);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [homeScope, locationEdges]);

  useEffect(() => {
    if (!session) {
      applyThemeForUser(null);
      return;
    }
    window.localStorage.setItem(sessionKey, JSON.stringify(session));
    applyThemeForUser(session.user.id);
    void loadSignedInData(session);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session]);

  async function syncFreshSession() {
    if (!session) return;
    const next = await refreshSessionIfNeeded(session);
    if (!next) logout();
    else if (next.access_token !== session.access_token) setSession(next);
  }

  useEffect(() => {
    void syncFreshSession();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function webInstallationID() {
    const existing = window.localStorage.getItem(webInstallKey);
    if (existing) return existing;
    const created = crypto.randomUUID();
    window.localStorage.setItem(webInstallKey, created);
    return created;
  }

  async function recordWebOpen() {
    try {
      const already = window.sessionStorage.getItem(webOpenSessionKey);
      if (already) {
        const count = await rpc<number>("get_weekly_app_open_count", {});
        setWeeklyViews(count);
        return;
      }
      const count = await rpc<number>("record_app_open", { p_session_id: webInstallationID() });
      window.sessionStorage.setItem(webOpenSessionKey, "1");
      setWeeklyViews(count);
    } catch (loadError) {
      console.warn("weekly views failed", loadError);
    }
  }

  async function loadLocationCatalog() {
    try {
      const [scopes, edges] = await Promise.all([
        rest<LocationScopeRecord[]>("location_scopes?select=id,slug,name,scope_type&order=name.asc"),
        rest<LocationEdgeRecord[]>("location_scope_edges?select=child_slug,parent_slug,relationship_type,sort_order&relationship_type=eq.widens_to"),
      ]);
      setLocationScopes(scopes);
      setLocationEdges(edges);
    } catch (loadError) {
      console.warn("location catalog failed", loadError);
    }
  }

  async function loadHomeTargets(scopeSlug: string) {
    try {
      const ladder = [...coverageSlugsFor(scopeSlug, locationEdges)];
      const rows = await rest<{ event_id: string; location_slug: string; target_type?: string }[]>(
        `published_event_location_targets?select=event_id,location_slug,target_type&location_slug=in.(${ladder.map((slug) => encodeURIComponent(slug)).join(",")})`
      );
      // fb2: exact-scope targets for listings; a poll targeted at a wider scope (region / NZ) reaches every area inside it.
      // Target rows include automatic "ancestor" rows (e.g. new-zealand) for every event, so only the poll's
      // PRIMARY target (its chosen coverage) may widen reach; ancestor rows must not.
      setWiderPollIDs(new Set(rows.filter((row) => row.target_type === "primary").map((row) => row.event_id)));
      setHomeEventIDs([...new Set(rows.filter((row) => row.location_slug === scopeSlug).map((row) => row.event_id))]);
    } catch (loadError) {
      console.warn("home targets failed", loadError);
      setHomeEventIDs(null);
    }
  }

  async function loadPublicData() {
    try {
      const eventSelect = [
        "id",
        "title",
        "category",
        "venue",
        "start_at",
        "end_at",
        "price_label",
        "short_description",
        "long_description",
        "location_display_name",
        "town",
        "status",
        "listing_kind",
        "poll_question",
        "poll_options",
        "poll_allows_custom_answer",
        "organisation_name",
        "business_profile_id",
        "is_free",
      ].join(",");
      const archiveCutoff = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString();
      let publicEvents: EventRecord[] = [];
      let publicHosts: HostRecord[] = [];
      try {
        publicEvents = await rest<EventRecord[]>(`public_events?select=${eventSelect}&end_at=gte.${encodeURIComponent(new Date().toISOString())}&order=start_at.asc&limit=40`);
      } catch (error) {
        console.error("public_events", error);
        setNotice({ kind: "warn", text: "Local board could not be loaded. Try refreshing shortly." });
      }
      if (publicEvents.length) {
        try {
          const ids = publicEvents.map((event) => event.id).join(",");
          const images = await rest<{ event_id: string; storage_path: string; position: number }[]>(
            `public_event_images?select=event_id,storage_path,position&event_id=in.(${ids})&order=position.asc`
          );
          const firstByEvent = new Map<string, string>();
          for (const image of images) {
            if (!firstByEvent.has(image.event_id)) {
              firstByEvent.set(image.event_id, image.storage_path);
            }
          }
          const signedEntries = await Promise.all(
            Array.from(firstByEvent.entries()).map(async ([eventId, storagePath]) => {
              const url = await signedListingImageUrl(storagePath);
              return [eventId, url] as const;
            })
          );
          const signedByEvent = new Map(signedEntries.filter((entry): entry is readonly [string, string] => Boolean(entry[1])));
          publicEvents = publicEvents.map((event) => ({
            ...event,
            image_url: signedByEvent.get(event.id) ?? null,
          }));
        } catch (error) {
          console.error("public_event_images", error);
        }
      }
      try {
        const rows = await rest<HostRecord[]>("public_member_profiles?select=*&order=display_name.asc&limit=1000");
        publicHosts = await Promise.all(rows.map(async (row) => {
          const [avatarUrl, heroUrl] = await Promise.all([
            row.avatar_image_path
              ? signedStorageImageUrl("member-images", row.avatar_image_path)
              : resolveMemberImage(row.avatar_image_url),
            row.hero_image_path
              ? signedStorageImageUrl("member-images", row.hero_image_path)
              : resolveMemberImage(row.hero_image_url),
          ]);
          return {
            ...row,
            business_name: row.display_name || row.business_name || "Host",
            about: row.bio ?? row.about,
            website: row.public_website ?? row.website,
            avatar_image_url: avatarUrl,
            hero_image_url: heroUrl,
          };
        }));
      } catch (error) {
        console.error("public_member_profiles", error);
      }
      if (publicEvents.length) {
        try {
          const ids = publicEvents.map((event) => event.id).join(",");
          const topicRows = await rest<{ event_id: string; topic_slug: string }[]>(
            `event_topics?select=event_id,topic_slug&event_id=in.(${ids})`
          );
          const topicsByEvent = new Map<string, string[]>();
          for (const row of topicRows) {
            const list = topicsByEvent.get(row.event_id) ?? [];
            list.push(row.topic_slug);
            topicsByEvent.set(row.event_id, list);
          }
          publicEvents = publicEvents.map((event) => ({
            ...event,
            topics: topicsByEvent.get(event.id) ?? [],
          }));
        } catch (error) {
          console.error("event_topics", error);
        }
      }
      // fb2: poll coverage scope (separate query so a missing column can't break the board).
      try {
        const pollIds = publicEvents.filter((event) => event.listing_kind === "poll").map((event) => event.id);
        if (pollIds.length) {
          const cov = await rest<{ id: string; primary_location_scope_id: string | null }[]>(`public_events?select=id,primary_location_scope_id&id=in.(${pollIds.join(",")})`);
          const byId = new Map(cov.map((row) => [row.id, row.primary_location_scope_id]));
          publicEvents = publicEvents.map((event) => (byId.has(event.id) ? { ...event, primary_location_scope_id: byId.get(event.id) } as EventRecord : event));
        }
      } catch (error) {
        console.warn("poll coverage unavailable; using location targets", error);
      }
      setEvents(publicEvents);
      setHosts(publicHosts);
    } catch (error) {
      console.error("loadPublicData", error);
      setNotice({ kind: "warn", text: "Local board could not be loaded. Try refreshing shortly." });
    }
  }

  async function loadSignedInData(activeSession = session) {
    if (!activeSession) {
      return;
    }

    try {
      const token = activeSession.access_token;
      const userID = activeSession.user.id;
      const profilePromise = rest<UserProfile[]>(
        `user_profiles?select=*&user_id=eq.${userID}&limit=1`,
        {},
        token,
      ).catch(() => []);
      const engagementPromise = rest<EngagementRecord[]>(
        `user_event_engagements?select=*,events(*)&user_id=eq.${userID}&order=updated_at.desc`,
        {},
        token,
      ).catch(() => []);
      const memberPromise = rest<HostRecord[]>(
        `business_profiles?select=*&owner_user_id=eq.${userID}&limit=1`,
        {},
        token,
      ).catch(() => []);
      const subscriptionPromise = rest<SubscriptionRecord[]>(
        `business_subscriptions?select=*&owner_user_id=eq.${userID}&order=created_at.desc`,
        {},
        token,
      ).catch(() => []);
      const mySupportPromise = rest<SupportRequest[]>(
        `support_requests?select=*&submitted_by=eq.${userID}&order=created_at.desc`,
        {},
        token,
      ).catch(() => []);
      const notificationPromise = rest<UserNotification[]>(
        `user_notifications?select=*&user_id=eq.${userID}&order=created_at.desc&limit=20`,
        {},
        token,
      ).catch(() => []);
      const followPromise = rest<MemberFollowRecord[]>(
        `member_follows?select=*&user_id=eq.${userID}&order=created_at.desc`,
        {},
        token,
      ).catch(() => []);
      const noticePromise = rest<MemberNoticeRecord[]>(
        `member_notices?select=*&owner_user_id=eq.${userID}&order=created_at.desc`,
        {},
        token,
      ).catch(() => []);

      const [profiles, savedRows, memberRows, subscriptionRows, myRequests, notificationRows, followRows, noticeRows] = await Promise.all([
        profilePromise,
        engagementPromise,
        memberPromise,
        subscriptionPromise,
        mySupportPromise,
        notificationPromise,
        followPromise,
        noticePromise,
      ]);

      setProfile(profiles[0] ?? null);
      setEngagements(savedRows);
      setMemberProfile(memberRows[0] ?? null);
      setSubscriptions(subscriptionRows);
      setSupportRequests(myRequests);
      setNotifications(notificationRows);
      setMemberFollows(followRows);
      setMemberNotices(noticeRows);

      const isSupport = await rpc<boolean>("current_user_is_support", {}, token).catch(() => false);
      setIsSupportUser(Boolean(isSupport));
      if (isSupport) {
        setSupportView("operator");
        await loadSupportData(token);
      }
    } catch (error) {
      setNotice({ kind: "warn", text: `Some signed-in details could not be loaded (${messageFromError(error)}). Your session may need a fresh sign in.` });
    }
  }

  async function loadSupportData(token = session?.access_token) {
    if (!token) {
      return;
    }
    const [profiles, subscriptions, listings, memberNoticeRows, notificationRows, auditRows, changeRows, supportRows] = await Promise.all([
      rest<HostRecord[]>("business_profiles?select=*&order=created_at.desc", {}, token),
      rest<SubscriptionRecord[]>("business_subscriptions?select=*&order=created_at.desc", {}, token),
      rest<EventRecord[]>("events?select=*&order=created_at.desc&limit=80", {}, token),
      rest<MemberNoticeRecord[]>("member_notices?select=*&order=created_at.desc&limit=80", {}, token).catch(() => []),
      rest<UserNotification[]>("user_notifications?select=*&order=created_at.desc&limit=80", {}, token).catch(() => []),
      rest<SupportAuditEvent[]>("support_audit_events?select=*&order=created_at.desc&limit=80", {}, token).catch(() => []),
      rest<ChangeRequest[]>("event_change_requests?select=*,events(*)&order=created_at.desc&limit=40", {}, token),
      rest<SupportRequest[]>("support_requests?select=*&order=created_at.desc&limit=80", {}, token),
    ]);
    setSupportProfiles(profiles);
    setSupportSubscriptions(subscriptions);
    setSupportListings(listings);
    setSupportMemberNotices(memberNoticeRows);
    setSupportNotifications(notificationRows);
    setSupportAuditEvents(auditRows);
    setChangeRequests(changeRows);
    setSupportInboxRequests(supportRows);
  }

  function logout() {
    window.localStorage.removeItem(sessionKey);
    setSession(null);
    setEngagements([]);
    setProfile(null);
    setMemberProfile(null);
    setSubscriptions([]);
    setSupportRequests([]);
    setSupportInboxRequests([]);
    setNotifications([]);
    setMemberFollows([]);
    setMemberNotices([]);
    setIsSupportUser(false);
    setSupportView("public");
    setSupportProfiles([]);
    setSupportSubscriptions([]);
    setSupportListings([]);
    setSupportMemberNotices([]);
    setSupportNotifications([]);
    setSupportAuditEvents([]);
    setChangeRequests([]);
  }

  async function handleAuth(email: string, password: string, mode: "sign-in" | "sign-up", fullName = "") {
    setBusy(true);
    setNotice(null);
    try {
      const nextSession = mode === "sign-in" ? await signIn(email, password) : await signUp(email, password, fullName);
      if (nextSession) {
        setSession(nextSession);
        setPendingVerifyEmail(null);
        setNotice({ kind: "good", text: mode === "sign-in" ? "Signed in." : "Account created and signed in." });
      } else {
        setPendingVerifyEmail(email.trim());
        setNotice({ kind: "good", text: "Check your email to confirm your account, then sign in." });
      }
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
    } finally {
      setBusy(false);
    }
  }

  async function saveProfile(next: UserProfile) {
    if (!session) return;
    setBusy(true);
    try {
      const rows = await rest<UserProfile[]>(
        "user_profiles?select=*",
        {
          method: "POST",
          headers: { Prefer: "resolution=merge-duplicates,return=representation" },
          body: JSON.stringify(next),
        },
        session.access_token,
      );
      setProfile(rows[0] ?? next);
      setNotice({ kind: "good", text: "Account settings saved." });
    } catch (error) {
      setNotice({ kind: "warn", text: `Could not save account settings: ${messageFromError(error)}` });
    } finally {
      setBusy(false);
    }
  }

  async function toggleEngagement(eventID: string, type: EngagementRecord["engagement_type"]) {
    if (!session) {
      setNotice({ kind: "warn", text: "Sign in first to save listings." });
      return;
    }
    const existing = engagements.find((row) => row.event_id === eventID && row.engagement_type === type);
    recordEventAnalytics(eventID, type === "saved" ? "save" : type, "engagement_row", session.access_token);
    setBusy(true);
    try {
      if (existing) {
        await rest<void>(`user_event_engagements?id=eq.${existing.id}`, { method: "DELETE" }, session.access_token);
      } else {
        await rest<EngagementRecord[]>(
          "user_event_engagements",
          {
            method: "POST",
            headers: { Prefer: "return=representation" },
            body: JSON.stringify({ user_id: session.user.id, event_id: eventID, engagement_type: type }),
          },
          session.access_token,
        );
      }
      if (!existing && type === "going" && readNotifyPrefs(session.user.id).autoCalendar) {
        const goingEvent = events.find((item) => item.id === eventID);
        if (goingEvent) downloadEventIcs(goingEvent);
      }
      await loadSignedInData();
      setNotice({
        kind: "good",
        text: existing
          ? `${type === "saved" ? "Removed from Saved" : type === "interested" ? "No longer Interested" : "Not going"}.`
          : `${type === "saved" ? "Saved" : type === "interested" ? "Marked Interested" : "Marked Going — open the listing to add it to your calendar"}.`,
      });
    } catch (error) {
      setNotice({ kind: "warn", text: `Could not update that: ${messageFromError(error)}` });
    } finally {
      setBusy(false);
    }
  }

  async function markNotificationRead(notificationID: string) {
    if (!session) return;
    setBusy(true);
    try {
      await rest<void>(
        `user_notifications?id=eq.${notificationID}`,
        {
          method: "PATCH",
          body: JSON.stringify({ read_at: new Date().toISOString() }),
        },
        session.access_token,
      );
      setNotifications((current) => current.map((notification) => (
        notification.id === notificationID
          ? { ...notification, read_at: new Date().toISOString() }
          : notification
      )));
      setNotice({ kind: "good", text: "Notification marked as read." });
    } catch (error) {
      setNotice({ kind: "warn", text: `Could not update that notification: ${messageFromError(error)}` });
    } finally {
      setBusy(false);
    }
  }

  async function uploadMemberImage(file: File, kind: "avatar" | "hero" | "notice") {
    if (!session) {
      throw new Error("Sign in before uploading images.");
    }
    const extension = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
    const path = `${session.user.id.toLowerCase()}/${kind}-${crypto.randomUUID().toLowerCase()}.${extension}`;
    const response = await fetch(`${supabaseUrl}/storage/v1/object/member-images/${path}`, {
      method: "POST",
      headers: {
        apikey: supabaseKey,
        Authorization: `Bearer ${session.access_token}`,
        "Content-Type": file.type || "image/jpeg",
        "x-upsert": "false",
      },
      body: file,
    });

    if (!response.ok) {
      throw new Error(userFacingServiceMessage(await response.text(), response.status));
    }

    return `${supabaseUrl}/storage/v1/object/public/member-images/${path}`;
  }

  async function registerOrganisation(draft: OrgRegistrationDraft) {
    if (!session) return false;
    setBusy(true);
    try {
      await rpc("save_my_business_profile", {
        p_business_name: draft.businessName.trim(),
        p_organisation_type: draft.organisationType,
        p_contact_name: draft.contactName.trim(),
        p_contact_email: draft.contactEmail.trim() || session.user.email,
        p_phone: draft.phone.trim() || null,
        p_address: draft.address.trim() || null,
        p_website: draft.website.trim() || null,
        p_about: draft.about.trim() || null,
        p_area_scope_id: draft.areaScopeId,
        p_selected_plan_id: draft.planId,
        p_hero_image_url: draft.heroImageUrl || null,
        p_avatar_image_url: draft.avatarImageUrl || null,
        p_hero_image_position_x: 50,
        p_hero_image_position_y: 50,
        p_avatar_image_position_x: 50,
        p_avatar_image_position_y: 50,
      }, session.access_token);
      await loadSignedInData();
      setNotice({ kind: "good", text: "Application submitted. Your membership application is pending review by Pōhutukawa Coast Calendar Support." });
      return true;
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function submitMemberApplication(draft: MemberDraft) {
    if (!session) return false;
    const payload = {
      owner_user_id: session.user.id,
      business_name: draft.business_name.trim(),
      contact_name: draft.contact_name.trim() || null,
      contact_email: draft.contact_email.trim() || session.user.email,
      phone: draft.phone.trim() || null,
      website: draft.website.trim() || null,
      about: draft.about.trim() || null,
      area_scope_id: draft.area_scope_id,
      selected_plan_id: draft.selected_plan_id,
      avatar_image_url: draft.avatar_image_url || null,
      hero_image_url: draft.hero_image_url || null,
      avatar_image_position_x: draft.avatar_image_position_x,
      avatar_image_position_y: draft.avatar_image_position_y,
      hero_image_position_x: draft.hero_image_position_x,
      hero_image_position_y: draft.hero_image_position_y,
      status: "pending_review",
    };
    setBusy(true);
    try {
      await rest(memberProfile ? `business_profiles?owner_user_id=eq.${session.user.id}` : "business_profiles", {
        method: memberProfile ? "PATCH" : "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      }, session.access_token);
      await loadSignedInData();
      setNotice({ kind: "good", text: "Membership submitted. You will get a notification when a decision is made." });
      return true;
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function toggleMemberBelong(host: HostRecord) {
    if (!session) {
      // iOS: signed-out Belong opens account access.
      setNotice({ kind: "warn", text: "Sign in or create a free account to Belong." });
      setSelectedEvent(null);
      setView("account");
      return;
    }

    const existing = memberFollows.find((follow) => follow.business_profile_id === host.id);
    setBusy(true);
    try {
      if (existing) {
        await rest<void>(`member_follows?id=eq.${existing.id}`, { method: "DELETE" }, session.access_token);
        setNotice({ kind: "good", text: `Removed ${host.business_name} from your Belonging.` });
      } else {
        await rest<MemberFollowRecord[]>("member_follows", {
          method: "POST",
          headers: { Prefer: "return=representation" },
          body: JSON.stringify({
            user_id: session.user.id,
            business_profile_id: host.id,
            notification_level: "all",
          }),
        }, session.access_token);
        setNotice({ kind: "good", text: `You Belong with ${host.business_name}. Notices can appear in your updates.` });
      }
      await loadSignedInData();
    } catch (error) {
      setNotice({ kind: "warn", text: `Belonging could not be saved: ${messageFromError(error)}` });
    } finally {
      setBusy(false);
    }
  }

  async function submitMemberNotice(draft: NoticeDraft) {
    if (!session || !memberProfile) return false;
    setBusy(true);
    try {
      await rest<MemberNoticeRecord[]>("member_notices", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify({
          business_profile_id: memberProfile.id,
          owner_user_id: session.user.id,
          title: draft.title.trim(),
          summary: draft.summary.trim() || null,
          body: draft.body.trim() || null,
          template_style: draft.template_style,
          status: draft.status,
          hero_image_url: draft.hero_image_url || null,
          image_urls: draft.hero_image_url ? [draft.hero_image_url] : [],
        }),
      }, session.access_token);
      await loadSignedInData();
      setNotice({
        kind: "good",
        text: draft.status === "published"
          ? "Notice published. People who Belong to this member can receive an update."
          : "Notice saved as a draft.",
      });
      return true;
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
      return false;
    } finally {
      setBusy(false);
    }
  }

    let listingSubmitLocked = false;
  async function submitListing(input: {
    title: string;
    description: string;
    date: string;
    time: string;
    location: string;
    placeName: string;
    locationScopeId: string | null;
    topics: string[];
    images: File[];
    poll?: { question: string; options: string[]; allowCustom: boolean } | null;
  }) {
    if (listingSubmitLocked) return false;
    if (!memberProfile?.id) {
      setNotice({ kind: "warn", text: "Organisation needed before a listing can be sent." });
      return false;
    }
    if (!session || !canPublish(memberProfile, subscriptions)) return false;
    const title = input.title.trim();
    const description = input.description.trim();
    const location = input.location.trim();
    if (!title || !description || (!input.poll && (!input.date || !input.time)) || !location || !input.placeName.trim()) {
      setNotice({ kind: "warn", text: "Add title, description, date, time, venue and a place." });
      return false;
    }
    // Polls start at creation time (see POLL_MAX_DAYS); date/time fields are hidden for polls.
    const startAt = input.poll ? new Date() : new Date(`${input.date}T${input.time}`);
    if (Number.isNaN(startAt.getTime())) {
      setNotice({ kind: "warn", text: "Check the date and time." });
      return false;
    }
    const topics = input.topics.length ? input.topics : ["Community"];
    const pollOptions = (input.poll?.options ?? []).map((option) => option.trim()).filter(Boolean).slice(0, POLL_MAX_OPTIONS);
    if (input.poll && (!input.poll.question.trim() || pollOptions.length < 2)) {
      setNotice({ kind: "warn", text: "Add a poll question and at least two options." });
      return false;
    }
    const pollFields = input.poll
      ? { poll_question: input.poll.question.trim(), poll_options: pollOptions, poll_allows_custom_answer: input.poll.allowCustom }
      : {};
    const pollStart = new Date();
    const payload = {
      title,
      category: topics[0],
      town: input.placeName.trim() || "Beachlands",
      primary_location_scope_id: input.locationScopeId,
      location_display_name: location,
      venue: location,
      // Polls: start now and close POLL_MAX_DAYS later. Other listings keep the chosen start + 2h.
      start_at: input.poll ? pollStart.toISOString() : startAt.toISOString(),
      end_at: input.poll ? new Date(pollStart.getTime() + POLL_MAX_MS).toISOString() : new Date(startAt.getTime() + 2 * 60 * 60 * 1000).toISOString(),
      price_label: "Free",
      is_free: true,
      audience: "Everyone",
      short_description: description,
      long_description: description,
      contact_name: memberProfile?.contact_name,
      contact_email: memberProfile?.contact_email,
      is_featured: false,
      is_paid_push: false,
      unverified_user_listing: false,
      status: "pending_review",
      listing_kind: input.poll ? "poll" : "event",
      ...pollFields,
      business_profile_id: memberProfile.id,
    };
    listingSubmitLocked = true;
    setBusy(true);
    try {
      const created = await rest<{ id: string }[]>("events", {
        method: "POST",
        headers: { Prefer: "return=representation" },
        body: JSON.stringify(payload),
      }, session.access_token);
      const eventId = created[0]?.id;
      const attachProblems: string[] = [];
      if (eventId) {
        await Promise.all(topics.map((topic, index) => rest("event_topics", {
          method: "POST",
          headers: { Prefer: "return=minimal" },
          body: JSON.stringify({ event_id: eventId, topic_slug: topic, source: "user", assigned_by: session.user.id }),
        }, session.access_token).catch((error: unknown) => { attachProblems.push(`topic: ${messageFromError(error)}`); return null; })));
        for (const [index, file] of input.images.entries()) {
          const imageId = crypto.randomUUID();
          const path = `${session.user.id}/${eventId}/${imageId}.jpg`;
          const upload = await fetch(`${supabaseUrl}/storage/v1/object/listing-images/${path}`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${session.access_token}`,
              apikey: supabaseKey,
              "Content-Type": file.type || "image/jpeg",
              "x-upsert": "true",
            },
            body: file,
          });
          if (!upload.ok) { attachProblems.push(`image ${index + 1} upload: ${userFacingServiceMessage(await upload.text(), upload.status)}`); continue; }
          await rest("event_images", {
            method: "POST",
            headers: { Prefer: "return=minimal" },
            body: JSON.stringify({ event_id: eventId, storage_path: path, position: index }),
          }, session.access_token).catch((error: unknown) => { attachProblems.push(`image ${index + 1}: ${messageFromError(error)}`); return null; });
        }
      }
      setNotice(attachProblems.length
        ? { kind: "warn", text: `Listing sent to Support for review, but some extras failed — ${attachProblems.join("; ")}` }
        : { kind: "good", text: "Listing sent to Support for review." });
      return true;
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
      return false;
    } finally {
    listingSubmitLocked = false;
      setBusy(false);
    }
  }

  async function requestAccountDeletion() {
    if (!session) return;
    const ok = window.confirm("Send Support a request to delete this account? This does not wipe the account immediately.");
    if (!ok) return;
    setBusy(true);
    try {
      await rpc("submit_support_request", {
        p_topic: "Account",
        p_message: "Please delete this Coast Calendar account.",
        p_listing_reference: null,
      }, session.access_token);
      await loadSignedInData();
      setNotice({ kind: "good", text: "Deletion request sent to Support." });
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
    } finally {
      setBusy(false);
    }
  }

  async function submitSupportRequest(form: HTMLFormElement): Promise<boolean> {
    if (!session) return false;
    const data = new FormData(form);
    setBusy(true);
    try {
      await rpc("submit_support_request", {
        p_topic: String(data.get("topic") ?? "Account"),
        p_message: String(data.get("message") ?? ""),
        p_listing_reference: String(data.get("listing_reference") ?? "") || null,
      }, session.access_token);
      form.reset();
      await loadSignedInData();
      setNotice({ kind: "good", text: "Support request sent." });
      return true;
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
      return false;
    } finally {
      setBusy(false);
    }
  }

  async function supportUpdate(table: "events" | "business_profiles" | "support_requests" | "event_change_requests" | "member_notices", id: string, patch: Record<string, unknown>) {
    if (!session) return;
    setBusy(true);
    try {
      await rest(`${table}?id=eq.${id}`, {
        method: "PATCH",
        headers: { Prefer: "return=minimal" },
        body: JSON.stringify(patch),
      }, session.access_token);
      await loadSupportData();
      setNotice({ kind: "good", text: "Support update saved." });
    } catch (error) {
      setNotice({ kind: "warn", text: messageFromError(error) });
    } finally {
      setBusy(false);
    }
  }

  const savedEvents = engagements
    .map((row) => row.events)
    .filter((event): event is EventRecord => Boolean(event));
  const showOperatorWorkspace = isSupportUser && supportView === "operator";

  return (
    <PollCardContext.Provider value={{ session, ownerProfileId: memberProfile?.id ?? null, onSignIn: () => { setSelectedEvent(null); setView("account"); }, noticeTools: { busy, canPublish: canPublish(memberProfile, subscriptions), onUploadImage: uploadMemberImage, onCreateNotice: submitMemberNotice } }}>
    <main>
      <QuickTour />
      <WelcomeResurface
        welcome={(() => { const row = events.find((event) => event.id === WELCOME_EVENT_ID); return row ? withWelcomeExtra(row) : null; })()}
        onOpen={(event) => { setSelectedEvent(event); setView("home"); }}
      />
      {notice ? <div className={`notice notice--${notice.kind}`}>{notice.text}</div> : null}

      {showOperatorWorkspace ? (
        <section className="section operator-shell" id="operator">
          <div className="dashboard-grid">
            <SupportAdminPanel
              onShowPublic={() => setSupportView("public")}
              onSignOut={() => { setSession(null); try { localStorage.removeItem("community_calendar_web_session"); } catch {}; setSupportView("public"); }}
              profiles={supportProfiles}
              subscriptions={supportSubscriptions}
              listings={supportListings}
              memberNotices={supportMemberNotices}
              requests={supportInboxRequests}
              changeRequests={changeRequests}
              notifications={supportNotifications}
              auditEvents={supportAuditEvents}
              busy={busy}
              onUpdate={supportUpdate}
            />
            <SupportRequestPanel requests={supportRequests} busy={busy} onSubmit={submitSupportRequest} />
            {session ? <AccountPanel session={session} profile={profile} busy={busy} onLogout={logout} onSave={saveProfile} /> : null}
          </div>
        </section>
      ) : (
        <div className="app-shell">
          <nav className="app-nav" aria-label="Main navigation">
            <button type="button" className={view === "home" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => { setSelectedEvent(null); setView("home"); }}>Home</button>
            <button type="button" className={view === "whatsOn" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => { setSelectedEvent(null); setView("whatsOn"); }}>What&apos;s On</button>
            {mounted && session ? (
              <button type="button" className={view === "create" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => setView("create")}>Create</button>
            ) : null}
            <button type="button" className={view === "hosts" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => { setSelectedHost(null); setView("hosts"); }}>Hosts</button>
            <button type="button" className={view === "settings" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => { void syncFreshSession(); setView("settings"); }}>Settings</button>
            {session && isSupportUser ? (
              <button type="button" className="app-nav__item" onClick={() => setSupportView("operator")}>Dashboard</button>
            ) : null}
            <div className="app-nav__bottom">
            {session ? (
              <button type="button" className="app-nav__item" onClick={() => { setSession(null); try { localStorage.removeItem("community_calendar_web_session"); } catch {} }}>
                Sign out
              </button>
            ) : (
              <button type="button" className={view === "account" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => setView("account")}>
                Sign in
              </button>
            )}
            <button type="button" className={view === "support" || view === "contact" ? "app-nav__item is-active" : "app-nav__item"} onClick={() => setView("contact")}>Support</button>
            </div>
          </nav>
          <div className="app-shell__main">
          <section className={view === "home" ? "hero" : "hero hero--page"}>
            <div className="hero__shade" />
            <div className="hero__content">
              {view === "home" ? (
                <>
                  <p className="eyebrow">Coast Calendar</p>
                  <h1>Coast Calendar</h1>
                  <p className="intro">Welcome to our community of communities. Stay informed and up to date with what is on in your area.</p>
                  <p className="panel-note">Your local guide to markets, music, family days, fundraisers and everything happening around Pōhutukawa Coast.</p>

                </>
              ) : view === "whatsOn" ? (
                <>
                  <p className="eyebrow">What&apos;s On</p>
                  <h1>What&apos;s On</h1>
                  <p className="intro">Look around, find your community, and see what is on and what is coming up. Stay informed.</p>
                </>
              ) : view === "hosts" ? (
                <>
                  <p className="eyebrow">Hosts</p>
                  <h1>Hosts</h1>
                  <p className="intro">A directory of organisations on Coast Calendar who take part so we can live, laugh and enjoy our communities.</p>
                </>
              ) : view === "create" ? (
                <>
                  <p className="eyebrow">Create</p>
                  <h1>Create</h1>
                  <p className="intro">This is where organisations create listings and polls for their community. Register as an organisation and start today.</p>
                </>
              ) : view === "account" ? (
                <>
                  <p className="eyebrow">Account</p>
                  <h1>Account</h1>
                  <p className="intro">Create an account to stay tuned in. Follow, share and set reminders so you and your friends are never the last to know.</p>
                </>
              ) : view === "contact" || view === "support" ? (
                <>
                  <p className="eyebrow">Support</p>
                  <h1>Support</h1>
                  <p className="intro">We are here to help. Send a message if there is something we should know, or something we could improve. This is our community.</p>
                </>
              ) : view === "settings" ? (
                <>
                  <p className="intro">Set yourself and your organisation up here. Settle in, and send feedback if something should work better.</p>
                </>
              ) : (
                <>
                  <p className="eyebrow">Coast Calendar</p>
                  <h1>{view}</h1>
                </>
              )}
            </div>
          </section>

          {!selectedEvent && view === "home" && (
          <section className="section section--tight" id="home-feed">

            <p className="eyebrow" style={{ color: "#fff", textShadow: "0 1px 8px rgba(0,0,0,0.45)", marginBottom: 8 }}>Search</p>
          <button type="button" className="area-pill" onClick={() => setShowFinder((open) => !open)} style={topicChipStyle(true)}>
              {locationScopes.find((scope) => scope.slug === homeScope)?.name ?? "Choose area"}
              {"  "}⌕
            </button>
            {!showFinder ? (
              <p className="panel-note" style={{ marginTop: 8 }}>Tap here to search again</p>
            ) : null}
            {showFinder ? (
              <div style={{ marginTop: 10 }}>
                <input
                  value={finderQuery}
                  onChange={(event) => setFinderQuery(event.target.value)}
                  placeholder="Search place or area"
                  autoCapitalize="off"
                  autoCorrect="off"
                  autoFocus
                  style={{ width: "100%", maxWidth: 360, padding: "10px 12px", borderRadius: 999, border: "1px solid rgba(16,33,31,0.16)" }}
                />
                <div className="area-row" style={{ marginTop: 8 }}>
                  {searchScopes(finderQuery, locationScopes).map((scope) => (
                    <button type="button" className="area-pill" key={`find-${scope.slug}`} onClick={() => { setHomeScope(scope.slug); setShowFinder(false); setFinderQuery(""); }}>
                      {scope.name}
                    </button>
                  ))}
                </div>
              </div>
            ) : null}
            <div className="area-row" style={{ marginTop: 10 }}>
              {primaryChipsOf(homeScope, locationScopes, locationEdges).map((scope) => (
                <button type="button" className="area-pill" key={`sib-${scope.slug}`} onClick={() => setHomeScope(scope.slug)}>
                  {scope.name}
                </button>
              ))}
            </div>
            <div className="area-row" style={{ marginTop: 8 }}>
              {ancestorScopesOf(homeScope, locationScopes, locationEdges).map((scope) => (
                <button type="button" className="area-pill" key={`anc-${scope.slug}`} onClick={() => setHomeScope(scope.slug)} style={{ color: "var(--pcc-green)", background: "rgba(31,77,51,0.10)", borderColor: "transparent" }}>
                  {scope.name}
                </button>
              ))}
            </div>
            <p className="panel-note"></p>
            <div className="area-row" style={{ marginTop: 8 }}>
              <span className="area-pill">{weeklyViews == null ? "—" : weeklyViews} views this week</span>
              <span className="area-pill">{(homeEventIDs ?? []).length} listings</span>
            </div>
            {visibleEvents.length === 0 ? (
              <EmptyState title="A quiet moment on the coast" text="New local listings will appear here as they’re published." />
            ) : (
              <div className="event-list" style={{ marginTop: 18 }}>
                {visibleEvents.slice(0, 30).map((event) => (
                  <EventCard
                    event={event}
                    host={event.submitted_by ? eventHost.get(event.submitted_by) : undefined}
                    key={`home-${event.id}`}
                    active={engagedByEvent.get(event.id)}
                    busy={busy}
                    onToggle={toggleEngagement}
                    onOpen={setSelectedEvent}
                  />
                ))}
              </div>
            )}
          </section>
          )}

          {!selectedEvent && view === "whatsOn" && (
          <section className="section" id="whats-on">
            <button type="button" className="area-pill" onClick={() => setShowFinder((open) => !open)} style={topicChipStyle(true)}>
              Showing {locationScopes.find((scope) => scope.slug === homeScope)?.name ?? "your area"} ⌕
            </button>
            {showFinder ? (
              <>
                <input
                  autoFocus
                  className="field"
                  placeholder="Search place or area"
                  value={finderQuery}
                  onChange={(e) => setFinderQuery(e.target.value)}
                  style={{ marginTop: 8, width: "100%" }}
                />
                <div className="area-row" style={{ marginTop: 8 }}>
                  {searchScopes(finderQuery, locationScopes).map((scope) => (
                    <button
                      type="button"
                      className="area-pill"
                      key={scope.slug}
                      onClick={() => { setHomeScope(scope.slug); setShowFinder(false); setFinderQuery(""); }}
                    >
                      {scope.name}
                    </button>
                  ))}
                </div>
              </>
            ) : null}
            <div className="area-row" style={{ margin: "8px 0 10px" }}>
              {(["today", "week", "month", "upcoming"] as const).map((scope) => (
                <button
                  type="button"
                  className="area-pill"
                  key={scope}
                  onClick={() => setDateScope(scope)}
                  style={topicChipStyle(dateScope === scope)}
                >
                  {scope === "today" ? "Today" : scope === "week" ? "This Week" : scope === "month" ? "This Month" : "Upcoming"}
                </button>
              ))}
            </div>
            <div className="area-row" style={{ margin: "12px 0 18px" }}>
              <button type="button" className="area-pill" onClick={() => setSelectedTopics([])} style={topicChipStyle(selectedTopics.length === 0)}>All</button>
              {topicFilters.map((topic) => (
                <button
                  type="button"
                  className="area-pill"
                  key={`wo-${topic.slug}`}
                  onClick={() => toggleTopic(topic.slug)}
                  style={topicChipStyle(selectedTopics.includes(topic.slug))}
                >
                  {topic.label}
                </button>
              ))}
            </div>
            {visibleEvents.length === 0 ? <EmptyState title={dateScope === "today" ? "Nothing scheduled here today" : dateScope === "week" ? "A quiet week in this area" : dateScope === "month" ? "No listings match this month" : "Nothing coming up in this area"} text={`Try a wider area or another topic to discover more around ${locationScopes.find((scope) => scope.slug === homeScope)?.name ?? "your area"}.`}>
              {ancestorScopesOf(homeScope, locationScopes, locationEdges).length ? (
                <div className="widen-row">
                  <span className="widen-row__label">Widen to</span>
                  {ancestorScopesOf(homeScope, locationScopes, locationEdges).slice(0, 3).map((scope) => (
                    <button type="button" className="area-pill" key={`widen-${scope.slug}`} onClick={() => setHomeScope(scope.slug)} style={topicChipStyle(false)}>{scope.name}</button>
                  ))}
                </div>
              ) : null}
            </EmptyState> : (
              <CompactCardsContext.Provider value={true}>
              <div className="event-grid event-grid--compact">
                {visibleEvents.slice(0, 30).map((event) => (
                  <EventCard
                    event={event}
                    host={event.submitted_by ? eventHost.get(event.submitted_by) : undefined}
                    key={event.id}
                    active={engagedByEvent.get(event.id)}
                    busy={busy}
                    onToggle={toggleEngagement}
                  onOpen={setSelectedEvent}
                  />
                ))}
              </div>
              </CompactCardsContext.Provider>
            )}
          </section>
          )}

          {selectedEvent && (
          <section className="section listing-detail" id="event-page">
            <div className="listing-detail__bar">
              <button className="listing-detail__back" type="button" onClick={() => setSelectedEvent(null)}>← Back</button>
            </div>
            {selectedEvent.image_url ? (
              <div className="listing-detail__hero"><img alt="" src={selectedEvent.image_url} /></div>
            ) : null}
            <div className="listing-detail__body">
              <p className="listing-detail__eyebrow">
                {selectedEvent.listing_kind === "poll" ? "Poll" : (selectedEvent.category || "Listing")}
                {selectedEvent.is_free ? <span className="listing-detail__badge">Free</span> : null}
              </p>
              <h2 className="listing-detail__title">{selectedEvent.title}</h2>
              <div className="listing-detail__meta">
                <span><span aria-hidden="true">◷</span> <DateText value={selectedEvent.start_at} /></span>
                {(selectedEvent.venue || selectedEvent.location_display_name || selectedEvent.town) ? (
                  <span><span aria-hidden="true">⌖</span> {[selectedEvent.venue, selectedEvent.location_display_name ?? selectedEvent.town].filter(Boolean).join(" · ")}</span>
                ) : null}
                {selectedEvent.price_label ? <span><span aria-hidden="true">$</span> {selectedEvent.price_label}</span> : null}
              </div>
              {selectedEvent.listing_kind === "poll" && selectedEvent.poll_question ? (
                <PollVoteCard
                  key={selectedEvent.id}
                  event={selectedEvent}
                  session={session}
                  isOwner={Boolean(memberProfile?.id && memberProfile.id === selectedEvent.business_profile_id)}
                  onSignIn={() => { setSelectedEvent(null); setView("account"); }}
                />
              ) : null}
              <div className="listing-detail__description">
                {selectedEvent.listing_kind === "poll" ? <h3>Why this poll is running</h3> : <h3>About this event</h3>}
                <p>{selectedEvent.listing_kind === "poll" ? (selectedEvent.long_description || "No extra context was added.") : (selectedEvent.long_description || selectedEvent.short_description)}</p>
                {(() => { const audience = (selectedEvent as EventRecord & { audience?: string | null }).audience; return audience ? <p><small>Good for</small> <strong>{audience}</strong></p> : null; })()}
              </div>
              {selectedEvent.organisation_name ? (() => {
                const orgHost = hosts.find((h) => h.id === selectedEvent.business_profile_id) ?? null;
                return (
                  <>
                    <button type="button" className="listing-detail__organiser" disabled={!orgHost} onClick={() => { if (orgHost) { setSelectedEvent(null); setSelectedHost(orgHost); setView("hosts"); } }}>
                      <span className="listing-detail__avatar" aria-hidden="true">{selectedEvent.organisation_name.slice(0, 1).toUpperCase()}</span>
                      <div><small>Listed by</small><strong>{selectedEvent.organisation_name}</strong>{orgHost ? <em>Tap to view this Organisation</em> : null}</div>
                    </button>
                    <PublicContactBlock event={selectedEvent} host={orgHost} />
                  </>
                );
              })() : null}
              {session && memberProfile?.id && memberProfile.id === selectedEvent.business_profile_id ? <ListingInsights eventID={selectedEvent.id} token={session.access_token} advanced={hasAdvancedInsights(subscriptions, selectedEvent)} /> : null}
              <div className="action-row">
                {(["interested", "going", "saved"] as const).map((type) => {
                  const on = Boolean(engagedByEvent.get(selectedEvent.id)?.has(type));
                  return (
                    <button type="button" key={type} className={on ? "chip chip--active" : "chip"} aria-pressed={on} disabled={busy} onClick={() => void toggleEngagement(selectedEvent.id, type)}>
                      <span aria-hidden="true">{type === "interested" ? (on ? "★" : "☆") : type === "going" ? (on ? "✔" : "○") : (on ? "▰" : "▱")}</span> {type === "saved" ? "Save" : type === "interested" ? "Interested" : "Going"}
                    </button>
                  );
                })}
                <button type="button" className="chip" onClick={() => downloadEventIcs(selectedEvent)}>
                  <span aria-hidden="true">📅</span> Add to calendar
                </button>
              </div>
              {engagedByEvent.get(selectedEvent.id)?.has("going") && readNotifyPrefs(session?.user.id).planPanel ? (
                <div className="plan-this" role="region" aria-label="Plan this">
                  <p className="plan-this__eyebrow">PLAN THIS</p>
                  <p className="plan-this__note">You're going. Add it to your phone's calendar — the file includes a reminder 1 hour before. The website doesn't send reminder emails.</p>
                  <div className="action-row">
                    <button type="button" className="button button--primary" onClick={() => downloadEventIcs(selectedEvent)}>Add to calendar</button>
                    <button type="button" className="button button--secondary" disabled={busy} aria-busy={busy} onClick={() => void toggleEngagement(selectedEvent.id, "going")}>Not going</button>
                  </div>
                </div>
              ) : null}
              <ReportListing key={`report-${selectedEvent.id}`} eventId={selectedEvent.id} session={session} onSignIn={() => { setSelectedEvent(null); setView("account"); }} />
            </div>
          </section>
          )}

          {!selectedEvent && view === "hosts" && selectedHost && (
          <section className="section" id="host-page">
            <div className="section__header">
              <p className="eyebrow">Host</p>
              <h2>{selectedHost.business_name}</h2>
              <button className="chip" type="button" onClick={() => setSelectedHost(null)}>Back to hosts</button>
            </div>
            <p className="event-card__meta">{selectedHost.public_location_text || areaLabel(selectedHost.area_scope_id)}</p>
            <p>{selectedHost.about ?? "A verified local member sharing listings with the community."}</p>
            <div className="action-row">
              {(() => {
                const belonging = memberFollows.some((follow) => follow.business_profile_id === selectedHost.id);
                return (
                  <button type="button" className={belonging ? "button button--primary is-belonging" : "button button--primary"} disabled={busy} aria-busy={busy} aria-pressed={belonging} onClick={() => void toggleMemberBelong(selectedHost)}>
                    <span aria-hidden="true">{belonging ? "✓" : "+"}</span> {belonging ? "Belonging" : "Belong"}
                  </button>
                );
              })()}
              {selectedHost.website ? <a className="chip" href={selectedHost.website} target="_blank" rel="noreferrer">Website</a> : null}
            </div>
            <HostNotices host={selectedHost} key={`notices-${selectedHost.id}`} />
            <div className="event-grid">
              {events.filter((event) => event.business_profile_id === selectedHost.id).length === 0 ? (
                <EmptyState title="Nothing coming up yet" text={`${selectedHost.business_name} has no published upcoming listings right now.`} />
              ) : events.filter((event) => event.business_profile_id === selectedHost.id).map((event) => (
                <EventCard
                  key={event.id}
                  event={event}
                  host={selectedHost}
                  active={engagedByEvent.get(event.id)}
                  busy={busy}
                  onToggle={toggleEngagement}
                  onOpen={setSelectedEvent}
                />
              ))}
            </div>
          </section>
          )}

          {view === "hosts" && !selectedHost && (
          <section className="section" id="hosts">
            <div className="host-search">
              <label>Search by location
                <input list="host-places" value={hostQuery} onChange={(e) => setHostQuery(e.target.value)} placeholder="All areas" />
              </label>
              <datalist id="host-places">{locationScopes.slice(0, 400).map((scope) => <option key={scope.id} value={scope.name} />)}</datalist>
              {hostQuery ? <button type="button" className="chip" onClick={() => setHostQuery("")}>All areas</button> : <span className="chip chip--active">All areas</span>}
            </div>
            {hosts.length === 0 ? <EmptyState title="Hosts will appear here" text="As organisations publish listings around Pōhutukawa Coast, their public pages will collect here." /> : (
              <div className="host-grid">
                {hosts.filter((host) => {
                  const q = hostQuery.trim().toLowerCase();
                  if (!q) return true;
                  const scopeName = locationScopes.find((scope) => scope.id === host.area_scope_id || scope.slug === host.area_scope_id)?.name ?? "";
                  return [host.business_name, host.public_location_text, scopeName, areaLabel(host.area_scope_id)].some((v) => String(v ?? "").toLowerCase().includes(q));
                }).map((host) => (
                  <HostCard
                    host={host}
                    isBelonging={memberFollows.some((follow) => follow.business_profile_id === host.id)}
                    busy={busy}
                    key={host.id}
                    onOpen={setSelectedHost}
                    onBelong={toggleMemberBelong}
                  />
                ))}
              </div>
            )}
          </section>
          )}

          {view === "create" && session && (
          <section className="section" id="create">
            <CreateListingPanel
              memberProfile={memberProfile}
              subscriptions={subscriptions}
              busy={busy}
              locationScopes={locationScopes}
              onCreateListing={submitListing}
              onOpenAccount={() => { setSettingsInitialPane("setup"); setView("settings"); }}
            />
          </section>
          )}

          {view === "account" && (
          <section className="section" id="account">

            {!session ? <AuthPanel busy={busy} onAuth={handleAuth} verifyEmail={pendingVerifyEmail} onClearVerify={() => setPendingVerifyEmail(null)} /> : accountSection === null ? (
              <div className="panel account-identity">
                <p className="eyebrow">Signed in</p>
                <h2>{memberProfile?.contact_name || memberProfile?.business_name || session.user.email}</h2>
                <p className="panel-note">{session.user.email}</p>
                <div className="action-row">
                  <button type="button" className="button" onClick={() => setView("settings")}>Open Settings</button>
                  <button type="button" className="button button--primary" onClick={logout}>Sign out</button>
                </div>
              </div>
            ) : (
              <>
              <button type="button" className="text-link" onClick={() => { setAccountSection(null); setView("settings"); }}>← Back to Settings</button>
              <AccountHub
                key={accountSection ?? "none"}
                initialSection={accountSection}
                onEditOrgCard={memberProfile ? () => { setAccountSection(null); setSettingsInitialPane("org"); setView("settings"); } : undefined}
                onRequestDelete={requestAccountDeletion}
                session={session}
                profile={profile}
                memberProfile={memberProfile}
                subscriptions={subscriptions}
                savedEvents={savedEvents}
                notifications={notifications}
                notices={memberNotices}
                busy={busy}
                onLogout={logout}
                onSave={saveProfile}
                onMarkNotificationRead={markNotificationRead}
                onSubmitMemberApplication={submitMemberApplication}
                onUploadMemberImage={uploadMemberImage}
                onCreateListing={submitListing}
                onCreateNotice={submitMemberNotice}
              />
              </>
            )}
          </section>
          )}

          {view === "support" && (
          <section className="section" id="support">
            <div className="section__header">
              <p className="eyebrow">Support</p>
              <h2>Help and review tools</h2>
            </div>
            {session ? (
              <div className="dashboard-grid">
                <SupportRequestPanel requests={supportRequests} busy={busy} onSubmit={submitSupportRequest} />
                {isSupportUser ? (
                  <div className="panel">
                    <h3>Support tools</h3>
                    <p className="panel-note">Open the operator dashboard to review membership, listing, Notice and support queues.</p>
                    <button className="button button--primary" type="button" onClick={() => setSupportView("operator")}>Open operator dashboard</button>
                  </div>
                ) : null}
              </div>
            ) : (
              <EmptyState title="Sign in for Support" text="Sign in so Support can reply through your app account." />
            )}
          </section>
          )}

          {view === "terms" && (
          <section className="section" id="terms">
            <div className="section__header">
              <p className="eyebrow">Terms</p>
              <h2>Terms of Use</h2>
            </div>
            <div className="panel">
              <p>Last updated 1 November 2026.</p>
              <p>Read the Terms of Use at <a href="/terms">coastcalendar.nz/terms</a>.</p>
              <p>Questions? Email <a href="mailto:support@coastcalendar.nz">support@coastcalendar.nz</a>.</p>
            </div>
          </section>
          )}

          {view === "privacy" && (
          <section className="section" id="privacy">
            <div className="section__header">
              <p className="eyebrow">Privacy</p>
              <h2>Privacy Policy</h2>
            </div>
            <div className="panel">
              <p>Last updated 1 November 2026.</p>
              <p>Read the Privacy Policy at <a href="/privacy">coastcalendar.nz/privacy</a>.</p>
              <p>Questions? Email <a href="mailto:support@coastcalendar.nz">support@coastcalendar.nz</a>.</p>
            </div>
          </section>
          )}

          
        {view === "settings" ? (
          <SettingsHub
            session={session}
            onAccount={() => setView("account")}
            userProfile={profile}
            onSaveProfile={saveProfile}
            notifications={notifications}
            onMarkNotificationRead={markNotificationRead}
            memberFollows={memberFollows}
            hosts={hosts}
            onToggleBelong={(host) => void toggleMemberBelong(host)}
            onSignOut={() => {
              setSession(null);
              localStorage.removeItem(sessionKey);
              setView("account");
            }}
            onOpenListing={(event) => { setSelectedEvent(event); setView("home"); }}
            onSupport={() => setView("contact")}
            onRequestDelete={requestAccountDeletion}
            engagements={engagements}
            boardEvents={events}
            busy={busy}
            onToggleEngagement={(eventID, type) => void toggleEngagement(eventID, type)}
            memberProfile={memberProfile}
            onPrivacy={() => setView("privacy")}
            onTerms={() => setView("terms")}
            subscriptions={subscriptions}
            onUploadImage={uploadMemberImage}
            onMembership={() => { setAccountSection("membership"); setView("account"); }}
            onAccountSection={(section) => { setAccountSection(section); setView("account"); }}
            onReload={() => loadSignedInData()}
            onReviewQueue={isSupportUser ? () => setSupportView("operator") : undefined}
            onRegisterOrg={registerOrganisation}
            initialPane={settingsInitialPane}
            onInitialPaneUsed={() => setSettingsInitialPane(null)}
            onPreviewOrg={memberProfile ? () => {
              setSelectedEvent(null);
              setSelectedHost(hosts.find((item) => item.id === memberProfile.id) ?? memberProfile);
              setView("hosts");
            } : undefined}
          />
        ) : null}

        {view === "contact" && (
          <section className="section" id="contact">
            <SupportChat
              authorName={memberProfile?.display_name || memberProfile?.contact_name || session?.user.email?.split("@")[0] || "You"}
              signedIn={Boolean(session)}
              requests={supportRequests}
              busy={busy}
              onSubmit={submitSupportRequest}
              onSignIn={() => setView("account")}
            />
          </section>
          )}
          </div>
        </div>
      )}

      <footer className="footer">
        <strong>Coast Calendar</strong>
        <span>iOS plus web access for Android and everyone else.</span>
        <nav className="footer__links" aria-label="Legal">
          <a href="/privacy">Privacy</a>
          <a href="/terms">Terms</a>
          <button type="button" onClick={() => setView("contact")}>Support</button>
        </nav>
      </footer>
    </main>
    </PollCardContext.Provider>
  );
}

function SupportViewSwitch({ view, onChange }: {
  view: "operator" | "public";
  onChange: (view: "operator" | "public") => void;
}) {
  return (
    <div className="mode-switch" aria-label="Support workspace switch">
      <span>Support view</span>
      <div className="mode-switch__buttons">
        <button type="button" aria-pressed={view === "operator"} onClick={() => onChange("operator")}>Operator</button>
        <button type="button" aria-pressed={view === "public"} onClick={() => onChange("public")}>Public app</button>
      </div>
    </div>
  );
}

// iOS OrganiserIdentitySheet "Public contact": profile public fields first, then listing contact fields.
function PublicContactBlock({ event, host }: { event: EventRecord; host: HostRecord | null }) {
  const h = (host ?? {}) as Record<string, unknown>;
  const e = event as unknown as Record<string, unknown>;
  const pick = (...vals: unknown[]) => { for (const v of vals) { if (typeof v === "string" && v.trim()) return v.trim(); } return null; };
  const email = pick(h.public_contact_email, e.contact_email);
  const phone = pick(h.public_phone, e.contact_phone);
  const address = pick(h.public_address, h.public_location_text);
  const website = pick(h.public_website);
  return (
    <div className="pcc-card public-contact">
      <h3>Public contact</h3>
      {email ? <p><small>Email</small> <a href={`mailto:${email}`}>{email}</a></p> : null}
      {phone ? <p><small>Phone</small> <a href={`tel:${phone.replace(/\s+/g, "")}`}>{phone}</a></p> : null}
      {address ? <p><small>Address</small> <a href={`https://maps.apple.com/?q=${encodeURIComponent(address)}`} target="_blank" rel="noreferrer">{address}</a></p> : null}
      {website ? <p><small>Website</small> <a href={/^https?:/i.test(website) ? website : `https://${website}`} target="_blank" rel="noreferrer">{website}</a></p> : null}
      {!email && !phone && !address && !website ? <p className="panel-note">No public contact details have been published for this organiser yet.</p> : null}
    </div>
  );
}

// iOS fetchListingAnalytics: sums event_analytics_daily rows (read-only).
// fb3: tiers per ANALYTICS_TIERS.md. Advanced = Growth/Sponsor member plan, or a listing tagged Boost + Insights (iOS inferredListingTier).
function hasAdvancedInsights(subscriptions: SubscriptionRecord[], event: EventRecord) {
  const activePlan = subscriptions.find((sub) => ["active", "trialing"].includes(String(sub.status)))?.plan_id ?? "";
  const label = String((event as EventRecord & { price_label?: string | null }).price_label ?? "").toLowerCase();
  return ["growth", "sponsor"].includes(activePlan) || label.includes("insights") || label.includes("$75") || label.includes("$14.99");
}

function ListingInsights({ eventID, token, advanced = false }: { eventID: string; token: string; advanced?: boolean }) {
  const [data, setData] = useState<{ impressions: number; detailViews: number; engaged: number; saves: number; shares: number } | null>(null);
  const [error, setError] = useState("");
  useEffect(() => {
    let cancelled = false;
    rest<{ impressions: number; detail_views: number; interested_taps: number; going_taps: number; save_taps: number; share_taps: number; poll_answers: number }[]>(
      `event_analytics_daily?select=impressions,detail_views,interested_taps,going_taps,save_taps,share_taps,poll_answers&event_id=eq.${eventID}`, {}, token)
      .then((rows) => {
        if (cancelled) return;
        const t = { impressions: 0, detailViews: 0, engaged: 0, saves: 0, shares: 0 };
        for (const r of rows ?? []) { t.impressions += r.impressions || 0; t.detailViews += r.detail_views || 0; t.engaged += (r.interested_taps || 0) + (r.going_taps || 0) + (r.poll_answers || 0); t.saves += r.save_taps || 0; t.shares += r.share_taps || 0; }
        setData(t);
      })
      .catch((err) => { if (!cancelled) setError(err instanceof Error ? err.message : "Insights unavailable"); });
    return () => { cancelled = true; };
  }, [eventID, token]);
  return (
    <div className="pcc-card listing-insights">
      <h3>Listing Insights</h3>
      <p className="panel-note">Compare visibility and engagement throughout the life of your listing.</p>
      {error ? <p className="panel-note"><strong>Insights unavailable</strong><br />{error}</p> : !data ? <p className="panel-note">Loading insights</p> : data.impressions + data.detailViews + data.engaged + data.saves + data.shares === 0 ? (
        <p className="panel-note">Activity will appear as people discover this listing.</p>
      ) : (
        <div className="listing-insights__grid">
          <p><strong>{data.impressions}</strong><small>Shown</small></p>
          <p><strong>{data.detailViews}</strong><small>Opened</small></p>
          <p><strong>{data.engaged}</strong><small>Engaged</small></p>
          <p><strong>{data.saves}</strong><small>Saves</small></p>
          <p><strong>{data.shares}</strong><small>Shares</small></p>
        </div>
      )}
      <div className={advanced ? "insights-advanced" : "insights-advanced is-locked"}>
        {[["Best times to list", "When people in your area open listings like this."], ["Audience areas", "Which suburbs and regions your viewers come from."], ["Trends", "Week-by-week reach and engagement."], ["Poll insights", "Answer timing and how results moved."]].map(([t, d]) => (
          <div key={t} className="insights-advanced__item">
            <strong>{t}</strong><small>{advanced ? "Coming soon — data is being collected." : d}</small>
            {advanced ? null : <span className="insights-advanced__lock">🔒 Upgrade</span>}
          </div>
        ))}
        {advanced ? null : <p className="panel-note">Advanced insights come with Growth Member or Community Partner plans, or a Boost + Insights listing. Plans are managed in the iOS app.</p>}
      </div>
    </div>
  );
}

function EmptyState({ title, text, children }: { title: string; text: string; children?: React.ReactNode }) {
  return (
    <div className="empty-state">
      <p className="empty-state__icon">+</p>
      <h3>{title}</h3>
      <p>{text}</p>
      {children}
    </div>
  );
}

function EventCard({ event, host, active, busy, onToggle, onOpen, ownerStatus, onRemove, onRequestEdit, ownerRequest }: {
  event: EventRecord;
  host?: HostRecord;
  active?: Set<string>;
  busy: boolean;
  onToggle: (eventID: string, type: EngagementRecord["engagement_type"]) => void;
  onOpen?: (event: EventRecord) => void;
  ownerStatus?: string;
  onRemove?: (eventID: string) => void;
  onRequestEdit?: (event: EventRecord) => void;
  ownerRequest?: ChangeRequest;
}) {
  const [pendingAction, setPendingAction] = useState<"" | "edit" | "remove">("");
  useEffect(() => { if (!busy) setPendingAction(""); }, [busy]);
  if (event.listing_kind === "poll" && !ownerStatus) {
    return <PollCard event={event} host={host} active={active} busy={busy} onToggle={onToggle} onOpen={onOpen} />;
  }
  return (
    <article className="event-card" onClick={() => onOpen?.(event)} style={onOpen ? { cursor: "pointer" } : undefined}>
      {event.image_url ? (
        <img className="event-card__photo" alt="" src={event.image_url} />
      ) : null}
      <div className="event-card__date"><DateText value={event.start_at} /></div>
      <div className="event-card__body">
        <p className="event-card__meta">{event.listing_kind === "poll" ? "Poll" : event.category} · {event.location_display_name ?? event.town}</p>
        <h3>{event.title}</h3>
      {event.listing_kind === "poll" && event.poll_question ? <p><strong>{event.poll_question}</strong></p> : null}
      <p>{event.short_description}</p>
      <div className="event-card__footer">
        <span>{event.venue}</span>
        <span>{event.price_label ?? "Free"}</span>
        {host ? <span>{host.business_name}</span> : null}
      </div>
      <div className="action-row">
        {onRemove ? (
          <>
            <span className="chip">{listingChip(ownerStatus ?? event.status)}</span>
            {event.status === "archived" || pollEnded(event) ? null : (
              <>
                {onRequestEdit ? (
                  <button type="button" className="button button--secondary" disabled={busy || ownerRequest?.status === "pending"} aria-busy={pendingAction === "edit"} onClick={(clickEvent) => { clickEvent.stopPropagation(); setPendingAction("edit"); onRequestEdit(event); }}>
                    {ownerRequest?.status === "pending" ? "Edit pending" : pendingAction === "edit" && busy ? "Sending…" : "Request edit"}
                  </button>
                ) : null}
                <button type="button" className="button button--secondary" disabled={busy} aria-busy={pendingAction === "remove"} onClick={(clickEvent) => { clickEvent.stopPropagation(); setPendingAction("remove"); onRemove(event.id); }}>{pendingAction === "remove" && busy ? "Removing…" : "Remove"}</button>
              </>
            )}
            {ownerRequest ? (
              <p className="panel-note">Edit request: {ownerRequest.status.replaceAll("_", " ")}{ownerRequest.support_note ? ` · Support: ${ownerRequest.support_note}` : ""}</p>
            ) : null}
          </>
        ) : (
          <>
            {/* iOS EngagementActionRow order and labels: Interested, Going, Save, Share; independent toggles. */}
            {(["interested", "going", "saved"] as const).map((type) => {
              const on = Boolean(active?.has(type));
              const icon = type === "interested" ? (on ? "★" : "☆") : type === "going" ? (on ? "✔" : "○") : (on ? "▰" : "▱");
              return (
                <button className={on ? "chip chip--active" : "chip"} aria-pressed={on} disabled={busy} key={type} onClick={(clickEvent) => { clickEvent.stopPropagation(); onToggle(event.id, type); }}>
                  <span aria-hidden="true">{icon}</span> {type === "saved" ? "Save" : type === "interested" ? "Interested" : "Going"}
                </button>
              );
            })}
            <button className="chip" type="button" onClick={(clickEvent) => { clickEvent.stopPropagation(); void shareEvent(event); }}>
              <span aria-hidden="true">↗</span> Share
            </button>
          </>
        )}
      </div>
    </div>
    {!ownerStatus ? <CardReport eventId={event.id} /> : null}
  </article>
  );
}

// Mirrors iOS EngagementActionRow.shareText.
// fb3: mirrors iOS recordEventAnalytics → rpc record_event_analytics. Fire-and-forget; never blocks the UI.
function recordEventAnalytics(eventID: string, eventType: string, source: string, token?: string | null) {
  void fetch(`${supabaseUrl}/rest/v1/rpc/record_event_analytics`, {
    method: "POST",
    headers: { apikey: supabaseKey, Authorization: `Bearer ${token || supabaseKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_event_id: eventID, p_event_type: eventType, p_source: source, p_location_scope_slug: null, p_session_id: null, p_metadata: {} }),
  }).catch(() => undefined);
}

async function shareEvent(event: EventRecord) {
  recordEventAnalytics(event.id, "share", "engagement_row");
  const when = new Date(event.start_at);
  const date = Number.isNaN(when.getTime()) ? "" : when.toLocaleDateString("en-NZ", { weekday: "short", day: "numeric", month: "short" });
  const time = Number.isNaN(when.getTime()) ? "" : when.toLocaleTimeString("en-NZ", { hour: "numeric", minute: "2-digit" });
  const place = [event.venue, event.location_display_name ?? event.town].filter(Boolean).join(", ");
  const text = `${event.title}\n${date}\n${time}\n${place}\n\nShared from Coast Calendar.`;
  try {
    if (typeof navigator !== "undefined" && "share" in navigator) {
      await navigator.share({ title: event.title, text });
      return;
    }
    await navigator.clipboard.writeText(text);
    window.alert("Listing details copied to clipboard.");
  } catch {
    // user cancelled share sheet or clipboard blocked: nothing to do
  }
}

// Mirrors iOS PollFeedCard (Components/EventFeedCard.swift): header badges, organiser + title,
// hero image or "Community poll" placeholder, "Poll closes" / "Asked by" meta, inline response panel,
// and the Open Poll / Save / Share action row.
function PollCard({ event, host, active, busy, onToggle, onOpen }: {
  event: EventRecord;
  host?: HostRecord;
  active?: Set<string>;
  busy: boolean;
  onToggle: (eventID: string, type: EngagementRecord["engagement_type"]) => void;
  onOpen?: (event: EventRecord) => void;
}) {
  const ctx = useContext(PollCardContext);
  const organiser = host?.business_name || event.organisation_name || "Community";
  const closed = ["archived", "rejected", "removed", "closed"].includes(String(event.status ?? "")) || pollEnded(event);
  const end = event.end_at ? new Date(event.end_at) : null;
  const endText = end && !Number.isNaN(end.getTime()) ? end.toLocaleDateString("en-NZ", { weekday: "short", day: "numeric", month: "short" }) : "";
  const saved = Boolean(active?.has("saved"));
  const place = event.location_display_name ?? event.town;
  const compactMode = useContext(CompactCardsContext);
  const [expandedState, setExpanded] = useState(false);
  const expanded = !compactMode || expandedState;
  if (!expanded) {
    return (
      <article className="poll-card poll-card--compact event-card">
        <span className="poll-overline" aria-hidden="true">POLL</span>
        <button type="button" className="poll-card__compact" aria-expanded={false} onClick={() => setExpanded(true)}>
          <span className="poll-badge"><span aria-hidden="true">📊</span> Poll</span>
          <span className="poll-card__title">{event.title}</span>
          <span className="poll-card__org">Asked by {organiser}{place ? ` · ${place}` : ""}</span>
          <span className="poll-card__closes">{closed ? "Poll closed" : `Poll closes ${endText}`}</span>
          <span className="poll-card__tap">Tap to answer ›</span>
        </button>
        <CardReport eventId={event.id} />
      </article>
    );
  }
  return (
    <article className={compactMode ? "poll-card is-expanded" : "poll-card"}>
      <span className="poll-overline" aria-hidden="true">POLL</span>
      {compactMode ? <button type="button" className="text-link poll-card__collapse" onClick={() => setExpanded(false)}>Collapse ▴</button> : null}
      <div className="poll-card__header">
        <span className="poll-badge"><span aria-hidden="true">📊</span> Poll</span>
        {event.category ? <span className="poll-card__cat">{event.category}</span> : null}
        {place ? <span className="poll-card__loc">{place}</span> : null}
      </div>
      <button type="button" className="poll-card__titles" onClick={() => onOpen?.(event)}>
        <span className="poll-card__org">{organiser}</span>
        <span className="poll-card__title">{event.title}</span>
        {event.short_description?.trim() ? <span className="poll-card__desc">{event.short_description}</span> : null}
      </button>
      {event.image_url ? (
        <img className="poll-card__hero" alt="" src={event.image_url} />
      ) : (
        <div className="poll-card__placeholder" aria-hidden="true">
          <span className="poll-card__placeholder-icon">📊</span>
          <span><strong>Community poll</strong><small>Have your say</small></span>
        </div>
      )}
      <div className="poll-card__meta">
        <span><span aria-hidden="true">🗓</span> {closed ? "Poll closed" : `Poll closes ${endText}`}</span>
        <span><span aria-hidden="true">👤</span> Asked by {organiser}</span>
      </div>
      {event.poll_question ? (
        ctx ? (
          <PollVoteCard
            event={event}
            session={ctx.session}
            isOwner={Boolean(ctx.ownerProfileId && ctx.ownerProfileId === event.business_profile_id)}
            onSignIn={ctx.onSignIn}
            compact
          />
        ) : (
          <div className="poll-panel"><p className="poll-panel__q">{event.poll_question}</p></div>
        )
      ) : (
        <p className="poll-panel poll-panel__status">This poll is being prepared. Check back shortly to have your say.</p>
      )}
      <div className="poll-card__actions">
        <button type="button" className="poll-action" onClick={() => onOpen?.(event)}><span aria-hidden="true">↗</span> Open Poll</button>
        <button type="button" className={saved ? "poll-action is-selected" : "poll-action"} aria-pressed={saved} disabled={busy} onClick={() => onToggle(event.id, "saved")}><span aria-hidden="true">{saved ? "▰" : "▱"}</span> Save</button>
        <button type="button" className="poll-action" onClick={() => void sharePoll(event)}><span aria-hidden="true">⇪</span> Share</button>
      </div>
      <CardReport eventId={event.id} />
    </article>
  );
}

// iOS PollActionRow.shareText
async function sharePoll(event: EventRecord) {
  recordEventAnalytics(event.id, "share", "poll_card");
  const text = `Poll: ${event.title}\n${event.location_display_name ?? event.town ?? ""}\n\nShared from Coast Calendar.`;
  try {
    if (typeof navigator !== "undefined" && "share" in navigator) { await navigator.share({ title: event.title, text }); return; }
    await navigator.clipboard.writeText(text);
    window.alert("Poll details copied to clipboard.");
  } catch {
    // share sheet cancelled or clipboard blocked
  }
}


// iOS parity: MemberNoticesScreen (EventDetailScreen.swift). Reads member_notices for the host
// and notice_reads for the signed-in user; opening a Notice marks it read (POST merge-duplicates).
function HostNotices({ host }: { host: HostRecord }) {
  const ctx = useContext(PollCardContext);
  const session = ctx?.session ?? null;
  const isOwner = !!ctx?.ownerProfileId && ctx.ownerProfileId === host.id;
  const [open, setOpen] = useState(false);
  const [notices, setNotices] = useState<MemberNoticeRecord[] | null>(null);
  const [readIDs, setReadIDs] = useState<Set<string>>(new Set());
  const [error, setError] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<string | null>(null);
  const [composing, setComposing] = useState(false);
  const load = useCallback(async () => {
    setError(null);
    try {
      const token = isOwner ? session?.access_token : undefined;
      const statusFilter = token ? "" : "&status=eq.published";
      const rows = await rest<MemberNoticeRecord[]>(
        `member_notices?select=id,business_profile_id,owner_user_id,title,summary,body,template_style,status,hero_image_url,published_at,created_at,updated_at&business_profile_id=eq.${host.id}${statusFilter}&order=published_at.desc.nullslast,created_at.desc`,
        {}, token);
      setNotices(rows ?? []);
      if (session) {
        const reads = await rest<{ notice_id: string }[]>("notice_reads?select=notice_id", {}, session.access_token).catch(() => []);
        setReadIDs(new Set((reads ?? []).map((r) => r.notice_id)));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not load Notices");
      setNotices([]);
    }
  }, [host.id, isOwner, session]);
  useEffect(() => { void load(); }, [load]);
  async function markRead(ids: string[]) {
    if (!session) return;
    setReadIDs((prev) => { const next = new Set(prev); ids.forEach((id) => next.add(id)); return next; });
    for (const id of ids) {
      try {
        await rest("notice_reads", { method: "POST", headers: { "Content-Type": "application/json", Prefer: "return=minimal,resolution=merge-duplicates" }, body: JSON.stringify({ notice_id: id, user_id: session.user.id }) }, session.access_token);
      } catch { /* iOS also ignores markRead failures */ }
    }
  }
  // letters1: owner Publish / Archive (RLS "Members manage own notices"; publish fires the follower-notification trigger).
  const [ownerBusy, setOwnerBusy] = useState<string | null>(null);
  async function setNoticeStatus(n: MemberNoticeRecord, status: "published" | "archived") {
    if (!session || !isOwner) return;
    setOwnerBusy(n.id); setError(null);
    try {
      const rows = await rest<MemberNoticeRecord[]>(`member_notices?id=eq.${n.id}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Prefer: "return=representation" },
        body: JSON.stringify(status === "archived" ? { status, archived_at: new Date().toISOString() } : { status }),
      }, session.access_token);
      if (!rows || rows.length === 0) throw new Error("Not saved — this Notice couldn't be updated (permission).");
      await load();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not update Notice");
    } finally {
      setOwnerBusy(null);
    }
  }
  const list = (notices ?? []).filter((n) => isOwner || n.status === "published");
  const unread = session ? list.filter((n) => n.status === "published" && !readIDs.has(n.id)).length : 0;
  return (
    <div className="host-notices">
      <button type="button" className="button host-notices__toggle" aria-expanded={open} onClick={() => setOpen((v) => !v)}>
        <span aria-hidden="true">📣</span> {unread > 0 ? `Notices ${unread}` : "Notices"}
      </button>
      {open ? (
        <div className="host-notices__panel pcc-card">
          <h3 className="host-notices__title">Notices</h3>
          <p className="event-card__meta">Latest from {host.business_name}</p>
          {isOwner && ctx?.noticeTools ? (
            composing ? (
              <NoticeComposer notices={[]} busy={ctx.noticeTools.busy} canPublish={ctx.noticeTools.canPublish} onUploadImage={ctx.noticeTools.onUploadImage} onCreateNotice={async (draft) => { const ok = await ctx.noticeTools!.onCreateNotice(draft); if (ok) { setComposing(false); void load(); } return ok; }} />
            ) : (
              <button type="button" className="button button--primary host-notices__create" onClick={() => setComposing(true)}><span aria-hidden="true">✎</span> Create Notice</button>
            )
          ) : null}
          {session && unread > 0 ? <button type="button" className="text-link" onClick={() => void markRead(list.map((n) => n.id))}>Mark all as read</button> : null}
          {notices !== null && error ? <p className="panel-note" role="alert">{error}</p> : null}
          {notices === null ? <p className="panel-note">Loading…</p> : error && list.length === 0 ? (
            <p className="panel-note"><strong>Could not load Notices</strong><br />{error}</p>
          ) : list.length === 0 ? (
            <p className="panel-note"><strong>No Notices yet</strong><br />{host.business_name} has not published a Notice or weekly letter yet.</p>
          ) : list.map((n) => {
            const isUnread = !!session && !readIDs.has(n.id);
            const isOpen = expanded === n.id;
            return (
              <article key={n.id} className={isUnread ? "notice-card is-unread" : "notice-card"}>
                <button type="button" className="notice-card__head" aria-expanded={isOpen} onClick={() => { setExpanded(isOpen ? null : n.id); if (isUnread) void markRead([n.id]); }}>
                  {isUnread ? <span className="notice-card__dot" aria-label="Unread" /> : null}
                  <span className="notice-card__icon" aria-hidden="true">{n.template_style === "weekly_letter" ? "📰" : "📣"}</span>
                  <span>
                    <strong>{n.title}</strong>
                    <em>{new Date(n.published_at ?? n.created_at).toLocaleDateString()}{n.status !== "published" ? ` · ${n.status}` : ""}</em>
                  </span>
                </button>
                {n.summary && !isOpen ? <p>{n.summary}</p> : null}
                {isOwner && session ? (
                  <div className="action-row notice-card__owner">
                    {n.status === "draft" ? <button type="button" className="button button--small" disabled={ownerBusy === n.id || !ctx?.noticeTools?.canPublish} onClick={() => void setNoticeStatus(n, "published")}>{ownerBusy === n.id ? "Publishing…" : "Publish"}</button> : null}
                    {n.status === "published" ? <button type="button" className="button button--small" disabled={ownerBusy === n.id} onClick={() => { if (window.confirm("Archive this Notice? It will be hidden from your page.")) void setNoticeStatus(n, "archived"); }}>{ownerBusy === n.id ? "Archiving…" : "Archive"}</button> : null}
                    {n.status === "archived" ? <button type="button" className="button button--small" disabled={ownerBusy === n.id} onClick={() => void setNoticeStatus(n, "published")}>Restore</button> : null}
                  </div>
                ) : null}
                {isOpen ? (
                  <div className="notice-card__body notice-detail">
                    {n.hero_image_url ? <img src={n.hero_image_url} alt="" /> : null}
                    <p className="notice-detail__org"><span aria-hidden="true">✓</span> {host.business_name}</p>
                    <h4 className="notice-detail__title">{n.title}</h4>
                    <p className="notice-detail__date">{new Date(n.published_at ?? n.created_at).toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long", year: "numeric" })}</p>
                    {n.summary ? <p className="notice-detail__summary">{n.summary}</p> : null}
                    {n.body ? n.body.split(/\n{2,}/).map((para, i) => <p key={i}>{para}</p>) : null}
                  </div>
                ) : null}
              </article>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}

function HostCard({ host, isBelonging, busy, onOpen, onBelong }: {
  host: HostRecord;
  isBelonging: boolean;
  busy: boolean;
  onOpen: (host: HostRecord) => void;
  onBelong: (host: HostRecord) => void;
}) {
  return (
    <article className="host-card" onClick={() => onOpen(host)} style={{ cursor: "pointer" }}>
      <div
        className="host-card__hero"
        aria-hidden="true"
        style={host.hero_image_url ? {
          backgroundImage: `url(${host.hero_image_url})`,
          backgroundSize: "cover",
          backgroundPosition: `${host.hero_image_position_x ?? 50}% ${host.hero_image_position_y ?? 50}%`,
        } : undefined}
      />
      <div
        className="host-card__avatar"
        aria-hidden="true"
        style={host.avatar_image_url ? {
          backgroundImage: `url(${host.avatar_image_url})`,
          backgroundSize: "cover",
          backgroundPosition: `${host.avatar_image_position_x ?? 50}% ${host.avatar_image_position_y ?? 50}%`,
        } : undefined}
      >
        {host.avatar_image_url ? null : (host.business_name || "?").slice(0, 1)}
      </div>
      <div className="host-card__body">
        <p className="event-card__meta">{host.public_location_text || areaLabel(host.area_scope_id)}</p>
        <h3>{host.business_name}</h3>
        <p>{host.about ?? "A verified local member sharing listings with the community."}</p>
        <div className="action-row">
          <button className={isBelonging ? "chip chip--active" : "chip"} disabled={busy} onClick={(event) => { event.stopPropagation(); onBelong(host); }}>
            <span aria-hidden="true">{isBelonging ? "✓" : "+"}</span> {isBelonging ? "Belonging" : "Belong"}
          </button>
          {host.website ? <a className="chip" href={host.website}>Website</a> : null}
        </div>
      </div>
    </article>
  );
}

type OrgRegistrationDraft = {
  businessName: string; organisationType: string; contactName: string; contactEmail: string; phone: string;
  address: string; website: string; about: string; areaScopeId: string; planId: string; heroImageUrl: string; avatarImageUrl: string;
};

// ob1: iOS "How it works" membership path (SettingsScreen MembershipStepRow 1-4) + plan + pay.
function GetSetUpGuide({ session, profile, subscriptions, busy, onBack, onSignIn, onRegister, onUploadImage, onReload, onManageOrg }: {
  session: AuthSession | null;
  profile: HostRecord | null;
  subscriptions: SubscriptionRecord[];
  busy: boolean;
  onBack: () => void;
  onSignIn: () => void;
  onRegister?: (draft: OrgRegistrationDraft) => Promise<boolean>;
  onUploadImage?: (file: File, kind: "avatar" | "hero") => Promise<string>;
  onReload?: () => Promise<void> | void;
  onManageOrg: () => void;
}) {
  const active = canPublish(profile, subscriptions);
  const status = profile?.status ?? null;
  const step = !session ? 1 : !profile ? 2 : status !== "approved" ? 3 : active ? 5 : 4;
  const [editing, setEditing] = useState(false);
  const [payNote, setPayNote] = useState("");
  const [paying, setPaying] = useState(false);
  // stripe1: return from Stripe Checkout (?checkout=success|cancelled, stashed by the app shell).
  useEffect(() => {
    let result: string | null = null;
    try { result = window.sessionStorage.getItem("cc-checkout"); window.sessionStorage.removeItem("cc-checkout"); } catch { /* ignore */ }
    if (result === "cancelled") { setPayNote("Checkout cancelled. No payment was taken."); return; }
    if (result !== "success") return;
    setPayNote("Payment received, activating…");
    let tries = 0;
    const timer = window.setInterval(() => {
      tries += 1;
      void onReload?.();
      if (tries >= 10) { window.clearInterval(timer); }
    }, 3000);
    void onReload?.();
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const [plan, setPlan] = useState<string>(profile?.selected_plan_id ?? "local_business");
  const [draft, setDraft] = useState<OrgRegistrationDraft>(() => ({
    businessName: profile?.business_name ?? "", organisationType: String((profile as (HostRecord & { organisation_type?: string }) | null)?.organisation_type ?? ""),
    contactName: profile?.contact_name ?? "", contactEmail: profile?.contact_email ?? session?.user.email ?? "", phone: profile?.phone ?? "",
    address: String((profile as (HostRecord & { address?: string }) | null)?.address ?? ""), website: profile?.website ?? "https://www.",
    about: profile?.about ?? "", areaScopeId: profile?.area_scope_id ?? "pohutukawa-coast", planId: profile?.selected_plan_id ?? "local_business",
    heroImageUrl: profile?.hero_image_url ?? "", avatarImageUrl: profile?.avatar_image_url ?? "",
  }));
  const [formError, setFormError] = useState("");
  const set = (key: keyof OrgRegistrationDraft) => (e: { target: { value: string } }) => setDraft((d) => ({ ...d, [key]: e.target.value }));
  const stepsCopy: [string, string][] = [
    ["Sign in normally", "Use a regular app account first. Browsing, saving and reminders stay separate from membership."],
    ["Register your Organisation", "Tell us who you represent and who is authorised to manage the membership. Public homepage details are set up separately."],
    ["Wait for admin approval", "Your application shows as pending until Support approves it."],
    ["Use your dashboard", "After approval, finish your page, activate the subscription, publish listings and post Notices for followers."],
  ];
  async function upload(file: File | undefined, kind: "hero" | "avatar") {
    if (!file || !onUploadImage) return;
    try { const url = await onUploadImage(file, kind); setDraft((d) => ({ ...d, [kind === "hero" ? "heroImageUrl" : "avatarImageUrl"]: url })); }
    catch (e) { setFormError(e instanceof Error ? e.message : "Image upload failed."); }
  }
  const showForm = step === 2 || (editing && step >= 3);
  return (
    <section className="panel account-panel setup-guide">
      <button type="button" className="text-link" onClick={onBack}>← Back to Settings</button>
      <p className="eyebrow">Organisations</p>
      <h2>Get set up</h2>
      <p className="panel-note">How it works</p>
      <ol className="setup-steps">
        {stepsCopy.map(([title, message], i) => (
          <li key={title} className={i + 1 < step ? "is-done" : i + 1 === step || (i === 3 && step >= 4) ? "is-current" : ""}>
            <span className="setup-steps__num" aria-hidden="true">{i + 1 < step ? "✓" : i + 1}</span>
            <span><strong>{title}</strong><small>{message}</small></span>
          </li>
        ))}
      </ol>

      {step === 1 ? (
        <div className="pcc-card setup-card">
          <h3>Start with your account</h3>
          <p className="panel-note">Create a free account or sign in. Then come back here to register your Organisation.</p>
          <button type="button" className="button button--primary" onClick={onSignIn}>Sign in or create account</button>
        </div>
      ) : null}

      {step >= 3 && !editing ? (
        <div className="pcc-card setup-card">
          {status === "pending_review" || status === "pending" ? (<>
            <h3>⏳ Application submitted</h3>
            <p className="panel-note">Your membership application is pending review by Pōhutukawa Coast Calendar Support. We'll let you know when it has been reviewed.</p>
          </>) : status === "rejected" ? (<>
            <h3>⚠️ Needs changes</h3>
            <p className="panel-note">{(profile as HostRecord & { rejection_reason?: string | null }).rejection_reason || profile?.support_note || "Support requested changes before this member profile can be approved."}</p>
            <button type="button" className="button button--primary" onClick={() => setEditing(true)}>Update application</button>
          </>) : status === "suspended" ? (<>
            <h3>⏸ Publishing suspended</h3>
            <p className="panel-note">{(profile as HostRecord & { suspension_reason?: string | null }).suspension_reason || profile?.support_note || "Support has paused publishing access for this member profile."}</p>
          </>) : status === "approved" && !active ? (<>
            <h3>✓ Approved - finish your page</h3>
            <p className="panel-note">{profile?.support_note || "Add or check your profile image, hero image, bio and contact details, then complete the selected monthly subscription to activate publishing access."}</p>
            <button type="button" className="button" onClick={onManageOrg}>Finish your page</button>
          </>) : active ? (<>
            <h3>✓ {iosPlans.find((p) => p.id === (subscriptions.find((sub) => ["active", "trialing"].includes(String(sub.status)))?.plan_id ?? profile?.selected_plan_id))?.title ?? "Plan"} active</h3>
            <p className="panel-note">Publishing is unlocked. Create listings, polls and Notices for people who Belong to your page.</p>
          </>) : null}
          {onReload ? <button type="button" className="text-link" onClick={() => void onReload()}>Check again</button> : null}
        </div>
      ) : null}

      {showForm ? (
        <form className="pcc-card setup-card form-grid" onSubmit={(e) => {
          e.preventDefault();
          if (!draft.organisationType) { setFormError("Choose the type that best fits this membership."); return; }
          if (!draft.businessName.trim() || !draft.contactName.trim()) { setFormError("Add the organisation name and public contact person."); return; }
          setFormError("");
          void onRegister?.(draft).then((ok) => { if (ok) setEditing(false); });
        }}>
          <h3 className="full">Register your Organisation</h3>
          <p className="panel-note full">Tell us who you represent and who is authorised to manage the membership. Public homepage details are set up separately.</p>
          <label className="full">Banner image<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => void upload(e.target.files?.[0], "hero")} />{draft.heroImageUrl ? <small>Banner added ✓</small> : null}</label>
          <label className="full">Profile image<input type="file" accept="image/jpeg,image/png,image/webp" onChange={(e) => void upload(e.target.files?.[0], "avatar")} />{draft.avatarImageUrl ? <small>Profile image added ✓</small> : null}</label>
          <label className="full">Organisation name <em>Required</em><input value={draft.businessName} onChange={set("businessName")} required /></label>
          <label className="full">Organisation type <em>Required</em>
            <select value={draft.organisationType} onChange={set("organisationType")} required>
              <option value="">Choose organisation type</option>
              {organisationTypes.map(([id, title]) => <option key={id} value={id}>{title}</option>)}
            </select>
          </label>
          <label>Application contact email<input type="email" value={draft.contactEmail} onChange={set("contactEmail")} required /></label>
          <label>Public contact person <em>Required</em><input value={draft.contactName} onChange={set("contactName")} required /></label>
          <label>Application phone<input value={draft.phone} onChange={set("phone")} inputMode="tel" /></label>
          <label>Business, school or group address<input value={draft.address} onChange={set("address")} /></label>
          <label className="full">Website or social link<input value={draft.website} onChange={set("website")} /><small>Start after https://www. Leave only the prefix if you do not have a website.</small></label>
          <label className="full">Area<select value={draft.areaScopeId} onChange={set("areaScopeId")}>
            <option value="pohutukawa-coast">Pohutukawa Coast</option><option value="franklin">Franklin</option><option value="east-auckland">East Auckland</option>
          </select><small>Choose the area shown on this page.</small></label>
          <label className="full">Application note<textarea value={draft.about} onChange={set("about")} placeholder="Tell Support enough to assess the application, including your connection to the organisation or member." /></label>
          <label className="full">Subscription plan<select value={draft.planId} onChange={set("planId")}>
            {iosPlans.map((p) => <option key={p.id} value={p.id}>{p.title} · {p.price} · {p.allowance}</option>)}
          </select></label>
          {formError ? <p className="panel-note full" role="alert">{formError}</p> : null}
          <div className="full action-row">
            <button className="button button--primary" disabled={busy} aria-busy={busy}>{busy ? "Submitting…" : profile ? "Resubmit application" : "Submit application"}</button>
            {editing ? <button type="button" className="button" onClick={() => setEditing(false)}>Cancel</button> : null}
          </div>
        </form>
      ) : null}

      {step >= 4 && active ? (
        <div className="pcc-card setup-card">
          <h3>Monthly member plans</h3>
          <SubscriptionEndLine subscriptions={subscriptions} />
          <CancelPlanControl subscriptions={subscriptions} session={session} profileId={profile?.id} />
        </div>
      ) : null}

      {step >= 4 && !active ? (
        <div className="pcc-card setup-card">
          <h3>Monthly member plans</h3>
          <SubscriptionEndLine subscriptions={subscriptions} />
          <CancelPlanControl subscriptions={subscriptions} session={session} profileId={profile?.id} />
          <p className="panel-note">After approval, choose a monthly plan below.</p>
          <div className="plan-grid">
            {iosPlans.map((p) => (
              <button type="button" key={p.id} className={plan === p.id ? "plan-card is-on" : "plan-card"} aria-pressed={plan === p.id} onClick={() => setPlan(p.id)}>
                <strong>{p.title}</strong><span className="plan-card__price">{p.price}</span><small>{p.allowance}</small><small>{p.blurb}</small>
              </button>
            ))}
          </div>
          <h3>Pay</h3>
          <button type="button" className="button button--primary" disabled={!STRIPE_ENABLED || busy || paying} aria-busy={paying} onClick={() => { if (!session || !profile || paying) return; setPaying(true); setPayNote("Opening secure checkout…"); startCheckout(plan, profile.id, session.access_token).catch((e) => { setPaying(false); setPayNote(e instanceof Error ? e.message : "Checkout failed."); }); }}>
            {paying ? "Opening checkout…" : STRIPE_ENABLED ? `Pay ${iosPlans.find((p) => p.id === plan)?.price ?? ""}` : "Pay by card"}
          </button>
          <p className="panel-note">{STRIPE_ENABLED ? payNote : "Card payments on web coming soon. Activate in the iPhone app for now."}</p>
        </div>
      ) : null}
    </section>
  );
}

function AuthPanel({ busy, onAuth, verifyEmail, onClearVerify }: { busy: boolean; onAuth: (email: string, password: string, mode: "sign-in" | "sign-up", fullName?: string) => void; verifyEmail?: string | null; onClearVerify?: () => void }) {
  const [mode, setMode] = useState<"sign-in" | "sign-up">("sign-in");
  const [email, setEmail] = useState("");
  const [authNote, setAuthNote] = useState("");
  const [working, setWorking] = useState(false);
  if (verifyEmail) {
    return (
      <div className="panel auth-verify">
        <p className="eyebrow">Email confirmation</p>
        <h2>Check your email</h2>
        <p className="panel-note">We sent a confirmation link to <strong>{verifyEmail}</strong>. Open the link in your email, then tap Check again.</p>
        {authNote ? <p className="panel-note" role="status">{authNote}</p> : null}
        <div className="action-row">
          <button type="button" className="button" disabled={working} aria-busy={working} onClick={() => { setWorking(true); setAuthNote(""); resendVerificationEmail(verifyEmail).then(() => setAuthNote("Confirmation email sent again. Check your inbox.")).catch((e) => setAuthNote(e instanceof Error ? e.message : "Could not resend. Try again soon.")).finally(() => setWorking(false)); }}>Resend email</button>
          <button type="button" className="button button--primary" onClick={() => { setMode("sign-in"); onClearVerify?.(); }}>Check again</button>
        </div>
      </div>
    );
  }
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const mismatch = mode === "sign-up" && confirmPassword.length > 0 && password !== confirmPassword;
  return (
    <form className="panel" onSubmit={(event) => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      if (mode === "sign-up" && password !== confirmPassword) {
        event.currentTarget.reportValidity();
        return;
      }
      onAuth(String(data.get("email") ?? ""), String(data.get("password") ?? ""), mode, String(data.get("full_name") ?? ""));
    }}>
      <div className="auth-intro">
        <p className="panel-note"><strong>Public browsing works without an account.</strong></p>
        <p className="panel-note"><strong>No Sign-In Needed</strong> Anyone can browse published local events without creating a profile or joining a membership.</p>
        <p className="panel-note"><strong>Manual Review</strong> Submitted listings are checked before they appear, so the public calendar stays useful, local and trusted.</p>
      </div>
      <div className="segmented">
        <button type="button" className={mode === "sign-in" ? "chip chip--active" : "chip"} onClick={() => setMode("sign-in")}>Sign in</button>
        <button type="button" className={mode === "sign-up" ? "chip chip--active" : "chip"} onClick={() => setMode("sign-up")}>Create account</button>
      </div>
      {mode === "sign-up" ? <label>Full name<input name="full_name" autoComplete="name" required placeholder="Used to greet you in the app. Not shown on public listings." /></label> : null}
      <label>Email<input name="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} /></label>
      <label>Password<input name="password" type="password" minLength={6} required value={password} onChange={(event) => setPassword(event.target.value)} /></label>
      {mode === "sign-up" ? (
        <label className={mismatch ? "field-error" : undefined}>
          Confirm password
          <input
            type="password"
            minLength={6}
            required
            value={confirmPassword}
            onChange={(event) => setConfirmPassword(event.target.value)}
            pattern={password.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}
            title="Passwords must match."
          />
          {mismatch ? <span>Passwords do not match yet.</span> : null}
        </label>
      ) : null}
      <button className="button button--primary" disabled={busy} aria-busy={busy}>{busy ? (mode === "sign-in" ? "Signing in…" : "Creating account…") : mode === "sign-in" ? "Sign in" : "Create account"}</button>
      {mode === "sign-in" ? (
        <button type="button" className="text-link" disabled={working} onClick={() => {
          if (!email.trim()) { setAuthNote("Enter your email first, then tap Forgot password."); return; }
          setWorking(true); setAuthNote("");
          sendPasswordResetEmail(email).then(() => setAuthNote("Password reset email sent. Check your inbox, then come back and sign in.")).catch(() => setAuthNote("Password reset email could not be sent. Check the address and try again.")).finally(() => setWorking(false));
        }}>Forgot password?</button>
      ) : null}
      {authNote ? <p className="panel-note" role="status">{authNote}</p> : null}
    </form>
  );
}

type AccountHubSection = "account" | "saved" | "notifications" | "membership" | null;


function useDebounced(value: string, ms = 280) {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), ms);
    return () => clearTimeout(id);
  }, [value, ms]);
  return debounced;
}

type LocationHit = { label: string; place: string };

// Shared Photon typeahead (same endpoint, params, debounce and .suggest-list markup Create's venue field used).
function LocationTypeahead({ value, onChange, onPick, placeholder, required }: {
  value: string;
  onChange: (value: string) => void;
  onPick?: (hit: LocationHit, typedValue: string) => void;
  placeholder?: string;
  required?: boolean;
}) {
  const [hits, setHits] = useState<LocationHit[]>([]);
  const pickedRef = useRef<string | null>(null);
  const debounced = useDebounced(value);
  useEffect(() => {
    const q = debounced.trim();
    if (q.length < 3 || pickedRef.current === debounced) {
      setHits([]);
      return;
    }
    const ctrl = new AbortController();
    const url = new URL("https://photon.komoot.io/api/");
    url.searchParams.set("q", q);
    url.searchParams.set("limit", "5");
    url.searchParams.set("lang", "en");
    url.searchParams.set("lat", "-36.88");
    url.searchParams.set("lon", "174.9");
    url.searchParams.set("bbox", "166,-47.5,179,-34");
    fetch(url, { signal: ctrl.signal })
      .then((r) => r.json())
      .then((body: { features?: { properties?: { name?: string; housenumber?: string; street?: string; district?: string; locality?: string; city?: string; state?: string } }[] }) => {
        const next = (body.features ?? []).map((f) => {
          const props = f.properties ?? {};
          const street = [props.housenumber, props.street].filter(Boolean).join(" ");
          const label = [props.name, street, props.district].filter(Boolean).join(", ");
          return { label, place: props.district || props.locality || props.name || "" };
        }).filter((hit) => hit.label);
        setHits(next.slice(0, 5));
      })
      .catch(() => setHits([]));
    return () => ctrl.abort();
  }, [debounced]);

  return (
    <>
      <input
        value={value}
        onChange={(e) => { pickedRef.current = null; onChange(e.target.value); }}
        onBlur={() => window.setTimeout(() => setHits([]), 150)}
        placeholder={placeholder}
        required={required}
        autoComplete="off"
      />
      {hits.length > 0 ? (
        <ul className="suggest-list">
          {hits.map((hit) => (
            <li key={hit.label}>
              <button
                type="button"
                onMouseDown={(e) => e.preventDefault()}
                onClick={() => { const typed = value; pickedRef.current = hit.label; onChange(hit.label); onPick?.(hit, typed); setHits([]); }}
              >
                {hit.label}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
    </>
  );
}

function CreateListingPanel({
  memberProfile,
  subscriptions,
  busy,
  onCreateListing,
  onOpenAccount,
  locationScopes,
}: {
  memberProfile: HostRecord | null;
  subscriptions: SubscriptionRecord[];
  busy: boolean;
  onCreateListing: (input: {
    title: string;
    description: string;
    date: string;
    time: string;
    location: string;
    placeName: string;
    locationScopeId: string | null;
    topics: string[];
    images: File[];
    poll?: { question: string; options: string[]; allowCustom: boolean } | null;
  }) => Promise<boolean | void>;
  onOpenAccount: () => void;
  locationScopes: LocationScopeRecord[];
}) {
  const approved = (TEMP_SUPPORT_OVERRIDE && Boolean(memberProfile)) || memberProfile?.status === "approved"; // TEMP_SUPPORT_OVERRIDE
  const paid = canPublish(memberProfile, subscriptions);
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("12:00");
  const [location, setLocation] = useState("");
  const [locationScopeId, setLocationScopeId] = useState("");
  const [placeQuery, setPlaceQuery] = useState("");
  const [topics, setTopics] = useState<string[]>([]);
  const [images, setImages] = useState<File[]>([]);
  const [status, setStatus] = useState("");
  const [isPoll, setIsPoll] = useState(false);
  const [pollQuestion, setPollQuestion] = useState("");
  const [pollOptions, setPollOptions] = useState<string[]>(["", ""]);
  const filledPollOptions = pollOptions.map((option) => option.trim()).filter(Boolean);
  const [pollAllowCustom, setPollAllowCustom] = useState(false);


  if (!memberProfile) {
    return (
      <div className="panel">
        <h3>Create your organisation</h3>
        <p className="panel-note">Set up your organisation page, then choose a subscription. Support approves the page before listings go public.</p>
        <button type="button" className="button button--primary" onClick={onOpenAccount}>Create your organisation</button>
      </div>
    );
  }
  if (!approved) {
    return (
      <div className="panel">
        <h3>Waiting for Support approval</h3>
        <p className="panel-note">Support approves your organisation first. You choose a monthly plan after that.</p>
        <button type="button" className="button button--primary" onClick={onOpenAccount}>{paid ? "Manage membership" : "Activate subscription"}</button>
      </div>
    );
  }

  if (!paid) {
    return (
      <div className="panel">
        <h3>Activate subscription</h3>
        <p className="panel-note">Your organisation is approved. An active subscription is required before listings or polls can be created.</p>
        <button type="button" className="button button--primary" onClick={onOpenAccount}>Activate subscription</button>
      </div>
    );
  }

  return (
    <form className="form-grid" onSubmit={(event) => {
      event.preventDefault();
      void (async () => {
        setStatus("");
        if (isPoll && !locationScopeId) { setStatus("Choose the poll location coverage from the known places list."); return; }
        const ok = await onCreateListing({ title, description, date, time, location: isPoll ? placeQuery.trim() : location, placeName: placeQuery.trim(), locationScopeId: locationScopeId || locationScopes.find((scope) => scope.scope_type === "place" && scope.name.toLowerCase() === placeQuery.trim().toLowerCase())?.id || null, topics, images, poll: isPoll ? { question: pollQuestion, options: filledPollOptions, allowCustom: pollAllowCustom } : null });
        if (ok) {
          setIsPoll(false);
          setPollQuestion("");
          setPollOptions(["", ""]);
          setPollAllowCustom(false);
          setTitle("");
          setDescription("");
          setDate("");
          setTime("12:00");
          setLocation("");
          setLocationScopeId("");
          setPlaceQuery("");
          setTopics([]);
          setImages([]);
          setStatus("Listing sent to Support for review.");
        } else {
          setStatus("Check title, description, date, time and location — then try again.");
        }
      })();
    }}>
      <div className="full create-kind" role="tablist" aria-label="What are you creating?">
        <button type="button" role="tab" aria-selected={!isPoll} className={isPoll ? "create-kind__pill" : "create-kind__pill is-on"} onClick={() => setIsPoll(false)}>Listing</button>
        <button type="button" role="tab" aria-selected={isPoll} className={isPoll ? "create-kind__pill is-on" : "create-kind__pill"} onClick={() => setIsPoll(true)}>Poll</button>
      </div>
      <label className="full">Title<input value={title} onChange={(e) => setTitle(e.target.value)} required /></label>
      <label className="full">Description<textarea value={description} onChange={(e) => setDescription(e.target.value)} required />{description.trim() ? null : <small>Add a short description so Support and locals understand it.</small>}</label>
      <p className="panel-note full">Listings are reviewed before they appear publicly.</p>
      {isPoll ? (
        <>
          <label className="full">Question<input value={pollQuestion} placeholder="What should the community choose?" onChange={(e) => setPollQuestion(e.target.value)} required /></label>
          <div className="full poll-create-options">
            <p className="panel-note">Add {POLL_MIN_OPTIONS} to {POLL_MAX_OPTIONS} answer options. The next answer field appears as you fill them in. <strong>{filledPollOptions.length}/{POLL_MAX_OPTIONS}</strong></p>
            {pollOptions.map((option, index) => (
              <div className="poll-create-option" key={index}>
                <input
                  value={option}
                  placeholder={`Answer ${index + 1}`}
                  aria-label={`Answer ${index + 1}`}
                  required={index < POLL_MIN_OPTIONS && filledPollOptions.length < POLL_MIN_OPTIONS}
                  onChange={(e) => setPollOptions(normalizePollOptions(pollOptions.map((item, i) => (i === index ? e.target.value : item))))}
                />
                {pollOptions.length > POLL_MIN_OPTIONS ? (
                  <button type="button" className="text-link" aria-label={`Remove answer ${index + 1}`} onClick={() => setPollOptions(normalizePollOptions(pollOptions.filter((_, i) => i !== index)))}>Remove</button>
                ) : null}
              </div>
            ))}
            <p className="panel-note">Add 2 to 10 answer options. The next answer field appears as people fill them in.</p>
            {filledPollOptions.length < POLL_MIN_OPTIONS ? <p className="panel-note">Add at least two answer options.</p> : null}
          </div>
          <label className="full"><span><input type="checkbox" checked={pollAllowCustom} onChange={(e) => setPollAllowCustom(e.target.checked)} /> Allow custom answer</span><small> People can write their own response, capped at 250 characters.</small></label>
        </>
      ) : null}
      {isPoll ? null : (
        <>
          <label>Date<input type="date" value={date} onChange={(e) => setDate(e.target.value)} required /></label>
          <label>Time<input type="time" value={time} onChange={(e) => setTime(e.target.value)} required /></label>
        </>
      )}
      {isPoll ? null : (<label className="full">Venue
        <LocationTypeahead
          value={location}
          onChange={setLocation}
          placeholder="Hall, park, clubrooms"
          required
          onPick={(hit, typedValue) => { const typed = typedValue.toLowerCase(); const match = locationScopes.filter((scope) => scope.scope_type === "place" && typed.includes(scope.name.toLowerCase())).sort((a, b) => b.name.length - a.name.length)[0]; if (match) { setPlaceQuery(match.name); setLocationScopeId(match.id); } }}
        />
      </label>)}
      <label className="full">{isPoll ? "Poll location coverage" : "Place"}
        <input
          value={placeQuery}
          onChange={(e) => {
            setPlaceQuery(e.target.value);
            setLocationScopeId("");
          }}
          placeholder={isPoll ? "Suburb, area, region or New Zealand" : "Start typing a place"}
          required
        />
        {isPoll ? <small>Only people browsing inside this area will see the poll. Choose a region (e.g. Auckland) to include all its suburbs, or New Zealand for everyone.{placeQuery.trim() && !locationScopeId ? " Pick a known place from the list." : ""}</small> : null}
        {placeQuery.trim().length > 0 && !locationScopeId ? (
          <ul className="suggest-list">
            {locationScopes
              .filter((scope) => (isPoll || scope.scope_type === "place") && scope.name.toLowerCase().includes(placeQuery.trim().toLowerCase()))
              .slice(0, 8)
              .map((scope) => (
                <li key={scope.id}>
                  <button type="button" onClick={() => { setLocationScopeId(scope.id); setPlaceQuery(scope.name); }}>
                    {scope.name}{isPoll ? <small> · {scope.scope_type === "place" ? "suburb / town" : scope.scope_type}</small> : null}
                  </button>
                </li>
              ))}
          </ul>
        ) : null}
      </label>
      <div className="full">
        <p className="panel-note">Topics</p>
        <div className="chip-row">
          {topicFilters.map((topic) => {
            const on = topics.includes(topic.slug);
            return (
              <button type="button" key={topic.slug} className={on ? "area-pill topic-on" : "area-pill"} onClick={() => {
                setTopics((current) => on ? current.filter((item) => item !== topic.slug) : [...current, topic.slug]);
              }}>{topic.label}</button>
            );
          })}
        </div>
      </div>
      <label className="full">Images
        <input type="file" accept="image/*" multiple onChange={(e) => setImages(Array.from(e.target.files ?? []))} />
        <span className="panel-note">First image is the listing card.</span>
      </label>
      <button className="button button--primary" disabled={busy} aria-busy={busy}>{busy ? "Publishing…" : "Submit"}</button>
      {status ? <p className="panel-note full">{status}</p> : null}
    </form>
  );
}

function AccountHub({
  session,
  profile,
  memberProfile,
  subscriptions,
  savedEvents,
  notifications,
  notices,
  busy,
  initialSection = null,
  onLogout,
  onSave,
  onMarkNotificationRead,
  onSubmitMemberApplication,
  onUploadMemberImage,
  onCreateListing,
  onCreateNotice,
  onEditOrgCard,
  onRequestDelete,
}: {
  onEditOrgCard?: () => void;
  onRequestDelete?: () => void;
  session: AuthSession;
  profile: UserProfile | null;
  memberProfile: HostRecord | null;
  subscriptions: SubscriptionRecord[];
  savedEvents: EventRecord[];
  notifications: UserNotification[];
  notices: MemberNoticeRecord[];
  busy: boolean;
  onLogout: () => void;
  onSave: (profile: UserProfile) => void;
  onMarkNotificationRead: (notificationID: string) => void;
  onSubmitMemberApplication: (draft: MemberDraft) => Promise<boolean>;
  onUploadMemberImage: (file: File, kind: "avatar" | "hero" | "notice") => Promise<string>;
  onCreateListing: (form: HTMLFormElement) => void;
  onCreateNotice: (draft: NoticeDraft) => Promise<boolean>;
  initialSection?: AccountHubSection;
}) {
  const [activeSection, setActiveSection] = useState<AccountHubSection>(initialSection);
  const unreadCount = notifications.filter((notification) => !notification.read_at).length;
  const membershipLabel = memberProfile
    ? memberProfile.status === "approved"
      ? "Manage membership"
      : memberProfile.status === "pending_review"
        ? "Membership pending"
        : "Membership needs review"
    : "Apply for membership";

  function toggleSection(section: Exclude<AccountHubSection, null>) {
    setActiveSection((current) => current === section ? null : section);
  }

  return (
    <div className="account-hub">
      <div className="panel account-summary">
        <div>
          <p className="eyebrow">Signed in</p>
          <h3>{session.user.email}</h3>
          <p className="panel-note">Your account lets you save listings, follow hosts and choose your area. Extra profile and membership details are optional.</p>
        </div>
        <div className="account-summary__actions">
          {onEditOrgCard ? <button type="button" className="button button--primary" onClick={onEditOrgCard}>Manage my organisation</button> : null}
          <button type="button" className="button button--secondary" onClick={onLogout}>Sign out</button>
          {onRequestDelete ? <button type="button" className="text-link" onClick={onRequestDelete}>Request account deletion</button> : null}
        </div>
      </div>

      <div className="action-card-grid" aria-label="Account actions">
        <button type="button" className={activeSection === "saved" ? "action-card action-card--active" : "action-card"} onClick={() => toggleSection("saved")}>
          <strong>Saved listings</strong>
          <span>{savedEvents.length ? `${savedEvents.length} saved, interested or going` : "Events you save will live here."}</span>
        </button>
        <button type="button" className={activeSection === "notifications" ? "action-card action-card--active" : "action-card"} onClick={() => toggleSection("notifications")}>
          <strong>Notifications</strong>
          <span>{unreadCount ? `${unreadCount} unread update${unreadCount === 1 ? "" : "s"}` : "Membership and Support updates."}</span>
        </button>
        <button type="button" className={activeSection === "membership" ? "action-card action-card--active" : "action-card"} onClick={() => toggleSection("membership")}>
          <strong>{membershipLabel}</strong>
          <span>Only open this if you want to publish listings, polls or Notices.</span>
        </button>
        <button type="button" className={activeSection === "account" ? "action-card action-card--active" : "action-card"} onClick={() => toggleSection("account")}>
          <strong>Account details</strong>
          <span>Optional name, phone and public profile settings.</span>
        </button>
      </div>

      {activeSection === "saved" ? <SavedEventsPanel events={savedEvents} /> : null}
      {activeSection === "notifications" ? <NotificationsPanel notifications={notifications} busy={busy} onMarkRead={onMarkNotificationRead} /> : null}
      {activeSection === "account" ? <AccountPanel session={session} profile={profile} busy={busy} onLogout={onLogout} onSave={onSave} /> : null}
      {activeSection === "membership" ? (
        <MemberPanel
              onManageOrg={onEditOrgCard}
          key={memberProfile?.id ?? `new-${session.user.id}`}
          session={session}
          profile={memberProfile}
          subscriptions={subscriptions}
          notices={notices}
          busy={busy}
          onSubmit={onSubmitMemberApplication}
          onUploadImage={onUploadMemberImage}
          onCreateListing={onCreateListing}
          onCreateNotice={onCreateNotice}
        />
      ) : null}
    </div>
  );
}

function AccountPanel({ session, profile, busy, onLogout, onSave }: {
  session: AuthSession;
  profile: UserProfile | null;
  busy: boolean;
  onLogout: () => void;
  onSave: (profile: UserProfile) => void;
}) {
  return (
    <form className="panel" onSubmit={(event) => {
      event.preventDefault();
      const data = new FormData(event.currentTarget);
      onSave({
        user_id: session.user.id,
        display_name: String(data.get("display_name") ?? ""),
        public_role: String(data.get("public_role") ?? ""),
        organisation_name: String(data.get("organisation_name") ?? ""),
        phone: String(data.get("phone") ?? ""),
        website: String(data.get("website") ?? ""),
        preferred_contact_email: String(data.get("preferred_contact_email") ?? session.user.email ?? ""),
        avatar_image_url: profile?.avatar_image_url ?? "",
        contact_visibility: String(data.get("contact_visibility") ?? "name_and_email") as UserProfile["contact_visibility"],
      });
    }}>
      <h3>Account settings</h3>
      <p className="panel-note">{session.user.email}</p>
      <label>Name<input name="display_name" defaultValue={profile?.display_name ?? ""} /></label>
      <label>Role<input name="public_role" defaultValue={profile?.public_role ?? ""} /></label>
      <label>Organisation<input name="organisation_name" defaultValue={profile?.organisation_name ?? ""} /></label>
      <label>Phone<input name="phone" defaultValue={profile?.phone ?? ""} /></label>
      <label>Website<input name="website" defaultValue={profile?.website ?? ""} /></label>
      <label>Preferred email<input name="preferred_contact_email" defaultValue={profile?.preferred_contact_email ?? session.user.email ?? ""} /></label>
      <label>Contact visibility<select name="contact_visibility" defaultValue={profile?.contact_visibility ?? "name_and_email"}>
        <option value="anonymous">Anonymous</option>
        <option value="name_and_email">Name and email</option>
        <option value="public_profile">Public profile</option>
      </select></label>
      <div className="action-row">
        <button className="button button--primary" disabled={busy}>Save</button>
        <button type="button" className="button button--secondary" onClick={onLogout}>Sign out</button>
      </div>
    </form>
  );
}

function SavedEventsPanel({ events }: { events: EventRecord[] }) {
  return (
    <div className="panel">
      <h3>Saved events</h3>
      {events.length === 0 ? <p className="panel-note">Saved, interested and going listings will live here.</p> : events.map((event) => (
        <p className="list-line" key={event.id}><strong>{event.title}</strong><span>{formatDate(event.start_at)}</span></p>
      ))}
    </div>
  );
}

function NotificationsPanel({ notifications, busy, onMarkRead }: {
  notifications: UserNotification[];
  busy: boolean;
  onMarkRead: (notificationID: string) => void;
}) {
  const unreadCount = notifications.filter((notification) => !notification.read_at).length;
  return (
    <div className="panel">
      <h3>Notifications</h3>
      <p className="panel-note">{unreadCount ? `${unreadCount} unread update${unreadCount === 1 ? "" : "s"}.` : "Membership and Support decisions will appear here."}</p>
      {notifications.length === 0 ? <p className="panel-note">No notifications yet.</p> : (
        <div className="notification-list">
          {notifications.map((notification) => (
            <div className={notification.read_at ? "notification-row" : "notification-row notification-row--unread"} key={notification.id}>
              <strong>{notification.title}</strong>
              <p>{notification.body}</p>
              <span>{formatDate(notification.created_at)}</span>
              {!notification.read_at ? (
                <button className="chip" disabled={busy} onClick={() => onMarkRead(notification.id)}>Mark read</button>
              ) : null}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function MemberPanel({ session, profile, subscriptions, notices, busy, onSubmit, onUploadImage, onCreateListing, onCreateNotice, onManageOrg }: {
  onManageOrg?: () => void;
  session: AuthSession;
  profile: HostRecord | null;
  subscriptions: SubscriptionRecord[];
  notices: MemberNoticeRecord[];
  busy: boolean;
  onSubmit: (draft: MemberDraft) => Promise<boolean>;
  onUploadImage: (file: File, kind: "avatar" | "hero" | "notice") => Promise<string>;
  onCreateListing: (form: HTMLFormElement) => void;
  onCreateNotice: (draft: NoticeDraft) => Promise<boolean>;
}) {
  const [draft, setDraft] = useState<MemberDraft>(() => memberDraftFromProfile(profile, session.user.email));
  const [editing, setEditing] = useState(!profile);
  const [uploading, setUploading] = useState<"avatar" | "hero" | null>(null);
  const [formError, setFormError] = useState("");
  const approvedAndPaid = canPublish(profile, subscriptions);
  const hasMembership = Boolean(profile);
  const isApproved = profile?.status === "approved";
  const isPending = profile?.status === "pending_review";
  const canEditMembership = !profile || isApproved;
  const heading = hasMembership ? "Manage membership and page" : "Apply for membership";

  function updateDraft<K extends keyof MemberDraft>(key: K, value: MemberDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  async function handleImageUpload(file: File | undefined, kind: "avatar" | "hero") {
    if (!file) return;
    setUploading(kind);
    try {
      const url = await onUploadImage(file, kind);
      updateDraft(kind === "avatar" ? "avatar_image_url" : "hero_image_url", url);
    } finally {
      setUploading(null);
    }
  }

  async function handleSubmit() {
    setFormError("");
    if (!draft.business_name.trim()) {
      setFormError("Add the member name before submitting.");
      document.querySelector<HTMLInputElement>("[aria-label='Member page name']")?.focus();
      return;
    }
    const submitted = await onSubmit(draft);
    if (submitted) {
      setEditing(false);
      window.setTimeout(() => {
        document.getElementById("account")?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 120);
    }
  }

  return (
    <div className="panel panel--wide">
      <h3>{heading}</h3>
      <p className="panel-note">Only approved members can list in our community. Start with a free account, choose the plan that fits, then submit your membership details for Support approval.</p>
      {profile ? <p className="status-pill">Status: {({ approved: "Approved", pending_review: "Pending review", pending: "Pending review", rejected: "Needs changes", suspended: "Suspended" } as Record<string, string>)[profile.status] ?? profile.status.replaceAll("_", " ")}</p> : null}
      {profile ? <SubscriptionEndLine subscriptions={subscriptions} /> : null}
      {profile ? <CancelPlanControl subscriptions={subscriptions} session={session} profileId={profile.id} /> : null}
      {isPending ? (
        <div className="status-card">
          <strong>Membership submitted</strong>
          <p>You will get a notification when a decision is made. Support can now check your details and approve, request changes or decline the application.</p>
        </div>
      ) : null}
      {profile?.status === "rejected" ? (
        <div className="status-card status-card--warn">
          <strong>Membership needs changes</strong>
          <p>{profile.rejection_reason ?? "Support needs more information before this membership can be approved."}</p>
        </div>
      ) : null}
      {formError ? (
        <div className="status-card status-card--warn">
          <strong>Check the form</strong>
          <p>{formError}</p>
        </div>
      ) : null}

      {profile && onManageOrg ? (
        <div className="status-card">
          <strong>Your organisation is managed in one place</strong>
          <p>Edit your public card, photos, contact details and subscription status from Manage my organisation.</p>
          <button type="button" className="button button--primary" onClick={onManageOrg}>Manage my organisation</button>
        </div>
      ) : (
      <>
      <MembershipPlanSection selectedPlan={draft.selected_plan_id} onSelect={(plan) => updateDraft("selected_plan_id", plan as MemberDraft["selected_plan_id"])} disabled={!editing} approvedAndPaid={approvedAndPaid} />

      <section className="member-page-editor">
        <div
          className="member-hero-preview"
          style={draft.hero_image_url ? {
            backgroundImage: `url(${draft.hero_image_url})`,
            backgroundPosition: objectPosition(draft.hero_image_position_x, draft.hero_image_position_y),
          } : undefined}
        >
          <div className="member-hero-shade" />
          <div
            className="member-avatar-preview"
            style={draft.avatar_image_url ? {
              backgroundImage: `url(${draft.avatar_image_url})`,
              backgroundPosition: objectPosition(draft.avatar_image_position_x, draft.avatar_image_position_y),
            } : undefined}
          >
            {!draft.avatar_image_url ? draft.business_name.slice(0, 1) || "+" : null}
          </div>
          <div className="member-hero-copy">
            <p className="eyebrow">{areaLabel(draft.area_scope_id)}</p>
            <input
              aria-label="Member page name"
              className="live-title-input"
              disabled={!editing}
              onChange={(event) => updateDraft("business_name", event.target.value)}
              placeholder="Member name"
              required
              value={draft.business_name}
            />
            <textarea
              aria-label="Member page bio"
              className="live-bio-input"
              disabled={!editing}
              onChange={(event) => updateDraft("about", event.target.value)}
              placeholder="Tell locals what you host, offer or support."
              value={draft.about}
            />
          </div>
        </div>

        {editing ? (
          <div className="image-tools">
            <label>Hero photo<input accept="image/jpeg,image/png,image/webp" type="file" onChange={(event) => void handleImageUpload(event.target.files?.[0], "hero")} /></label>
            <label>Profile photo<input accept="image/jpeg,image/png,image/webp" type="file" onChange={(event) => void handleImageUpload(event.target.files?.[0], "avatar")} /></label>
            <label>Hero left/right<input type="range" min="0" max="100" value={draft.hero_image_position_x} onChange={(event) => updateDraft("hero_image_position_x", Number(event.target.value))} /></label>
            <label>Hero up/down<input type="range" min="0" max="100" value={draft.hero_image_position_y} onChange={(event) => updateDraft("hero_image_position_y", Number(event.target.value))} /></label>
            <label>Profile left/right<input type="range" min="0" max="100" value={draft.avatar_image_position_x} onChange={(event) => updateDraft("avatar_image_position_x", Number(event.target.value))} /></label>
            <label>Profile up/down<input type="range" min="0" max="100" value={draft.avatar_image_position_y} onChange={(event) => updateDraft("avatar_image_position_y", Number(event.target.value))} /></label>
            {uploading ? <p className="panel-note">Uploading {uploading} photo...</p> : null}
          </div>
        ) : null}

        <form className="form-grid" onSubmit={(event) => { event.preventDefault(); void handleSubmit(); }}>
          <label>Contact name<input disabled={!editing} value={draft.contact_name} onChange={(event) => updateDraft("contact_name", event.target.value)} /></label>
          <label>Contact email<input disabled={!editing} type="email" value={draft.contact_email} onChange={(event) => updateDraft("contact_email", event.target.value)} required /></label>
          <label>Phone<input disabled={!editing} value={draft.phone} onChange={(event) => updateDraft("phone", event.target.value)} /></label>
          <label>Website<input disabled={!editing} type="url" value={draft.website} onChange={(event) => updateDraft("website", event.target.value)} placeholder="https://www.example.co.nz" /></label>
          <label>Area<select disabled={!editing} value={draft.area_scope_id} onChange={(event) => updateDraft("area_scope_id", event.target.value)}>
            <option value="pohutukawa-coast">Pohutukawa Coast</option>
            <option value="franklin">Franklin</option>
            <option value="east-auckland">East Auckland</option>
          </select></label>
          <label>Selected plan<select disabled={!editing} value={draft.selected_plan_id} onChange={(event) => updateDraft("selected_plan_id", event.target.value)}>
            <option value="local_business">Local Member</option>
            <option value="growth">Growth Member</option>
            <option value="sponsor">Community Partner</option>
          </select></label>
          <div className="action-row full">
            {profile && !editing && canEditMembership ? <button type="button" className="button button--secondary" onClick={() => setEditing(true)}>Edit page</button> : null}
            {editing ? <button className="button button--primary" disabled={busy || Boolean(uploading)}>{hasMembership ? (isApproved ? "Save membership page" : "Submit for Support review") : "Submit membership application"}</button> : null}
          </div>
        </form>
      </section>
      </>
      )}

            <NoticeComposer
        notices={notices}
        busy={busy}
        canPublish={approvedAndPaid}
        onUploadImage={onUploadImage}
        onCreateNotice={onCreateNotice}
      />

    </div>
  );
}

function NoticeComposer({ notices, busy, canPublish, onUploadImage, onCreateNotice }: {
  notices: MemberNoticeRecord[];
  busy: boolean;
  canPublish: boolean;
  onUploadImage: (file: File, kind: "notice") => Promise<string>;
  onCreateNotice: (draft: NoticeDraft) => Promise<boolean>;
}) {
  const [draft, setDraft] = useState<NoticeDraft>(emptyNoticeDraft);
  const [uploading, setUploading] = useState(false);

  function updateDraft<K extends keyof NoticeDraft>(key: K, value: NoticeDraft[K]) {
    setDraft((current) => ({ ...current, [key]: value }));
  }

  async function handleImageUpload(file: File | undefined) {
    if (!file) return;
    setUploading(true);
    try {
      const url = await onUploadImage(file, "notice");
      updateDraft("hero_image_url", url);
    } finally {
      setUploading(false);
    }
  }

  async function handleSubmit(status: NoticeDraft["status"]) {
    const submitted = await onCreateNotice({ ...draft, status });
    if (submitted) {
      setDraft(emptyNoticeDraft());
    }
  }

  return (
    <section className="notice-composer">
      <div className="section-mini-header">
        <p className="eyebrow">Notices</p>
        <h3>Weekly letters and member updates</h3>
        <p className="panel-note">Choose a fixed template, add words and photos, then publish to people who Belong to your page. This keeps it clean for members and safer for review.</p>
      </div>

      <div className="template-grid" role="radiogroup" aria-label="Notice template">
        {([
          ["weekly_letter", "Weekly Letter", "Best for schools, clubs and regular community updates."],
          ["photo_update", "Photo Update", "Best for a strong image, caption and short story."],
          ["notice_board", "Notice Board", "Best for short notices with dates, places and action."],
        ] as const).map(([value, title, text]) => (
          <button
            type="button"
            className={draft.template_style === value ? "template-card template-card--active" : "template-card"}
            key={value}
            onClick={() => updateDraft("template_style", value)}
          >
            <strong>{title}</strong>
            <span>{text}</span>
          </button>
        ))}
      </div>

      <div className={`notice-preview notice-preview--${draft.template_style}`}>
        {draft.hero_image_url ? <img alt="" src={draft.hero_image_url} /> : <div className="notice-preview__placeholder">Add a photo</div>}
        <div>
          <p className="eyebrow">{draft.template_style.replaceAll("_", " ")}</p>
          <h3>{draft.title || "Notice title"}</h3>
          <p>{draft.summary || "Short summary for followers."}</p>
        </div>
      </div>

      <div className="form-grid">
        <label>Photo<input accept="image/jpeg,image/png,image/webp" type="file" onChange={(event) => void handleImageUpload(event.target.files?.[0])} /></label>
        <label>Title<input value={draft.title} onChange={(event) => updateDraft("title", event.target.value)} placeholder="Weekly update, term notice, community update..." required /></label>
        <label className="full">Summary<textarea value={draft.summary} onChange={(event) => updateDraft("summary", event.target.value)} placeholder="A short version for notifications and lists." /></label>
        <label className="full">Notice body<textarea value={draft.body} onChange={(event) => updateDraft("body", event.target.value)} placeholder="Write the full weekly letter or notice here." /></label>
      </div>

      {uploading ? <p className="panel-note">Uploading Notice photo...</p> : null}

      <div className="action-row">
        <button className="button button--secondary" disabled={busy || uploading || !draft.title.trim()} onClick={() => void handleSubmit("draft")}>Save draft</button>
        <button className="button button--primary" disabled={busy || uploading || !canPublish || !draft.title.trim()} onClick={() => void handleSubmit("published")}>Publish Notice</button>
      </div>
      {!canPublish ? <p className="panel-note">Publishing unlocks after Support approval and active membership subscription. Drafts can be prepared first.</p> : null}

      <div className="notice-list">
        <h4>Latest Notices</h4>
        {notices.length === 0 ? <p className="panel-note">No Notices yet.</p> : notices.map((notice) => (
          <p className="list-line" key={notice.id}>
            <strong>{notice.title}</strong>
            <span>{notice.status} · {formatDate(notice.created_at)}</span>
          </p>
        ))}
      </div>
    </section>
  );
}

type PollCountRow = { option_text: string; response_count: number };

function PollVoteCard({ event, session, isOwner, onSignIn, compact = false }: {
  event: EventRecord;
  session: AuthSession | null;
  isOwner: boolean;
  onSignIn: () => void;
  compact?: boolean;
}) {
  const options = event.poll_options ?? [];
  const [mine, setMine] = useState<{ selected_option: string | null; custom_answer: string | null } | null>(null);
  const [counts, setCounts] = useState<PollCountRow[] | null>(null);
  const [custom, setCustom] = useState("");
  const [showOther, setShowOther] = useState(false);
  const [working, setWorking] = useState(false);
  const [workingOption, setWorkingOption] = useState<string | null>(null);
  const [error, setError] = useState("");
  const [otherAnswers, setOtherAnswers] = useState<{ id: string; custom_answer: string; created_at: string }[]>([]);
  // No poll close column exists on events (probed: poll_closes_at/poll_closed/closes_at absent), so a poll is
  // treated as closed once the listing is no longer live (archived / rejected / removed).
  const pollEndsAt = (event as { end_at?: string | null }).end_at ? new Date(String((event as { end_at?: string | null }).end_at)) : null;
  const pollEndValid = Boolean(pollEndsAt && !Number.isNaN(pollEndsAt.getTime()));
  const [nowMs, setNowMs] = useState(() => Date.now());
  useEffect(() => {
    if (!pollEndValid) return;
    const timer = window.setInterval(() => setNowMs(Date.now()), 30000);
    return () => window.clearInterval(timer);
  }, [pollEndValid]);
  const pollClosed = ["archived", "rejected", "removed", "closed"].includes(String(event.status ?? ""))
    || pollEnded(event as { listing_kind?: string | null; end_at?: string | null }, nowMs);
  const inFlight = useRef(false);

  async function loadCounts() {
    if (isOwner && session && event.poll_allows_custom_answer) {
      void rpc<{ id: string; custom_answer: string; created_at: string }[]>("poll_custom_responses_for_event", { p_event_id: event.id }, session.access_token)
        .then((rows) => setOtherAnswers(rows ?? []))
        .catch(() => setOtherAnswers([]));
    }
    try {
      const rows = isOwner && session
        ? await rpc<PollCountRow[]>("poll_owner_response_counts_for_event", { p_event_id: event.id }, session.access_token)
        : await rpc<PollCountRow[]>("poll_response_counts_for_event", { p_event_id: event.id });
      setCounts(rows ?? []);
    } catch {
      setCounts(null);
    }
  }

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (session) {
        try {
          const rows = await rest<{ selected_option: string | null; custom_answer: string | null }[]>(
            `event_poll_responses?select=selected_option,custom_answer,updated_at&event_id=eq.${event.id}&respondent_id=eq.${session.user.id}&order=updated_at.desc.nullslast&limit=1`,
            {},
            session.access_token,
          );
          if (!cancelled) setMine(rows[0] ?? null);
        } catch {
          if (!cancelled) setMine(null);
        }
      }
      if (isOwner || pollClosed) await loadCounts();
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [event.id, session?.user.id, isOwner]);

  useEffect(() => {
    if (mine && !isOwner) void loadCounts();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mine]);

  // Live results: refresh counts every 10s while the poll is open, results are visible and the tab is visible.
  useEffect(() => {
    if (pollClosed || !(mine || isOwner)) return;
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") void loadCounts();
    }, 10000);
    return () => window.clearInterval(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pollClosed, Boolean(mine), isOwner, event.id]);

  async function answer(selected: string | null, customAnswer: string | null) {
    if (!session || pollClosed || inFlight.current) return;
    inFlight.current = true;
    setWorking(true);
    setWorkingOption(selected ?? "__other__");
    setError("");
    const body = {
      event_id: event.id,
      respondent_id: session.user.id,
      selected_option: selected?.trim() || null,
      custom_answer: customAnswer?.trim().slice(0, 250) || null,
    };
    try {
      // fb1: clear this user's earlier row(s) first so a changed vote (option or Other) replaces, never adds.
      await rest<void>(`event_poll_responses?event_id=eq.${event.id}&respondent_id=eq.${session.user.id}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }, session.access_token);
      await rest<void>("event_poll_responses?on_conflict=event_id,respondent_id", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "resolution=merge-duplicates,return=minimal" },
        body: JSON.stringify(body),
      }, session.access_token);
      setMine({ selected_option: body.selected_option, custom_answer: body.custom_answer });
      recordEventAnalytics(event.id, "poll_answer", compact ? "poll_card" : "event_detail", session.access_token);
      setShowOther(false);
      setCustom("");
      // Non-owners refresh via the [mine] effect; only owners need an explicit refresh here.
      if (isOwner) void loadCounts();
    } catch (err) {
      setError(messageFromError(err));
    } finally {
      inFlight.current = false;
      setWorking(false);
      setWorkingOption(null);
    }
  }

  async function withdraw() {
    if (!session || pollClosed || inFlight.current) return;
    inFlight.current = true;
    setWorking(true);
    setError("");
    try {
      // fb3: remove every row this user has for the poll (old duplicates included), then confirm none remain.
      await rest<void>(`event_poll_responses?event_id=eq.${event.id}&respondent_id=eq.${session.user.id}`, { method: "DELETE", headers: { Prefer: "return=minimal" } }, session.access_token);
      const left = await rest<{ selected_option: string | null }[]>(`event_poll_responses?select=selected_option&event_id=eq.${event.id}&respondent_id=eq.${session.user.id}`, {}, session.access_token).catch(() => []);
      if (left && left.length) throw new Error(`${left.length} earlier answer${left.length === 1 ? "" : "s"} couldn't be removed (the database refused the delete). Ask Support to clear it.`);
      setMine(null);
      if (!isOwner) setCounts(null); else await loadCounts();
    } catch (err) {
      setError(messageFromError(err));
    } finally {
      inFlight.current = false;
      setWorking(false);
    }
  }

  const total = (counts ?? []).reduce((sum, row) => sum + row.response_count, 0);
  const countFor = (option: string) => (counts ?? []).find((row) => row.option_text === option)?.response_count ?? 0;
  const showResults = Boolean(counts && (mine || isOwner || pollClosed));

  const otherChosen = Boolean(mine && !mine.selected_option && mine.custom_answer);
  const statusText = error
    ? error
    : pollClosed
      ? (mine ? `Voting closed. Your answer: ${mine.selected_option ?? mine.custom_answer}.` : "Voting closed.")
      : mine
        ? `Your answer: ${mine.selected_option ?? mine.custom_answer}.`
        : showResults
          ? (total === 0 ? "Be the first to answer." : `${total} response${total === 1 ? "" : "s"} so far.`)
          : "Have your say.";
  const row = (key: string, label: string, chosen: boolean, n: number, onTap: () => void, subtitle?: string) => {
    const pct = total ? Math.round((n / total) * 100) : 0;
    return (
      <button
        key={key}
        type="button"
        className={`poll-row${chosen ? " is-selected" : ""}${workingOption === key ? " is-busy" : ""}`}
        aria-pressed={chosen}
        aria-busy={workingOption === key}
        disabled={working || pollClosed}
        onClick={(e) => { e.stopPropagation(); if (!session) { onSignIn(); return; } onTap(); }}
      >
        <span className="poll-row__top">
          <span className="poll-row__radio" aria-hidden="true">{chosen ? "✓" : ""}</span>
          <span className="poll-row__text">
            <span className="poll-row__label">{label}</span>
            {subtitle ? <span className="poll-row__sub">{subtitle}</span> : null}
          </span>
          {showResults ? <span className="poll-row__count">{n} · {pct}%</span> : null}
        </span>
        {showResults && total > 0 ? <span className="poll-row__track"><span className="poll-row__fill" style={{ width: `${pct}%` }} /></span> : null}
      </button>
    );
  };

  return (
    <div className={`poll-panel${compact ? " poll-panel--compact" : ""}`}>
      <p className="poll-panel__q">{event.poll_question}</p>
      <div className="poll-panel__options">
        {options.map((option) => row(option, option, mine?.selected_option === option, countFor(option), () => {
          // iOS: tapping your current answer withdraws it.
          if (mine?.selected_option === option) void withdraw(); else void answer(option, null);
        }))}
        {event.poll_allows_custom_answer ? row("__other__", "Other", otherChosen, countFor("Other"), () => { setCustom(mine?.custom_answer ?? ""); setShowOther(true); }, otherChosen ? "Edit your answer" : "Type your own answer") : null}
        {event.poll_allows_custom_answer && showOther && session && !pollClosed ? (
          <form className="poll-other" onClick={(e) => e.stopPropagation()} onSubmit={(e) => { e.preventDefault(); if (custom.trim()) void answer(null, custom); else if (otherChosen) void withdraw(); }}>
            <textarea value={custom} maxLength={250} rows={2} placeholder="Your answer" aria-label="Your answer" onChange={(e) => setCustom(e.target.value)} />
            <div className="poll-other__bar">
              <small>{custom.length}/250</small>
              <button type="submit" className="poll-other__save" disabled={working || (!custom.trim() && !otherChosen)}>✓ Save</button>
            </div>
          </form>
        ) : null}
      </div>
      <p className={`poll-panel__status${error ? " is-error" : ""}`} role="status">{working ? "Saving… " : ""}{statusText}</p>
      {!compact ? (pollClosed ? <p className="listing-detail__poll-note"><strong>Poll closed</strong> · final results</p> : pollEndValid && pollEndsAt ? (
        <p className="listing-detail__poll-note">Poll closes {pollEndsAt.toLocaleString("en-NZ", { day: "numeric", month: "short", hour: "numeric", minute: "2-digit" })}</p>
      ) : null) : null}
      {isOwner && !compact && !otherAnswers.length ? <p className="listing-detail__poll-note">No custom answers have been submitted.</p> : null}
      {isOwner && otherAnswers.length ? (
        <div className="listing-detail__poll-note">
          <strong>Custom answers ({otherAnswers.length})</strong>
          <small> Option totals are anonymous. Custom answers stay private to you and Support.</small>
          <ul>
            {otherAnswers.map((item) => <li key={item.id}>{item.custom_answer}</li>)}
          </ul>
        </div>
      ) : null}
      {isOwner && showResults ? <p className="listing-detail__poll-note">Owner view · {total} {total === 1 ? "response" : "responses"}</p> : null}
      {!session ? (
        <p className="listing-detail__poll-note"><button type="button" className="text-link" onClick={(e) => { e.stopPropagation(); onSignIn(); }}>Sign in</button> to answer this poll.</p>
      ) : mine && !pollClosed ? (
        <button type="button" className="text-link" disabled={working} onClick={(e) => { e.stopPropagation(); void withdraw(); }}>Withdraw my answer</button>
      ) : null}
    </div>
  );
}

function icsStamp(value: Date) {
  return value.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function icsEscape(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

function downloadEventIcs(event: EventRecord) {
  const start = new Date(event.start_at);
  if (Number.isNaN(start.getTime())) return;
  const rawEnd = (event as { end_at?: string | null }).end_at;
  const endDate = rawEnd ? new Date(rawEnd) : new Date(start.getTime() + 2 * 60 * 60 * 1000);
  const end = Number.isNaN(endDate.getTime()) || endDate <= start ? new Date(start.getTime() + 2 * 60 * 60 * 1000) : endDate;
  const where = [event.venue, event.location_display_name ?? event.town].filter(Boolean).join(", ");
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Coast Calendar//Web//EN",
    "BEGIN:VEVENT",
    `UID:${event.id}@coastcalendar`,
    `DTSTAMP:${icsStamp(new Date())}`,
    `DTSTART:${icsStamp(start)}`,
    `DTEND:${icsStamp(end)}`,
    `SUMMARY:${icsEscape(event.title || "Coast Calendar listing")}`,
    where ? `LOCATION:${icsEscape(where)}` : "",
    `DESCRIPTION:${icsEscape((event.short_description || event.long_description || "").slice(0, 900))}`,
    "BEGIN:VALARM",
    "TRIGGER:-PT1H",
    "ACTION:DISPLAY",
    "DESCRIPTION:Reminder",
    "END:VALARM",
    "END:VEVENT",
    "END:VCALENDAR",
  ].filter(Boolean);
  const body = lines.join("\r\n") + "\r\n";
  const filename = `${(event.title || "listing").replace(/[^a-z0-9]+/gi, "-").replace(/^-|-$/g, "").slice(0, 40) || "listing"}.ics`;
  // iOS Safari ignores the download attribute on blob links; a text/calendar data: URL opens the
  // "Add to Calendar" sheet there. Android Chrome and desktop get a normal .ics file download.
  const ua = typeof navigator !== "undefined" ? navigator.userAgent : "";
  const isIOS = /iPad|iPhone|iPod/.test(ua) || (ua.includes("Macintosh") && typeof document !== "undefined" && "ontouchend" in document);
  if (isIOS) {
    window.location.href = `data:text/calendar;charset=utf-8,${encodeURIComponent(body)}`;
    return;
  }
  const blob = new Blob([body], { type: "text/calendar;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  link.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const eventReportCategories: { id: string; label: string }[] = [
  { id: "wrong_or_outdated", label: "Wrong or outdated" },
  { id: "spam_or_scam", label: "Spam or scam" },
  { id: "unsafe_or_harmful", label: "Unsafe or harmful" },
  { id: "inappropriate_content", label: "Inappropriate content" },
  { id: "wrong_location", label: "Wrong location" },
  { id: "other", label: "Other" },
];

function ReportListing({ eventId, session, onSignIn }: { eventId: string; session: AuthSession | null; onSignIn: () => void }) {
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState("wrong_or_outdated");
  const [details, setDetails] = useState("");
  const [state, setState] = useState<"" | "sending" | "sent" | string>("");
  if (!session) {
    return <p className="panel-note"><strong>Something not right?</strong> <button type="button" className="text-link" onClick={onSignIn}>Sign in to send a private report</button></p>;
  }
  if (state === "sent") return <p className="panel-note">Thanks. Support will review this listing.</p>;
  if (!open) return <p className="panel-note"><strong>Something not right?</strong> <button type="button" className="text-link" onClick={() => setOpen(true)}>Report this listing</button></p>;
  return (
    <form
      className="panel"
      onSubmit={(e) => {
        e.preventDefault();
        setState("sending");
        const label = eventReportCategories.find((item) => item.id === category)?.label ?? category;
        const send = TEMP_BRIDGES.report_via_support
          // TEMP_BRIDGE: report_via_support — remove this branch once submit_event_report exists.
          ? rpc<string>("submit_support_request", {
            p_topic: "Listing report",
            p_message: `Category: ${label} (${category})${details.trim() ? `\n\nDetails: ${details.trim()}` : ""}`,
            p_listing_reference: eventId,
          }, session.access_token)
          : rpc<string>("submit_event_report", { p_event_id: eventId, p_category: category, p_details: details.trim() || null }, session.access_token);
        void send
          .then(() => setState("sent"))
          .catch((error: unknown) => setState(`Not sent: ${messageFromError(error)}`));
      }}
    >
      <label>Reason
        <select value={category} onChange={(e) => setCategory(e.target.value)}>
          {eventReportCategories.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
        </select>
      </label>
      <label>Details (optional)
        <textarea value={details} maxLength={1000} onChange={(e) => setDetails(e.target.value)} />
      </label>
      <div className="action-row">
        <button type="submit" className="button button--primary" disabled={state === "sending"}>{state === "sending" ? "Sending…" : "Send report"}</button>
        <button type="button" className="text-link" onClick={() => setOpen(false)}>Cancel</button>
      </div>
      {state && state !== "sending" ? <p className="panel-note">{state}</p> : null}
    </form>
  );
}

// TEMP_BRIDGE: report_via_support — same send path as ReportListing; switches with TEMP_BRIDGES.
async function sendListingReport(eventId: string, category: string, details: string, token: string) {
  const label = eventReportCategories.find((item) => item.id === category)?.label ?? category;
  return TEMP_BRIDGES.report_via_support
    ? rpc<string>("submit_support_request", {
      p_topic: "Listing report",
      p_message: `Category: ${label} (${category})${details.trim() ? `\n\nDetails: ${details.trim()}` : ""}`,
      p_listing_reference: eventId,
    }, token)
    : rpc<string>("submit_event_report", { p_event_id: eventId, p_category: category, p_details: details.trim() || null }, token);
}

// Small ⚑ report control for listing and poll cards (bottom-right).
function CardReport({ eventId }: { eventId: string }) {
  const ctx = useContext(PollCardContext);
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState("wrong_or_outdated");
  const [details, setDetails] = useState("");
  const [state, setState] = useState<"" | "sending" | "sent" | string>("");
  const stop = (e: { stopPropagation: () => void }) => e.stopPropagation();
  return (
    <div className="card-report" onClick={stop}>
      {state === "sent" ? <span className="card-report__done" role="status">Thanks. Support will review this listing.</span> : null}
      <button
        type="button"
        className="card-report__flag"
        aria-label="Report this listing"
        aria-expanded={open}
        onClick={(e) => { e.stopPropagation(); if (!ctx?.session) { ctx?.onSignIn(); return; } setOpen(!open); }}
      >⚑</button>
      {open && ctx?.session ? (
        <form
          className="card-report__popover"
          onSubmit={(e) => {
            e.preventDefault();
            e.stopPropagation();
            if (!ctx.session) return;
            setState("sending");
            void sendListingReport(eventId, category, details, ctx.session.access_token)
              .then(() => { setState("sent"); setOpen(false); setDetails(""); })
              .catch((error: unknown) => setState(`Not sent: ${messageFromError(error)}`));
          }}
        >
          <label>Reason
            <select value={category} onChange={(e) => setCategory(e.target.value)}>
              {eventReportCategories.map((item) => <option key={item.id} value={item.id}>{item.label}</option>)}
            </select>
          </label>
          <label>Details (optional)
            <textarea value={details} maxLength={1000} rows={2} onChange={(e) => setDetails(e.target.value)} />
          </label>
          <div className="card-report__actions">
            <button type="button" className="text-link" onClick={() => setOpen(false)}>Cancel</button>
            <button type="submit" className="button button--primary" disabled={state === "sending"} aria-busy={state === "sending"}>{state === "sending" ? "Sending…" : "Send"}</button>
          </div>
          {state && state !== "sending" && state !== "sent" ? <p className="panel-note" role="alert">{state}</p> : null}
        </form>
      ) : null}
    </div>
  );
}

function supportStamp(value: string) {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleString(undefined, { day: "numeric", month: "short", year: "numeric", hour: "numeric", minute: "2-digit" });
}

function SupportChat({ signedIn, requests, busy, onSubmit, onSignIn, authorName = "You" }: {
  signedIn: boolean;
  requests: SupportRequest[];
  busy: boolean;
  onSubmit: (form: HTMLFormElement) => Promise<boolean | void> | void;
  onSignIn: () => void;
  authorName?: string;
}) {
  const [issue, setIssue] = useState("");
  const [suggestion, setSuggestion] = useState("");
  const [pending, setPending] = useState<{ text: string; at: string } | null>(null);
  const [error, setError] = useState("");
  const statusLabel: Record<SupportRequest["status"], string> = { open: "Sent", in_review: "Support is looking", closed: "Closed" };
  const thread = [...requests].sort((a, b) => a.created_at.localeCompare(b.created_at));
  const [collapsed, setCollapsed] = useState(false);
  const threadRef = useRef<HTMLDivElement | null>(null);
  const idleRef = useRef<number | null>(null);
  const poke = useCallback(() => {
    setCollapsed(false);
    if (idleRef.current) window.clearTimeout(idleRef.current);
    idleRef.current = window.setTimeout(() => setCollapsed(true), 5000);
  }, []);
  useEffect(() => { poke(); return () => { if (idleRef.current) window.clearTimeout(idleRef.current); }; }, [poke]);
  useEffect(() => { const el = threadRef.current; if (el && !collapsed) el.scrollTop = el.scrollHeight; }, [collapsed, requests.length, pending]);
  const latest = thread[thread.length - 1];
  const combined = suggestion.trim() ? `Issue: ${issue.trim()}\n\nSuggestion: ${suggestion.trim()}` : `Issue: ${issue.trim()}`;
  const ready = Boolean(issue.trim()) && !busy && !pending;
  if (!signedIn) {
    return (
      <div className="support-chat support-chat--signed-out">
        <h3>Message Support privately</h3>
        <p>Sign in to send a private message. Only you and Support can see it.</p>
        <button className="button button--primary" type="button" onClick={onSignIn}>Sign in</button>
      </div>
    );
  }
  return (
    <div className="support-chat" onMouseMove={poke} onKeyDown={poke} onTouchStart={poke} onFocus={poke}>
      <div className="support-chat__head">
        <span className="support-chat__avatar" aria-hidden="true">CC</span>
        <div><strong>Coast Calendar Support</strong><small>🔒 Private — only you and Support can see this</small></div>
      </div>
      {collapsed && (thread.length > 0 || pending) ? (
        <button type="button" className="support-chat__summary" onClick={poke}>
          <span>{thread.length} {thread.length === 1 ? "message" : "messages"}</span>
          {latest ? <span className="support-chat__summary-text">{latest.support_note ? `Support: ${latest.support_note}` : latest.message}</span> : null}
          {latest ? <span className={`support-chat__status support-chat__status--${latest.status}`}>{statusLabel[latest.status] ?? latest.status}</span> : null}
          <span aria-hidden="true">▾</span>
        </button>
      ) : null}
      <div className="support-chat__thread" aria-live="polite" ref={threadRef} hidden={collapsed && (thread.length > 0 || Boolean(pending))}>
        {thread.length === 0 && !pending ? (
          <div className="support-chat__empty">
            <strong>No support requests yet. Messages you send will appear here with Support replies.</strong>
            <ol>
              <li>Tell us what went wrong or what's confusing.</li>
              <li>Optionally, suggest how it could work better.</li>
              <li>Press Send. Support replies here, privately.</li>
            </ol>
          </div>
        ) : null}
        {thread.map((request) => (
          <div className="support-chat__item" key={request.id}>
            <div className="support-chat__bubble support-chat__bubble--me">
              <span className="support-chat__author">{authorName}</span>
              <p>{request.message}</p>
              <span className="support-chat__meta">{supportStamp(request.created_at)} <span className={`support-chat__status support-chat__status--${request.status}`}>{statusLabel[request.status] ?? request.status}</span></span>
            </div>
            {request.support_note ? (
              <div className="support-chat__bubble support-chat__bubble--support">
                <strong>Support</strong>
                <p>{request.support_note}</p>
                <span className="support-chat__meta">{request.updated_at ? supportStamp(request.updated_at) : "Reply"} <span className={`support-chat__status support-chat__status--${request.status}`}>{statusLabel[request.status] ?? request.status}</span></span>
              </div>
            ) : null}
          </div>
        ))}
        {pending ? (
          <div className="support-chat__item">
            <div className="support-chat__bubble support-chat__bubble--me is-pending">
              <span className="support-chat__author">{authorName}</span>
              <p>{pending.text}</p>
              <span className="support-chat__meta">{supportStamp(pending.at)} <span className="support-chat__status">Sending…</span></span>
            </div>
          </div>
        ) : null}
      </div>
      <form
        className="support-chat__form"
        onSubmit={(event) => {
          event.preventDefault();
          if (!issue.trim() || pending) return;
          const form = event.currentTarget;
          const saved = { issue, suggestion };
          setError("");
          setPending({ text: combined, at: new Date().toISOString() });
          setIssue("");
          setSuggestion("");
          void Promise.resolve(onSubmit(form)).then((ok) => {
            setPending(null);
            if (!ok) {
              setIssue(saved.issue);
              setSuggestion(saved.suggestion);
              setError("Your message wasn't sent. Check the notice above and try again.");
            }
          });
        }}
      >
        <input type="hidden" name="topic" value="General" />
        <input type="hidden" name="message" value={combined} />
        <label className="support-chat__field">
          <span>What's your issue? <em>required</em></span>
          <textarea rows={2} value={issue} placeholder="e.g. My listing photo won't show on the board" onChange={(e) => setIssue(e.target.value)} />
        </label>
        <label className="support-chat__field">
          <span>What would you suggest? <em>optional</em></span>
          <textarea rows={2} value={suggestion} placeholder="e.g. Let me pick the cover photo" onChange={(e) => setSuggestion(e.target.value)} />
        </label>
        <div className="support-chat__actions">
          {error ? <span className="support-chat__error">{error}</span> : <span className="support-chat__note">Private: only you and Support see this.</span>}
          <button className={ready ? "support-chat__send-pill is-ready" : "support-chat__send-pill"} type="submit" disabled={!ready}>Send ↑</button>
        </div>
      </form>
    </div>
  );
}

function SupportRequestPanel({ requests, busy, onSubmit }: {
  requests: SupportRequest[];
  busy: boolean;
  onSubmit: (form: HTMLFormElement) => void;
}) {
  return (
    <div className="panel">
      <h3>Contact Support</h3>
      <form onSubmit={(event) => { event.preventDefault(); onSubmit(event.currentTarget); }}>
        <label>Topic<input name="topic" defaultValue="Account" required /></label>
        <label>Listing reference<input name="listing_reference" /></label>
        <label>Message<textarea name="message" required /></label>
        <button className="button button--primary" disabled={busy}>Send</button>
      </form>
      {requests.map((request) => (
        <p className="list-line" key={request.id}><strong>{request.topic}</strong><span>{request.status}</span></p>
      ))}
    </div>
  );
}

function SupportAdminPanel({ profiles, subscriptions, listings, memberNotices, requests, changeRequests, notifications, auditEvents, busy, onUpdate, onShowPublic, onSignOut }: {
  profiles: HostRecord[];
  subscriptions: SubscriptionRecord[];
  listings: EventRecord[];
  memberNotices: MemberNoticeRecord[];
  requests: SupportRequest[];
  changeRequests: ChangeRequest[];
  notifications: UserNotification[];
  auditEvents: SupportAuditEvent[];
  busy: boolean;
  onUpdate: (table: "events" | "business_profiles" | "support_requests" | "event_change_requests" | "member_notices", id: string, patch: Record<string, unknown>) => void;
  onShowPublic?: () => void;
  onSignOut?: () => void;
}) {
  const subscriptionsByProfile = useMemo(() => {
    const map = new Map<string, SubscriptionRecord[]>();
    subscriptions.forEach((subscription) => {
      const rows = map.get(subscription.business_profile_id) ?? [];
      rows.push(subscription);
      map.set(subscription.business_profile_id, rows);
    });
    return map;
  }, [subscriptions]);
  const pendingProfiles = profiles.filter((profile) => profile.status === "pending_review");
  const pendingListings = listings.filter((listing) => listing.status === "pending_review");
  const publishedNotices = memberNotices.filter((notice) => notice.status === "published");
  const openSupportRequests = requests.filter((request) => request.status !== "closed");
  const pendingChangeRequests = changeRequests.filter((request) => request.status === "pending");
  const failedNotifications = notifications.filter((notification) => notification.push_status === "failed");
  const queuedNotifications = notifications.filter((notification) => notification.push_status === "queued");
  const activeSubscriptions = subscriptions.filter((subscription) => ["active", "trialing"].includes(subscription.status));
  const [memberReviewNotes, setMemberReviewNotes] = useState<Record<string, string>>({});
  const [hqTab, setHqTab] = useState<"apps" | "listings" | "notices" | "inbox" | "reports" | "edits" | "alerts" | "audit">("listings");
  // TEMP_BRIDGE: listing reports arrive as support_requests with topic "Listing report".
  const isListingReport = (request: SupportRequest) => request.topic === "Listing report";

  function memberReviewNote(profile: HostRecord) {
    return memberReviewNotes[profile.id] ?? "";
  }

  function updateMemberReviewNote(profileID: string, note: string) {
    setMemberReviewNotes((current) => ({ ...current, [profileID]: note }));
  }

  function reviewPatch(profile: HostRecord, status: "approved" | "rejected" | "suspended") {
    const note = memberReviewNote(profile).trim();
    const now = new Date().toISOString();

    if (status === "approved") {
      return {
        status,
        approved_at: now,
        rejected_at: null,
        suspended_at: null,
        rejection_reason: null,
        suspension_reason: null,
        support_note: note || null,
        reviewed_at: now,
      };
    }

    if (status === "rejected") {
      const reason = note || "Support needs more detail before this membership can be approved.";
      return {
        status,
        rejected_at: now,
        rejection_reason: reason,
        support_note: note || reason,
        reviewed_at: now,
      };
    }

    const reason = note || "Support review required before this membership can continue.";
    return {
      status,
      suspended_at: now,
      suspension_reason: reason,
      support_note: note || reason,
      reviewed_at: now,
    };
  }

  return (
    <div className="panel panel--wide">
      <div className="hq-layout">
      <nav className="hq-side" aria-label="Support queues">
        <button type="button" aria-pressed={hqTab === "listings"} onClick={() => setHqTab("listings")}>Pending Listings <span>{pendingListings.length}</span></button>
        <button type="button" aria-pressed={hqTab === "reports"} onClick={() => setHqTab("reports")}>Listing Reports <span>{openSupportRequests.filter(isListingReport).length}</span></button>
        <button type="button" aria-pressed={hqTab === "edits"} onClick={() => setHqTab("edits")}>Change Requests <span>{pendingChangeRequests.length}</span></button>
        <button type="button" aria-pressed={hqTab === "apps"} onClick={() => setHqTab("apps")}>Member Applications <span>{pendingProfiles.length}</span></button>
        <button type="button" aria-pressed={hqTab === "inbox"} onClick={() => setHqTab("inbox")}>Support Inbox <span>{openSupportRequests.filter((r) => !isListingReport(r)).length}</span></button>
        <button type="button" aria-pressed={hqTab === "notices"} onClick={() => setHqTab("notices")}>Notices <span>{publishedNotices.length}</span></button>
        <button type="button" aria-pressed={hqTab === "alerts"} onClick={() => setHqTab("alerts")}>Alerts <span>{failedNotifications.length + queuedNotifications.length}</span></button>
        <button type="button" aria-pressed={hqTab === "audit"} onClick={() => setHqTab("audit")}>Audit</button>
        {onShowPublic ? <button type="button" className="hq-side__public" onClick={onShowPublic}>Public app</button> : null}
        {onSignOut ? <button type="button" className="hq-side__public" onClick={onSignOut}>Sign out</button> : null}
      </nav>
      <div className="hq-main">
      <details className="hq-panel" open hidden={hqTab !== "apps"}>
      <summary>Member Applications <span>{pendingProfiles.length}</span></summary>
      <p className="panel-note">Pending applications only.</p>
      {pendingProfiles.length === 0 ? <p className="panel-note">No member applications have been submitted yet.</p> : null}
      {pendingProfiles.map((profile) => (
        <div className="review-card" key={profile.id}>
          <strong>{profile.business_name}</strong>
          <span>{profile.status}</span>
          <p>{profile.about}</p>
          <div className="review-detail-grid">
            <p><strong>Contact</strong><span>{profile.contact_name ?? "Not supplied"}</span></p>
            <p><strong>Email</strong><span>{profile.contact_email}</span></p>
            <p><strong>Phone</strong><span>{profile.phone ?? "Not supplied"}</span></p>
            <p><strong>Website</strong><span>{profile.website ?? "Not supplied"}</span></p>
            <p><strong>Area</strong><span>{areaLabel(profile.area_scope_id)}</span></p>
            <p><strong>Plan</strong><span>{profile.selected_plan_id ?? "local_business"}</span></p>
          </div>
          <p className="panel-note">
            {subscriptionsByProfile.get(profile.id)?.[0]
              ? `Payment: ${subscriptionsByProfile.get(profile.id)?.[0].plan_id} · ${subscriptionsByProfile.get(profile.id)?.[0].status}`
              : "Payment: no subscription record yet"}
          </p>
          {profile.support_note ? <p className="panel-note">Last Support note: {profile.support_note}</p> : null}
          <label className="full">
            Support note
            <textarea
              value={memberReviewNote(profile)}
              onChange={(event) => updateMemberReviewNote(profile.id, event.target.value)}
              placeholder="Optional note for approval, or what needs changing before approval."
            />
          </label>
          <div className="action-row">
            <button disabled={busy} onClick={() => onUpdate("business_profiles", profile.id, reviewPatch(profile, "approved"))}>Approve</button>
            <button disabled={busy} onClick={() => onUpdate("business_profiles", profile.id, reviewPatch(profile, "rejected"))}>Request changes</button>
            <button disabled={busy} onClick={() => onUpdate("business_profiles", profile.id, reviewPatch(profile, "suspended"))}>Suspend</button>
          </div>
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "listings"}>
      <summary>Pending listings <span>{pendingListings.length}</span></summary>
      {pendingListings.length === 0 ? <p className="panel-note">No listings waiting.</p> : null}
      {pendingListings.map((listing) => (
        <div className="review-card" key={listing.id}>
          <strong>{listing.title}</strong>
          <span>{listing.status}</span>
          <p>{listing.short_description || listing.long_description || "No description supplied."}</p>
          <p className="panel-note">{listing.category} · {listing.location_display_name ?? listing.venue ?? listing.town ?? "No place"}</p>

          <div className="action-row">
            <button disabled={busy} onClick={() => onUpdate("events", listing.id, { status: "published" })}>Publish</button>
            <button disabled={busy} onClick={() => onUpdate("events", listing.id, { status: "rejected" })}>Reject</button>
            <button disabled={busy} onClick={() => onUpdate("events", listing.id, { status: "archived" })}>Archive</button>
          </div>
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "notices"}>
      <summary>Member Notices <span>{publishedNotices.length}</span></summary>
      <h4 className="sr-only">Member Notices</h4>
      <p className="panel-note">Weekly letters and member updates. Archive anything that should not remain visible while you review it.</p>
      {memberNotices.length === 0 ? <p className="panel-note">No member Notices yet.</p> : memberNotices.map((notice) => (
        <div className="review-card" key={notice.id}>
          <strong>{notice.title}</strong>
          <span>{notice.status}</span>
          <p>{notice.summary ?? notice.body ?? "No summary supplied."}</p>
          <div className="review-detail-grid">
            <p><strong>Template</strong><span>{notice.template_style.replaceAll("_", " ")}</span></p>
            <p><strong>Created</strong><span>{formatDate(notice.created_at)}</span></p>
            <p><strong>Published</strong><span>{notice.published_at ? formatDate(notice.published_at) : "Not published"}</span></p>
            <p><strong>Member</strong><span>{profiles.find((profile) => profile.id === notice.business_profile_id)?.business_name ?? notice.business_profile_id}</span></p>
          </div>
          <div className="action-row">
            <button disabled={busy || notice.status === "published"} onClick={() => onUpdate("member_notices", notice.id, { status: "published" })}>Publish</button>
            <button disabled={busy || notice.status === "archived"} onClick={() => onUpdate("member_notices", notice.id, { status: "archived" })}>Archive</button>
          </div>
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "inbox" && hqTab !== "reports"}>
      <summary>{hqTab === "reports" ? "Listing Reports" : "Support Inbox"} <span>{openSupportRequests.filter((r) => (hqTab === "reports") === isListingReport(r)).length}</span></summary>
      {requests.filter((r) => (hqTab === "reports") === isListingReport(r)).length === 0 ? <p className="panel-note">{hqTab === "reports" ? "No listing reports yet." : "No support messages yet."}</p> : null}
      {requests.filter((r) => (hqTab === "reports") === isListingReport(r)).map((request) => (
        <div className="review-card" key={request.id}>
          <strong>{request.topic}</strong>
          <span>{request.status}</span>
          <small className="support-inbox__author">
            From {(request.submitted_by && profiles.find((profile) => profile.owner_user_id === request.submitted_by)?.contact_name) || (request.submitted_by && profiles.find((profile) => profile.owner_user_id === request.submitted_by)?.business_name) || (request.submitted_by ? `user ${request.submitted_by.slice(0, 8)}` : "unknown user")} · {supportStamp(request.created_at)}
            {request.listing_reference ? ` · listing ${request.listing_reference}` : ""}
          </small>
          <p>{request.message}</p>
          <div className="action-row">
            <button disabled={busy} onClick={() => onUpdate("support_requests", request.id, { status: "in_review" })}>In review</button>
            <button disabled={busy} onClick={() => onUpdate("support_requests", request.id, { status: "closed" })}>Close</button>
          </div>
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "edits"}>
      <summary>Edit requests <span>{pendingChangeRequests.length}</span></summary>
      {changeRequests.map((request) => (
        <div className="review-card" key={request.id}>
          <strong>{request.events?.title ?? request.change_type}</strong>
          <span>{request.status}</span>
          <p>{request.requester_note ?? "No requester note supplied."}</p>
          <div className="action-row">
            <button disabled={busy} onClick={() => onUpdate("event_change_requests", request.id, {
              status: "applied",
              review_reason: "approved_applied",
              reviewed_at: new Date().toISOString(),
              applied_at: new Date().toISOString(),
              support_note: "Applied by Support.",
            })}>Mark applied</button>
            <button disabled={busy} onClick={() => onUpdate("event_change_requests", request.id, {
              status: "rejected",
              review_reason: "other",
              reviewed_at: new Date().toISOString(),
              support_note: "Not approved by Support.",
            })}>Reject</button>
          </div>
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "alerts"}>
      <summary>Notifications</summary>
      <h4 className="sr-only">Notifications</h4>
      <p className="panel-note">In-app/web notifications and push state. Push retry controls should stay server-side in the future operator workstation so secrets never enter the browser.</p>
      {notifications.length === 0 ? <p className="panel-note">No notifications yet.</p> : notifications.slice(0, 20).map((notification) => (
        <div className="review-card" key={notification.id}>
          <strong>{notification.title}</strong>
          <span>{notification.push_status ?? "queued"}</span>
          <p>{notification.body}</p>
          <div className="review-detail-grid">
            <p><strong>Type</strong><span>{notification.notification_type}</span></p>
            <p><strong>Created</strong><span>{formatDate(notification.created_at)}</span></p>
            <p><strong>Attempts</strong><span>{notification.push_attempts ?? 0}</span></p>
            <p><strong>Sent</strong><span>{notification.push_sent_at ? formatDate(notification.push_sent_at) : "Not sent"}</span></p>
          </div>
          {notification.push_error ? <p className="panel-note">Push error: {notification.push_error}</p> : null}
        </div>
      ))}
      </details>
      <details className="hq-panel" open hidden={hqTab !== "audit"}>
      <summary>Audit trail</summary>
      <h4 className="sr-only">Audit trail</h4>
      {auditEvents.length === 0 ? <p className="panel-note">No support audit events yet.</p> : auditEvents.slice(0, 24).map((event) => (
        <div className="review-card" key={event.id}>
          <strong>{event.action}</strong>
          <span>{event.entity_table}</span>
          <div className="review-detail-grid">
            <p><strong>When</strong><span>{formatDate(event.created_at)}</span></p>
            <p><strong>Entity</strong><span>{event.entity_id}</span></p>
            <p><strong>Actor</strong><span>{event.actor_user_id ?? "System"}</span></p>
            <p><strong>Reason</strong><span>{event.reason ?? "Not supplied"}</span></p>
          </div>
        </div>
      ))}
      </details>
      </div>
      </div>
    </div>
  );
}

function OpsMetric({ title, value, detail, tone }: {
  title: string;
  value: number;
  detail: string;
  tone: "good" | "warn" | "bad";
}) {
  return (
    <div className={`ops-metric ops-metric--${tone}`}>
      <strong>{value}</strong>
      <span>{title}</span>
      <p>{detail}</p>
    </div>
  );
}
