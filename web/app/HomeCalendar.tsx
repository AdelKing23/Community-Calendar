"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";
import "./home-calendar.css";
import {
  HOME_VIEW_MODE_KEY,
  INITIAL_MONTH_COUNT,
  MAXIMUM_MONTH_COUNT,
  MAXIMUM_VISIBLE_DOTS,
  MONTHS_PER_LOAD,
  TOPIC_COLOURS,
  TOPIC_LABELS,
  TOPIC_PALETTE,
  addMonths,
  dateFromKey,
  dayKey,
  dayOrdering,
  eventsOnDay,
  gridCells,
  isFinished,
  isShownOnHome,
  monthStarts,
  topicsByDay,
} from "./homeCalendarLogic";
import type { CalendarEventFields, HomeViewMode } from "./homeCalendarLogic";

const DAY_STORAGE_KEY = "communityCalendar.home.calendarDay";
const ID_BATCH = 150;
const EVENT_SELECT = [
  "id", "title", "category", "venue", "start_at", "end_at", "price_label", "short_description", "long_description",
  "location_display_name", "town", "status", "listing_kind", "poll_question", "poll_options", "poll_allows_custom_answer",
  "organisation_name", "business_profile_id", "is_free", "created_at", "is_featured", "is_paid_push",
].join(",");

type CalendarRecord = CalendarEventFields & {
  listing_kind?: string | null;
  primary_location_scope_id?: string | null;
  image_url?: string | null;
};

export function useHomeViewMode(): [HomeViewMode, (mode: HomeViewMode) => void] {
  const [mode, setMode] = useState<HomeViewMode>("board");
  useEffect(() => {
    try {
      if (window.localStorage.getItem(HOME_VIEW_MODE_KEY) === "calendar") setMode("calendar");
    } catch { /* ignore */ }
  }, []);
  const update = useCallback((next: HomeViewMode) => {
    setMode(next);
    try { window.localStorage.setItem(HOME_VIEW_MODE_KEY, next); } catch { /* ignore */ }
  }, []);
  return [mode, update];
}

export function HomeViewToggle({ mode, onChange }: { mode: HomeViewMode; onChange: (mode: HomeViewMode) => void }) {
  const showingBoard = mode === "board";
  return (
    <button
      type="button"
      className="home-view-toggle"
      aria-label={showingBoard ? "Show calendar" : "Show board"}
      title={showingBoard ? "Show calendar" : "Show board"}
      onClick={() => onChange(showingBoard ? "calendar" : "board")}
    >
      {showingBoard ? (
        <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><rect x="3.5" y="5" width="17" height="15.5" rx="3" fill="none" stroke="currentColor" strokeWidth="2" /><path d="M3.5 10h17M8 3v4M16 3v4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" fill="none" /></svg>
      ) : (
        <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="4" width="16" height="7" rx="2" fill="none" stroke="currentColor" strokeWidth="2" /><rect x="4" y="14" width="16" height="7" rx="2" fill="none" stroke="currentColor" strokeWidth="2" /></svg>
      )}
    </button>
  );
}

type Props<E> = {
  homeScope: string;
  areaName: string;
  homeEventIDs: string[] | null;
  widerPollIDs: Set<string>;
  covering: Set<string>;
  slugById: Map<string, string>;
  excludeIDs: string[];
  rest: <T>(path: string) => Promise<T>;
  signImage: (storagePath: string) => Promise<string | null>;
  renderCard: (event: E) => ReactNode;
};

function chunks<T>(items: T[], size: number) {
  const result: T[][] = [];
  for (let index = 0; index < items.length; index += size) result.push(items.slice(index, index + size));
  return result;
}

