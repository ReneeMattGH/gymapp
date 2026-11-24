import type { Config } from '../config.js';
import { normalizeCountry } from './countries.js';

/**
 * Server-side gym discovery. Provider calls happen only here, so API keys
 * never reach the iOS app, and every request is debounced, rate limited and
 * cached by the community service before it reaches this module.
 */
export interface ProviderGym {
  providerId: string;
  providerName: string;
  name: string;
  address?: string | null;
  neighborhood?: string | null;
  city?: string | null;
  region?: string | null;
  country?: string | null;
  countryCode?: string | null;
  postalCode?: string | null;
  latitude: number;
  longitude: number;
  website?: string | null;
  phone?: string | null;
}

export interface GymProvider {
  readonly name: 'google' | 'osm';
  searchText(query: string, limit: number): Promise<ProviderGym[]>;
  searchNearby(latitude: number, longitude: number, radiusMeters: number, limit: number): Promise<ProviderGym[]>;
}

export interface ProviderStatus {
  configured: boolean;
  name: string | null;
  /** Why discovery is unavailable, for an honest client-side message. */
  reason: string | null;
  /** Public, user-visible credit required by the data source. */
  attribution: string | null;
}

const GOOGLE_ENDPOINT = 'https://places.googleapis.com/v1';
const FIELD_MASK = [
  'places.id',
  'places.displayName',
  'places.formattedAddress',
  'places.location',
  'places.addressComponents',
  'places.websiteUri',
  'places.nationalPhoneNumber',
  'places.internationalPhoneNumber',
].join(',');

interface GooglePlace {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  websiteUri?: string;
  nationalPhoneNumber?: string;
  internationalPhoneNumber?: string;
  addressComponents?: Array<{
    longText?: string;
    shortText?: string;
    types?: string[];
  }>;
}

function component(place: GooglePlace, ...types: string[]): string | null {
  for (const wanted of types) {
    const found = place.addressComponents?.find((item) => item.types?.includes(wanted));
    if (found) return found.longText ?? found.shortText ?? null;
  }
  return null;
}

function googlePlaceToGym(place: GooglePlace): ProviderGym | null {
  const latitude = place.location?.latitude;
  const longitude = place.location?.longitude;
  const name = place.displayName?.text?.trim();
  if (!place.id || !name || latitude === undefined || longitude === undefined) return null;
  const country = normalizeCountry(component(place, 'country'));
  return {
    providerId: place.id,
    providerName: 'google',
    name,
    address: place.formattedAddress ?? null,
    neighborhood: component(place, 'neighborhood', 'sublocality_level_1', 'sublocality'),
    city: component(place, 'locality', 'postal_town', 'administrative_area_level_2'),
    region: component(place, 'administrative_area_level_1'),
    country: country.name,
    countryCode: country.code,
    postalCode: component(place, 'postal_code'),
    latitude,
    longitude,
    website: place.websiteUri ?? null,
    phone: place.internationalPhoneNumber ?? place.nationalPhoneNumber ?? null,
  };
}

class GooglePlacesProvider implements GymProvider {
  readonly name = 'google' as const;

  constructor(
    private readonly apiKey: string,
    private readonly timeoutMs: number,
  ) {}

  private async call(path: string, body: unknown): Promise<GooglePlace[]> {
    const response = await fetch(`${GOOGLE_ENDPOINT}/${path}`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-goog-api-key': this.apiKey,
        'x-goog-fieldmask': FIELD_MASK,
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!response.ok) {
      const detail = await response.text().catch(() => '');
      throw new Error(`Google Places returned ${response.status}${detail ? `: ${detail.slice(0, 200)}` : ''}`);
    }
    const payload = (await response.json()) as { places?: GooglePlace[] };
    return payload.places ?? [];
  }

  async searchText(query: string, limit: number): Promise<ProviderGym[]> {
    const places = await this.call('places:searchText', {
      textQuery: query,
      maxResultCount: Math.min(Math.max(limit, 1), 20),
      includedType: 'gym',
      languageCode: 'en',
    });
    return places.map(googlePlaceToGym).filter((gym): gym is ProviderGym => gym !== null);
  }

  async searchNearby(latitude: number, longitude: number, radiusMeters: number, limit: number): Promise<ProviderGym[]> {
    const places = await this.call('places:searchNearby', {
      includedTypes: ['gym'],
      maxResultCount: Math.min(Math.max(limit, 1), 20),
      locationRestriction: {
        circle: {
          center: { latitude, longitude },
          radius: Math.min(Math.max(radiusMeters, 100), 50000),
        },
      },
    });
    return places.map(googlePlaceToGym).filter((gym): gym is ProviderGym => gym !== null);
  }
}

interface OverpassElement {
  type?: string;
  id?: number;
  lat?: number;
  lon?: number;
  center?: { lat?: number; lon?: number };
  tags?: Record<string, string>;
}

