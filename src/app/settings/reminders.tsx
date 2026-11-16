import { useRouter } from 'expo-router';
import {
  ArrowLeft,
  BellRing,
  CheckCircle2,
  Info,
  RefreshCw,
  Save,
  Settings2,
  TriangleAlert,
} from 'lucide-react-native';
import React, { useEffect, useState } from 'react';
import { Pressable, StyleSheet, Switch, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Badge, InlineError } from '@/components/ui/Misc';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { IconButton } from '@/components/ui/IconButton';
import { Input } from '@/components/ui/Input';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { WEEKDAY_LABEL } from '@/data/types';
import { formatTimeOfDay } from '@/lib/date';
import {
  cancelAllReminders,
  getPermissionState,
  notificationsSupported,
  openSystemSettings,
  requestPermission,
  syncReminders,
  type PermissionState,
} from '@/lib/notifications';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const DAYS = [1, 2, 3, 4, 5, 6, 7];
const TIME_PATTERN = /^([01]\d|2[0-3]):[0-5]\d$/;

export default function RemindersScreen() {
  return (
    <RequireOnboarded>
      <RemindersContent />
    </RequireOnboarded>
  );
}

function RemindersContent() {
  const { colors } = useTheme();
  const router = useRouter();
  const { user, preferences, plan, reminders, saveReminders } = useApp();

  const [enabled, setEnabled] = useState(reminders?.enabled ?? false);
  const [workoutTime, setWorkoutTime] = useState(
    reminders?.workoutTime ?? preferences?.reminderTime ?? '18:00',
  );
  const [days, setDays] = useState<number[]>(reminders?.days ?? preferences?.workoutDays ?? [1, 3, 5]);
  const [restDayReminders, setRestDayReminders] = useState(reminders?.restDayReminders ?? true);
  const [hydrationReminders, setHydrationReminders] = useState(reminders?.hydrationReminders ?? false);
  const [weeklyProgressReminder, setWeeklyProgressReminder] = useState(
    reminders?.weeklyProgressReminder ?? true,
  );
  const [scheduledCount, setScheduledCount] = useState(reminders?.scheduledIds.length ?? 0);
  const [permission, setPermission] = useState<PermissionState | 'loading'>('loading');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    getPermissionState()
      .then((state) => {
        if (active) setPermission(state);
      })
      .catch(() => {
        if (active) setPermission('unsupported');
      });
    return () => {
      active = false;
    };
  }, []);

  const refreshPermission = async () => {
    const state = await getPermissionState();
    setPermission(state);
    return state;
  };

  const toggleDay = (day: number) => {
    setSuccess(null);
    setDays((current) => {
      if (current.includes(day)) {
        if (current.length === 1) return current;
        return current.filter((item) => item !== day);
      }
      return [...current, day].sort((a, b) => a - b);
    });
  };

  const save = async () => {
    if (!user) return;
    if (!notificationsSupported) {
      setError('Local reminders are only available in the iOS and Android app.');
      return;
    }
    if (!TIME_PATTERN.test(workoutTime.trim())) {
      setError('Enter a time in 24-hour format, for example 18:00.');
      return;
    }
    if (days.length === 0) {
      setError('Choose at least one reminder day.');
      return;
    }

    setSaving(true);
    setError(null);
    setSuccess(null);
    try {
      if (!enabled) {
        await cancelAllReminders();
        await saveReminders({
          userId: user.id,
          enabled: false,
          workoutTime: workoutTime.trim(),
          days,
          restDayReminders,
          hydrationReminders,
          weeklyProgressReminder,
          scheduledIds: [],
        });
        setScheduledCount(0);
        setSuccess('Reminders are off. Forma removed its scheduled notifications from this device.');
        return;
      }

      let state = permission;
      if (state !== 'granted') {
        state = await requestPermission();
        setPermission(state);
      }
      if (state !== 'granted') {
        setError(
          state === 'denied'
            ? 'Notifications are turned off for Forma in device settings. Turn them on, then try again.'
            : 'Notification permission was not granted, so nothing was scheduled.',
        );
        return;
      }

      const result = await syncReminders(
        {
          userId: user.id,
          enabled: true,
          workoutTime: workoutTime.trim(),
          days,
          restDayReminders,
          hydrationReminders,
          weeklyProgressReminder,
          scheduledIds: [],
        },
        plan,
      );

      if (!result.ok) {
        await saveReminders({
          userId: user.id,
          enabled: false,
          workoutTime: workoutTime.trim(),
          days,
          restDayReminders,
          hydrationReminders,
          weeklyProgressReminder,
          scheduledIds: [],
        });
        setScheduledCount(0);
        setEnabled(false);
        setError(`${result.message} Nothing is scheduled.`);
        return;
      }

      await saveReminders({
        userId: user.id,
        enabled: result.count > 0,
        workoutTime: workoutTime.trim(),
        days,
        restDayReminders,
        hydrationReminders,
        weeklyProgressReminder,
        scheduledIds: result.scheduledIds,
      });
      setScheduledCount(result.count);
      if (result.count === 0) {
        setEnabled(false);
        setError('No reminders were scheduled. Check your selected days and try again.');
      } else {
        setSuccess(
          `${result.count} local reminder${result.count === 1 ? '' : 's'} scheduled on this device. The operating system delivers them; Forma cannot guarantee delivery after the app is closed.`,
        );
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not update your reminders.');
    } finally {
      setSaving(false);
    }
  };

  if (!notificationsSupported) {
    return (
      <Screen scroll contentContainerStyle={styles.content}>
        <View style={styles.header}>
          <IconButton accessibilityLabel="Go back" onPress={() => router.back()} size={38}>
            <ArrowLeft size={17} color={colors.text} />
          </IconButton>
          <View style={styles.flex}>
            <Text variant="overline" color={colors.textTertiary}>
              Settings
            </Text>
          </View>
        </View>
        <View>
          <Text variant="title">Reminders</Text>
          <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
            Local workout reminders, scheduled by your device.
          </Text>
        </View>
        <Card style={{ backgroundColor: colors.warningSoft }}>
          <View style={styles.warningRow}>
            <TriangleAlert size={20} color={colors.warning} />
            <View style={styles.flex}>
              <Text variant="bodyStrong" color={colors.warning}>
                Not available in the browser
              </Text>
              <Text variant="caption" color={colors.warning} style={{ marginTop: 4 }}>
                Browsers in this build cannot schedule system notifications, so Forma does not pretend to.
                Install the iOS or Android app to turn on real local reminders.
              </Text>
            </View>
          </View>
        </Card>
        <Pressable
          accessibilityRole="button"
          onPress={() => router.back()}
          style={({ pressed }) => [
            styles.secondary,
            { borderColor: colors.border, opacity: pressed ? 0.8 : 1 },
          ]}
        >
          <Text variant="label">Back to profile</Text>
        </Pressable>
      </Screen>
    );
  }

  return (
    <Screen scroll contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <IconButton accessibilityLabel="Go back" onPress={() => router.back()} size={38}>
          <ArrowLeft size={17} color={colors.text} />
        </IconButton>
        <View style={styles.flex}>
          <Text variant="overline" color={colors.textTertiary}>
            Settings
          </Text>
        </View>
        <Badge
          label={
            permission === 'granted'
              ? 'Permission granted'
              : permission === 'denied'
                ? 'Permission off'
                : permission === 'loading'
                  ? 'Checking…'
                  : 'Not requested'
          }
          tone={permission === 'granted' ? 'accent' : permission === 'denied' ? 'warning' : 'neutral'}
        />
      </View>

      <View>
        <Text variant="title">Reminders</Text>
        <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
          Local notifications on this device. Nothing is sent from a server.
        </Text>
      </View>

      {permission === 'denied' ? (
        <Card style={{ backgroundColor: colors.warningSoft }}>
          <View style={styles.warningRow}>
            <TriangleAlert size={18} color={colors.warning} />
            <View style={styles.flex}>
              <Text variant="caption" color={colors.warning}>
                Notifications are blocked for Forma. Enable them in your device settings before scheduling.
              </Text>
            </View>
          </View>
          <Pressable
            accessibilityRole="button"
            onPress={openSystemSettings}
            style={({ pressed }) => [
              styles.linkButton,
              { borderColor: colors.warning, opacity: pressed ? 0.75 : 1 },
            ]}
          >
            <Settings2 size={14} color={colors.warning} />
            <Text variant="label" color={colors.warning}>
              Open device settings
            </Text>
          </Pressable>
        </Card>
      ) : null}

      <Card>
        <View style={styles.switchRow}>
          <View style={[styles.switchIcon, { backgroundColor: colors.accentSoft }]}>
            <BellRing size={18} color={colors.accentText} />
          </View>
          <View style={styles.flex}>
            <Text variant="bodyStrong">Workout reminders</Text>
            <Text variant="caption" style={{ marginTop: 2 }}>
              {scheduledCount > 0
                ? `${scheduledCount} reminder${scheduledCount === 1 ? '' : 's'} last saved`
                : 'No reminders scheduled yet'}
            </Text>
          </View>
          <Switch
            value={enabled}
            onValueChange={(value) => {
              setEnabled(value);
              setSuccess(null);
              setError(null);
            }}
            trackColor={{ false: colors.surfaceRaised, true: colors.accentBorder }}
            thumbColor={enabled ? colors.accent : colors.textTertiary}
            accessibilityLabel="Workout reminders"
          />
        </View>

        <View style={[styles.divider, { backgroundColor: colors.border }]} />

        <View style={styles.fieldGroup}>
          <Text variant="label" color={colors.textSecondary}>
            Reminder time
          </Text>
          <Input
            value={workoutTime}
            onChangeText={(value) => {
              setWorkoutTime(value);
              setSuccess(null);
            }}
            keyboardType="numbers-and-punctuation"
            placeholder="18:00"
            maxLength={5}
            hint={`24-hour time. Currently ${TIME_PATTERN.test(workoutTime) ? formatTimeOfDay(workoutTime) : 'invalid'}.`}
          />
        </View>

        <View style={styles.fieldGroup}>
          <Text variant="label" color={colors.textSecondary}>
            Days
          </Text>
          <View style={styles.chipWrap}>
            {DAYS.map((day) => (
              <Chip
                key={day}
                label={WEEKDAY_LABEL[day]}
                selected={days.includes(day)}
                onPress={() => toggleDay(day)}
                disabled={!enabled}
              />
            ))}
          </View>
        </View>

        <SwitchRow
          title="Rest-day reminders"
          subtitle="A recovery nudge on days you are not training."
          value={restDayReminders}
          onValueChange={(value) => {
            setRestDayReminders(value);
            setSuccess(null);
          }}
          disabled={!enabled}
        />
        <SwitchRow
          title="Hydration reminders"
          subtitle="Two gentle prompts at 11:00 and 16:00."
          value={hydrationReminders}
          onValueChange={(value) => {
            setHydrationReminders(value);
            setSuccess(null);
          }}
          disabled={!enabled}
        />
        <SwitchRow
          title="Weekly review"
          subtitle="Sunday at 18:00, based on your completed sessions."
          value={weeklyProgressReminder}
          onValueChange={(value) => {
            setWeeklyProgressReminder(value);
            setSuccess(null);
          }}
          disabled={!enabled}
          last
        />
      </Card>

      {error ? <InlineError message={error} /> : null}
      {success ? (
        <Card style={{ backgroundColor: colors.accentSoft }}>
          <View style={styles.warningRow}>
            <CheckCircle2 size={17} color={colors.accentText} />
            <Text variant="caption" color={colors.accentText} style={styles.flex}>
              {success}
            </Text>
          </View>
        </Card>
      ) : null}

      <Pressable
        accessibilityRole="button"
        onPress={save}
        disabled={saving}
        style={({ pressed }) => [
          styles.primary,
          { backgroundColor: colors.accent, opacity: saving ? 0.6 : pressed ? 0.85 : 1 },
        ]}
      >
        {enabled ? <RefreshCw size={16} color={colors.accentInk} /> : <Save size={16} color={colors.accentInk} />}
        <Text variant="label" color={colors.accentInk}>
          {saving ? 'Updating…' : enabled ? 'Save & schedule' : 'Save and turn off'}
        </Text>
      </Pressable>

      <Pressable
        accessibilityRole="button"
        onPress={() => void refreshPermission()}
        style={({ pressed }) => [styles.secondary, { borderColor: colors.border, opacity: pressed ? 0.8 : 1 }]}
      >
        <Text variant="label">Check permission again</Text>
      </Pressable>

      <View style={styles.note}>
        <Info size={14} color={colors.textTertiary} />
        <Text variant="caption" color={colors.textTertiary} style={styles.flex}>
          Saving replaces every Forma reminder previously scheduled. The system may delay notifications in
          low-power mode. Forma only records what the operating system accepted.
        </Text>
      </View>
    </Screen>
  );
}

