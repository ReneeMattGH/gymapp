import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import {
  BookOpen,
  ChevronDown,
  Clock,
  Dumbbell,
  Heart,
  Moon,
  Play,
  Plus,
  Sparkles,
  Users,
} from 'lucide-react-native';
import React, { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { FadeIn } from '@/components/ui/FadeIn';
import { IconButton } from '@/components/ui/IconButton';
import { Badge, Divider, EmptyState, InlineError, SectionHeader } from '@/components/ui/Misc';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import {
  EQUIPMENT_LABEL,
  GOAL_LABEL,
  MUSCLE_LABEL,
  WEEKDAY_LABEL,
  type WorkoutDay,
} from '@/data/types';
import { clock } from '@/lib/date';
import { exerciseName } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useWorkout } from '@/state/WorkoutProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

export default function WorkoutsScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { profile, preferences, plan, dataLoading } = useApp();
  const { active, elapsedSeconds, startWorkout } = useWorkout();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [starting, setStarting] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const todayWeekday = new Date().getDay() === 0 ? 7 : new Date().getDay();
  const days = plan ? [...plan.days].sort((a, b) => (a.weekday ?? 0) - (b.weekday ?? 0)) : [];

  const handleStart = async (day: WorkoutDay) => {
    if (!plan || day.isRestDay) return;
    setError(null);
    if (active) {
      router.push('/workout/active');
      return;
    }
    setStarting(day.id);
    try {
      await startWorkout(day, plan);
      router.push('/workout/active');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start the workout.');
    } finally {
      setStarting(null);
    }
  };

  return (
    <Screen scroll bottomInset={layout.tabBarHeight + 32} contentContainerStyle={styles.content}>
      <FadeIn>
        <View style={styles.headerRow}>
          <View style={styles.flex}>
            <Text variant="title">Training</Text>
            <Text variant="caption" style={{ marginTop: 2 }}>
              {plan
                ? `${plan.name} · ${plan.daysPerWeek} day${plan.daysPerWeek === 1 ? '' : 's'} per week`
                : 'Build a plan around your week'}
            </Text>
          </View>
          <IconButton accessibilityLabel="Generate a new plan" onPress={() => router.push('/plan/generate')}>
            <Plus size={19} color={colors.text} strokeWidth={2.2} />
          </IconButton>
        </View>
      </FadeIn>

      {error ? <InlineError message={error} /> : null}

      {active ? (
        <FadeIn delay={40}>
          <Card padded={false} style={styles.resumeCard} onPress={() => router.push('/workout/active')}>
            <View style={styles.resumeBody}>
              <View style={[styles.resumeIcon, { backgroundColor: colors.accent }]}>
                <Play size={18} color={colors.accentInk} fill={colors.accentInk} />
              </View>
              <View style={styles.flex}>
                <Text variant="overline" color={colors.accentText}>
                  Session in progress
                </Text>
                <Text variant="bodyStrong">{active.title}</Text>
                <Text variant="caption">
                  {clock(elapsedSeconds)} elapsed · {active.sets.length} set
                  {active.sets.length === 1 ? '' : 's'} logged
                </Text>
              </View>
              <Text variant="label" color={colors.accentText}>
                Resume
              </Text>
            </View>
          </Card>
        </FadeIn>
      ) : null}

      {!plan ? (
        <FadeIn delay={60}>
          <Card>
            <EmptyState
              icon={<Dumbbell size={24} color={colors.accentText} />}
              title={dataLoading ? 'Loading your plan' : 'No plan yet'}
              message="Generate a weekly training plan based on your experience, equipment, and schedule."
              action={
                <Button label="Create my plan" onPress={() => router.push('/plan/generate')} />
              }
            />
          </Card>
        </FadeIn>
      ) : (
        <>
          <FadeIn delay={60}>
            <Card padded={false} style={styles.planCard}>
              <LinearGradient
                colors={[colors.accentSoft, 'transparent']}
                start={{ x: 0, y: 0 }}
                end={{ x: 1, y: 1 }}
                style={StyleSheet.absoluteFill}
              />
              <View style={styles.planBody}>
                <View style={styles.planTop}>
                  <Badge label={plan.source === 'ai' ? 'AI generated' : 'On-device plan'} tone="accent" />
                  <Text variant="caption">{GOAL_LABEL[plan.goal]}</Text>
                </View>
                <Text variant="heading">{plan.name}</Text>
                <View style={styles.planMeta}>
                  <View style={styles.metaItem}>
                    <CalendarDot color={colors.accent} />
                    <Text variant="caption">{plan.daysPerWeek} days / week</Text>
                  </View>
                  <View style={styles.metaItem}>
                    <Clock size={13} color={colors.textTertiary} />
                    <Text variant="caption">{plan.sessionMinutes} min sessions</Text>
                  </View>
                  <View style={styles.metaItem}>
                    <Users size={13} color={colors.textTertiary} />
                    <Text variant="caption" style={{ textTransform: 'capitalize' }}>
                      {plan.experience}
                    </Text>
                  </View>
                </View>
                <View style={styles.equipmentRow}>
                  {plan.equipment.slice(0, 4).map((item) => (
                    <View
                      key={item}
                      style={[styles.equipmentChip, { borderColor: colors.border }]}
                    >
                      <Text variant="caption" color={colors.textTertiary} style={styles.equipmentText}>
                        {EQUIPMENT_LABEL[item]}
                      </Text>
                    </View>
                  ))}
                  {plan.equipment.length > 4 ? (
                    <Text variant="caption" color={colors.textTertiary}>
                      +{plan.equipment.length - 4}
                    </Text>
                  ) : null}
                </View>
                <Button
                  label="Regenerate plan"
                  variant="secondary"
                  size="md"
                  icon={<Sparkles size={15} color={colors.text} />}
                  onPress={() => router.push('/plan/generate')}
                />
              </View>
            </Card>
          </FadeIn>

          <FadeIn delay={120}>
            <SectionHeader title="Your week" caption="Tap a day to see the full session" />
          </FadeIn>

          <View style={styles.dayList}>
            {days.map((day, index) => {
              const isToday = day.weekday === todayWeekday;
              const isOpen = expanded === day.id;
              const exerciseCount = day.exercises.length;
              const setCount = day.exercises.reduce((total, row) => total + row.sets, 0);

              return (
                <FadeIn key={day.id} delay={160 + index * 30}>
                  <Card padded={false} style={[styles.dayCard, isToday ? { borderColor: colors.accentBorder } : null]}>
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel={`${day.title} on ${WEEKDAY_LABEL[day.weekday ?? 1]}`}
                      onPress={() => setExpanded(isOpen ? null : day.id)}
                      style={({ pressed }) => [styles.dayHeader, { opacity: pressed ? 0.8 : 1 }]}
                    >
                      <View
                        style={[
                          styles.dayTag,
                          {
                            backgroundColor: day.isRestDay
                              ? colors.surfaceRaised
                              : isToday
                                ? colors.accent
                                : colors.accentSoft,
                            borderColor: day.isRestDay ? colors.border : colors.accentBorder,
                          },
                        ]}
                      >
                        {day.isRestDay ? (
                          <Moon size={13} color={colors.textTertiary} />
                        ) : (
                          <Text
                            variant="overline"
                            color={isToday ? colors.accentInk : colors.accentText}
                            style={styles.dayTagText}
                          >
                            {WEEKDAY_LABEL[day.weekday ?? 1]}
                          </Text>
                        )}
                      </View>
                      <View style={styles.flex}>
                        <View style={styles.dayTitleRow}>
                          <Text variant="bodyStrong">{day.isRestDay ? 'Recovery' : day.title}</Text>
                          {isToday ? <Badge label="Today" tone="accent" /> : null}
                        </View>
                        <Text variant="caption" numberOfLines={isOpen ? 3 : 1}>
                          {day.isRestDay
                            ? day.restNote ?? 'Rest and recover.'
                            : `${day.focus.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')} · ${exerciseCount} exercises · ${setCount} sets`}
                        </Text>
                      </View>
                      {!day.isRestDay ? (
                        <ChevronDown
                          size={17}
                          color={colors.textTertiary}
                          style={{ transform: [{ rotate: isOpen ? '180deg' : '0deg' }] }}
                        />
                      ) : null}
                    </Pressable>

                    {isOpen && !day.isRestDay ? (
                      <View style={styles.dayExpanded}>
                        <Divider />
                        {day.warmup.length > 0 ? (
                          <View style={styles.expandSection}>
                            <Text variant="overline" color={colors.textTertiary}>
                              Warm-up
                            </Text>
                            {day.warmup.map((step) => (
                              <Text key={step} variant="caption" color={colors.textSecondary}>
                                • {step}
                              </Text>
                            ))}
                          </View>
                        ) : null}

                        <View style={styles.exerciseList}>
                          {day.exercises.map((row, rowIndex) => (
                            <Pressable
                              key={row.id}
                              accessibilityRole="button"
                              accessibilityLabel={`${exerciseName(row.exerciseId)} details`}
                              onPress={() => router.push(`/exercise/${row.exerciseId}`)}
                              style={({ pressed }) => [
                                styles.exerciseRow,
                                { borderColor: colors.border, opacity: pressed ? 0.65 : 1 },
                              ]}
                            >
                              <Text variant="caption" color={colors.textTertiary} style={styles.exerciseIndex}>
                                {String(rowIndex + 1).padStart(2, '0')}
                              </Text>
                              <View style={styles.flex}>
                                <Text variant="label" style={styles.exerciseName}>
                                  {exerciseName(row.exerciseId)}
                                </Text>
                                <Text variant="caption" color={colors.textTertiary}>
                                  {row.sets} × {row.repsMin}–{row.repsMax} reps · {row.restSeconds}s rest
                                </Text>
                              </View>
                            </Pressable>
                          ))}
                        </View>

                        {day.cooldown.length > 0 ? (
                          <View style={styles.expandSection}>
                            <Text variant="overline" color={colors.textTertiary}>
                              Cool-down
                            </Text>
                            {day.cooldown.map((step) => (
                              <Text key={step} variant="caption" color={colors.textSecondary}>
                                • {step}
                              </Text>
                            ))}
                          </View>
                        ) : null}

                        <Button
                          label={active ? 'Resume active session' : 'Start this workout'}
                          icon={<Play size={16} color={colors.accentInk} fill={colors.accentInk} />}
                          loading={starting === day.id}
                          onPress={() => (active ? router.push('/workout/active') : handleStart(day))}
                          fullWidth
                        />
                      </View>
                    ) : null}
                  </Card>
                </FadeIn>
              );
            })}
          </View>
        </>
      )}

      <FadeIn delay={340}>
        <SectionHeader title="Tools" />
        <View style={styles.toolList}>
          <ToolRow
            icon={<BookOpen size={18} color={colors.accentText} />}
            title="Exercise library"
            caption="Browse 60 movements with form cues"
            onPress={() => router.push('/exercise')}
          />
          <ToolRow
            icon={<Heart size={18} color={colors.accentText} />}
            title="Recovery & mobility"
            caption="Rest-day guidance and gentle sessions"
            onPress={() => router.push('/recovery')}
          />
          <ToolRow
            icon={<Sparkles size={18} color={colors.accentText} />}
            title="Generate a new plan"
            caption={
              profile
                ? `Tuned to ${preferences?.sessionMinutes ?? 45} min sessions and your equipment`
                : 'Personalised to your schedule'
            }
            onPress={() => router.push('/plan/generate')}
          />
        </View>
      </FadeIn>
    </Screen>
  );
}

