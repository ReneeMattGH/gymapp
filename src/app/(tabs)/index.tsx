import { isSameDay } from 'date-fns';
import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import {
  ArrowUpRight,
  BookOpen,
  Check,
  ChevronRight,
  Clock,
  Dumbbell,
  Flame,
  Heart,
  ListChecks,
  Play,
  Sparkles,
  Target,
  TrendingUp,
} from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { ExerciseArt } from '@/components/ui/ExerciseArt';
import { FadeIn } from '@/components/ui/FadeIn';
import { Badge, InlineError } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { Wordmark } from '@/components/ui/Brand';
import { CoachNote } from '@/features/home/CoachNote';
import { MUSCLE_LABEL, WEEKDAY_LABEL } from '@/data/types';
import {
  clock,
  completedSessions,
  currentStreak,
  currentWeekCount,
  formatLongDate,
  greeting,
  sessionsOnDay,
  weekDates,
} from '@/lib/date';
import { nextTrainingDay, planForDate } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useWorkout } from '@/state/WorkoutProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

const QUICK_ACTIONS = [
  {
    key: 'coach',
    label: 'Ask AI coach',
    caption: 'Form, swaps, recovery',
    icon: Sparkles,
    href: '/(tabs)/coach',
  },
  {
    key: 'plan',
    label: 'Workout plan',
    caption: 'Your weekly split',
    icon: Dumbbell,
    href: '/(tabs)/workouts',
  },
  {
    key: 'library',
    label: 'Exercise library',
    caption: '60 guided movements',
    icon: BookOpen,
    href: '/exercise',
  },
  {
    key: 'progress',
    label: 'Progress',
    caption: 'Trends and history',
    icon: TrendingUp,
    href: '/(tabs)/progress',
  },
  {
    key: 'recovery',
    label: 'Recovery',
    caption: 'Rest and mobility',
    icon: Heart,
    href: '/recovery',
  },
  {
    key: 'profile',
    label: 'Preferences',
    caption: 'Training and reminders',
    icon: Target,
    href: '/(tabs)/profile',
  },
] as const;

