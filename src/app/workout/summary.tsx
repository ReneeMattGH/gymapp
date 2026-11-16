import { format, parseISO } from 'date-fns';
import * as Haptics from 'expo-haptics';
import { LinearGradient } from 'expo-linear-gradient';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { ChartColumn, Check, ChevronLeft, Dumbbell, Flame, ListChecks, Repeat } from 'lucide-react-native';
import React, { useEffect, useMemo } from 'react';
import { Animated, Platform, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { EmptyState } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import { MUSCLE_LABEL, type CompletedSet } from '@/data/types';
import { clock, currentWeekCount } from '@/lib/date';
import { exerciseName } from '@/lib/plan';
import { toDisplayWeight, weightLabel, weightUnit } from '@/lib/units';
import { useAnimatedValue } from '@/lib/useAnimatedValue';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export default function WorkoutSummaryScreen() {
  return (
    <RequireOnboarded>
      <SummaryContent />
    </RequireOnboarded>
  );
}

function SummaryContent() {
  const { colors } = useTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { sessionId } = useLocalSearchParams<{ sessionId?: string }>();
  const { sessions, preferences, dataLoading, refreshSessions } = useApp();

  const session = useMemo(
    () => sessions.find((item) => item.id === sessionId) ?? null,
    [sessions, sessionId],
  );

  const scale = useAnimatedValue(0.7);
  const opacity = useAnimatedValue(0);

  useEffect(() => {
    if (!session) return;
    Animated.parallel([
      Animated.spring(scale, { toValue: 1, speed: 12, bounciness: 8, useNativeDriver: true }),
      Animated.timing(opacity, { toValue: 1, duration: 320, useNativeDriver: true }),
    ]).start();
    if (Platform.OS !== 'web' && session.status === 'completed') {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
    }
  }, [opacity, scale, session]);

  useEffect(() => {
    if (!session && !dataLoading && sessionId) void refreshSessions();
  }, [dataLoading, refreshSessions, session, sessionId]);

  if (!session) {
    return (
      <View style={[styles.root, { backgroundColor: colors.background, paddingTop: insets.top + 40 }]}>
        <EmptyState
          icon={<ListChecks size={24} color={colors.accentText} />}
          title={dataLoading ? 'Loading session' : 'Session not found'}
          message={
            dataLoading
              ? 'Fetching your saved workout…'
              : 'This session may have been discarded or removed. Your other workouts are unchanged.'
          }
          action={<Button label="Back to home" onPress={() => router.replace('/(tabs)')} />}
        />
      </View>
    );
  }

  const units = preferences?.units ?? 'kg';
  const sets = session.sets;
  const reps = sets.reduce((total, set) => total + set.reps, 0);
  const exerciseIds = Array.from(new Set(sets.map((set) => set.exerciseId)));
  const volumeKg = sets.reduce(
    (total, set) => total + (set.weightKg ? set.reps * set.weightKg : 0),
    0,
  );
  const weekCount = currentWeekCount(sessions);
  const completed = session.status === 'completed';

  const groups = groupSets(sets);

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <View style={[styles.header, { paddingTop: insets.top + spacing.sm }]}>
        <Button
          label="Done"
          variant="ghost"
          size="sm"
          icon={<ChevronLeft size={16} color={colors.textSecondary} />}
          onPress={() => router.replace('/(tabs)')}
        />
      </View>

      <Animated.ScrollView
        style={{ flex: 1, opacity }}
        contentContainerStyle={styles.body}
        showsVerticalScrollIndicator={false}
      >
        <Card padded={false} style={styles.hero}>
          <LinearGradient
            colors={[colors.accentSoft, 'transparent']}
            start={{ x: 1, y: 0 }}
            end={{ x: 0, y: 1 }}
            style={StyleSheet.absoluteFill}
          />
          <View style={styles.heroBody}>
            <Animated.View
              style={[
                styles.check,
                { backgroundColor: completed ? colors.accent : colors.surfaceRaised, transform: [{ scale }] },
              ]}
            >
              <Check size={34} color={completed ? colors.accentInk : colors.textSecondary} strokeWidth={2.6} />
            </Animated.View>
            <Text variant="overline" color={colors.accentText}>
              {completed ? 'Session complete' : 'Session ended'}
            </Text>
            <Text variant="title" align="center">
              {session.title}
            </Text>
            <Text variant="caption" align="center">
              {format(parseISO(session.startedAt), 'EEEE d MMMM · HH:mm')}
            </Text>
            <Text variant="body" color={colors.textSecondary} align="center" style={styles.heroCopy}>
              {completed
                ? weekCount > 1
                  ? `${weekCount} sessions completed this week. Recovery now is what turns today's work into progress.`
                  : 'First session of the week logged. Recovery now is what turns today\'s work into progress.'
                : 'This session has no completed sets, so it was not added to your progress.'}
            </Text>
            {session.focus.length > 0 ? (
              <View style={styles.focusRow}>
                {session.focus.slice(0, 4).map((muscle) => (
                  <View key={muscle} style={[styles.focusChip, { borderColor: colors.border }]}>
                    <Text variant="caption" color={colors.textTertiary}>
                      {MUSCLE_LABEL[muscle]}
                    </Text>
                  </View>
                ))}
              </View>
            ) : null}
          </View>
        </Card>

        <View style={styles.statGrid}>
          <StatCell icon={<Repeat size={15} color={colors.accentText} />} label="Duration" value={clock(session.durationSeconds)} />
          <StatCell icon={<ListChecks size={15} color={colors.accentText} />} label="Sets" value={String(sets.length)} />
          <StatCell icon={<Flame size={15} color={colors.accentText} />} label="Reps" value={String(reps)} />
          <StatCell icon={<Dumbbell size={15} color={colors.accentText} />} label="Exercises" value={String(exerciseIds.length)} />
        </View>

        {volumeKg > 0 ? (
          <Text variant="caption" color={colors.textTertiary} align="center">
            Training volume: {toDisplayWeight(volumeKg, units)} {weightUnit(units)}
          </Text>
        ) : null}

        {session.notes ? (
          <Card style={styles.noteCard}>
            <Text variant="overline" color={colors.textTertiary}>
              Your note
            </Text>
            <Text variant="body" color={colors.textSecondary}>
              {session.notes}
            </Text>
          </Card>
        ) : null}

        <View style={styles.section}>
          <Text variant="heading">Session details</Text>
          {groups.length === 0 ? (
            <Text variant="body" color={colors.textSecondary}>
              No sets were logged in this session.
            </Text>
          ) : (
            groups.map((group) => (
              <Card key={group.exerciseId} style={styles.groupCard}>
                <View style={styles.groupHead}>
                  <Text variant="bodyStrong" style={styles.flex}>
                    {exerciseName(group.exerciseId)}
                  </Text>
                  <Text variant="caption" color={colors.textTertiary}>
                    {group.sets.length} set{group.sets.length === 1 ? '' : 's'}
                  </Text>
                </View>
                {group.sets.map((set) => (
                  <View key={set.id} style={styles.setRow}>
                    <Text variant="caption" color={colors.textTertiary} style={styles.setLabel}>
                      Set {set.setNumber}
                    </Text>
                    <Text variant="caption" color={colors.textSecondary} style={styles.flex}>
                      {set.reps} reps
                    </Text>
                    <Text variant="caption" color={colors.textTertiary}>
                      {weightLabel(set.weightKg, units)}
                    </Text>
                  </View>
                ))}
              </Card>
            ))
          )}
        </View>
      </Animated.ScrollView>

      <View style={[styles.footer, { paddingBottom: insets.bottom + spacing.md, borderTopColor: colors.border }]}>
        <Button label="Back to home" onPress={() => router.replace('/(tabs)')} fullWidth />
        <Button
          label="View progress"
          variant="secondary"
          icon={<ChartColumn size={16} color={colors.text} />}
          onPress={() => router.replace('/(tabs)/progress')}
          fullWidth
        />
      </View>
    </View>
  );
}

