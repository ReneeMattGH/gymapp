import {
  addDays,
  differenceInCalendarDays,
  format,
  isSameDay,
  parseISO,
  startOfWeek,
  subDays,
  subWeeks,
} from 'date-fns';

import type { WorkoutSession } from '@/data/types';

export function dateKey(date: Date = new Date()): string {
  return format(date, 'yyyy-MM-dd');
}

export function isoWeekday(date: Date = new Date()): number {
  const day = date.getDay();
  return day === 0 ? 7 : day;
}

export function greeting(date: Date = new Date()): string {
  const hour = date.getHours();
  if (hour < 5) return 'Late session';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

export function formatLongDate(date: Date = new Date()): string {
  return format(date, 'EEEE, d MMMM');
}

export function formatShortDate(date: Date | string): string {
  return format(typeof date === 'string' ? parseISO(date) : date, 'd MMM');
}

export function clock(seconds: number): string {
  const safe = Math.max(0, Math.floor(seconds));
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  const secs = safe % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
  }
  return `${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
}

export function minutesLabel(seconds: number): string {
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes} min`;
  const hours = Math.floor(minutes / 60);
  const rest = minutes % 60;
  return rest === 0 ? `${hours} hr` : `${hours} hr ${rest} min`;
}

export function timeLabel(seconds: number): string {
  return clock(seconds);
}

export function weekDates(reference: Date = new Date()): { weekday: number; date: Date; label: string }[] {
  const start = startOfWeek(reference, { weekStartsOn: 1 });
  return Array.from({ length: 7 }, (_, index) => {
    const date = addDays(start, index);
    return { weekday: index + 1, date, label: format(date, 'EEEEE') };
  });
}

export function startOfWeekMonday(reference: Date = new Date()): Date {
  return startOfWeek(reference, { weekStartsOn: 1 });
}

export function completedSessions(sessions: WorkoutSession[]): WorkoutSession[] {
  return sessions.filter((session) => session.status === 'completed' && session.endedAt);
}

export function sessionsOnDay(sessions: WorkoutSession[], date: Date): WorkoutSession[] {
  return completedSessions(sessions).filter((session) => isSameDay(parseISO(session.startedAt), date));
}

export function activeDayKeys(sessions: WorkoutSession[]): Set<string> {
  return new Set(completedSessions(sessions).map((session) => dateKey(parseISO(session.startedAt))));
}

export function currentWeekCount(sessions: WorkoutSession[], reference: Date = new Date()): number {
  const start = startOfWeekMonday(reference);
  return completedSessions(sessions).filter((session) => {
    const date = parseISO(session.startedAt);
    return date >= start && date <= reference;
  }).length;
}

export function lastWeeksCounts(
  sessions: WorkoutSession[],
  weeks: number,
  reference: Date = new Date(),
): { label: string; value: number; start: Date }[] {
  const currentStart = startOfWeekMonday(reference);
  return Array.from({ length: weeks }, (_, index) => {
    const start = subWeeks(currentStart, weeks - 1 - index);
    const end = addDays(start, 7);
    const value = completedSessions(sessions).filter((session) => {
      const date = parseISO(session.startedAt);
      return date >= start && date < end;
    }).length;
    return { label: format(start, 'd MMM'), value, start };
  });
}

/** Consecutive calendar days with a completed session, counting back from today or yesterday. */
export function currentStreak(sessions: WorkoutSession[], reference: Date = new Date()): number {
  const days = activeDayKeys(sessions);
  let day = reference;
  if (!days.has(dateKey(day))) {
    day = subDays(reference, 1);
    if (!days.has(dateKey(day))) return 0;
  }
  let streak = 0;
  while (days.has(dateKey(day))) {
    streak += 1;
    day = subDays(day, 1);
  }
  return streak;
}

export function daysSince(date: string | Date): number {
  return Math.max(0, differenceInCalendarDays(new Date(), typeof date === 'string' ? parseISO(date) : date));
}

export function formatTimeOfDay(time: string): string {
  const [hourText, minuteText] = time.split(':');
  const hour = Number(hourText);
  const minute = Number(minuteText);
  if (Number.isNaN(hour) || Number.isNaN(minute)) return time;
  const suffix = hour >= 12 ? 'PM' : 'AM';
  const display = hour % 12 === 0 ? 12 : hour % 12;
  return `${display}:${String(minute).padStart(2, '0')} ${suffix}`;
}

export function sumSetVolume(sets: { reps: number }[]): number {
  return sets.reduce((total, set) => total + set.reps, 0);
}
