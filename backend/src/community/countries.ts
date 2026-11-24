/**
 * Country normalization for the gym directory. Providers return ISO 3166-1
 * alpha-2 codes; people type names ("India", "sg", "UAE"). Both are accepted
 * and stored as a normalized code plus a display name.
 */

const displayNames = new Intl.DisplayNames(['en'], { type: 'region' });

// Deprecated, exceptionally reserved or user-assigned codes share display
// names with the current ISO 3166-1 code (FR/FX, DE/DD, RS/CS…). Map only
// the canonical code.
const retiredCodes = new Set([
  'AN', 'BU', 'CS', 'DD', 'DY', 'FX', 'HV', 'NH', 'RH', 'SU', 'TP', 'UK', 'VD', 'YD', 'YU', 'ZR',
]);

const codeByName = new Map<string, string>();
for (let first = 65; first <= 90; first += 1) {
  for (let second = 65; second <= 90; second += 1) {
    const code = String.fromCharCode(first, second);
    if (retiredCodes.has(code)) continue;
    const name = displayNames.of(code);
    if (!name || name === code) continue;
    codeByName.set(normalizeKey(name), code);
  }
}

const aliases: Record<string, string> = {
  usa: 'US',
  'united states of america': 'US',
  america: 'US',
  uk: 'GB',
  'great britain': 'GB',
  england: 'GB',
  uae: 'AE',
  emirates: 'AE',
  'south korea': 'KR',
  korea: 'KR',
  russia: 'RU',
  'czech republic': 'CZ',
  turkey: 'TR',
  turkiye: 'TR',
  vietnam: 'VN',
  'viet nam': 'VN',
  'hong kong': 'HK',
  singapore: 'SG',
  india: 'IN',
};

function normalizeKey(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

export interface NormalizedCountry {
  code: string | null;
  name: string | null;
}

/** Accepts a name, an alias or a code and returns a consistent pair. */
export function normalizeCountry(input: string | null | undefined): NormalizedCountry {
  const raw = (input ?? '').trim();
  if (raw === '') return { code: null, name: null };

  const key = normalizeKey(raw);
  const aliasCode = aliases[key];
  const directCode = /^[a-zA-Z]{2}$/.test(raw) ? raw.toUpperCase() : null;
  const code =
    aliasCode ??
    codeByName.get(key) ??
    (directCode && !retiredCodes.has(directCode) && displayNames.of(directCode) !== directCode
      ? directCode
      : null);

  if (!code) return { code: null, name: raw.slice(0, 80) };
  const name = displayNames.of(code);
  return { code, name: name && name !== code ? name : raw.slice(0, 80) };
}

/** Country code for a provider payload, normalized or null. */
export function countryCodeFrom(value: string | null | undefined): string | null {
  return normalizeCountry(value).code;
}
