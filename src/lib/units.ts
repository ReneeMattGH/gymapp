import type { Preferences } from '@/data/types';

export function weightUnit(units: Preferences['units']): 'kg' | 'lb' {
  return units === 'lb' ? 'lb' : 'kg';
}

export function toDisplayWeight(kg: number, units: Preferences['units']): number {
  if (units === 'lb') return Math.round(kg * 2.20462 * 2) / 2;
  return Math.round(kg * 2) / 2;
}

export function toKg(value: number, units: Preferences['units']): number {
  if (units === 'lb') return Math.round((value / 2.20462) * 100) / 100;
  return Math.round(value * 100) / 100;
}

export function weightLabel(kg: number | null, units: Preferences['units']): string {
  if (kg === null || kg <= 0) return 'Bodyweight';
  return `${toDisplayWeight(kg, units)} ${weightUnit(units)}`;
}