export default function HomeCalendar<E extends CalendarRecord>({
  homeScope, areaName, homeEventIDs, widerPollIDs, covering, slugById, excludeIDs, rest, signImage, renderCard,
}: Props<E>) {
  const [monthCount, setMonthCount] = useState(INITIAL_MONTH_COUNT);
  const [byMonth, setByMonth] = useState<Record<string, E[]>>({});
  const [loading, setLoading] = useState<Set<string>>(new Set());
  const [failed, setFailed] = useState<Set<string>>(new Set());
  const [selectedDay, setSelectedDay] = useState<string | null>(null);
  const [dayEvents, setDayEvents] = useState<E[] | null>(null);
  const inFlight = useRef(new Set<string>());
  const sentinel = useRef<HTMLDivElement | null>(null);
  const topRef = useRef<HTMLDivElement | null>(null);

  const now = useMemo(() => new Date(), []);
  const todayKey = dayKey(now);
  const months = useMemo(() => monthStarts(now, monthCount), [now, monthCount]);

  // Same location rule as the Home board: listings targeted at this area, polls whose coverage includes it.
  const scopedIDs = useMemo(() => (homeEventIDs === null ? null : [...new Set([...homeEventIDs, ...widerPollIDs])]), [homeEventIDs, widerPollIDs]);
  const scopeKey = `${homeScope}|${scopedIDs === null ? "all" : scopedIDs.slice().sort().join(",")}`;
  const passesHome = useCallback((event: E) => {
    if (excludeIDs.includes(event.id)) return false;
    if (event.listing_kind === "poll") {
      const cov = slugById.get(String(event.primary_location_scope_id ?? ""));
      return cov ? covering.has(cov) : widerPollIDs.has(event.id);
    }
    return homeEventIDs === null ? true : homeEventIDs.includes(event.id);
  }, [excludeIDs, slugById, covering, widerPollIDs, homeEventIDs]);
  const scopeKeyRef = useRef(scopeKey);
  scopeKeyRef.current = scopeKey;
  const passesHomeRef = useRef(passesHome);
  passesHomeRef.current = passesHome;

  useEffect(() => {
    try { setSelectedDay(window.sessionStorage.getItem(DAY_STORAGE_KEY)); } catch { /* ignore */ }
  }, []);

  useEffect(() => {
    setByMonth({});
    setFailed(new Set());
    inFlight.current = new Set();
  }, [scopeKey]);

  const loadMonth = useCallback(async (month: Date, key: string, requestKey: string) => {
    // Start of today, so listings that ended earlier today still load (shown as Finished until midnight).
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0);
    const from = new Date(Math.max(month.getTime(), todayStart.getTime())).toISOString();
    const to = addMonths(month, 1).toISOString();
    const range = `end_at=gte.${encodeURIComponent(from)}&start_at=lt.${encodeURIComponent(to)}&order=start_at.asc`;
    let rows: E[] = [];
    if (scopedIDs === null) {
      rows = await rest<E[]>(`public_events?select=${EVENT_SELECT}&${range}`);
    } else {
      for (const batch of chunks(scopedIDs, ID_BATCH)) {
        rows.push(...await rest<E[]>(`public_events?select=${EVENT_SELECT}&id=in.(${batch.join(",")})&${range}`));
      }
    }
    if (rows.length) {
      try {
        const topicRows: { event_id: string; topic_slug: string }[] = [];
        for (const batch of chunks(rows.map((row) => row.id), ID_BATCH)) {
          topicRows.push(...await rest<{ event_id: string; topic_slug: string }[]>(`event_topics?select=event_id,topic_slug&event_id=in.(${batch.join(",")})`));
        }
        const topics = new Map<string, string[]>();
        topicRows.forEach((row) => topics.set(row.event_id, [...(topics.get(row.event_id) ?? []), row.topic_slug]));
        rows = rows.map((row) => ({ ...row, topics: topics.get(row.id) ?? [] }));
      } catch (error) {
        console.warn("home calendar topics", error);
      }
      const pollIDs = rows.filter((row) => row.listing_kind === "poll").map((row) => row.id);
      if (pollIDs.length) {
        try {
          const cov = await rest<{ id: string; primary_location_scope_id: string | null }[]>(`public_events?select=id,primary_location_scope_id&id=in.(${pollIDs.join(",")})`);
          const byID = new Map(cov.map((row) => [row.id, row.primary_location_scope_id]));
          rows = rows.map((row) => (byID.has(row.id) ? { ...row, primary_location_scope_id: byID.get(row.id) } : row));
        } catch (error) {
          console.warn("home calendar poll coverage", error);
        }
      }
    }
    const nowTime = new Date();
    const visible = rows.filter((row) => isShownOnHome(row, nowTime) && passesHomeRef.current(row));
    return { key, requestKey, visible };
  }, [scopedIDs, rest]);

  useEffect(() => {
    const requestKey = scopeKey;
    for (const month of months) {
      const key = dayKey(month);
      if (byMonth[key] || failed.has(key) || inFlight.current.has(key)) continue;
      inFlight.current.add(key);
      setLoading((current) => new Set(current).add(key));
      loadMonth(month, key, requestKey)
        .then((result) => {
          if (result.requestKey !== scopeKeyRef.current) return;
          setByMonth((current) => ({ ...current, [result.key]: result.visible }));
        })
        .catch((error) => {
          console.warn("home calendar month", error);
          if (requestKey === scopeKeyRef.current) setFailed((current) => new Set(current).add(key));
        })
        .finally(() => {
          inFlight.current.delete(key);
          setLoading((current) => { const next = new Set(current); next.delete(key); return next; });
        });
    }
  }, [months, byMonth, failed, loadMonth, scopeKey]);

  useEffect(() => {
    const node = sentinel.current;
    if (!node || selectedDay || monthCount >= MAXIMUM_MONTH_COUNT) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting)) {
        setMonthCount((count) => Math.min(count + MONTHS_PER_LOAD, MAXIMUM_MONTH_COUNT));
      }
    }, { rootMargin: "400px 0px" });
    observer.observe(node);
    return () => observer.disconnect();
  }, [selectedDay, monthCount]);

  const openDay = (key: string | null) => {
    setSelectedDay(key);
    try {
      if (key) window.sessionStorage.setItem(DAY_STORAGE_KEY, key);
      else window.sessionStorage.removeItem(DAY_STORAGE_KEY);
    } catch { /* ignore */ }
    window.requestAnimationFrame(() => topRef.current?.scrollIntoView({ block: "start", behavior: "smooth" }));
  };

  // Day view: listings for the chosen day, placement first, then first listed. Images and placement load on open.
  const selectedMonthKey = selectedDay ? dayKey(new Date(dateFromKey(selectedDay).getFullYear(), dateFromKey(selectedDay).getMonth(), 1)) : null;
  const selectedMonthRows = selectedMonthKey ? byMonth[selectedMonthKey] : undefined;
  useEffect(() => {
    if (!selectedDay) { setDayEvents(null); return; }
    if (!selectedMonthRows) {
      // Month not loaded yet (e.g. restored after reload): make sure it is in range.
      const target = dateFromKey(selectedDay);
      const needed = (target.getFullYear() - now.getFullYear()) * 12 + target.getMonth() - now.getMonth() + 1;
      if (needed > monthCount && needed <= MAXIMUM_MONTH_COUNT) setMonthCount(needed);
      if (needed < 1 || needed > MAXIMUM_MONTH_COUNT) openDay(null);
      setDayEvents(null);
      return;
    }
    let cancelled = false;
    const base = eventsOnDay(selectedMonthRows, dateFromKey(selectedDay));
    setDayEvents(base);
    if (!base.length) return;
    (async () => {
      const ids = base.map((event) => event.id).join(",");
      let enriched = base;
      try {
        const promotions = await rest<{ event_id: string; placement_rank: number; paid_at: string | null }[]>(
          `active_event_promotions?select=event_id,placement_rank,paid_at&event_id=in.(${ids})&order=placement_rank.desc,paid_at.asc`
        );
        const best = new Map<string, { placement_rank: number; paid_at: string | null }>();
        promotions.forEach((row) => { if (!best.has(row.event_id)) best.set(row.event_id, row); });
        enriched = enriched.map((event) => {
          const promotion = best.get(event.id);
          return promotion ? { ...event, promotion_rank: promotion.placement_rank, promotion_paid_at: promotion.paid_at } : event;
        });
      } catch (error) {
        console.warn("home calendar placement", error);
      }
      try {
        const images = await rest<{ event_id: string; storage_path: string; position: number }[]>(
          `public_event_images?select=event_id,storage_path,position&event_id=in.(${ids})&order=position.asc`
        );
        const first = new Map<string, string>();
        images.forEach((image) => { if (!first.has(image.event_id)) first.set(image.event_id, image.storage_path); });
        const signed = new Map<string, string | null>(await Promise.all([...first.entries()].map(async ([id, path]) => [id, await signImage(path)] as [string, string | null])));
        enriched = enriched.map((event) => (signed.get(event.id) ? { ...event, image_url: signed.get(event.id) } : event));
      } catch (error) {
        console.warn("home calendar images", error);
      }
      if (!cancelled) setDayEvents([...enriched].sort(dayOrdering));
    })();
    return () => { cancelled = true; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedDay, selectedMonthRows]);

  if (selectedDay) {
    const date = dateFromKey(selectedDay);
    const title = date.toLocaleDateString("en-NZ", { weekday: "long", day: "numeric", month: "long" });
    return (
      <div className="home-calendar home-calendar--day" ref={topRef}>
        <button type="button" className="home-calendar__back" onClick={() => openDay(null)}>← Back to calendar</button>
        <div className="home-calendar__day-head">
          <h2>{title}</h2>
          <p>{dayEvents === null ? (selectedMonthKey && failed.has(selectedMonthKey) ? "This day could not be loaded." : "Loading…") : dayEvents.length ? `${dayEvents.length} ${dayEvents.length === 1 ? "listing" : "listings"} around ${areaName}` : `Around ${areaName}`}</p>
        </div>
        {dayEvents === null ? (selectedMonthKey && failed.has(selectedMonthKey) ? (
          <button type="button" className="home-calendar__retry" onClick={() => setFailed((current) => { const next = new Set(current); next.delete(selectedMonthKey); return next; })}>Try again</button>
        ) : null) : dayEvents.length === 0 ? (
          <div className="empty-state">
            <p className="empty-state__icon">+</p>
            <h3>Nothing listed for this day yet</h3>
            <p>This date is free around {areaName}. If your organisation has something on, list it so locals can find it.</p>
          </div>
        ) : (
          <div className="event-list">
            {dayEvents.map((event) => isFinished(event, new Date()) ? (
              <div key={`day-${event.id}`} className="home-calendar__finished">
                <span className="home-calendar__finished-tag">✓ Finished</span>
                <div className="home-calendar__finished-card">{renderCard(event)}</div>
              </div>
            ) : <div key={`day-${event.id}`}>{renderCard(event)}</div>)}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="home-calendar" ref={topRef}>
      <div className="home-calendar__legend" aria-label="Dot colours show listing topics">
        {TOPIC_PALETTE.map((entry) => (
          <span key={entry.topic} className="home-calendar__legend-item">
            <i style={{ background: entry.colour }} aria-hidden="true" />{entry.label}
          </span>
        ))}
      </div>
      {months.map((month) => {
        const key = dayKey(month);
        const marks = topicsByDay(byMonth[key] ?? [], month);
        return (
          <section className="home-calendar__month" key={key} aria-label={month.toLocaleDateString("en-NZ", { month: "long", year: "numeric" })}>
            <header className="home-calendar__month-head">
              <h3>{month.toLocaleDateString("en-NZ", { month: "long", year: "numeric" })}</h3>
              {loading.has(key) ? <span className="home-calendar__status">Loading…</span> : failed.has(key) ? (
                <button type="button" className="home-calendar__retry" onClick={() => setFailed((current) => { const next = new Set(current); next.delete(key); return next; })}>Try again</button>
              ) : null}
            </header>
            <div className="home-calendar__grid" role="grid">
              {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label) => (
                <span key={label} className="home-calendar__weekday" aria-hidden="true">{label.slice(0, 1)}</span>
              ))}
              {gridCells(month).map((day, index) => {
                if (!day) return <span key={`pad-${index}`} className="home-calendar__pad" />;
                const cellKey = dayKey(day);
                const past = cellKey < todayKey;
                const today = cellKey === todayKey;
                const topics = marks.get(cellKey) ?? [];
                const visible = topics.slice(0, MAXIMUM_VISIBLE_DOTS);
                const label = `${today ? "Today, " : ""}${day.toLocaleDateString("en-NZ", { weekday: "long", day: "numeric", month: "long" })}, ${topics.length ? topics.map((topic) => TOPIC_LABELS.get(topic) ?? topic).join(", ") : "nothing listed"}`;
                return (
                  <button
                    type="button"
                    key={cellKey}
                    className={`home-calendar__day${past ? " is-past" : ""}${today ? " is-today" : ""}`}
                    disabled={past}
                    aria-label={label}
                    onClick={() => openDay(cellKey)}
                  >
                    <span className="home-calendar__num">{day.getDate()}</span>
                    <span className="home-calendar__dots" aria-hidden="true">
                      {visible.map((topic) => <i key={topic} style={{ background: TOPIC_COLOURS.get(topic) }} />)}
                      {topics.length > visible.length ? <b>+</b> : null}
                    </span>
                  </button>
                );
              })}
            </div>
          </section>
        );
      })}
      {monthCount < MAXIMUM_MONTH_COUNT ? (
        <div ref={sentinel} className="home-calendar__more">
          <button type="button" className="text-link" onClick={() => setMonthCount((count) => Math.min(count + MONTHS_PER_LOAD, MAXIMUM_MONTH_COUNT))}>Show more months</button>
        </div>
      ) : null}
    </div>
  );
}
