/**
 * Weboldal-cím normalizálása mentés előtt. Elfogadja a séma nélküli alakot
 * (pl. `www.pelda.hu` → `https://www.pelda.hu`), de csak http(s) linket enged
 * (javascript:, mailto: stb. nem kerülhet a mobil „Weboldal” gombjára).
 * Üres bemenetre üres sztringet, érvénytelenre `null`-t ad.
 */
export function normalizeWebsite(raw) {
  const value = String(raw ?? '').trim();
  if (!value) return '';
  const withScheme = /^[a-z][a-z0-9+.-]*:/i.test(value) ? value : `https://${value}`;
  try {
    const url = new URL(withScheme);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    if (!url.hostname.includes('.')) return null;
    return url.toString();
  } catch {
    return null;
  }
}

/** A link megjelenítendő rövid alakja (séma és záró perjel nélkül). */
export const websiteLabel = (url) =>
  String(url ?? '').replace(/^https?:\/\//, '').replace(/\/$/, '');