function StatCell({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.statCell, { backgroundColor: colors.surface, borderColor: colors.border }]}>
      <View style={styles.statLabelRow}>
        {icon}
        <Text variant="caption" color={colors.textTertiary}>
          {label}
        </Text>
      </View>
      <Text variant="number">{value}</Text>
    </View>
  );
}

function groupSets(sets: CompletedSet[]): { exerciseId: string; sets: CompletedSet[] }[] {
  const order: string[] = [];
  const map = new Map<string, CompletedSet[]>();
  for (const set of sets) {
    if (!map.has(set.exerciseId)) {
      map.set(set.exerciseId, []);
      order.push(set.exerciseId);
    }
    map.get(set.exerciseId)!.push(set);
  }
  return order.map((exerciseId) => ({ exerciseId, sets: map.get(exerciseId) ?? [] }));
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  header: { paddingHorizontal: spacing.md, alignItems: 'flex-start' },
  body: { gap: spacing.lg, paddingHorizontal: spacing.lg, paddingBottom: spacing.xl },
  hero: { overflow: 'hidden' },
  heroBody: { alignItems: 'center', padding: spacing.xl, gap: spacing.sm },
  check: {
    width: 76,
    height: 76,
    borderRadius: 26,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  heroCopy: { maxWidth: 300, marginTop: spacing.xs },
  focusRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, justifyContent: 'center', marginTop: spacing.xs },
  focusChip: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.pill,
    paddingHorizontal: 9,
    paddingVertical: 4,
  },
  statGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  statCell: {
    flexGrow: 1,
    flexBasis: '46%',
    borderRadius: radii.lg,
    borderWidth: StyleSheet.hairlineWidth,
    padding: spacing.md,
    gap: 6,
  },
  statLabelRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  noteCard: { gap: 6 },
  section: { gap: spacing.sm },
  groupCard: { gap: 6 },
  groupHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, marginBottom: 2 },
  setRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: 3 },
  setLabel: { width: 48 },
  footer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    gap: spacing.sm,
  },
});
