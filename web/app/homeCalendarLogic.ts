// Home calendar rules shared by the web Home view. Mirrors iOS HomeCalendarLogic.swift.

export const HOME_VIEW_MODE_KEY = "communityCalendar.home.viewMode";
export type HomeViewMode = "board" | "calendar";

export const INITIAL_MONTH_COUNT = 3;
export const MONTHS_PER_LOAD = 2;
export const MAXIMUM_MONTH_COUNT = 18;
export const MAXIMUM_VISIBLE_DOTS = 4;

// One colour per topic (EventCategory raw values). Keep identical to iOS PCCTopicPalette.
export const TOPIC_PALETTE: { topic: string; label: string; colour: string }[] = [
  { topic: "Live Music", label: "Live Music", colour: "#7E57C2" },
  { topic: "Food & Drink", label: "Food", colour: "#E8A317" },
  { topic: "Markets", label: "Markets", colour: "#D1495B" },
  { topic: "Kids & Family", label: "Family", colour: "#F28C28" },
  { topic: "Sport", label: "Sport", colour: "#2E86DE" },
  { topic: "Community", label: "Community", colour: "#2F855A" },
  { topic: "Fundraisers", label: "Fundraisers", colour: "#E05297" },
  { topic: "Classes & Workshops", label: "Workshops", colour: "#1A9E9E" },
  { topic: "Seniors", label: "Seniors", colour: "#8D6E63" },
  { topic: "Church / Marae / Cultural", label: "Culture", colour: "#5C6BC0" },
  { topic: "Nightlife", label: "Nightlife", colour: "#2C3E70" },
  { topic: "Public Notices", label: "Notices", colour: "#6B7280" },
];

const TOPIC_ORDER = new Map(TOPIC_PALETTE.map((entry, index) => [entry.topic, index]));
export const TOPIC_COLOURS = new Map(TOPIC_PALETTE.map((entry) => [entry.topic, entry.colour]));
export const TOPIC_LABELS = new Map(TOPIC_PALETTE.map((entry) => [entry.topic, entry.label]));

export type CalendarEventFields = {
  id: string;
  category: string;
  topics?: string[];
  start_at: string;
  end_at: string;
  created_at?: string | null;
  is_featured?: boolean | null;
  is_paid_push?: boolean | null;
  promotion_rank?: number | null;
  promotion_paid_at?: string | null;
};

export function dayKey(date: Date) {
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${month}-${day}`;
}

export function dateFromKey(key: string) {
  const [year, month, day] = key.split("-").map(Number);
  return new Date(year, month - 1, day);
}

export function monthStart(date: Date) {
  return new Date(date.getFullYear(), date.getMonth(), 1);
}

export function addMonths(date: Date, count: number) {
  return new Date(date.getFullYear(), date.getMonth() + count, 1);
}

export function monthStarts(now: Date, count: number) {
  const first = monthStart(now);
  return Array.from({ length: Math.max(0, count) }, (_, index) => addMonths(first, index));
}

/** Grid cells for a month card, Monday first, with leading nulls. */
export function gridCells(month: Date): (Date | null)[] {
  const padding = (month.getDay() + 6) % 7;
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  return [
    ...Array.from({ length: padding }, () => null),
    ...Array.from({ length: days }, (_, index) => new Date(month.getFullYear(), month.getMonth(), index + 1)),
  ];
}

function eventRange(event: CalendarEventFields) {
  const start = new Date(event.start_at).getTime();
  const end = Math.max(start, new Date(event.end_at || event.start_at).getTime());
  return { start, end };
}

/** Same rule as iOS DateScope.today: start < endOfDay && end >= startOfDay. */
export function overlapsDay(event: CalendarEventFields, day: Date) {
  const startOfDay = new Date(day.getFullYear(), day.getMonth(), day.getDate()).getTime();
  const endOfDay = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1).getTime();
  const { start, end } = eventRange(event);
  return start < endOfDay && end >= startOfDay;
}

/** event_topics slugs first, falling back to the listing's primary category. */
export function topicsFor(event: CalendarEventFields) {
  const known = (event.topics ?? []).filter((topic) => TOPIC_ORDER.has(topic));
  if (known.length) return known;
  return TOPIC_ORDER.has(event.category) ? [event.category] : [];
}

/** Distinct topics per day (dayKey) inside a month. Multi-day listings mark every overlapped day. */
export function topicsByDay(events: CalendarEventFields[], month: Date) {
  const next = addMonths(month, 1);
  const sets = new Map<string, Set<string>>();
  for (const event of events) {
    const { start, end } = eventRange(event);
    if (start >= next.getTime() || end < month.getTime()) continue;
    const from = new Date(Math.max(start, month.getTime()));
    let day = new Date(from.getFullYear(), from.getMonth(), from.getDate());
    const topics = topicsFor(event);
    while (day < next && overlapsDay(event, day)) {
      const key = dayKey(day);
      const set = sets.get(key) ?? new Set<string>();
      topics.forEach((topic) => set.add(topic));
      sets.set(key, set);
      day = new Date(day.getFullYear(), day.getMonth(), day.getDate() + 1);
    }
  }
  const result = new Map<string, string[]>();
  sets.forEach((set, key) => result.set(key, [...set].sort((a, b) => (TOPIC_ORDER.get(a) ?? 99) - (TOPIC_ORDER.get(b) ?? 99))));
  return result;
}

/** Same placement signal as iOS effectivePromotionRank (topTen = 1 when is_paid_push). */
export function effectiveRank(event: CalendarEventFields) {
  return Math.max(event.promotion_rank ?? 0, event.is_paid_push ? 1 : 0);
}

/** Highest placement first; within a placement, earliest created (first listed) first. */
export function dayOrdering(a: CalendarEventFields, b: CalendarEventFields) {
  const rankA = effectiveRank(a);
  const rankB = effectiveRank(b);
  if (rankA !== rankB) return rankB - rankA;
  if (rankA >= 2 && a.promotion_paid_at !== b.promotion_paid_at) {
    return (a.promotion_paid_at ? Date.parse(a.promotion_paid_at) : Infinity) - (b.promotion_paid_at ? Date.parse(b.promotion_paid_at) : Infinity);
  }
  if (Boolean(a.is_featured) !== Boolean(b.is_featured)) return a.is_featured ? -1 : 1;
  const createdA = a.created_at ? Date.parse(a.created_at) : 0;
  const createdB = b.created_at ? Date.parse(b.created_at) : 0;
  if (createdA !== createdB) return createdA - createdB;
  return Date.parse(a.start_at) - Date.parse(b.start_at);
}

export function eventsOnDay<E extends CalendarEventFields>(events: E[], day: Date) {
  return events.filter((event) => overlapsDay(event, day)).sort(dayOrdering);
}

/** Home visibility rule: listings that have not finished yet (same as the Board's end_at >= now). */
export function isShownOnHome(event: CalendarEventFields, now: Date) {
  return eventRange(event).end >= now.getTime();
}
