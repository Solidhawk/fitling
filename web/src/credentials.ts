/** The same checks as Credentials in AuthViewModels.swift. */
export const minimumPasswordLength = 8;

export function normalizedEmail(email: string): string {
  return email.trim();
}

export function isPlausibleEmail(email: string): boolean {
  const parts = normalizedEmail(email).split("@");
  return parts.length === 2 && parts[0].length > 0 && parts[1].includes(".") && !parts[1].endsWith(".");
}
