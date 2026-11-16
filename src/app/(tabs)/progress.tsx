import {
  addMonths,
  addWeeks,
  differenceInCalendarDays,
  format,
  parseISO,
  startOfMonth,
  subMonths,
  subWeeks,
} from 'date-fns';
import { useRouter } from 'expo-router';
import {
  CalendarCheck,
  Check,
  ChevronRight,
  Flame,
  Lock,
  Scale,
  Sparkles,
  TrendingUp,
} from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { ActivityHeatmap } from '@/components/charts/ActivityHeatmap';
import { TrendLine } from '@/components/charts/TrendLine';
import { WeeklyBars } from '@/components/charts/WeeklyBars';
import { Badge, EmptyState, InlineError, SectionHeader } from '@/components/ui/Misc';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { Input } from '@/components/ui/Input';
import { ProgressRing } from '@/components/ui/ProgressRing';
import { Screen } from '@/components/ui/Screen';
import { Sheet } from '@/components/ui/Sheet';
import { Text } from '@/components/ui/Text';
import type { WorkoutSession } from '@/data/types';
import {
  activeDayKeys,
  completedSessions,
  currentStreak,
  currentWeekCount,
  formatShortDate,
  minutesLabel,
  startOfWeekMonday,
} from '@/lib/date';
import { newId } from '@/lib/id';
import { toDisplayWeight, weightUnit } from '@/lib/units';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

type Range = 'weekly' | 'monthly';

function sessionVolumeKg(session: WorkoutSession): number {
  return session.sets.reduce((total, set) => {
    return total + (set.weightKg !== null ? set.weightKg * set.reps : 0);
  }, 0);
}

function longestStreak(keys: Set<string>): number {
  const days = [...keys].sort();
  let best = 0;
  let run = 0;
  let previous: Date | null = null;
  for (const key of days) {
    const date = parseISO(key);
    run = previous && differenceInCalendarDays(date, previous) === 1 ? run + 1 : 1;
    previous = date;
    best = Math.max(best, run);
  }
  return best;
}

