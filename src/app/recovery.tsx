import { parseISO, subDays } from 'date-fns';
import { useRouter } from 'expo-router';
import {
  ArrowLeft,
  BedDouble,
  CheckCircle2,
  Info,
  Moon,
  PersonStanding,
  Save,
  Sparkles,
  TriangleAlert,
  Waves,
} from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Card } from '@/components/ui/Card';
import { IconButton } from '@/components/ui/IconButton';
import { Input } from '@/components/ui/Input';
import { Badge, Divider, InlineError } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import type { WorkoutDay } from '@/data/types';
import { completedSessions, dateKey, formatShortDate } from '@/lib/date';
import { newId } from '@/lib/id';
import { planForDate } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const MOBILITY = [
  {
    key: 'reset',
    title: 'Full-body reset',
    minutes: 6,
    focus: 'Hips, spine, shoulders',
    steps: [
      'Cat-cow, 8 slow breaths.',
      '90/90 hip switches, 6 per side.',
      'Wall slides, 8 controlled reps.',
      'Standing forward fold, 30 seconds.',
    ],
    icon: Waves,
  },
  {
    key: 'lower',
    title: 'Lower-body unwind',
    minutes: 7,
    focus: 'Quads, hamstrings, calves',
    steps: [
      'Half-kneeling hip flexor stretch, 40 seconds per side.',
      'Seated hamstring reach, 40 seconds per side.',
      'Couch stretch or glute bridge, 10 slow reps.',
      'Calf stretch against a wall, 30 seconds per side.',
    ],
    icon: PersonStanding,
  },
  {
    key: 'upper',
    title: 'Upper-body release',
    minutes: 5,
    focus: 'Chest, lats, neck',
    steps: [
      'Doorway chest stretch, 30 seconds per side.',
      'Child’s pose with side reach, 40 seconds per side.',
      'Slow neck turns, 6 per side, no forcing.',
      'Shoulder circles and wrist rolls, 30 seconds.',
    ],
    icon: Sparkles,
  },
];

type RecoveryStatus = {
  label: string;
  tone: 'accent' | 'warning' | 'neutral';
  headline: string;
  detail: string;
};

function statusFor(params: {
  sessionsLast7: number;
  weekTarget: number;
  consecutiveDays: number;
  trainedToday: boolean;
}): RecoveryStatus {
  const { sessionsLast7, weekTarget, consecutiveDays, trainedToday } = params;
  if (sessionsLast7 === 0) {
    return {
      label: 'Fresh start',
      tone: 'accent',
      headline: 'No sessions in the last 7 days',
      detail: 'Start with a planned session at a comfortable effort. No catch-up needed.',
    };
  }
  if (consecutiveDays >= 4 || sessionsLast7 >= weekTarget + 3) {
    return {
      label: 'High recent load',
      tone: 'warning',
      headline: `${sessionsLast7} sessions in the last 7 days`,
      detail:
        'Your recent frequency is above your plan. Take an easy day, sleep well, and return when you feel ready.',
    };
  }
  if (trainedToday) {
    return {
      label: 'Steady',
      tone: 'accent',
      headline: 'You trained today',
      detail: 'Refuel, hydrate, and let the session settle. Mobility below is optional, not a second workout.',
    };
  }
  return {
    label: 'Ready',
    tone: 'accent',
    headline: `${sessionsLast7} session${sessionsLast7 === 1 ? '' : 's'} in the last 7 days`,
    detail: 'You are inside your planned frequency. Keep the next session at a repeatable effort.',
  };
}

export default function RecoveryScreen() {
  return (
    <RequireOnboarded>
      <RecoveryContent />
    </RequireOnboarded>
  );
}

