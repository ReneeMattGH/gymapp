import { useLocalSearchParams, useRouter } from 'expo-router';
import { ArrowLeft, Check, ChevronRight, Info, TriangleAlert } from 'lucide-react-native';
import React, { useMemo } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Card } from '@/components/ui/Card';
import { ExerciseArt } from '@/components/ui/ExerciseArt';
import { IconButton } from '@/components/ui/IconButton';
import { Badge, Divider, EmptyState } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { EQUIPMENT_LABEL, MUSCLE_LABEL, type Exercise } from '@/data/types';
import { EXERCISE_LIBRARY, exerciseMap } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export default function ExerciseDetailScreen() {
  return (
    <RequireOnboarded>
      <ExerciseDetail />
    </RequireOnboarded>
  );
}

function ExerciseDetail() {
  const { colors } = useTheme();
  const router = useRouter();
  const { id } = useLocalSearchParams<{ id?: string }>();
  const { exercises } = useApp();

  const exercise = useMemo(
    () => exercises.find((item) => item.id === id) ?? (id ? exerciseMap[id] : undefined),
    [exercises, id],
  );

  const alternatives = useMemo(() => {
    if (!exercise) return [];
    const fromLibrary = exercise.alternatives
      .map((alternativeId) => exerciseMap[alternativeId])
      .filter((item): item is Exercise => Boolean(item));
    if (fromLibrary.length > 0) return fromLibrary;
    return EXERCISE_LIBRARY.filter(
      (item) =>
        item.id !== exercise.id &&
        item.primaryMuscles.some((muscle) => exercise.primaryMuscles.includes(muscle)),
    ).slice(0, 5);
  }, [exercise]);

  if (!exercise) {
    return (
      <Screen scroll contentContainerStyle={styles.missing}>
        <EmptyState
          icon={<Info size={24} color={colors.accentText} />}
          title="Exercise not found"
          message="This movement is not in the library. Browse the full library to find a replacement."
          action={
            <Pressable onPress={() => router.replace('/exercise')} accessibilityRole="button">
              <Text variant="label" color={colors.accentText}>
                Open the library
              </Text>
            </Pressable>
          }
        />
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
            Exercise library
          </Text>
        </View>
        <Badge
          label={exercise.difficulty.charAt(0).toUpperCase() + exercise.difficulty.slice(1)}
          tone={exercise.difficulty === 'advanced' ? 'warning' : 'neutral'}
        />
      </View>

      <ExerciseArt
        id={exercise.id}
        muscle={exercise.primaryMuscles[0]}
        category={exercise.category}
        height={210}
        label={exercise.category}
      />

      <View style={styles.titleBlock}>
        <Text variant="title">{exercise.name}</Text>
        <Text variant="body" color={colors.textSecondary}>
          {exercise.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')}
          {exercise.isUnilateral ? ' · Per side' : ''}
        </Text>
      </View>

      <View style={styles.chipWrap}>
        <View style={[styles.metaChip, { borderColor: colors.border, backgroundColor: colors.surface }]}>
          <Text variant="caption" color={colors.textSecondary}>
            {exercise.category.charAt(0).toUpperCase() + exercise.category.slice(1)}
          </Text>
        </View>
        {exercise.equipment.map((item) => (
          <View
            key={item}
            style={[styles.metaChip, { borderColor: colors.border, backgroundColor: colors.surface }]}
          >
            <Text variant="caption" color={colors.textSecondary}>
              {EQUIPMENT_LABEL[item]}
            </Text>
          </View>
        ))}
      </View>

      <Card style={styles.section}>
        <Text variant="overline" color={colors.textTertiary}>
          How to perform it
        </Text>
        {exercise.instructions.map((step, index) => (
          <View key={step} style={styles.stepRow}>
            <View style={[styles.stepNumber, { backgroundColor: colors.surfaceRaised }]}>
              <Text variant="caption" color={colors.accentText} style={styles.stepNumberText}>
                {index + 1}
              </Text>
            </View>
            <Text variant="body" color={colors.textSecondary} style={styles.flex}>
              {step}
            </Text>
          </View>
        ))}
      </Card>

      <Card style={styles.section}>
        <Text variant="overline" color={colors.textTertiary}>
          Form cues
        </Text>
        {exercise.cues.map((cue) => (
          <View key={cue} style={styles.bulletRow}>
            <Check size={14} color={colors.accentText} style={styles.bulletIcon} />
            <Text variant="body" color={colors.textSecondary} style={styles.flex}>
              {cue}
            </Text>
          </View>
        ))}
      </Card>

      <Card style={[styles.section, { borderColor: colors.warningSoft }]}>
        <View style={styles.warnHead}>
          <TriangleAlert size={15} color={colors.warning} />
          <Text variant="overline" color={colors.warning}>
            Common mistakes
          </Text>
        </View>
        {exercise.mistakes.map((mistake) => (
          <View key={mistake} style={styles.bulletRow}>
            <View style={[styles.dot, { backgroundColor: colors.warning }]} />
            <Text variant="body" color={colors.textSecondary} style={styles.flex}>
              {mistake}
            </Text>
          </View>
        ))}
      </Card>

      <Card style={styles.section}>
        <Text variant="overline" color={colors.textTertiary}>
          Targets
        </Text>
        <View style={styles.muscleRow}>
          <Text variant="label" color={colors.textSecondary} style={styles.muscleLabel}>
            Primary
          </Text>
          <Text variant="body" color={colors.text} style={styles.flex}>
            {exercise.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(', ')}
          </Text>
        </View>
        {exercise.secondaryMuscles.length > 0 ? (
          <>
            <Divider />
            <View style={styles.muscleRow}>
              <Text variant="label" color={colors.textSecondary} style={styles.muscleLabel}>
                Secondary
              </Text>
              <Text variant="body" color={colors.textSecondary} style={styles.flex}>
                {exercise.secondaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(', ')}
              </Text>
            </View>
          </>
        ) : null}
      </Card>

      {alternatives.length > 0 ? (
        <View style={styles.section}>
          <Text variant="heading">Alternatives</Text>
          <Text variant="caption" style={{ marginTop: -6 }}>
            Swap movements when equipment is unavailable or something feels uncomfortable.
          </Text>
          <View style={styles.alternatives}>
            {alternatives.slice(0, 6).map((alternative) => (
              <Pressable
                key={alternative.id}
                accessibilityRole="button"
                accessibilityLabel={`Open ${alternative.name}`}
                onPress={() => router.push(`/exercise/${alternative.id}`)}
                style={({ pressed }) => [
                  styles.altRow,
                  { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.75 : 1 },
                ]}
              >
                <View style={styles.thumb}>
                  <ExerciseArt
                    id={alternative.id}
                    muscle={alternative.primaryMuscles[0]}
                    category={alternative.category}
                    height={52}
                    compact
                    label={alternative.category}
                    style={styles.thumbArt}
                  />
                </View>
                <View style={styles.flex}>
                  <Text variant="bodyStrong" numberOfLines={1}>
                    {alternative.name}
                  </Text>
                  <Text variant="caption" numberOfLines={1}>
                    {alternative.equipment.map((item) => EQUIPMENT_LABEL[item]).join(', ')} ·{' '}
                    {alternative.difficulty}
                  </Text>
                </View>
                <ChevronRight size={16} color={colors.textTertiary} />
              </Pressable>
            ))}
          </View>
        </View>
      ) : null}

      <View style={[styles.safety, { backgroundColor: colors.surface, borderColor: colors.border }]}>
        <Text variant="caption" color={colors.textTertiary}>
          Stop any movement that causes sharp pain, dizziness or unusual shortness of breath. This
          library is educational and does not replace advice from a qualified professional.
        </Text>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  content: { gap: spacing.lg },
  missing: { justifyContent: 'center' },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  titleBlock: { gap: 4, marginTop: -4 },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  metaChip: {
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  section: { gap: spacing.sm },
  stepRow: { flexDirection: 'row', gap: spacing.md, alignItems: 'flex-start' },
  stepNumber: {
    width: 22,
    height: 22,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 2,
  },
  stepNumberText: { fontFamily: 'Inter_600SemiBold', fontSize: 11 },
  bulletRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  bulletIcon: { marginTop: 4 },
  dot: { width: 5, height: 5, borderRadius: 3, marginTop: 8 },
  warnHead: { flexDirection: 'row', alignItems: 'center', gap: 6 },
  muscleRow: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.md },
  muscleLabel: { width: 78 },
  alternatives: { gap: spacing.sm },
  altRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.sm,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
  },
  thumb: { width: 52, height: 52, borderRadius: 12, overflow: 'hidden' },
  thumbArt: { width: 52, borderRadius: 12 },
  safety: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    padding: spacing.md,
  },
});