function overpassElementToGym(element: OverpassElement): ProviderGym | null {
  const tags = element.tags ?? {};
  const name = tags.name?.trim();
  const latitude = element.lat ?? element.center?.lat;
  const longitude = element.lon ?? element.center?.lon;
  if (!name || latitude === undefined || longitude === undefined || element.id === undefined) return null;
  const country = normalizeCountry(tags['addr:country']);
  const street = [tags['addr:housenumber'], tags['addr:street']].filter(Boolean).join(' ');
  const address = street || tags['addr:full'] || null;
  return {
    providerId: `${element.type ?? 'node'}/${element.id}`,
    providerName: 'osm',
    name,
    address,
    neighborhood: tags['addr:suburb'] ?? tags['addr:neighbourhood'] ?? null,
    city: tags['addr:city'] ?? tags['addr:town'] ?? tags['addr:village'] ?? null,
    region: tags['addr:state'] ?? null,
    country: country.name,
    countryCode: country.code,
    postalCode: tags['addr:postcode'] ?? null,
    latitude,
    longitude,
    website: tags.website ?? tags['contact:website'] ?? null,
    phone: tags.phone ?? tags['contact:phone'] ?? null,
  };
}

function overpassLiteral(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

class OsmOverpassProvider implements GymProvider {
  readonly name = 'osm' as const;
  private lastCall = 0;

  constructor(
    private readonly endpoint: string,
    private readonly timeoutMs: number,
    private readonly minIntervalMs: number,
    private readonly allowTextSearch: boolean,
  ) {}

  private async query(overpass: string): Promise<OverpassElement[]> {
    const wait = this.minIntervalMs - (Date.now() - this.lastCall);
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    this.lastCall = Date.now();
    const response = await fetch(this.endpoint, {
      method: 'POST',
      headers: {
        'content-type': 'application/x-www-form-urlencoded',
        'user-agent': 'FormaGymDirectory/1.0 (gym discovery; contact the Forma operator)',
      },
      body: new URLSearchParams({ data: overpass }).toString(),
      signal: AbortSignal.timeout(this.timeoutMs),
    });
    if (!response.ok) {
      throw new Error(`Overpass returned ${response.status}`);
    }
    const payload = (await response.json()) as { elements?: OverpassElement[] };
    return payload.elements ?? [];
  }

  async searchText(query: string, limit: number): Promise<ProviderGym[]> {
    if (!this.allowTextSearch) return [];
    const parts = query
      .split(',')
      .map((part) => part.trim())
      .filter((part) => part.length > 1);
    if (parts.length === 0) return [];
    const name = parts[0];
    if (name === undefined) return [];
    const places = parts.slice(1);
    let filter = `["leisure"="fitness_centre"]["name"~"${overpassLiteral(name)}",i]`;
    for (const place of places.slice(0, 2)) {
      filter += `["addr:city"~"${overpassLiteral(place)}",i]`;
    }
    const overpass = `[out:json][timeout:20];nwr${filter};out center tags ${Math.min(Math.max(limit, 1), 30)};`;
    const elements = await this.query(overpass);
    return elements.map(overpassElementToGym).filter((gym): gym is ProviderGym => gym !== null);
  }

  async searchNearby(latitude: number, longitude: number, radiusMeters: number, limit: number): Promise<ProviderGym[]> {
    const radius = Math.min(Math.max(Math.round(radiusMeters), 100), 50000);
    const overpass =
      `[out:json][timeout:20];` +
      `nwr["leisure"="fitness_centre"](around:${radius},${latitude.toFixed(6)},${longitude.toFixed(6)});` +
      `out center tags ${Math.min(Math.max(limit, 1), 40)};`;
    const elements = await this.query(overpass);
    return elements.map(overpassElementToGym).filter((gym): gym is ProviderGym => gym !== null);
  }
}

export function createGymProvider(config: Config): GymProvider | null {
  if (config.gymProvider === 'none') return null;
  // Tests never reach the network; a fake provider is injected explicitly.
  if (config.nodeEnv === 'test' && config.gymProvider === 'auto') return null;

  if (config.gymProvider === 'google' || (config.gymProvider === 'auto' && config.googlePlacesApiKey)) {
    if (!config.googlePlacesApiKey) return null;
    return new GooglePlacesProvider(config.googlePlacesApiKey, config.gymProviderTimeoutMs);
  }
  return new OsmOverpassProvider(
    config.osmOverpassUrl,
    config.gymProviderTimeoutMs,
    config.gymProviderMinIntervalMs,
    config.osmTextSearch,
  );
}

export function providerStatus(config: Config, provider: GymProvider | null): ProviderStatus {
  if (provider) {
    return {
      configured: true,
      name: provider.name,
      reason: null,
      attribution: provider.name === 'google' ? 'Gym data from Google Places' : 'Gym data © OpenStreetMap contributors',
    };
  }
  if (config.gymProvider === 'google' && !config.googlePlacesApiKey) {
    return {
      configured: false,
      name: null,
      reason: 'GOOGLE_PLACES_API_KEY is not set on the backend, so worldwide gym lookup is unavailable.',
      attribution: null,
    };
  }
  return {
    configured: false,
    name: null,
    reason: 'No gym directory provider is configured. Forma still searches its own directory and requested gyms.',
    attribution: null,
  };
}
