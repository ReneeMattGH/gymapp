import { useRouter } from 'expo-router';
import {
  Check,
  ChevronRight,
  Clock,
  Info,
  Pause,
  Play,
  Repeat,
  SkipForward,
  Timer,
  X,
} from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import {
  Pressable,
  ScrollView,
  StyleSheet,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { BootSplash } from '@/components/ui/BootSplash';
import { Button } from '@/components/ui/Button';
import { Chip } from '@/components/ui/Chip';
import { ExerciseArt } from '@/components/ui/ExerciseArt';
import { IconButton } from '@/components/ui/IconButton';
import { Input } from '@/components/ui/Input';
import { Badge, Divider, EmptyState, InlineError } from '@/components/ui/Misc';
import { ProgressRing } from '@/components/ui/ProgressRing';
import { Sheet } from '@/components/ui/Sheet';
import { Stepper } from '@/components/ui/Stepper';
import { Text } from '@/components/ui/Text';
import {
  MUSCLE_LABEL,
  type CompletedSet,
  type Exercise,
  type WorkoutExercise,
  type WorkoutSession,
} from '@/data/types';
import { clock } from '@/lib/date';
import { EXERCISE_LIBRARY, exerciseMap, getExercise } from '@/lib/plan';
import { toDisplayWeight, toKg, weightLabel } from '@/lib/units';
import { useApp } from '@/state/AppProvider';
import { useWorkout } from '@/state/WorkoutProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export default function ActiveWorkoutScreen() {
  return (
    <RequireOnboarded>
      <ActiveWorkout />
    </RequireOnboarded>
  );
}