function RecoveryContent() {
  const { colors } = useTheme();
  const router = useRouter();
  const { sessions, preferences, plan, progressRecords, addProgressRecord, user } = useApp();
  const [note, setNote] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const today = useMemo(() => new Date(), []);
  const completed = useMemo(() => completedSessions(sessions), [sessions]);
  const weekTarget = Math.max(1, preferences?.workoutDays.length ?? 3);

  const sessionsLast7 = completed.filter((session) => {
    const date = parseISO(session.startedAt);
    return date >= subDays(today, 6) && date <= today;
  });

  const keys = new Set(completed.map((session) => dateKey(parseISO(session.startedAt))));
  const trainedToday = keys.has(dateKey(today));
  let consecutiveDays = 0;
  let cursor = today;
  while (keys.has(dateKey(cursor))) {
    consecutiveDays += 1;
    cursor = subDays(cursor, 1);
  }

  const status = statusFor({
    sessionsLast7: sessionsLast7.length,
    weekTarget,
    consecutiveDays,
    trainedToday,
  });

  const todayPlan: WorkoutDay | undefined = plan ? planForDate(plan, today) : undefined;
  const loadSets = sessionsLast7.reduce((total, session) => total + session.sets.length, 0);
  const recoveryNotes = progressRecords.filter((record) => record.notes && record.bodyweightKg === null).slice(0, 3);

  const saveNote = async () => {
    if (!user) return;
    const trimmed = note.trim();
    if (!trimmed) {
      setError('Write a short note first.');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await addProgressRecord({
        id: newId('recovery'),
        userId: user.id,
        recordedAt: new Date().toISOString(),
        bodyweightKg: null,
        notes: trimmed.slice(0, 400),
      });
      setNote('');
      setSaved(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save your note.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <Screen scroll contentContainerStyle={styles.content}>
      <View style={styles.header}>
        <IconButton accessibilityLabel="Go back" onPress={() => router.back()} size={38}>
          <ArrowLeft size={17} color={colors.text} />
        </IconButton>
        <View style={styles.flex}>
          <Text variant="overline" color={colors.textTertiary}>
            Recovery
          </Text>
        </View>
      </View>

      <View>
        <Text variant="title">Recover with intent.</Text>
        <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
          Based only on the sessions you have recorded. This is training guidance, not medical advice.
        </Text>
      </View>

      <Card variant={status.tone === 'warning' ? 'default' : 'accent'}>
        <View style={styles.statusRow}>
          <View
            style={[
              styles.statusIcon,
              {
                backgroundColor: status.tone === 'warning' ? colors.warningSoft : colors.accentSoft,
                borderColor: status.tone === 'warning' ? 'transparent' : colors.accentBorder,
              },
            ]}
          >
            {status.tone === 'warning' ? (
              <Moon size={22} color={colors.warning} />
            ) : (
              <CheckCircle2 size={22} color={colors.accentText} />
            )}
          </View>
          <View style={styles.flex}>
            <Badge label={status.label} tone={status.tone} />
            <Text variant="subheading" style={{ marginTop: 7 }}>
              {status.headline}
            </Text>
            <Text variant="caption" style={{ marginTop: 4 }}>
              {status.detail}
            </Text>
          </View>
        </View>
        <Divider style={{ marginVertical: spacing.lg }} />
        <View style={styles.loadRow}>
          <View style={styles.loadCell}>
            <Text variant="number" style={{ fontSize: 22 }}>
              {sessionsLast7.length}
            </Text>
            <Text variant="caption" color={colors.textTertiary}>
              sessions / 7 days
            </Text>
          </View>
          <View style={styles.loadCell}>
            <Text variant="number" style={{ fontSize: 22 }}>
              {loadSets}
            </Text>
            <Text variant="caption" color={colors.textTertiary}>
              sets / 7 days
            </Text>
          </View>
          <View style={styles.loadCell}>
            <Text variant="number" style={{ fontSize: 22 }}>
              {consecutiveDays}
            </Text>
            <Text variant="caption" color={colors.textTertiary}>
              day streak
            </Text>
          </View>
        </View>
      </Card>

      <Card
        onPress={() => router.push('/(tabs)/workouts')}
        accessibilityLabel="View today's plan"
      >
        <View style={styles.planRow}>
          <View style={[styles.planIcon, { backgroundColor: colors.surfaceRaised }]}>
            <BedDouble size={19} color={colors.accentText} />
          </View>
          <View style={styles.flex}>
            <Text variant="overline" color={colors.textTertiary}>
              Today&apos;s plan
            </Text>
            <Text variant="bodyStrong" style={{ marginTop: 3 }}>
              {todayPlan
                ? todayPlan.isRestDay
                  ? 'Rest day'
                  : todayPlan.title
                : 'No active plan'}
            </Text>
            <Text variant="caption" style={{ marginTop: 3 }}>
              {todayPlan
                ? todayPlan.isRestDay
                  ? todayPlan.restNote ?? 'Keep movement easy and prioritise sleep.'
                  : `${todayPlan.exercises.length} exercises · about ${todayPlan.estimatedMinutes} min`
                : 'Create a plan to see today’s training and rest days.'}
            </Text>
          </View>
        </View>
      </Card>

      <View style={styles.section}>
        <Text variant="heading">Mobility routines</Text>
        <Text variant="caption" style={styles.sectionCaption}>
          Short, optional sequences. Stop any movement that causes pain.
        </Text>
        <View style={styles.routines}>
          {MOBILITY.map((routine) => {
            const Icon = routine.icon;
            return (
              <Card key={routine.key} padded={false}>
                <View style={styles.routineHeader}>
                  <View style={[styles.routineIcon, { backgroundColor: colors.accentSoft }]}>
                    <Icon size={18} color={colors.accentText} />
                  </View>
                  <View style={styles.flex}>
                    <Text variant="bodyStrong">{routine.title}</Text>
                    <Text variant="caption" style={{ marginTop: 2 }}>
                      {routine.minutes} min · {routine.focus}
                    </Text>
                  </View>
                </View>
                <View style={[styles.routineSteps, { borderTopColor: colors.border }]}>
                  {routine.steps.map((step, index) => (
                    <View key={step} style={styles.stepRow}>
                      <Text variant="overline" color={colors.accentText} style={styles.stepIndex}>
                        {String(index + 1).padStart(2, '0')}
                      </Text>
                      <Text variant="body" color={colors.textSecondary} style={styles.flex}>
                        {step}
                      </Text>
                    </View>
                  ))}
                </View>
              </Card>
            );
          })}
        </View>
      </View>

      <Card style={{ backgroundColor: colors.warningSoft }}>
        <View style={styles.safetyRow}>
          <TriangleAlert size={18} color={colors.warning} />
          <Text variant="caption" color={colors.warning} style={styles.flex}>
            Sharp, sudden, joint-related, or worsening pain is a reason to stop. Dizziness, chest pain, or
            shortness of breath needs medical attention. Forma cannot diagnose an injury.
          </Text>
        </View>
      </Card>

      <View style={styles.section}>
        <Text variant="heading">Recovery notes</Text>
        <Text variant="caption" style={styles.sectionCaption}>
          Your own words, saved with the date. Useful when you review a hard week.
        </Text>
        <Card>
          <Input
            value={note}
            onChangeText={(value) => {
              setNote(value);
              setSaved(false);
            }}
            placeholder="Sleep, soreness, stress, what helped…"
            multiline
            maxLength={400}
            hint="Soreness notes are not a diagnosis. Describe what you feel in plain language."
          />
          {error ? <InlineError message={error} /> : null}
          {saved ? (
            <View style={styles.savedRow}>
              <CheckCircle2 size={14} color={colors.accentText} />
              <Text variant="caption" color={colors.accentText}>
                Note saved.
              </Text>
            </View>
          ) : null}
          <Pressable
            accessibilityRole="button"
            onPress={saveNote}
            disabled={saving}
            style={({ pressed }) => [
              styles.saveButton,
              {
                backgroundColor: colors.surfaceRaised,
                borderColor: colors.border,
                opacity: saving ? 0.6 : pressed ? 0.8 : 1,
                marginTop: spacing.sm,
              },
            ]}
          >
            <Save size={15} color={colors.text} />
            <Text variant="label">{saving ? 'Saving…' : 'Save note'}</Text>
          </Pressable>
        </Card>

        {recoveryNotes.length > 0 ? (
          <View style={styles.noteList}>
            {recoveryNotes.map((record) => (
              <View key={record.id} style={[styles.noteRow, { borderBottomColor: colors.border }]}>
                <Text variant="caption" color={colors.textTertiary}>
                  {formatShortDate(record.recordedAt)}
                </Text>
                <Text variant="body" style={styles.noteText}>
                  {record.notes}
                </Text>
              </View>
            ))}
          </View>
        ) : null}
      </View>

      <View style={styles.footnote}>
        <Info size={14} color={colors.textTertiary} />
        <Text variant="caption" color={colors.textTertiary} style={styles.flex}>
          Recovery status is calculated from completed sessions and your chosen training days. It is not a
          readiness score and cannot detect injury or illness.
        </Text>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { gap: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  statusRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.md },
  statusIcon: {
    width: 46,
    height: 46,
    borderRadius: 16,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadRow: { flexDirection: 'row', gap: spacing.md },
  loadCell: { flex: 1 },
  planRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  planIcon: {
    width: 42,
    height: 42,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  section: { gap: spacing.sm },
  sectionCaption: { marginBottom: spacing.xs },
  routines: { gap: spacing.md },
  routineHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, padding: spacing.lg },
  routineIcon: {
    width: 38,
    height: 38,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  routineSteps: { borderTopWidth: StyleSheet.hairlineWidth, padding: spacing.lg, gap: 9 },
  stepRow: { flexDirection: 'row', gap: spacing.md, alignItems: 'flex-start' },
  stepIndex: { fontSize: 9.5, marginTop: 3 },
  safetyRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  savedRow: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  saveButton: {
    height: 46,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 7,
  },
  noteList: { gap: spacing.sm },
  noteRow: { borderBottomWidth: StyleSheet.hairlineWidth, paddingVertical: spacing.sm, gap: 3 },
  noteText: { marginTop: 1 },
  footnote: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
});
