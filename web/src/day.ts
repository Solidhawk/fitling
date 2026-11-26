/** Today where the user is, as Postgres writes a date: "2026-11-24". */
export function today(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

/** The same day thirty years back, where the date picker opens (BirthDayPicking.day). */
export function thirtyYearsBefore(day: string): string {
  const [year, month, date] = day.split("-").map(Number);
  const candidate = new Date(Date.UTC(year - 30, month - 1, date));
  // 29 February becomes 28 February.
  if (candidate.getUTCMonth() !== month - 1) candidate.setUTCDate(0);
  return candidate.toISOString().slice(0, 10);
}

/** A date as FitlingCore's Day reads it: four digits for the year. A desktop date field also allows five or six. */
export function isIsoDay(text: string): boolean {
  return /^\d{4}-\d{2}-\d{2}$/.test(text);
}

/** The day `count` days later (or earlier, when negative), as "2026-11-24". */
export function addDays(day: string, count: number): string {
  const [year, month, date] = day.split("-").map(Number);
  return new Date(Date.UTC(year, month - 1, date + count)).toISOString().slice(0, 10);
}