function ActiveWorkout() {
  const { colors } = useTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { sessions, preferences } = useApp();
  const {
    active,
    restored,
    elapsedSeconds,
    restRemaining,
    restRunning,
    currentExercise,
    addSet,
    goToExercise,
    nextExercise,
    substituteCurrent,
    skipCurrent,
    pauseWorkout,
    resumeWorkout,
    startRest,
    pauseRest,
    resumeRest,
    addRestTime,
    skipRest,
    finishWorkout,
    discardWorkout,
  } = useWorkout();

  const [endVisible, setEndVisible] = useState(false);
  const [swapVisible, setSwapVisible] = useState(false);
  const [guideVisible, setGuideVisible] = useState(false);
  const [exerciseInfoVisible, setExerciseInfoVisible] = useState(false);
  const [notes, setNotes] = useState('');
  const [finishing, setFinishing] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const exerciseDef = currentExercise ? getExercise(currentExercise.exerciseId) : undefined;
  const setsForExercise = useMemo(
    () =>
      active && currentExercise
        ? active.sets.filter((set) => set.workoutExerciseId === currentExercise.id)
        : [],
    [active, currentExercise],
  );
  const totalSets = active ? active.exercises.reduce((sum, row) => sum + row.sets, 0) : 0;
  const doneSets = active?.sets.length ?? 0;
  const progress = totalSets > 0 ? Math.min(1, doneSets / totalSets) : 0;
  const allDone = Boolean(currentExercise && setsForExercise.length >= currentExercise.sets);
  const isLastExercise = Boolean(active && currentExercise && active.currentExerciseIndex === active.exercises.length - 1);
  const restFinished = Boolean(active?.rest) && restRemaining === 0;
  const restPaused = active?.rest?.pausedRemaining !== null && active?.rest?.pausedRemaining !== undefined;
  const units = preferences?.units ?? 'kg';

  const lastPerformance = useMemo(() => {
    if (!currentExercise) return null;
    return findLastPerformance(currentExercise.exerciseId, sessions);
  }, [currentExercise, sessions]);

  const swapOptions = useMemo(() => {
    if (!exerciseDef) return [];
    return alternativesFor(exerciseDef, preferences?.equipment ?? []);
  }, [exerciseDef, preferences?.equipment]);

  if (!restored) return <BootSplash />;

  if (!active) {
    return (
      <View style={[styles.root, { backgroundColor: colors.background, paddingTop: insets.top + 32 }]}>
        <View style={styles.emptyWrap}>
          <EmptyState
            icon={<Timer size={24} color={colors.accentText} />}
            title="No active workout"
            message="Start a session from your plan, or resume it from the dashboard if you already began."
            action={<Button label="Back to home" onPress={() => router.replace('/(tabs)')} />}
          />
        </View>
      </View>
    );
  }

  if (active.status === 'paused') {
    return (
      <View
        style={[
          styles.root,
          styles.pausedRoot,
          { backgroundColor: colors.background, paddingTop: insets.top, paddingBottom: insets.bottom + spacing.xl },
        ]}
      >
        <View style={styles.pausedTop}>
          <Pressable
            onPress={() => setEndVisible(true)}
            accessibilityRole="button"
            accessibilityLabel="End workout"
            style={({ pressed }) => [styles.closeButton, { borderColor: colors.border, opacity: pressed ? 0.6 : 1 }]}
          >
            <X size={18} color={colors.text} />
          </Pressable>
          <Badge label="Paused" />
          <View style={styles.closeButtonSpacer} />
        </View>

        <View style={styles.pausedBody}>
          <View style={[styles.pausedIcon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
            <Pause size={28} color={colors.accentText} />
          </View>
          <Text variant="title" align="center">
            Session paused
          </Text>
          <Text variant="body" color={colors.textSecondary} align="center" style={styles.pausedText}>
            Your timer is on hold and every logged set is saved. Take the time you need.
          </Text>
          <View style={styles.pausedStats}>
            <View style={styles.pausedStat}>
              <Text variant="number">{clock(elapsedSeconds)}</Text>
              <Text variant="caption" color={colors.textTertiary}>
                Elapsed
              </Text>
            </View>
            <View style={[styles.statDivider, { backgroundColor: colors.border }]} />
            <View style={styles.pausedStat}>
              <Text variant="number">{doneSets}</Text>
              <Text variant="caption" color={colors.textTertiary}>
                Sets logged
              </Text>
            </View>
          </View>
        </View>

        <View style={styles.pausedActions}>
          <Button
            label="Resume workout"
            icon={<Play size={17} color={colors.accentInk} fill={colors.accentInk} />}
            onPress={resumeWorkout}
            fullWidth
          />
          <Button label="End workout" variant="ghost" onPress={() => setEndVisible(true)} fullWidth />
        </View>

        <EndWorkoutSheet
          visible={endVisible}
          onClose={() => setEndVisible(false)}
          doneSets={doneSets}
          elapsed={elapsedSeconds}
          notes={notes}
          onChangeNotes={setNotes}
          finishing={finishing}
          error={error}
          onDiscard={async () => {
            setEndVisible(false);
            await discardWorkout();
            router.replace('/(tabs)');
          }}
          onFinish={async () => {
            setFinishing(true);
            setError(null);
            try {
              const session = await finishWorkout(notes.trim() ? notes.trim() : null);
              setEndVisible(false);
              router.replace(`/workout/summary?sessionId=${session.id}`);
            } catch (err) {
              setError(err instanceof Error ? err.message : 'Could not save the workout.');
            } finally {
              setFinishing(false);
            }
          }}
        />
      </View>
    );
  }

  if (!currentExercise) {
    return (
      <View style={[styles.root, styles.pausedRoot, { backgroundColor: colors.background }]}>
        <EmptyState
          icon={<Info size={24} color={colors.accentText} />}
          title="Session has no exercises"
          message="This plan day could not be loaded correctly. End the session and start again from your plan."
          action={<Button label="End workout" onPress={() => setEndVisible(true)} />}
        />
      </View>
    );
  }

  const setNumber = Math.min(setsForExercise.length + 1, currentExercise.sets);
  const canSwap = swapOptions.length > 0;
  const canSkip = !isLastExercise;

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <View style={[styles.header, { paddingTop: insets.top + 8 }]}>
        <Pressable
          onPress={() => setEndVisible(true)}
          accessibilityRole="button"
          accessibilityLabel="End workout"
          style={({ pressed }) => [
            styles.closeButton,
            { borderColor: colors.border, backgroundColor: colors.surface, opacity: pressed ? 0.6 : 1 },
          ]}
        >
          <X size={17} color={colors.text} />
        </Pressable>
        <View style={styles.flex}>
          <Text variant="overline" color={colors.textTertiary}>
            Current session
          </Text>
          <Text variant="bodyStrong" numberOfLines={1}>
            {active.title}
          </Text>
        </View>
        <View style={styles.elapsed}>
          <Clock size={13} color={colors.textTertiary} />
          <Text variant="label" color={colors.textSecondary} style={styles.elapsedText}>
            {clock(elapsedSeconds)}
          </Text>
        </View>
        <IconButton accessibilityLabel="Pause workout" onPress={pauseWorkout} size={38}>
          <Pause size={16} color={colors.text} />
        </IconButton>
      </View>

      <View style={styles.progressRow}>
        <View style={[styles.progressTrack, { backgroundColor: colors.surfaceRaised }]}>
          <View style={[styles.progressFill, { width: `${progress * 100}%`, backgroundColor: colors.accent }]} />
        </View>
        <Text variant="caption" color={colors.textTertiary} style={styles.progressText}>
          {doneSets}/{totalSets} sets
        </Text>
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        contentContainerStyle={styles.scrollContent}
        keyboardShouldPersistTaps="handled"
      >
        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.chipStrip}
          style={styles.chipScroll}
        >
          {active.exercises.map((row, index) => {
            const count = active.sets.filter((set) => set.workoutExerciseId === row.id).length;
            const isCurrent = index === active.currentExerciseIndex;
            const complete = count >= row.sets;
            return (
              <Chip
                key={row.id}
                label={`${index + 1}. ${exerciseMap[row.exerciseId]?.name ?? row.exerciseId}${
                  complete ? ' ✓' : ` · ${count}/${row.sets}`
                }`}
                selected={isCurrent}
                onPress={() => goToExercise(index)}
              />
            );
          })}
        </ScrollView>

        <Pressable
          onPress={() => setGuideVisible(true)}
          accessibilityRole="button"
          style={({ pressed }) => [styles.guideLink, { opacity: pressed ? 0.6 : 1 }]}
        >
          <Info size={13} color={colors.accentText} />
          <Text variant="caption" color={colors.accentText}>
            Warm-up, cool-down & safety
          </Text>
        </Pressable>

        <View>
          <ExerciseArt
            id={currentExercise.exerciseId}
            muscle={exerciseDef?.primaryMuscles[0] ?? 'full-body'}
            category={exerciseDef?.category}
            height={186}
            label={MUSCLE_LABEL[exerciseDef?.primaryMuscles[0] ?? 'full-body']}
          />
          <View style={styles.artBadge}>
            <Badge label={`Exercise ${active.currentExerciseIndex + 1} of ${active.exercises.length}`} tone="accent" />
          </View>
        </View>

        <View style={styles.exerciseHead}>
          <View style={styles.flex}>
            <Text variant="title">{exerciseDef?.name ?? currentExercise.exerciseId}</Text>
            <Text variant="caption" style={{ marginTop: 3 }}>
              {exerciseDef
                ? `${exerciseDef.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')} · ${
                    exerciseDef.isUnilateral ? 'Per side' : 'Both sides'
                  }`
                : 'Exercise details unavailable'}
            </Text>
          </View>
          <IconButton accessibilityLabel="Exercise instructions" onPress={() => setExerciseInfoVisible(true)} size={38}>
            <Info size={16} color={colors.text} />
          </IconButton>
        </View>

        <View style={styles.setInfoRow}>
          <View style={[styles.infoPill, { borderColor: colors.border, backgroundColor: colors.surface }]}>
            <Text variant="caption" color={colors.textSecondary}>
              Set {setNumber} of {currentExercise.sets}
            </Text>
          </View>
          <View style={[styles.infoPill, { borderColor: colors.border, backgroundColor: colors.surface }]}>
            <Text variant="caption" color={colors.textSecondary}>
              Target {currentExercise.repsMin}–{currentExercise.repsMax} reps
            </Text>
          </View>
          <View style={[styles.infoPill, { borderColor: colors.border, backgroundColor: colors.surface }]}>
            <Timer size={12} color={colors.textTertiary} />
            <Text variant="caption" color={colors.textSecondary}>
              {currentExercise.restSeconds}s rest
            </Text>
          </View>
        </View>

        {lastPerformance ? (
          <Text variant="caption" color={colors.textTertiary}>
            Last completed: {lastPerformance.reps} reps · {weightLabel(lastPerformance.weightKg, units)}
          </Text>
        ) : (
          <Text variant="caption" color={colors.textTertiary}>
            First time logging this movement. Choose a load you can control for every rep.
          </Text>
        )}

        {currentExercise.notes ? (
          <View style={[styles.noteCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <Text variant="caption" color={colors.textSecondary}>
              {currentExercise.notes}
            </Text>
          </View>
        ) : null}

        {!active.rest && !allDone ? (
          <View style={[styles.noteCard, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <Text variant="caption" color={colors.textSecondary}>
              Use the controls at the bottom of the screen to log your set. Rest starts
              automatically after each set except the last one.
            </Text>
          </View>
        ) : null}

        {error ? <InlineError message={error} /> : null}

        <View style={styles.secondaryActions}>
          {canSwap ? (
            <Pressable
              onPress={() => setSwapVisible(true)}
              accessibilityRole="button"
              style={({ pressed }) => [
                styles.secondaryAction,
                { borderColor: colors.border, opacity: pressed ? 0.6 : 1 },
              ]}
            >
              <Repeat size={14} color={colors.textSecondary} />
              <Text variant="label" color={colors.textSecondary}>
                Swap exercise
              </Text>
            </Pressable>
          ) : null}
          {canSkip ? (
            <Pressable
              onPress={skipCurrent}
              accessibilityRole="button"
              style={({ pressed }) => [
                styles.secondaryAction,
                { borderColor: colors.border, opacity: pressed ? 0.6 : 1 },
              ]}
            >
              <SkipForward size={14} color={colors.textSecondary} />
              <Text variant="label" color={colors.textSecondary}>
                Skip exercise
              </Text>
            </Pressable>
          ) : null}
        </View>
      </ScrollView>

      <View
        style={[
          styles.footer,
          {
            paddingBottom: insets.bottom + spacing.md,
            backgroundColor: colors.background,
            borderTopColor: colors.border,
          },
        ]}
      >
        {active.rest ? (
          <RestPanel
            remaining={restRemaining}
            duration={active.rest.durationSeconds}
            finished={restFinished}
            paused={restPaused}
            pausedRunning={!restRunning && !restFinished}
            nextLabel={
              allDone
                ? isLastExercise
                  ? 'Finish workout when ready'
                  : 'Next exercise when ready'
                : `Next: set ${setNumber} · ${currentExercise.repsMin}–${currentExercise.repsMax} reps`
            }
            onFinishRest={skipRest}
            onPause={pauseRest}
            onResume={resumeRest}
            onAddTime={() => addRestTime(15)}
            onSkip={skipRest}
          />
        ) : allDone ? (
          <View style={styles.allDone}>
            <View style={styles.allDoneHead}>
              <View style={[styles.doneIcon, { backgroundColor: colors.accent }]}>
                <Check size={16} color={colors.accentInk} strokeWidth={3} />
              </View>
              <View style={styles.flex}>
                <Text variant="bodyStrong">All sets logged</Text>
                <Text variant="caption">
                  {exerciseDef?.name ?? 'This exercise'} is complete. Move on when your breathing is steady.
                </Text>
              </View>
            </View>
            <Button
              label={isLastExercise ? 'Finish workout' : 'Next exercise'}
              icon={
                isLastExercise ? (
                  <Check size={17} color={colors.accentInk} />
                ) : (
                  <ChevronRight size={17} color={colors.accentInk} />
                )
              }
              onPress={() => (isLastExercise ? setEndVisible(true) : nextExercise())}
              fullWidth
            />
          </View>
        ) : (
          <SetLoggerFooter
            key={`footer-${currentExercise.id}`}
            exercise={currentExercise}
            previousSets={setsForExercise}
            units={units}
            disabled={Boolean(active.rest)}
            onComplete={async (reps, weightKg) => {
              setError(null);
              try {
                await addSet({ reps, weightKg, exerciseId: currentExercise.exerciseId });
                if (setsForExercise.length + 1 < currentExercise.sets) {
                  startRest(currentExercise.restSeconds, currentExercise.exerciseId);
                }
              } catch (err) {
                setError(err instanceof Error ? err.message : 'Could not log the set.');
              }
            }}
          />
        )}
        <Text variant="caption" color={colors.textTertiary} align="center" style={styles.safety}>
          Stop if you feel sharp pain, dizziness, or unusual shortness of breath.
        </Text>
      </View>

      <Sheet
        visible={guideVisible}
        onClose={() => setGuideVisible(false)}
        title="Warm-up & cool-down"
        subtitle="Follow these before and after the session."
      >
        <ScrollView contentContainerStyle={styles.sheetScroll} showsVerticalScrollIndicator={false}>
          <View style={styles.sheetSection}>
            <Text variant="overline" color={colors.textTertiary}>
              Warm-up
            </Text>
            {(active.warmup ?? []).length > 0 ? (
              (active.warmup ?? []).map((step) => (
                <Text key={step} variant="body" color={colors.textSecondary}>
                  • {step}
                </Text>
              ))
            ) : (
              <Text variant="body" color={colors.textSecondary}>
                5 minutes of easy movement and a light set of your first exercise.
              </Text>
            )}
          </View>
          <Divider />
          <View style={styles.sheetSection}>
            <Text variant="overline" color={colors.textTertiary}>
              Cool-down
            </Text>
            {(active.cooldown ?? []).length > 0 ? (
              (active.cooldown ?? []).map((step) => (
                <Text key={step} variant="body" color={colors.textSecondary}>
                  • {step}
                </Text>
              ))
            ) : (
              <Text variant="body" color={colors.textSecondary}>
                3–5 minutes of easy walking and gentle stretching for the muscles you trained.
              </Text>
            )}
          </View>
          <View style={[styles.safetyCard, { backgroundColor: colors.warningSoft }]}>
            <Text variant="caption" color={colors.warning}>
              Stop immediately if you feel sharp pain, chest tightness, dizziness, or faintness. This
              app does not provide medical advice — speak with a qualified professional if symptoms
              persist.
            </Text>
          </View>
        </ScrollView>
      </Sheet>

      <Sheet
        visible={exerciseInfoVisible}
        onClose={() => setExerciseInfoVisible(false)}
        title={exerciseDef?.name ?? 'Exercise'}
        subtitle="Form cues and common mistakes."
      >
        <ScrollView contentContainerStyle={styles.sheetScroll} showsVerticalScrollIndicator={false}>
          {exerciseDef ? (
            <>
              <View style={styles.sheetSection}>
                <Text variant="overline" color={colors.textTertiary}>
                  How to perform it
                </Text>
                {exerciseDef.instructions.map((step, index) => (
                  <View key={step} style={styles.stepRow}>
                    <Text variant="caption" color={colors.accentText} style={styles.stepNumber}>
                      {index + 1}
                    </Text>
                    <Text variant="body" color={colors.textSecondary} style={styles.flex}>
                      {step}
                    </Text>
                  </View>
                ))}
              </View>
              <Divider />
              <View style={styles.sheetSection}>
                <Text variant="overline" color={colors.textTertiary}>
                  Form cues
                </Text>
                {exerciseDef.cues.map((cue) => (
                  <Text key={cue} variant="body" color={colors.textSecondary}>
                    • {cue}
                  </Text>
                ))}
              </View>
              <Divider />
              <View style={styles.sheetSection}>
                <Text variant="overline" color={colors.textTertiary}>
                  Common mistakes
                </Text>
                {exerciseDef.mistakes.map((mistake) => (
                  <Text key={mistake} variant="body" color={colors.textSecondary}>
                    • {mistake}
                  </Text>
                ))}
              </View>
            </>
          ) : (
            <Text variant="body" color={colors.textSecondary}>
              Instructions are unavailable for this movement.
            </Text>
          )}
        </ScrollView>
      </Sheet>

      <Sheet
        visible={swapVisible}
        onClose={() => setSwapVisible(false)}
        title="Swap exercise"
        subtitle={
          setsForExercise.length > 0
            ? 'Sets you already logged stay in this session. Pick a movement for the remaining sets.'
            : 'Choose a movement that matches your equipment and feels comfortable.'
        }
      >
        <ScrollView contentContainerStyle={styles.swapList} showsVerticalScrollIndicator={false}>
          {swapOptions.map((option) => (
            <Pressable
              key={option.id}
              accessibilityRole="button"
              onPress={() => {
                substituteCurrent(
                  option.id,
                  currentExercise.sets,
                  currentExercise.repsMin,
                  currentExercise.repsMax,
                  currentExercise.restSeconds,
                );
                setSwapVisible(false);
              }}
              style={({ pressed }) => [
                styles.swapRow,
                { borderColor: colors.border, backgroundColor: colors.surfaceRaised, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <View style={styles.flex}>
                <Text variant="bodyStrong">{option.name}</Text>
                <Text variant="caption">
                  {option.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')} ·{' '}
                  {option.difficulty}
                </Text>
              </View>
              <ChevronRight size={16} color={colors.textTertiary} />
            </Pressable>
          ))}
        </ScrollView>
      </Sheet>

      <EndWorkoutSheet
        visible={endVisible}
        onClose={() => setEndVisible(false)}
        doneSets={doneSets}
        elapsed={elapsedSeconds}
        notes={notes}
        onChangeNotes={setNotes}
        finishing={finishing}
        error={error}
        onDiscard={async () => {
          setEndVisible(false);
          await discardWorkout();
          router.replace('/(tabs)');
        }}
        onFinish={async () => {
          setFinishing(true);
          setError(null);
          try {
            const session = await finishWorkout(notes.trim() ? notes.trim() : null);
            setEndVisible(false);
            router.replace(`/workout/summary?sessionId=${session.id}`);
          } catch (err) {
            setError(err instanceof Error ? err.message : 'Could not save the workout.');
          } finally {
            setFinishing(false);
          }
        }}
      />
    </View>
  );
}

function SetLoggerFooter({
  exercise,
  previousSets,
  units,
  disabled,
  onComplete,
}: {
  exercise: WorkoutExercise;
  previousSets: CompletedSet[];
  units: 'kg' | 'lb';
  disabled: boolean;
  onComplete: (reps: number, weightKg: number | null) => void;
}) {
  const { colors } = useTheme();
  const latest = previousSets[previousSets.length - 1];
  const [reps, setReps] = useState(latest?.reps ?? exercise.repsMax);
  const [weight, setWeight] = useState(toDisplayWeight(latest?.weightKg ?? 0, units));
  const step = units === 'lb' ? 5 : 2.5;

  return (
    <View style={styles.footerLogger}>
      <View style={styles.stepperRow}>
        <View style={styles.flex}>
          <Stepper
            label="Reps"
            value={reps}
            onChange={setReps}
            min={1}
            max={60}
            step={1}
            suffix="reps"
            compact
          />
        </View>
        <View style={styles.flex}>
          <Stepper
            label={`Weight (${units})`}
            value={weight}
            onChange={setWeight}
            min={0}
            max={units === 'lb' ? 1500 : 700}
            step={step}
            suffix={units}
            compact
          />
        </View>
      </View>
      <Button
        label="Complete set"
        disabled={disabled}
        onPress={() => onComplete(reps, weight > 0 ? toKg(weight, units) : null)}
        fullWidth
        icon={<Check size={17} color={colors.accentInk} />}
      />
    </View>
  );
}

function RestPanel({
  remaining,
  duration,
  finished,
  paused,
  pausedRunning,
  nextLabel,
  onFinishRest,
  onPause,
  onResume,
  onAddTime,
  onSkip,
}: {
  remaining: number;
  duration: number;
  finished: boolean;
  paused: boolean;
  pausedRunning: boolean;
  nextLabel: string;
  onFinishRest: () => void;
  onPause: () => void;
  onResume: () => void;
  onAddTime: () => void;
  onSkip: () => void;
}) {
  const { colors } = useTheme();
  const progress = duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 0;

  return (
    <View style={styles.restPanel}>
      <View style={styles.restHead}>
        <View>
          <Text variant="overline" color={colors.textTertiary}>
            {finished ? 'Rest complete' : pausedRunning ? 'Rest paused' : 'Resting'}
          </Text>
          <Text variant="caption" color={colors.textSecondary} numberOfLines={1}>
            {nextLabel}
          </Text>
        </View>
        <Pressable onPress={onSkip} accessibilityRole="button" hitSlop={8}>
          <Text variant="label" color={colors.accentText}>
            Skip rest
          </Text>
        </Pressable>
      </View>
      <View style={styles.restBody}>
        <ProgressRing
          progress={finished ? 1 : progress}
          size={124}
          strokeWidth={8}
          value={finished ? 'GO' : clock(remaining)}
          label={finished ? 'READY' : 'SECONDS'}
        />
        <View style={styles.restActions}>
          {!finished ? (
            <>
              <Button label="+15s" variant="secondary" size="md" onPress={onAddTime} style={styles.restButton} />
              <Button
                label={pausedRunning ? 'Resume' : 'Pause'}
                variant="secondary"
                size="md"
                onPress={pausedRunning ? onResume : onPause}
                style={styles.restButton}
              />
            </>
          ) : null}
          <Button
            label={finished ? 'Back to the set' : 'End rest now'}
            size="md"
            onPress={finished ? onFinishRest : onSkip}
            style={styles.restButton}
          />
        </View>
      </View>
    </View>
  );
}

function EndWorkoutSheet({
  visible,
  onClose,
  doneSets,
  elapsed,
  notes,
  onChangeNotes,
  finishing,
  error,
  onDiscard,
  onFinish,
}: {
  visible: boolean;
  onClose: () => void;
  doneSets: number;
  elapsed: number;
  notes: string;
  onChangeNotes: (value: string) => void;
  finishing: boolean;
  error: string | null;
  onDiscard: () => Promise<void>;
  onFinish: () => Promise<void>;
}) {
  const { colors } = useTheme();
  const hasSets = doneSets > 0;

  return (
    <Sheet
      visible={visible}
      onClose={onClose}
      title={hasSets ? 'Finish this session?' : 'End this session?'}
      subtitle={
        hasSets
          ? `${doneSets} set${doneSets === 1 ? '' : 's'} logged in ${clock(elapsed)}. Add a short note if it helps your future self.`
          : 'No sets have been logged yet. Nothing will be saved to your history.'
      }
    >
      {hasSets ? (
        <Input
          label="Session note (optional)"
          value={notes}
          onChangeText={onChangeNotes}
          placeholder="Energy, form, anything to remember"
          multiline
          maxLength={280}
        />
      ) : null}
      {error ? <InlineError message={error} /> : null}
      <View style={styles.endActions}>
        {hasSets ? (
          <Button
            label={finishing ? 'Saving session…' : 'Save & finish'}
            loading={finishing}
            onPress={onFinish}
            fullWidth
          />
        ) : null}
        <Button
          label={hasSets ? 'Discard this session' : 'Discard workout'}
          variant={hasSets ? 'ghost' : 'danger'}
          onPress={onDiscard}
          disabled={finishing}
          fullWidth
        />
        <Button
          label="Keep training"
          variant="ghost"
          onPress={onClose}
          disabled={finishing}
          fullWidth
        />
      </View>
      <Text variant="caption" color={colors.textTertiary} align="center">
        Stopping early is a valid training decision. Do not train through pain or exhaustion.
      </Text>
    </Sheet>
  );
}

function findLastPerformance(exerciseId: string, sessions: WorkoutSession[]): CompletedSet | null {
  const all: CompletedSet[] = [];
  for (const session of sessions) {
    if (session.status !== 'completed') continue;
    for (const set of session.sets) {
      if (set.exerciseId === exerciseId) all.push(set);
    }
  }
  if (all.length === 0) return null;
  all.sort((a, b) => new Date(b.completedAt).getTime() - new Date(a.completedAt).getTime());
  return all[0];
}

function alternativesFor(exercise: Exercise, equipment: string[]): Exercise[] {
  const allowed = (item: Exercise) =>
    item.equipment.every((equipmentItem) => equipmentItem === 'bodyweight' || equipment.includes(equipmentItem));
  const preferred = exercise.alternatives
    .map((id) => exerciseMap[id])
    .filter((item): item is Exercise => Boolean(item))
    .filter(allowed);
  if (preferred.length > 0) return preferred;

  return EXERCISE_LIBRARY.filter(
    (item) =>
      item.id !== exercise.id &&
      allowed(item) &&
      item.primaryMuscles.some((muscle) => exercise.primaryMuscles.includes(muscle)),
  ).slice(0, 8);
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  emptyWrap: { flex: 1, justifyContent: 'center' },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.sm,
  },
  closeButton: {
    width: 38,
    height: 38,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  closeButtonSpacer: { width: 38 },
  elapsed: { flexDirection: 'row', alignItems: 'center', gap: 5 },
  elapsedText: { fontVariant: ['tabular-nums'] },
  progressRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
  },
  progressTrack: { flex: 1, height: 5, borderRadius: 3, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: 3 },
  progressText: { fontVariant: ['tabular-nums'] },
  scrollContent: { paddingHorizontal: spacing.lg, paddingBottom: spacing.xl, gap: spacing.md },
  chipScroll: { marginHorizontal: -spacing.lg },
  chipStrip: { paddingHorizontal: spacing.lg, gap: spacing.sm },
  guideLink: { flexDirection: 'row', alignItems: 'center', gap: 5, alignSelf: 'flex-start' },
  artBadge: { position: 'absolute', top: spacing.md, left: spacing.md },
  exerciseHead: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.sm },
  setInfoRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  infoPill: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.pill,
    paddingHorizontal: 10,
    paddingVertical: 5,
  },
  noteCard: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    padding: spacing.md,
  },
  stepperRow: { flexDirection: 'row', gap: spacing.md },
  secondaryActions: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.xs },
  secondaryAction: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.pill,
    paddingHorizontal: spacing.md,
    paddingVertical: 7,
  },
  footer: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.md,
    gap: spacing.sm,
  },
  footerLogger: { gap: spacing.sm },
  safety: { fontSize: 10.5, lineHeight: 14 },
  allDone: { gap: spacing.md },
  allDoneHead: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  doneIcon: {
    width: 34,
    height: 34,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  restPanel: { gap: spacing.sm },
  restHead: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: spacing.md },
  restBody: { flexDirection: 'row', alignItems: 'center', gap: spacing.lg },
  restActions: { flex: 1, gap: spacing.sm },
  restButton: { width: '100%' },
  sheetScroll: { gap: spacing.md, paddingBottom: spacing.lg },
  sheetSection: { gap: 6 },
  stepRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  stepNumber: { width: 16, marginTop: 4, fontFamily: 'Inter_600SemiBold' },
  safetyCard: { padding: spacing.md, borderRadius: radii.md },
  swapList: { gap: spacing.sm, paddingBottom: spacing.lg },
  swapRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
  },
  endActions: { gap: spacing.sm },
  pausedRoot: { paddingHorizontal: spacing.xl },
  pausedTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingTop: spacing.lg },
  pausedBody: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: spacing.md },
  pausedIcon: {
    width: 72,
    height: 72,
    borderRadius: 24,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: spacing.sm,
  },
  pausedText: { maxWidth: 300 },
  pausedStats: { flexDirection: 'row', alignItems: 'center', gap: spacing.xl, marginTop: spacing.md },
  pausedStat: { alignItems: 'center', gap: 2 },
  statDivider: { width: StyleSheet.hairlineWidth, height: 30 },
  pausedActions: { gap: spacing.sm },
});