export default function ProgressScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { sessions, preferences, progressRecords, addProgressRecord, user, dataLoading } = useApp();
  const [range, setRange] = useState<Range>('weekly');
  const [checkinOpen, setCheckinOpen] = useState(false);
  const [weightInput, setWeightInput] = useState('');
  const [noteInput, setNoteInput] = useState('');
  const [saving, setSaving] = useState(false);
  const [checkinError, setCheckinError] = useState<string | null>(null);

  const units = preferences?.units ?? 'kg';
  const unit = weightUnit(units);
  const weekTarget = Math.max(1, preferences?.workoutDays.length ?? 3);
  const today = useMemo(() => new Date(), []);
  const completed = useMemo(() => completedSessions(sessions), [sessions]);

  const weekCount = currentWeekCount(sessions, today);
  const weekSessions = useMemo(() => {
    const start = startOfWeekMonday(today);
    return completed.filter((session) => {
      const date = parseISO(session.startedAt);
      return date >= start && date <= today;
    });
  }, [completed, today]);
  const weekMinutes = Math.round(
    weekSessions.reduce((total, session) => total + session.durationSeconds, 0) / 60,
  );
  const weekSets = weekSessions.reduce((total, session) => total + session.sets.length, 0);
  const weekVolume = weekSessions.reduce((total, session) => total + sessionVolumeKg(session), 0);
  const streak = currentStreak(sessions, today);
  const longest = useMemo(() => longestStreak(activeDayKeys(sessions)), [sessions]);
  const avgMinutes = completed.length
    ? Math.round(completed.reduce((total, session) => total + session.durationSeconds, 0) / completed.length / 60)
    : 0;

  const windowWeeks = 4;
  const windowStart = subWeeks(startOfWeekMonday(today), windowWeeks - 1);
  const windowCount = completed.filter((session) => {
    const date = parseISO(session.startedAt);
    return date >= windowStart && date <= today;
  }).length;
  const consistency = Math.min(1, windowCount / (weekTarget * windowWeeks));

  const bars = useMemo(() => {
    if (range === 'weekly') {
      const currentStart = startOfWeekMonday(today);
      return Array.from({ length: 6 }, (_, index) => {
        const start = subWeeks(currentStart, 5 - index);
        const end = addWeeks(start, 1);
        const value = completed.filter((session) => {
          const date = parseISO(session.startedAt);
          return date >= start && date < end;
        }).length;
        return {
          label: format(start, 'd MMM'),
          value,
          target: weekTarget,
          highlight: index === 5,
        };
      });
    }
    const currentStart = startOfMonth(today);
    return Array.from({ length: 6 }, (_, index) => {
      const start = subMonths(currentStart, 5 - index);
      const end = addMonths(start, 1);
      const value = completed.filter((session) => {
        const date = parseISO(session.startedAt);
        return date >= start && date < end;
      }).length;
      return { label: format(start, 'MMM'), value, highlight: index === 5 };
    });
  }, [completed, range, today, weekTarget]);

  const volumeTrend = useMemo(() => {
    if (range === 'weekly') {
      const currentStart = startOfWeekMonday(today);
      return Array.from({ length: 6 }, (_, index) => {
        const start = subWeeks(currentStart, 5 - index);
        const end = addWeeks(start, 1);
        const value = completed
          .filter((session) => {
            const date = parseISO(session.startedAt);
            return date >= start && date < end;
          })
          .reduce((total, session) => total + sessionVolumeKg(session), 0);
        return { label: format(start, 'd MMM'), value: Math.round(toDisplayWeight(value, units)) };
      });
    }
    const currentStart = startOfMonth(today);
    return Array.from({ length: 6 }, (_, index) => {
      const start = subMonths(currentStart, 5 - index);
      const end = addMonths(start, 1);
      const value = completed
        .filter((session) => {
          const date = parseISO(session.startedAt);
          return date >= start && date < end;
        })
        .reduce((total, session) => total + sessionVolumeKg(session), 0);
      return { label: format(start, 'MMM'), value: Math.round(toDisplayWeight(value, units)) };
    });
  }, [completed, range, today, units]);

  const activeDays = useMemo(() => activeDayKeys(sessions), [sessions]);

  const milestones = useMemo(() => {
    const items = [
      { key: 'first', title: 'First session', detail: 'Complete your first workout', achieved: completed.length >= 1 },
      { key: 'ten', title: 'Ten sessions', detail: 'Ten workouts completed', achieved: completed.length >= 10 },
      { key: 'twentyfive', title: 'Twenty-five', detail: '25 workouts completed', achieved: completed.length >= 25 },
      { key: 'fifty', title: 'Fifty sessions', detail: '50 workouts completed', achieved: completed.length >= 50 },
      {
        key: 'consistency',
        title: 'Four-week consistency',
        detail: 'Reach 80% of planned sessions over four weeks',
        achieved: consistency >= 0.8 && windowCount > 0,
      },
      { key: 'streak', title: 'Seven-day streak', detail: 'Train on seven consecutive days', achieved: longest >= 7 },
    ];
    const next = items.find((item) => !item.achieved);
    return { achieved: items.filter((item) => item.achieved), next };
  }, [completed.length, consistency, longest, windowCount]);

  const history = completed.slice(0, 12);
  const latestCheckin = progressRecords[0] ?? null;

  const openCheckin = () => {
    const latestWeight = latestCheckin?.bodyweightKg;
    setWeightInput(
      latestWeight !== null && latestWeight !== undefined
        ? String(toDisplayWeight(latestWeight, units))
        : '',
    );
    setNoteInput('');
    setCheckinError(null);
    setCheckinOpen(true);
  };

  const saveCheckin = async () => {
    if (!user) return;
    const trimmed = weightInput.trim().replace(',', '.');
    const note = noteInput.trim();
    if (!trimmed && !note) {
      setCheckinError('Add a bodyweight, a note, or both.');
      return;
    }
    let bodyweightKg: number | null = null;
    if (trimmed) {
      const parsed = Number(trimmed);
      if (!Number.isFinite(parsed) || parsed <= 0) {
        setCheckinError(`Enter a valid bodyweight in ${unit}.`);
        return;
      }
      const kg = units === 'lb' ? parsed / 2.20462 : parsed;
      if (kg < 25 || kg > 350) {
        setCheckinError(`Enter a bodyweight between ${units === 'lb' ? 55 : 25} and ${units === 'lb' ? 770 : 350} ${unit}.`);
        return;
      }
      bodyweightKg = Math.round(kg * 10) / 10;
    }
    setSaving(true);
    setCheckinError(null);
    try {
      await addProgressRecord({
        id: newId('checkin'),
        userId: user.id,
        recordedAt: new Date().toISOString(),
        bodyweightKg,
        notes: note || null,
      });
      setCheckinOpen(false);
      setWeightInput('');
      setNoteInput('');
    } catch (error) {
      setCheckinError(error instanceof Error ? error.message : 'Could not save your check-in.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Screen scroll bottomInset={layout.tabBarHeight + 28}>
      <View style={styles.header}>
        <View>
          <Text variant="overline" color={colors.accentText}>
            Progress
          </Text>
          <Text variant="title" style={{ marginTop: 2 }}>
            The work, measured.
          </Text>
        </View>
        <View style={[styles.avatar, { backgroundColor: colors.surfaceRaised, borderColor: colors.border }]}>
          <TrendingUp size={18} color={colors.accentText} />
        </View>
      </View>

      <Card variant="accent" style={styles.hero}>
        <ProgressRing
          progress={weekCount / weekTarget}
          value={String(weekCount)}
          label={`of ${weekTarget}`}
          size={92}
        />
        <View style={styles.flex}>
          <Text variant="overline" color={colors.accentText}>
            This week
          </Text>
          <Text variant="subheading" style={{ marginTop: 3 }}>
            {weekCount >= weekTarget ? 'Target complete' : `${weekTarget - weekCount} session${weekTarget - weekCount === 1 ? '' : 's'} to go`}
          </Text>
          <Text variant="caption" style={{ marginTop: 4 }}>
            {weekMinutes} min · {weekSets} sets
            {weekVolume > 0 ? ` · ${Math.round(toDisplayWeight(weekVolume, units))} ${unit} volume` : ''}
          </Text>
        </View>
      </Card>

      {completed.length === 0 ? (
        <Card>
          <EmptyState
            icon={<CalendarCheck size={24} color={colors.accentText} />}
            title={dataLoading ? 'Loading your training' : 'No completed workouts yet'}
            message={
              dataLoading
                ? 'Reading your saved sessions…'
                : 'Finish a session and every chart here fills in from your recorded sets. Nothing is estimated or invented.'
            }
            action={<Button label="Go to workouts" onPress={() => router.push('/(tabs)/workouts')} />}
          />
        </Card>
      ) : (
        <>
          <View style={styles.statGrid}>
            <StatTile icon={<Flame size={16} color={colors.accentText} />} label="Current streak" value={`${streak}`} suffix={streak === 1 ? 'day' : 'days'} />
            <StatTile icon={<CalendarCheck size={16} color={colors.accentText} />} label="Completed" value={`${completed.length}`} suffix="sessions" />
            <StatTile icon={<TrendingUp size={16} color={colors.accentText} />} label="Longest streak" value={`${longest}`} suffix={longest === 1 ? 'day' : 'days'} />
            <StatTile icon={<Sparkles size={16} color={colors.accentText} />} label="Average session" value={`${avgMinutes}`} suffix="min" />
          </View>

          <View style={styles.section}>
            <SectionHeader title="Training load" caption="Completed sessions and weighted volume" />
            <View style={styles.chips}>
              <Chip label="Weekly" selected={range === 'weekly'} onPress={() => setRange('weekly')} />
              <Chip label="Monthly" selected={range === 'monthly'} onPress={() => setRange('monthly')} />
            </View>
            <Card>
              <Text variant="caption" style={styles.chartCaption}>
                {range === 'weekly' ? 'Sessions per week · target shown behind each bar' : 'Sessions per month'}
              </Text>
              <WeeklyBars data={bars} height={148} showValues />
              <View style={[styles.divider, { backgroundColor: colors.border }]} />
              <Text variant="caption" style={styles.chartCaption}>
                Weighted volume ({unit})
              </Text>
              {volumeTrend.some((point) => point.value > 0) ? (
                <TrendLine data={volumeTrend} suffix={` ${unit}`} />
              ) : (
                <Text variant="caption" color={colors.textTertiary}>
                  Log a weight with your sets to see volume trends. Bodyweight sets are not counted as volume.
                </Text>
              )}
            </Card>
          </View>

          <View style={styles.section}>
            <SectionHeader title="Consistency" caption={`${windowCount} of ${weekTarget * windowWeeks} planned sessions in the last ${windowWeeks} weeks`} />
            <Card>
              <View style={styles.consistencyRow}>
                <ProgressRing
                  progress={consistency}
                  size={70}
                  strokeWidth={6}
                  value={`${Math.round(consistency * 100)}%`}
                />
                <View style={styles.flex}>
                  <Text variant="bodyStrong">
                    {consistency >= 0.8 ? 'Strong rhythm' : consistency >= 0.5 ? 'Finding a rhythm' : 'Building the habit'}
                  </Text>
                  <Text variant="caption" style={{ marginTop: 3 }}>
                    {consistency >= 0.8
                      ? 'You are hitting your planned frequency. Keep sessions comfortable and repeatable.'
                      : `Your plan asks for ${weekTarget} sessions a week. Short sessions count — consistency beats intensity.`}
                  </Text>
                </View>
              </View>
              <View style={[styles.divider, { backgroundColor: colors.border }]} />
              <Text variant="caption" style={styles.chartCaption}>
                Last 14 weeks
              </Text>
              <ActivityHeatmap activeDays={activeDays} weeks={14} />
            </Card>
          </View>

          <View style={styles.section}>
            <SectionHeader title="Milestones" caption="Based on sessions you actually completed" />
            <Card padded={false}>
              {milestones.achieved.map((item) => (
                <View key={item.key} style={[styles.milestone, { borderColor: colors.border }]}>
                  <View style={[styles.milestoneIcon, { backgroundColor: colors.accentSoft }]}>
                    <Check size={15} color={colors.accentText} strokeWidth={2.6} />
                  </View>
                  <View style={styles.flex}>
                    <Text variant="bodyStrong">{item.title}</Text>
                    <Text variant="caption">{item.detail}</Text>
                  </View>
                  <Badge label="Done" tone="accent" />
                </View>
              ))}
              {milestones.next ? (
                <View style={[styles.milestone, { borderColor: colors.border }]}>
                  <View style={[styles.milestoneIcon, { backgroundColor: colors.surfaceRaised }]}>
                    <Lock size={14} color={colors.textTertiary} />
                  </View>
                  <View style={styles.flex}>
                    <Text variant="bodyStrong" color={colors.textSecondary}>
                      Next · {milestones.next.title}
                    </Text>
                    <Text variant="caption">{milestones.next.detail}</Text>
                  </View>
                </View>
              ) : (
                <View style={styles.milestone}>
                  <Text variant="caption">Every milestone on this list is complete. Set a new goal in your plan.</Text>
                </View>
              )}
            </Card>
          </View>

          <View style={styles.section}>
            <SectionHeader
              title="History"
              caption={`${completed.length} completed session${completed.length === 1 ? '' : 's'}`}
            />
            <View style={styles.historyList}>
              {history.map((session) => {
                const volume = sessionVolumeKg(session);
                return (
                  <Pressable
                    key={session.id}
                    accessibilityRole="button"
                    onPress={() => router.push({ pathname: '/progress/[id]', params: { id: session.id } })}
                    style={({ pressed }) => [
                      styles.historyRow,
                      {
                        backgroundColor: colors.surface,
                        borderColor: colors.border,
                        opacity: pressed ? 0.8 : 1,
                      },
                    ]}
                  >
                    <View style={[styles.historyDate, { backgroundColor: colors.surfaceRaised }]}>
                      <Text variant="overline" color={colors.accentText} style={{ fontSize: 9 }}>
                        {format(parseISO(session.startedAt), 'MMM').toUpperCase()}
                      </Text>
                      <Text variant="heading" style={{ fontSize: 17 }}>
                        {format(parseISO(session.startedAt), 'd')}
                      </Text>
                    </View>
                    <View style={styles.flex}>
                      <Text variant="bodyStrong" numberOfLines={1}>
                        {session.title}
                      </Text>
                      <Text variant="caption" style={{ marginTop: 2 }}>
                        {format(parseISO(session.startedAt), 'EEE')} · {minutesLabel(session.durationSeconds)} ·{' '}
                        {session.sets.length} sets
                        {volume > 0 ? ` · ${Math.round(toDisplayWeight(volume, units))} ${unit}` : ''}
                      </Text>
                    </View>
                    <ChevronRight size={17} color={colors.textTertiary} />
                  </Pressable>
                );
              })}
            </View>
            {completed.length > history.length ? (
              <Text variant="caption" color={colors.textTertiary}>
                Showing the 12 most recent sessions.
              </Text>
            ) : null}
          </View>
        </>
      )}

      <View style={styles.section}>
        <SectionHeader
          title="Check-in"
          caption="Bodyweight and notes you record yourself"
          actionLabel="Add check-in"
          onAction={openCheckin}
        />
        <Card>
          {progressRecords.length === 0 ? (
            <View style={styles.checkinEmpty}>
              <Scale size={20} color={colors.textTertiary} />
              <Text variant="caption" style={styles.flex}>
                No check-ins yet. Add one whenever you want a dated reference point — never estimated for you.
              </Text>
            </View>
          ) : (
            <View style={styles.checkinList}>
              {progressRecords.slice(0, 3).map((record, index) => (
                <View
                  key={record.id}
                  style={[
                    styles.checkinRow,
                    index > 0 ? { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border } : null,
                  ]}
                >
                  <View style={styles.flex}>
                    <Text variant="bodyStrong">
                      {record.bodyweightKg !== null
                        ? `${toDisplayWeight(record.bodyweightKg, units)} ${unit}`
                        : 'Note only'}
                    </Text>
                    {record.notes ? (
                      <Text variant="caption" numberOfLines={2} style={{ marginTop: 2 }}>
                        {record.notes}
                      </Text>
                    ) : null}
                  </View>
                  <Text variant="caption" color={colors.textTertiary}>
                    {formatShortDate(record.recordedAt)}
                  </Text>
                </View>
              ))}
            </View>
          )}
        </Card>
      </View>

      <Sheet
        visible={checkinOpen}
        onClose={() => {
          if (!saving) setCheckinOpen(false);
        }}
        title="New check-in"
        subtitle="Saved to your private progress records."
      >
        <Input
          label={`Bodyweight (${unit})`}
          value={weightInput}
          onChangeText={setWeightInput}
          keyboardType="decimal-pad"
          placeholder={unit === 'lb' ? 'e.g. 165' : 'e.g. 75'}
          hint={`Stored in kilograms${unit === 'lb' ? ', shown in pounds' : ''}.`}
        />
        <Input
          label="Notes"
          value={noteInput}
          onChangeText={setNoteInput}
          placeholder="Energy, sleep, measurements, anything useful"
          multiline
          maxLength={400}
        />
        {checkinError ? <InlineError message={checkinError} /> : null}
        <Button label="Save check-in" onPress={saveCheckin} loading={saving} fullWidth />
      </Sheet>
    </Screen>
  );
}

function StatTile({
  icon,
  label,
  value,
  suffix,
}: {
  icon: React.ReactNode;
  label: string;
  value: string;
  suffix: string;
}) {
  const { colors } = useTheme();
  return (
    <Card style={styles.statTile}>
      <View style={styles.statTop}>
        {icon}
        <Text variant="caption" color={colors.textTertiary} style={styles.statLabel}>
          {label}
        </Text>
      </View>
      <View style={styles.statValueRow}>
        <Text variant="number" style={{ fontSize: 26 }}>
          {value}
        </Text>
        <Text variant="caption" color={colors.textTertiary} style={{ marginBottom: 3 }}>
          {suffix}
        </Text>
      </View>
    </Card>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md },
  avatar: {
    width: 42,
    height: 42,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  hero: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  statGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.md },
  statTile: { flexBasis: '47%', flexGrow: 1, padding: spacing.md },
  statTop: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  statLabel: { fontSize: 10.5 },
  statValueRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 5, marginTop: spacing.sm },
  section: { gap: spacing.md },
  chips: { flexDirection: 'row', gap: spacing.sm },
  chartCaption: { marginBottom: spacing.sm },
  divider: { height: StyleSheet.hairlineWidth, marginVertical: spacing.lg },
  consistencyRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  milestone: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  milestoneIcon: {
    width: 30,
    height: 30,
    borderRadius: 10,
    alignItems: 'center',
    justifyContent: 'center',
  },
  historyList: { gap: spacing.sm },
  historyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.lg,
    padding: spacing.md,
  },
  historyDate: {
    width: 46,
    height: 50,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 1,
  },
  checkinEmpty: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  checkinList: { gap: spacing.sm },
  checkinRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
});
