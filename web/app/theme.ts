export const WALLPAPER_KEY = "communityCalendar.wallpaperStyle";
export const CARD_KEY = "communityCalendar.cardTintStyle";

export const wallpapers = [
  { id: "ornament", title: "Original", file: null },
  { id: "beachPohutukawa", title: "Pohutukawa Beach", file: "/wallpapers/beach-pohutukawa.jpg" },
  { id: "bushWalk", title: "Bush Walk", file: "/wallpapers/bush-walk.jpg" },
  { id: "clearBlueSea", title: "Clear Blue Sea", file: "/wallpapers/clear-blue-sea.jpg" },
  { id: "clifftopCoast", title: "Clifftop Coast", file: "/wallpapers/clifftop-coast.jpg" },
  { id: "coastalSunrise", title: "Coastal Sunrise", file: "/wallpapers/coastal-sunrise.jpg" },
  { id: "estuarySunset", title: "Estuary Sunset", file: "/wallpapers/estuary-sunset.jpg" },
  { id: "jettyHarbour", title: "Jetty Harbour", file: "/wallpapers/jetty-harbour.jpg" },
  { id: "sandyBeach", title: "Sandy Beach", file: "/wallpapers/sandy-beach.jpg" },
  { id: "sunsetRocks", title: "Sunset Rocks", file: "/wallpapers/sunset-rocks.jpg" },
] as const;

export const cardTints = [
  { id: "clean", title: "Clean white" },
  { id: "warm", title: "Warm cream" },
  { id: "sage", title: "Soft sage" },
  { id: "sky", title: "Coastal blue" },
  { id: "blush", title: "Pohutukawa blush" },
] as const;

export type WallpaperId = (typeof wallpapers)[number]["id"];
export type CardId = (typeof cardTints)[number]["id"];

function themeKeys(userId?: string | null) {
  const suffix = userId ? `.${userId}` : ".guest";
  return {
    wallpaper: WALLPAPER_KEY + suffix,
    card: CARD_KEY + suffix,
  };
}

export function readTheme(userId?: string | null) {
  const keys = themeKeys(userId);
  const wallpaper = (localStorage.getItem(keys.wallpaper) ?? "ornament") as WallpaperId;
  const card = (localStorage.getItem(keys.card) ?? "clean") as CardId;
  return { wallpaper, card };
}

export function applyTheme(wallpaper: string, card: string) {
  document.documentElement.dataset.wallpaper = wallpaper;
  document.documentElement.dataset.card = card;
}

export function saveTheme(partial: { wallpaper?: string; card?: string }, userId?: string | null) {
  const next = { ...readTheme(userId), ...partial };
  const keys = themeKeys(userId);
  localStorage.setItem(keys.wallpaper, next.wallpaper);
  localStorage.setItem(keys.card, next.card);
  applyTheme(next.wallpaper, next.card);
  return next;
}

export function applyThemeForUser(userId?: string | null) {
  const current = readTheme(userId);
  applyTheme(current.wallpaper, current.card);
  return current;
}