function SwitchRow({
  title,
  subtitle,
  value,
  onValueChange,
  disabled,
  last,
}: {
  title: string;
  subtitle: string;
  value: boolean;
  onValueChange: (value: boolean) => void;
  disabled?: boolean;
  last?: boolean;
}) {
  const { colors } = useTheme();
  return (
    <View
      style={[
        styles.switchRow,
        { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border },
        last ? { paddingBottom: 0 } : null,
        disabled ? { opacity: 0.5 } : null,
      ]}
    >
      <View style={styles.flex}>
        <Text variant="bodyStrong">{title}</Text>
        <Text variant="caption" style={{ marginTop: 2 }}>
          {subtitle}
        </Text>
      </View>
      <Switch
        value={value}
        onValueChange={onValueChange}
        disabled={disabled}
        trackColor={{ false: colors.surfaceRaised, true: colors.accentBorder }}
        thumbColor={value ? colors.accent : colors.textTertiary}
        accessibilityLabel={title}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { gap: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  switchRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.md },
  switchIcon: {
    width: 40,
    height: 40,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  divider: { height: StyleSheet.hairlineWidth, marginBottom: spacing.md },
  fieldGroup: { gap: spacing.sm, marginTop: spacing.md },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  warningRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  linkButton: {
    marginTop: spacing.md,
    height: 40,
    borderRadius: radii.sm,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 6,
  },
  primary: {
    height: 52,
    borderRadius: radii.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  secondary: {
    height: 46,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  note: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
});