export default function HomeScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { profile, preferences, plan, sessions, previewMode } = useApp();
  const { active, elapsedSeconds, startWorkout } = useWorkout();
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const today = useMemo(() => new Date(), []);
  const todayPlan = plan ? planForDate(plan, today) : undefined;
  const todaysCompleted = useMemo(
    () =>
      sessionsOnDay(sessions, today).filter(
        (session) => !todayPlan || session.planDayId === todayPlan.id,
      ),
    [sessions, today, todayPlan],
  );
  const completedToday = todaysCompleted.length > 0;
  const nextDay = plan ? nextTrainingDay(plan, today) : undefined;
  const completed = completedSessions(sessions);
  const weekCount = currentWeekCount(sessions);
  const streak = currentStreak(sessions);
  const weekTarget = plan
    ? plan.days.filter((day) => !day.isRestDay).length
    : preferences?.workoutDays.length ?? 0;
  const week = weekDates(today);

  const firstName = profile?.name.trim().split(/\s+/)[0] || 'there';
  const greetingText = greeting(today);

  const handleStart = async () => {
    setError(null);
    if (active) {
      router.push('/workout/active');
      return;
    }
    if (!plan || !todayPlan || todayPlan.isRestDay) return;
    setStarting(true);
    try {
      await startWorkout(todayPlan, plan);
      router.push('/workout/active');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start the workout.');
    } finally {
      setStarting(false);
    }
  };

  const initials = (profile?.name ?? '')
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? '')
    .join('');

  return (
    <Screen scroll bottomInset={layout.tabBarHeight + 32} contentContainerStyle={styles.content}>
      <FadeIn>
        <View style={styles.topRow}>
          <Wordmark compact />
          <View style={styles.topActions}>
            {previewMode ? <Badge label="Preview" tone="accent" /> : null}
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Open profile"
              onPress={() => router.push('/(tabs)/profile')}
              style={({ pressed }) => [
                styles.avatar,
                {
                  backgroundColor: colors.surfaceRaised,
                  borderColor: colors.border,
                  opacity: pressed ? 0.7 : 1,
                },
              ]}
            >
              <Text variant="label" color={colors.accentText}>
                {initials || 'F'}
              </Text>
            </Pressable>
          </View>
        </View>
      </FadeIn>

      <FadeIn delay={60}>
        <View style={styles.greeting}>
          <Text variant="overline" color={colors.textTertiary}>
            {formatLongDate(today)}
          </Text>
          <Text variant="title" style={styles.greetingTitle}>
            {greetingText}, {firstName}.
          </Text>
          <Text variant="body" color={colors.textSecondary}>
            {completedToday
              ? 'Session logged. Recovery starts now — hydrate and refuel.'
              : todayPlan?.isRestDay
                ? 'A planned recovery day. Keep it easy and let your training settle.'
                : todayPlan
                  ? 'Your session is ready when you are. Start with the warm-up.'
                  : 'Set up your training plan to get a personalised daily session.'}
          </Text>
        </View>
      </FadeIn>

      {error ? <InlineError message={error} /> : null}

      <FadeIn delay={120}>
        {active ? (
          <Card padded={false} style={styles.heroCard}>
            <LinearGradient
              colors={[colors.accentSoft, 'transparent']}
              start={{ x: 1, y: 0 }}
              end={{ x: 0, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <View style={styles.heroBody}>
              <View style={styles.heroTopRow}>
                <Badge label={active.status === 'paused' ? 'Paused' : 'Session in progress'} tone="accent" />
                <Text variant="caption" color={colors.textSecondary}>
                  {clock(elapsedSeconds)} elapsed
                </Text>
              </View>
              <Text variant="heading" style={styles.heroTitle}>
                {active.title}
              </Text>
              <Text variant="body" color={colors.textSecondary}>
                {active.sets.length} set{active.sets.length === 1 ? '' : 's'} logged ·{' '}
                {active.exercises.length} exercise{active.exercises.length === 1 ? '' : 's'} planned
              </Text>
              <Button
                label="Resume workout"
                icon={<Play size={17} color={colors.accentInk} fill={colors.accentInk} />}
                onPress={() => router.push('/workout/active')}
                fullWidth
              />
            </View>
          </Card>
        ) : completedToday ? (
          <Card padded={false} style={styles.heroCard}>
            <LinearGradient
              colors={[colors.accentSoft, 'transparent']}
              start={{ x: 1, y: 0 }}
              end={{ x: 0, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <View style={styles.heroBody}>
              <View style={styles.heroTopRow}>
                <Badge label="Completed today" tone="accent" icon={<Check size={11} color={colors.accentText} />} />
                <Text variant="caption" color={colors.textSecondary}>
                  {todaysCompleted.length} session{todaysCompleted.length === 1 ? '' : 's'}
                </Text>
              </View>
              <Text variant="heading" style={styles.heroTitle}>
                {todaysCompleted[0].title}
              </Text>
              <View style={styles.completedMeta}>
                <View style={styles.metaItem}>
                  <Clock size={14} color={colors.textTertiary} />
                  <Text variant="caption">{Math.round(todaysCompleted[0].durationSeconds / 60)} min</Text>
                </View>
                <View style={styles.metaItem}>
                  <ListChecks size={14} color={colors.textTertiary} />
                  <Text variant="caption">{todaysCompleted[0].sets.length} sets</Text>
                </View>
              </View>
              <Text variant="body" color={colors.textSecondary}>
                Nice work. The best next step is recovery — a short walk, water, and an early night.
              </Text>
            </View>
          </Card>
        ) : !plan ? (
          <Card padded={false} style={styles.heroCard}>
            <LinearGradient
              colors={[colors.accentSoft, 'transparent']}
              start={{ x: 1, y: 0 }}
              end={{ x: 0, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <View style={styles.heroBody}>
              <Badge label="Get started" tone="accent" />
              <Text variant="heading" style={styles.heroTitle}>
                Build your training plan
              </Text>
              <Text variant="body" color={colors.textSecondary}>
                Generate a weekly plan around your experience, equipment, schedule, and goals.
              </Text>
              <Button
                label="Create my plan"
                icon={<Sparkles size={17} color={colors.accentInk} />}
                onPress={() => router.push('/plan/generate')}
                fullWidth
              />
            </View>
          </Card>
        ) : todayPlan?.isRestDay ? (
          <Card padded={false} style={styles.heroCard}>
            <View style={styles.recoveryRow}>
              <ExerciseArt muscle="mobility" category="mobility" height={128} compact style={styles.recoveryArt} />
              <View style={styles.recoveryBody}>
                <Badge label="Recovery day" />
                <Text variant="heading" style={{ marginTop: spacing.sm }}>
                  Let your body adapt
                </Text>
                <Text variant="body" color={colors.textSecondary} numberOfLines={4}>
                  {todayPlan.restNote ?? 'Keep today light. Rest is part of the plan.'}
                </Text>
              </View>
            </View>
            <View style={styles.heroBody}>
              <View style={styles.buttonRow}>
                <Button
                  label="Recovery ideas"
                  variant="secondary"
                  size="md"
                  onPress={() => router.push('/recovery')}
                  style={styles.flexButton}
                />
                {nextDay ? (
                  <Button
                    label={`Next: ${WEEKDAY_LABEL[nextDay.weekday ?? 1]}`}
                    variant="ghost"
                    size="md"
                    onPress={() => router.push('/(tabs)/workouts')}
                    style={styles.flexButton}
                  />
                ) : null}
              </View>
            </View>
          </Card>
        ) : todayPlan ? (
          <Card padded={false} style={styles.heroCard}>
            <LinearGradient
              colors={[colors.accentSoft, 'transparent']}
              start={{ x: 1, y: 0 }}
              end={{ x: 0, y: 1 }}
              style={StyleSheet.absoluteFill}
            />
            <View style={styles.heroBody}>
              <View style={styles.heroTopRow}>
                <Badge label="Today's session" tone="accent" />
                <Text variant="caption" color={colors.textSecondary}>
                  ~{todayPlan.estimatedMinutes} min
                </Text>
              </View>
              <Text variant="heading" style={styles.heroTitle}>
                {todayPlan.title}
              </Text>
              <Text variant="body" color={colors.textSecondary}>
                {todayPlan.focus.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')}
              </Text>
              <View style={styles.heroMeta}>
                <View style={styles.metaItem}>
                  <Dumbbell size={14} color={colors.textTertiary} />
                  <Text variant="caption">
                    {todayPlan.exercises.length} exercise{todayPlan.exercises.length === 1 ? '' : 's'}
                  </Text>
                </View>
                <View style={styles.metaItem}>
                  <ListChecks size={14} color={colors.textTertiary} />
                  <Text variant="caption">
                    {todayPlan.exercises.reduce((total, row) => total + row.sets, 0)} sets
                  </Text>
                </View>
                <View style={styles.metaItem}>
                  <Clock size={14} color={colors.textTertiary} />
                  <Text variant="caption">{todayPlan.estimatedMinutes} min</Text>
                </View>
              </View>
              <Button
                label={starting ? 'Preparing session…' : 'Start workout'}
                loading={starting}
                icon={<Play size={17} color={colors.accentInk} fill={colors.accentInk} />}
                onPress={handleStart}
                fullWidth
              />
            </View>
          </Card>
        ) : null}
      </FadeIn>

      <FadeIn delay={180}>
        <Card style={styles.weekCard}>
          <View style={styles.weekHeader}>
            <View>
              <Text variant="heading">This week</Text>
              <Text variant="caption" style={{ marginTop: 2 }}>
                {weekTarget > 0
                  ? `${weekCount} of ${weekTarget} planned sessions`
                  : 'No training days scheduled'}
              </Text>
            </View>
            <Pressable
              onPress={() => router.push('/(tabs)/progress')}
              accessibilityRole="button"
              style={({ pressed }) => [styles.link, { opacity: pressed ? 0.6 : 1 }]}
            >
              <Text variant="label" color={colors.accentText}>
                Progress
              </Text>
              <ChevronRight size={14} color={colors.accentText} />
            </Pressable>
          </View>

          <View style={styles.weekStrip}>
            {week.map(({ weekday, date, label }) => {
              const dayPlan = plan ? planForDate(plan, date) : undefined;
              const isToday = isSameDay(date, today);
              const isDone = sessionsOnDay(sessions, date).length > 0;
              const isPlanned = Boolean(dayPlan && !dayPlan.isRestDay);
              const isFuture = date > today;

              return (
                <View key={weekday} style={styles.dayColumn}>
                  <Text
                    variant="caption"
                    color={isToday ? colors.accentText : colors.textTertiary}
                    style={styles.dayLabel}
                  >
                    {label}
                  </Text>
                  <View
                    style={[
                      styles.dayCell,
                      {
                        backgroundColor: isDone
                          ? colors.accent
                          : isPlanned
                            ? colors.accentSoft
                            : colors.surfaceRaised,
                        borderColor: isDone
                          ? colors.accent
                          : isToday
                            ? colors.accentBorder
                            : isPlanned
                              ? colors.accentBorder
                              : colors.border,
                        opacity: isDone ? 1 : isFuture || isPlanned || isToday ? 1 : 0.55,
                      },
                    ]}
                  >
                    {isDone ? (
                      <Check size={14} color={colors.accentInk} strokeWidth={3} />
                    ) : (
                      <Text
                        variant="caption"
                        color={isPlanned ? colors.accentText : colors.textTertiary}
                        style={styles.dayNumber}
                      >
                        {date.getDate()}
                      </Text>
                    )}
                  </View>
                  <View
                    style={[
                      styles.todayDot,
                      { backgroundColor: isToday ? colors.accent : 'transparent' },
                    ]}
                  />
                </View>
              );
            })}
          </View>

          <View style={[styles.weekFooter, { borderTopColor: colors.border }]}>
            <View style={styles.stat}>
              <Text variant="number">{weekCount}</Text>
              <Text variant="caption" color={colors.textTertiary}>
                Week sessions
              </Text>
            </View>
            <View style={[styles.statDivider, { backgroundColor: colors.border }]} />
            <View style={styles.stat}>
              <View style={styles.statValueRow}>
                <Flame size={16} color={streak > 0 ? colors.accent : colors.textTertiary} />
                <Text variant="number">{streak}</Text>
              </View>
              <Text variant="caption" color={colors.textTertiary}>
                Day streak
              </Text>
            </View>
            <View style={[styles.statDivider, { backgroundColor: colors.border }]} />
            <View style={styles.stat}>
              <Text variant="number">{completed.length}</Text>
              <Text variant="caption" color={colors.textTertiary}>
                Total sessions
              </Text>
            </View>
          </View>
        </Card>
      </FadeIn>

      <FadeIn delay={240}>
        <CoachNote />
      </FadeIn>

      <FadeIn delay={300}>
        <View style={styles.quickHeader}>
          <Text variant="heading">Quick actions</Text>
        </View>
        <View style={styles.quickGrid}>
          {QUICK_ACTIONS.map((action) => {
            const Icon = action.icon;
            return (
              <Pressable
                key={action.key}
                accessibilityRole="button"
                accessibilityLabel={action.label}
                onPress={() => {
                  if (action.key === 'progress') {
                    router.push('/(tabs)/progress');
                  } else {
                    router.push(action.href);
                  }
                }}
                style={({ pressed }) => [
                  styles.quickTile,
                  {
                    backgroundColor: colors.surface,
                    borderColor: colors.border,
                    opacity: pressed ? 0.8 : 1,
                  },
                ]}
              >
                <View style={[styles.quickIcon, { backgroundColor: colors.surfaceRaised }]}>
                  <Icon size={17} color={colors.accentText} strokeWidth={2} />
                </View>
                <View style={styles.quickText}>
                  <Text variant="label" style={styles.quickLabel}>
                    {action.label}
                  </Text>
                  <Text variant="caption" color={colors.textTertiary} numberOfLines={1}>
                    {action.caption}
                  </Text>
                </View>
                <ArrowUpRight size={14} color={colors.textTertiary} />
              </Pressable>
            );
          })}
        </View>
      </FadeIn>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { gap: spacing.xl },
  topRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  topActions: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  avatar: {
    width: 38,
    height: 38,
    borderRadius: 19,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  greeting: { gap: 4 },
  greetingTitle: { marginTop: 2 },
  heroCard: { overflow: 'hidden' },
  heroBody: { padding: spacing.lg, gap: spacing.md },
  heroTopRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  heroTitle: { marginTop: -2 },
  heroMeta: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.lg },
  metaItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  completedMeta: { flexDirection: 'row', gap: spacing.lg, marginTop: -4 },
  buttonRow: { flexDirection: 'row', gap: spacing.sm },
  flexButton: { flex: 1 },
  recoveryRow: { flexDirection: 'row', gap: spacing.md, alignItems: 'center' },
  recoveryArt: { width: 118, borderRadius: 0 },
  recoveryBody: { flex: 1, paddingVertical: spacing.lg, paddingRight: spacing.lg, gap: 2 },
  weekCard: { gap: spacing.lg },
  weekHeader: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between' },
  link: { flexDirection: 'row', alignItems: 'center', gap: 2, paddingTop: 3 },
  weekStrip: { flexDirection: 'row', gap: spacing.xs },
  dayColumn: { flex: 1, alignItems: 'center', gap: 7 },
  dayLabel: { fontSize: 10.5, letterSpacing: 0.6 },
  dayCell: {
    width: '100%',
    aspectRatio: 1,
    maxWidth: 42,
    borderRadius: 13,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayNumber: { fontSize: 12, fontFamily: 'Inter_600SemiBold' },
  todayDot: { width: 4, height: 4, borderRadius: 2 },
  weekFooter: {
    flexDirection: 'row',
    alignItems: 'center',
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingTop: spacing.md,
  },
  stat: { flex: 1, alignItems: 'center', gap: 1 },
  statValueRow: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  statDivider: { width: StyleSheet.hairlineWidth, height: 26 },
  quickHeader: { marginBottom: spacing.md },
  quickGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  quickTile: {
    width: '48.5%',
    flexGrow: 1,
    flexBasis: 150,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    padding: spacing.md,
    borderRadius: radii.lg,
    borderWidth: StyleSheet.hairlineWidth,
  },
  quickIcon: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  quickText: { flex: 1, gap: 1 },
  quickLabel: { fontFamily: 'Inter_600SemiBold' },
});
