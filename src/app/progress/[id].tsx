import { format, parseISO } from 'date-fns';
import { useLocalSearchParams, useRouter } from 'expo-router';
import {
  ArrowLeft,
  CheckCircle2,
  ChevronRight,
  Clock,
  Dumbbell,
  Flame,
  ListChecks,
  Repeat,
  TriangleAlert,
} from 'lucide-react-native';
import React, { useEffect, useMemo } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Badge, Divider, EmptyState } from '@/components/ui/Misc';
import { Card } from '@/components/ui/Card';
import { IconButton } from '@/components/ui/IconButton';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import type { CompletedSet } from '@/data/types';
import { MUSCLE_LABEL } from '@/data/types';
import { clock, minutesLabel } from '@/lib/date';
import { exerciseName } from '@/lib/plan';
import { toDisplayWeight, weightUnit } from '@/lib/units';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export default function SessionDetailScreen() {
  return (
    <RequireOnboarded>
      <SessionDetail />
    </RequireOnboarded>
  );
}

function SessionDetail() {
  const { colors } = useTheme();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { sessions, preferences, dataLoading, refreshSessions } = useApp();

  const session = useMemo(() => sessions.find((item) => item.id === id) ?? null, [sessions, id]);

  useEffect(() => {
    if (!session && !dataLoading && id) void refreshSessions();
  }, [dataLoading, id, refreshSessions, session]);

  const units = preferences?.units ?? 'kg';
  const unit = weightUnit(units);

  const groups = useMemo(() => {
    if (!session) return [];
    const map = new Map<string, CompletedSet[]>();
    for (const set of session.sets) {
      const list = map.get(set.exerciseId) ?? [];
      list.push(set);
      map.set(set.exerciseId, list);
    }
    return [...map.entries()].map(([exerciseId, sets]) => ({
      exerciseId,
      sets: sets.slice().sort((a, b) => a.setNumber - b.setNumber),
    }));
  }, [session]);

  if (!session) {
    return (
      <Screen scroll contentContainerStyle={styles.missing}>
        <EmptyState
          icon={<ListChecks size={24} color={colors.accentText} />}
          title={dataLoading ? 'Loading session' : 'Session not found'}
          message={
            dataLoading
              ? 'Fetching your saved workout…'
              : 'This session may have been removed or belongs to another account.'
          }
          action={
            <Pressable accessibilityRole="button" onPress={() => router.replace('/(tabs)/progress')}>
              <Text variant="label" color={colors.accentText}>
                Back to progress
              </Text>
            </Pressable>
          }
        />
      </Screen>
    );
  }

  const totalReps = session.sets.reduce((total, set) => total + set.reps, 0);
  const totalVolume = session.sets.reduce(
    (total, set) => total + (set.weightKg !== null ? set.weightKg * set.reps : 0),
    0,
  );
  const completed = session.status === 'completed';

  return (
    <Screen scroll contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <IconButton accessibilityLabel="Go back" onPress={() => router.back()} size={38}>
          <ArrowLeft size={17} color={colors.text} />
        </IconButton>
        <View style={styles.flex}>
          <Text variant="overline" color={colors.textTertiary}>
            Session detail
          </Text>
        </View>
        <Badge
          label={completed ? 'Completed' : 'Ended early'}
          tone={completed ? 'accent' : 'warning'}
          icon={
            completed ? (
              <CheckCircle2 size={11} color={colors.accentText} />
            ) : (
              <TriangleAlert size={11} color={colors.warning} />
            )
          }
        />
      </View>

      <View>
        <Text variant="title">{session.title}</Text>
        <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
          {format(parseISO(session.startedAt), 'EEEE d MMMM yyyy · HH:mm')}
        </Text>
      </View>

      {session.focus.length > 0 ? (
        <View style={styles.focusRow}>
          {session.focus.map((muscle) => (
            <Badge key={muscle} label={MUSCLE_LABEL[muscle]} />
          ))}
        </View>
      ) : null}

      <Card variant="raised" style={styles.hero}>
        <View style={styles.heroRow}>
          <View style={styles.flex}>
            <Text variant="overline" color={colors.accentText}>
              Total time
            </Text>
            <Text variant="display" style={{ fontSize: 34, lineHeight: 38, marginTop: 2 }}>
              {clock(session.durationSeconds)}
            </Text>
            <Text variant="caption" style={{ marginTop: 2 }}>
              {minutesLabel(session.durationSeconds)} · {session.sets.length} sets
            </Text>
          </View>
          <View style={[styles.heroIcon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
            <Clock size={22} color={colors.accentText} />
          </View>
        </View>
        <Divider style={{ marginVertical: spacing.lg }} />
        <View style={styles.statRow}>
          <Stat label="Reps" value={String(totalReps)} icon={<Repeat size={14} color={colors.textTertiary} />} />
          <Stat
            label={`Volume (${unit})`}
            value={totalVolume > 0 ? String(Math.round(toDisplayWeight(totalVolume, units))) : '—'}
            icon={<Flame size={14} color={colors.textTertiary} />}
          />
          <Stat
            label="Exercises"
            value={String(groups.length)}
            icon={<Dumbbell size={14} color={colors.textTertiary} />}
          />
        </View>
      </Card>

      {session.notes ? (
        <Card>
          <Text variant="overline" color={colors.textTertiary}>
            Your notes
          </Text>
          <Text variant="body" style={{ marginTop: 6 }}>
            {session.notes}
          </Text>
        </Card>
      ) : null}

      <View style={styles.section}>
        <Text variant="heading">Sets</Text>
        <View style={styles.groups}>
          {groups.map((group) => (
            <Card key={group.exerciseId} padded={false}>
              <Pressable
                accessibilityRole="button"
                onPress={() =>
                  router.push({ pathname: '/exercise/[id]', params: { id: group.exerciseId } })
                }
                style={styles.groupHeader}
              >
                <View style={styles.flex}>
                  <Text variant="bodyStrong">{exerciseName(group.exerciseId)}</Text>
                  <Text variant="caption" style={{ marginTop: 2 }}>
                    {group.sets.length} set{group.sets.length === 1 ? '' : 's'} ·{' '}
                    {group.sets.reduce((total, set) => total + set.reps, 0)} reps
                  </Text>
                </View>
                <ChevronRight size={16} color={colors.textTertiary} />
              </Pressable>
              <View style={[styles.setTable, { borderTopColor: colors.border }]}>
                <View style={styles.setRow}>
                  <Text variant="overline" color={colors.textTertiary} style={styles.setLabel}>
                    Set
                  </Text>
                  <Text variant="overline" color={colors.textTertiary} style={styles.setCell}>
                    Reps
                  </Text>
                  <Text variant="overline" color={colors.textTertiary} style={styles.setCell}>
                    Weight
                  </Text>
                </View>
                {group.sets.map((set) => (
                  <View key={set.id} style={[styles.setRow, styles.setData]}>
                    <Text variant="body" style={styles.setLabel}>
                      {set.setNumber}
                    </Text>
                    <Text variant="body" style={styles.setCell}>
                      {set.reps}
                    </Text>
                    <Text variant="body" color={set.weightKg === null ? colors.textTertiary : colors.text} style={styles.setCell}>
                      {set.weightKg === null ? 'Bodyweight' : `${toDisplayWeight(set.weightKg, units)} ${unit}`}
                    </Text>
                  </View>
                ))}
              </View>
            </Card>
          ))}
        </View>
      </View>

      <View style={styles.footer}>
        <Pressable
          accessibilityRole="button"
          onPress={() => router.back()}
          style={({ pressed }) => [
            styles.footerButton,
            { borderColor: colors.border, backgroundColor: colors.surface, opacity: pressed ? 0.8 : 1 },
          ]}
        >
          <Text variant="label">Back</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          onPress={() => router.push('/(tabs)/workouts')}
          style={({ pressed }) => [
            styles.footerButton,
            { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft, opacity: pressed ? 0.8 : 1 },
          ]}
        >
          <Text variant="label" color={colors.accentText}>
            Train again
          </Text>
        </Pressable>
      </View>
    </Screen>
  );
}

function Stat({ label, value, icon }: { label: string; value: string; icon: React.ReactNode }) {
  const { colors } = useTheme();
  return (
    <View style={styles.stat}>
      <View style={styles.statLabelRow}>
        {icon}
        <Text variant="caption" color={colors.textTertiary} style={{ fontSize: 10.5 }}>
          {label}
        </Text>
      </View>
      <Text variant="subheading" style={{ marginTop: 3 }}>
        {value}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { gap: spacing.lg },
  missing: { justifyContent: 'center', flexGrow: 1 },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  focusRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  hero: { gap: 0 },
  heroRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  heroIcon: {
    width: 50,
    height: 50,
    borderRadius: 18,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  statRow: { flexDirection: 'row', gap: spacing.md },
  stat: { flex: 1 },
  statLabelRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  section: { gap: spacing.md },
  groups: { gap: spacing.md },
  groupHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
  },
  setTable: { borderTopWidth: StyleSheet.hairlineWidth, paddingHorizontal: spacing.lg, paddingBottom: spacing.md },
  setRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 7 },
  setData: {},
  setLabel: { width: 44 },
  setCell: { flex: 1 },
  footer: { flexDirection: 'row', gap: spacing.md, marginTop: spacing.sm },
  footerButton: {
    flex: 1,
    height: 50,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