function CalendarDot({ color }: { color: string }) {
  return <View style={[styles.calendarDot, { backgroundColor: color }]} />;
}

function ToolRow({
  icon,
  title,
  caption,
  onPress,
}: {
  icon: React.ReactNode;
  title: string;
  caption: string;
  onPress: () => void;
}) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={title}
      onPress={onPress}
      style={({ pressed }) => [
        styles.toolRow,
        { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.75 : 1 },
      ]}
    >
      <View style={[styles.toolIcon, { backgroundColor: colors.surfaceRaised }]}>{icon}</View>
      <View style={styles.flex}>
        <Text variant="label" style={styles.exerciseName}>
          {title}
        </Text>
        <Text variant="caption" color={colors.textTertiary} numberOfLines={1}>
          {caption}
        </Text>
      </View>
      <ChevronDown size={16} color={colors.textTertiary} style={{ transform: [{ rotate: '-90deg' }] }} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  content: { gap: spacing.xl },
  flex: { flex: 1 },
  headerRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  resumeCard: { borderColor: 'transparent' },
  resumeBody: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.lg },
  resumeIcon: {
    width: 40,
    height: 40,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  planCard: { overflow: 'hidden' },
  planBody: { padding: spacing.lg, gap: spacing.sm },
  planTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  planMeta: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.lg, marginVertical: 2 },
  metaItem: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  calendarDot: { width: 7, height: 7, borderRadius: 4 },
  equipmentRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 6, marginBottom: spacing.sm },
  equipmentChip: {
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
  },
  equipmentText: { fontSize: 10.5 },
  dayList: { gap: spacing.sm },
  dayCard: { overflow: 'hidden' },
  dayHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
  },
  dayTag: {
    width: 46,
    height: 46,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayTagText: { fontSize: 10, letterSpacing: 0.8 },
  dayTitleRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: 2 },
  dayExpanded: {
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.lg,
    gap: spacing.md,
  },
  expandSection: { gap: 4, paddingTop: spacing.xs },
  exerciseList: { gap: 2 },
  exerciseRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: 9,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  exerciseIndex: { width: 20, fontSize: 10, letterSpacing: 0.5 },
  exerciseName: { fontFamily: 'Inter_600SemiBold' },
  toolList: { gap: spacing.sm },
  toolRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radii.lg,
    borderWidth: StyleSheet.hairlineWidth,
  },
  toolIcon: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
