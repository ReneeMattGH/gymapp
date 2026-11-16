import * as Notifications from 'expo-notifications';
import { Linking, Platform } from 'react-native';

import type { ReminderSettings, WorkoutPlan } from '@/data/types';
import { formatTimeOfDay } from '@/lib/date';

export const notificationsSupported = Platform.OS !== 'web';

export type PermissionState = 'granted' | 'denied' | 'undetermined' | 'unsupported';

const CHANNEL_ID = 'forma-reminders';

export function configureNotificationHandler() {
  if (!notificationsSupported) return;
  Notifications.setNotificationHandler({
    handleNotification: async () => ({
      shouldShowBanner: true,
      shouldShowList: true,
      shouldPlaySound: false,
      shouldSetBadge: false,
    }),
  });
}

export async function getPermissionState(): Promise<PermissionState> {
  if (!notificationsSupported) return 'unsupported';
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return 'granted';
  if (current.canAskAgain) return 'undetermined';
  return 'denied';
}

export async function requestPermission(): Promise<PermissionState> {
  if (!notificationsSupported) return 'unsupported';
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync(CHANNEL_ID, {
      name: 'Workout reminders',
      // Runtime enum is exported through a barrel; import/namespace cannot trace it.
      // eslint-disable-next-line import/namespace
      importance: Notifications.AndroidImportance.DEFAULT,
      vibrationPattern: [0, 200, 120, 200],
      lightColor: '#C7FA4F',
    });
  }
  const result = await Notifications.requestPermissionsAsync({
    ios: { allowAlert: true, allowBadge: false, allowSound: true },
  });
  if (result.granted) return 'granted';
  return result.canAskAgain ? 'undetermined' : 'denied';
}

export async function openSystemSettings(): Promise<void> {
  try {
    await Linking.openSettings();
  } catch {
    // Settings cannot be opened on this platform.
  }
}

function parseTime(time: string): { hour: number; minute: number } {
  const [hourText, minuteText] = time.split(':');
  const hour = Number(hourText);
  const minute = Number(minuteText);
  return {
    hour: Number.isFinite(hour) ? Math.max(0, Math.min(23, hour)) : 18,
    minute: Number.isFinite(minute) ? Math.max(0, Math.min(59, minute)) : 0,
  };
}

/** expo-notifications uses 1 = Sunday; the app uses ISO 1 = Monday. */
function expoWeekday(isoWeekday: number): number {
  return isoWeekday === 7 ? 1 : isoWeekday + 1;
}

export type ScheduleResult =
  | { ok: true; scheduledIds: string[]; count: number }
  | { ok: false; reason: 'unsupported' | 'denied' | 'error'; message: string };

async function scheduleWeekly(params: {
  weekday: number;
  hour: number;
  minute: number;
  title: string;
  body: string;
}): Promise<string> {
  return Notifications.scheduleNotificationAsync({
    content: {
      title: params.title,
      body: params.body,
      sound: false,
      data: { source: 'forma-reminder' },
    },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.WEEKLY,
      weekday: expoWeekday(params.weekday),
      hour: params.hour,
      minute: params.minute,
      channelId: CHANNEL_ID,
    },
  });
}

/**
 * Cancels every app reminder then schedules exactly what the settings describe.
 * Returns only ids that the OS actually accepted.
 */
export async function syncReminders(
  settings: ReminderSettings,
  plan: WorkoutPlan | null,
): Promise<ScheduleResult> {
  if (!notificationsSupported) {
    return {
      ok: false,
      reason: 'unsupported',
      message: 'Local reminders are only available in the iOS and Android app, not in the browser.',
    };
  }

  const permission = await getPermissionState();
  if (permission !== 'granted') {
    return {
      ok: false,
      reason: permission === 'denied' ? 'denied' : 'error',
      message:
        permission === 'denied'
          ? 'Notifications are turned off for Forma in your device settings.'
          : 'Notification permission has not been granted.',
    };
  }

  try {
    await cancelAllReminders();
    if (!settings.enabled) {
      return { ok: true, scheduledIds: [], count: 0 };
    }

    const { hour, minute } = parseTime(settings.workoutTime);
    const trainingDays = new Set(settings.days);
    const planDays = plan?.days ?? [];
    const ids: string[] = [];

    for (let weekday = 1; weekday <= 7; weekday += 1) {
      const planned = planDays.find((day) => day.weekday === weekday && !day.isRestDay);
      if (trainingDays.has(weekday)) {
        const title = planned ? `${planned.title} is ready` : 'Your workout is ready';
        const body = planned
          ? `${planned.exercises.length} exercises · about ${planned.estimatedMinutes} min. Open Forma when you're ready.`
          : 'Your planned workout is ready whenever you are.';
        ids.push(await scheduleWeekly({ weekday, hour, minute, title, body }));
      } else if (settings.restDayReminders) {
        ids.push(
          await scheduleWeekly({
            weekday,
            hour,
            minute,
            title: 'Recovery day',
            body:
              planned?.restNote ??
              'Take a moment to recover, walk gently, and prepare for your next session.',
          }),
        );
      }
    }

    if (settings.hydrationReminders) {
      for (const hydrationHour of [11, 16]) {
        ids.push(
          await Notifications.scheduleNotificationAsync({
            content: {
              title: 'Hydration check',
              body: 'A glass of water now is an easy win.',
              sound: false,
              data: { source: 'forma-reminder' },
            },
            trigger: {
              type: Notifications.SchedulableTriggerInputTypes.DAILY,
              hour: hydrationHour,
              minute: 0,
              channelId: CHANNEL_ID,
            },
          }),
        );
      }
    }

    if (settings.weeklyProgressReminder) {
      ids.push(
        await scheduleWeekly({
          weekday: 7,
          hour: 18,
          minute: 0,
          title: 'Your week in review',
          body: 'See what you completed and how your training is trending.',
        }),
      );
    }

    return { ok: true, scheduledIds: ids, count: ids.length };
  } catch (error) {
    // A failure mid-schedule can leave a partial set of reminders behind.
    // Remove everything we own so the saved settings never overstate reality.
    await cancelAllReminders().catch(() => {});
    return {
      ok: false,
      reason: 'error',
      message: error instanceof Error ? error.message : 'The reminders could not be scheduled.',
    };
  }
}

export async function cancelAllReminders(): Promise<void> {
  if (!notificationsSupported) return;
  const scheduled = await Notifications.getAllScheduledNotificationsAsync();
  const ours = scheduled.filter(
    (request) => (request.content.data as { source?: string } | null)?.source === 'forma-reminder',
  );
  await Promise.all(
    ours.map((request) => Notifications.cancelScheduledNotificationAsync(request.identifier)),
  );
}

export function reminderSummary(settings: ReminderSettings | null): string {
  if (!settings || !settings.enabled) return 'Reminders are off';
  const count = settings.days.length;
  return `${count} training day${count === 1 ? '' : 's'} · ${formatTimeOfDay(settings.workoutTime)}`;
}
