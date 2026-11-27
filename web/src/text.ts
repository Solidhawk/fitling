/**
 * At most `limit` code points, cut between whole characters (String.limited(toScalars:) in FitlingCore). Postgres
 * counts code points in char_length, so an emoji of five scalars takes five; `slice` counts UTF-16 units and can cut
 * an emoji in half.
 */
export function limitedText(text: string, limit: number): string {
  let result = "";
  let scalars = 0;
  for (const { segment } of new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)) {
    scalars += [...segment].length;
    if (scalars > limit) break;
    result += segment;
  }
  return result;
}
