import { useRouter } from 'expo-router';
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  Bell,
  Calendar,
  Check,
  ChevronLeft,
  Dumbbell,
  Flame,
  Home,
  Layers,
  ShieldCheck,
  Sparkles,
} from 'lucide-react-native';
import React, { useEffect, useMemo, useState } from 'react';
import {
  Animated,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { AvoidExerciseSheet } from '@/features/onboarding/AvoidExerciseSheet';
import { useAnimatedValue } from '@/lib/useAnimatedValue';
import { OptionCard } from '@/features/onboarding/OptionCard';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Stepper } from '@/components/ui/Stepper';
import { Text } from '@/components/ui/Text';
import { Wordmark } from '@/components/ui/Brand';
import type {
  Equipment,
  Experience,
  Goal,
  Preferences,
  Profile,
  ReminderSettings,
  WorkoutPlan,
} from '@/data/types';
import {
  EQUIPMENT_LABEL,
  EXPERIENCE_LABEL,
  GOAL_LABEL,
  WEEKDAY_LABEL,
} from '@/data/types';
import { formatTimeOfDay } from '@/lib/date';
import { isPreviewMode } from '@/data';
import {
  notificationsSupported,
  requestPermission,
  syncReminders,
} from '@/lib/notifications';
import { generateLocalPlan, planForDate } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

const TOTAL_STEPS = 7;
const DAYS = [1, 2, 3, 4, 5, 6, 7];
const DURATIONS = [20, 30, 45, 60, 75];
const GOALS: Goal[] = ['strength', 'endurance', 'mobility', 'general', 'consistency'];
const ALL_EQUIPMENT = Object.keys(EQUIPMENT_LABEL) as Equipment[];
const REMINDER_TIMES = ['07:00', '08:00', '12:00', '17:30', '18:00', '19:00', '20:00'];

type FinishResult = {
  plan: WorkoutPlan;
  reminderMessage: string;
  scheduledCount: number;
};

export default function OnboardingScreen() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const {
    user,
    profile: existingProfile,
    exercises,
    saveProfile,
    savePreferences,
    savePlan,
    saveReminders,
  } = useApp();

  const [step, setStep] = useState(0);
  const [name, setName] = useState(existingProfile?.name ?? '');
  const [age, setAge] = useState(existingProfile?.age ?? 28);
  const [experience, setExperience] = useState<Experience>(existingProfile?.experience ?? 'beginner');
  const [environment, setEnvironment] = useState<Profile['environment']>(existingProfile?.environment ?? 'both');
  const [goals, setGoals] = useState<Goal[]>(existingProfile?.goals?.length ? existingProfile.goals : ['general']);
  const [days, setDays] = useState<number[]>([1, 3, 5]);
  const [minutes, setMinutes] = useState(45);
  const [equipment, setEquipment] = useState<Equipment[]>(['bodyweight', 'dumbbells', 'bench']);
  const [avoid, setAvoid] = useState<string[]>([]);
  const [limitations, setLimitations] = useState('');
  const [reminderTime, setReminderTime] = useState('18:00');
  const [remindersOn, setRemindersOn] = useState(notificationsSupported);
  const [avoidOpen, setAvoidOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [finishing, setFinishing] = useState(false);
  const [result, setResult] = useState<FinishResult | null>(null);

  const fade = useAnimatedValue(1);
  const rise = useAnimatedValue(0);

  useEffect(() => {
    fade.setValue(0);
    rise.setValue(10);
    Animated.parallel([
      Animated.timing(fade, { toValue: 1, duration: 280, useNativeDriver: true }),
      Animated.timing(rise, { toValue: 0, duration: 280, useNativeDriver: true }),
    ]).start();
  }, [step, fade, rise]);

  const canContinue = useMemo(() => {
    switch (step) {
      case 0:
        return name.trim().length >= 2 && age >= 13 && age <= 90;
      case 1:
        return Boolean(experience);
      case 2:
        return goals.length > 0 && Boolean(environment);
      case 3:
        return days.length >= 1 && days.length <= 6 && minutes >= 20;
      case 4:
        return equipment.length > 0;
      default:
        return true;
    }
  }, [step, name, age, experience, goals, environment, days, minutes, equipment]);

  const helper = useMemo(() => {
    if (canContinue) return null;
    if (step === 0) return 'Add your name and an age between 13 and 90.';
    if (step === 2) return 'Choose at least one goal.';
    if (step === 3) return 'Choose at least one training day.';
    if (step === 4) return 'Choose at least one equipment option.';
    return null;
  }, [canContinue, step]);

  const toggleIn = <T,>(list: T[], value: T, max?: number): T[] => {
    if (list.includes(value)) return list.filter((item) => item !== value);
    if (max && list.length >= max) return list;
    return [...list, value];
  };

  const toggleDay = (day: number) => {
    if (days.includes(day)) {
      if (days.length === 1) return;
      setDays(days.filter((item) => item !== day));
      return;
    }
    if (days.length >= 6) return;
    setDays([...days, day].sort((a, b) => a - b));
  };

  const finish = async () => {
    setError(null);
    if (!user) {
      setError('Your session expired. Sign in again to finish onboarding.');
      return;
    }
    setFinishing(true);
    try {
      const now = new Date().toISOString();
      const nextProfile: Profile = {
        id: user.id,
        name: name.trim(),
        age,
        experience,
        environment,
        goals,
        limitations: limitations.trim() ? limitations.trim() : null,
        onboardingCompleted: true,
        createdAt: existingProfile?.createdAt ?? now,
      };
      const nextPreferences: Preferences = {
        userId: user.id,
        workoutDays: [...days].sort((a, b) => a - b),
        sessionMinutes: minutes,
        equipment,
        avoidExercises: avoid,
        reminderTime,
        units: 'kg',
      };

      await saveProfile(nextProfile);
      await savePreferences(nextPreferences);

      const plan = generateLocalPlan({ userId: user.id, profile: nextProfile, preferences: nextPreferences });
      await savePlan(plan);

      const baseSettings: ReminderSettings = {
        userId: user.id,
        enabled: remindersOn && notificationsSupported,
        workoutTime: reminderTime,
        days: nextPreferences.workoutDays,
        restDayReminders: true,
        hydrationReminders: false,
        weeklyProgressReminder: true,
        scheduledIds: [],
      };

      let reminderMessage = 'Reminders are off. You can turn them on from Profile → Reminders.';
      let scheduledCount = 0;
      let finalSettings = baseSettings;

      if (remindersOn) {
        if (!notificationsSupported) {
          reminderMessage = 'Local reminders run in the iOS or Android app, not in the browser. Nothing was scheduled.';
          finalSettings = { ...baseSettings, enabled: false };
        } else {
          const permission = await requestPermission();
          if (permission !== 'granted') {
            reminderMessage =
              'Notification permission was not granted, so nothing was scheduled. You can enable it later in Profile → Reminders.';
            finalSettings = { ...baseSettings, enabled: false };
          } else {
            const scheduled = await syncReminders(baseSettings, plan);
            if (scheduled.ok) {
              scheduledCount = scheduled.count;
              finalSettings = { ...baseSettings, scheduledIds: scheduled.scheduledIds, enabled: scheduled.count > 0 };
              reminderMessage = scheduled.count
                ? `${scheduled.count} weekly reminders scheduled on this device.`
                : 'No reminders were scheduled — check your reminder settings.';
            } else {
              finalSettings = { ...baseSettings, enabled: false };
              reminderMessage = `${scheduled.message} Nothing was scheduled.`;
            }
          }
        }
      }

      await saveReminders(finalSettings);
      setResult({ plan, reminderMessage, scheduledCount });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Your plan could not be saved. Please try again.');
    } finally {
      setFinishing(false);
    }
  };

  const next = () => {
    if (!canContinue) return;
    if (step === TOTAL_STEPS - 1) {
      void finish();
    } else {
      setError(null);
      setStep((current) => Math.min(TOTAL_STEPS - 1, current + 1));
    }
  };

  const back = () => {
    setError(null);
    if (step === 0) return;
    setStep((current) => Math.max(0, current - 1));
  };

  if (result) {
    return <PlanReady result={result} />;
  }

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <View style={[styles.header, { paddingTop: insets.top + spacing.sm }]}>
        <View style={styles.headerRow}>
          {step > 0 ? (
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Previous step"
              onPress={back}
              hitSlop={8}
              style={({ pressed }) => [
                styles.back,
                { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <ChevronLeft size={19} color={colors.text} strokeWidth={2.2} />
            </Pressable>
          ) : (
            <Wordmark compact />
          )}
          <Text variant="overline" color={colors.textSecondary}>
            {String(step + 1).padStart(2, '0')} / {String(TOTAL_STEPS).padStart(2, '0')}
          </Text>
        </View>
        <View style={[styles.progressTrack, { backgroundColor: colors.surfaceRaised }]}>
          <View
            style={[
              styles.progressFill,
              { backgroundColor: colors.accent, width: `${((step + 1) / TOTAL_STEPS) * 100}%` },
            ]}
          />
        </View>
      </View>

      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 12 : 0}
      >
        <ScrollView
          contentContainerStyle={[styles.content, { paddingBottom: spacing.xxxl }]}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
        >
          <Animated.View style={{ opacity: fade, transform: [{ translateY: rise }] }}>
            {step === 0 ? (
              <>
                <StepHeader
                  eyebrow="About you"
                  title="Let's make this yours."
                  subtitle="A few honest answers now saves guesswork later. Nothing here is shared publicly."
                />
                <Input
                  label="Name"
                  value={name}
                  onChangeText={setName}
                  placeholder="What should the coach call you?"
                  autoCapitalize="words"
                  autoComplete="name"
                  textContentType="name"
                />
                <View style={styles.stepperRow}>
                  <Stepper label="Age" value={age} min={13} max={90} onChange={setAge} suffix="years" />
                </View>
                <Card variant="raised" style={styles.noteCard}>
                  <View style={styles.noteRow}>
                    <ShieldCheck size={17} color={colors.accentText} />
                    <Text variant="caption" style={styles.noteText}>
                      Your age helps calibrate sensible training loads. It is not used for body-image scoring or
                      anything public.
                    </Text>
                  </View>
                </Card>
              </>
            ) : null}

            {step === 1 ? (
              <>
                <StepHeader
                  eyebrow="Experience"
                  title="Where are you starting?"
                  subtitle="Be honest — the plan will meet you there and progress from it."
                />
                <View style={styles.stack}>
                  {(
                    [
                      {
                        value: 'beginner' as const,
                        icon: <Activity size={19} />,
                        body: 'New, or returning after a long break. We keep volume conservative and technique first.',
                      },
                      {
                        value: 'intermediate' as const,
                        icon: <Dumbbell size={19} />,
                        body: 'Training consistently for six months or more. Comfortable with the main movement patterns.',
                      },
                      {
                        value: 'advanced' as const,
                        icon: <Flame size={19} />,
                        body: 'Years of structured training. You know your body and can manage higher intensity.',
                      },
                    ] as const
                  ).map((option) => (
                    <OptionCard
                      key={option.value}
                      title={EXPERIENCE_LABEL[option.value]}
                      body={option.body}
                      icon={option.icon}
                      selected={experience === option.value}
                      onPress={() => setExperience(option.value)}
                    />
                  ))}
                </View>
              </>
            ) : null}

            {step === 2 ? (
              <>
                <StepHeader
                  eyebrow="Direction"
                  title="What are you training for?"
                  subtitle="Pick up to three. You can change this whenever your focus shifts."
                />
                <View style={styles.chipWrap}>
                  {GOALS.map((goal) => (
                    <Chip
                      key={goal}
                      label={GOAL_LABEL[goal]}
                      selected={goals.includes(goal)}
                      onPress={() => setGoals((current) => toggleIn(current, goal, 3))}
                    />
                  ))}
                </View>

                <View style={styles.section}>
                  <Text variant="overline" color={colors.textSecondary}>
                    Where will you train?
                  </Text>
                  <View style={styles.stack}>
                    <OptionCard
                      title="Gym"
                      body="Full equipment access, including machines and cables."
                      icon={<Dumbbell size={19} />}
                      selected={environment === 'gym'}
                      onPress={() => setEnvironment('gym')}
                    />
                    <OptionCard
                      title="Home"
                      body="A mix of bodyweight, dumbbells, bands, or a small setup."
                      icon={<Home size={19} />}
                      selected={environment === 'home'}
                      onPress={() => setEnvironment('home')}
                    />
                    <OptionCard
                      title="Both"
                      body="Sometimes at home, sometimes at the gym."
                      icon={<Layers size={19} />}
                      selected={environment === 'both'}
                      onPress={() => setEnvironment('both')}
                    />
                  </View>
                </View>
              </>
            ) : null}

            {step === 3 ? (
              <>
                <StepHeader
                  eyebrow="Schedule"
                  title="Build the week around your life."
                  subtitle="Choose the days you can realistically show up. Up to six training days; recovery stays in the plan."
                />
                <View>
                  <Text variant="overline" color={colors.textSecondary} style={styles.label}>
                    Training days
                  </Text>
                  <View style={styles.daysRow}>
                    {DAYS.map((day) => {
                      const selected = days.includes(day);
                      return (
                        <Pressable
                          key={day}
                          accessibilityRole="button"
                          accessibilityState={{ selected }}
                          onPress={() => toggleDay(day)}
                          style={({
                            pressed,
                          }) => [
                            styles.day,
                            {
                              backgroundColor: selected ? colors.accent : colors.surface,
                              borderColor: selected ? colors.accent : colors.border,
                              opacity: pressed ? 0.75 : 1,
                            },
                          ]}
                        >
                          <Text
                            variant="label"
                            color={selected ? colors.accentInk : colors.textSecondary}
                            style={styles.dayLabel}
                          >
                            {WEEKDAY_LABEL[day]}
                          </Text>
                        </Pressable>
                      );
                    })}
                  </View>
                  <Text variant="caption" color={colors.textTertiary} style={{ marginTop: 8 }}>
                    {days.length} day{days.length === 1 ? '' : 's'} selected · at least one recovery day stays open.
                  </Text>
                </View>

                <View>
                  <Text variant="overline" color={colors.textSecondary} style={styles.label}>
                    Session length
                  </Text>
                  <View style={styles.chipWrap}>
                    {DURATIONS.map((duration) => (
                      <Chip
                        key={duration}
                        label={`${duration} min`}
                        selected={minutes === duration}
                        onPress={() => setMinutes(duration)}
                      />
                    ))}
                  </View>
                </View>

                <Card variant="raised" style={styles.noteCard}>
                  <View style={styles.noteRow}>
                    <Calendar size={17} color={colors.accentText} />
                    <Text variant="caption" style={styles.noteText}>
                      Consistency beats intensity. Two or three focused sessions per week is a strong foundation.
                    </Text>
                  </View>
                </Card>
              </>
            ) : null}

            {step === 4 ? (
              <>
                <StepHeader
                  eyebrow="Equipment"
                  title="What do you have access to?"
                  subtitle="Your plan only uses movements you can actually do. Bodyweight is always included."
                />
                <View style={styles.chipWrap}>
                  {ALL_EQUIPMENT.map((item) => {
                    const locked = item === 'bodyweight';
                    return (
                      <Chip
                        key={item}
                        label={EQUIPMENT_LABEL[item]}
                        selected={locked || equipment.includes(item)}
                        disabled={locked}
                        onPress={() => setEquipment((current) => toggleIn(current, item))}
                      />
                    );
                  })}
                </View>
                <Card variant="raised" style={styles.noteCard}>
                  <View style={styles.noteRow}>
                    <Dumbbell size={17} color={colors.accentText} />
                    <Text variant="caption" style={styles.noteText}>
                      Not sure? Choose fewer options. You can add equipment later and regenerate the plan.
                    </Text>
                  </View>
                </Card>
              </>
            ) : null}

            {step === 5 ? (
              <>
                <StepHeader
                  eyebrow="Preferences"
                  title="Anything to work around?"
                  subtitle="Optional. This helps the plan avoid movements you would rather skip."
                />
                <Input
                  label="Injuries or limitations (optional)"
                  value={limitations}
                  onChangeText={setLimitations}
                  placeholder="e.g. left knee feels sensitive on deep squats"
                  multiline
                  hint="Forma does not diagnose or treat injuries. For persistent pain, see a qualified professional."
                />

                <Pressable
                  accessibilityRole="button"
                  onPress={() => setAvoidOpen(true)}
                  style={({ pressed }) => [
                    styles.pickerRow,
                    {
                      backgroundColor: colors.surface,
                      borderColor: colors.border,
                      opacity: pressed ? 0.8 : 1,
                    },
                  ]}
                >
                  <View style={[styles.pickerIcon, { backgroundColor: colors.surfaceRaised }]}>
                    <AlertTriangle size={17} color={colors.textSecondary} />
                  </View>
                  <View style={styles.flex}>
                    <Text variant="bodyStrong">Exercises to skip</Text>
                    <Text variant="caption" color={colors.textTertiary}>
                      {avoid.length ? `${avoid.length} selected` : 'None selected'}
                    </Text>
                  </View>
                  <ArrowRight size={17} color={colors.textTertiary} />
                </Pressable>

                <View>
                  <Text variant="overline" color={colors.textSecondary} style={styles.label}>
                    Preferred reminder time
                  </Text>
                  <View style={styles.chipWrap}>
                    {REMINDER_TIMES.map((time) => (
                      <Chip
                        key={time}
                        label={formatTimeOfDay(time)}
                        selected={reminderTime === time}
                        onPress={() => setReminderTime(time)}
                      />
                    ))}
                  </View>
                </View>

                <Card style={styles.toggleCard}>
                  <View style={styles.noteRow}>
                    <View style={[styles.pickerIcon, { backgroundColor: colors.accentSoft }]}>
                      <Bell size={17} color={colors.accentText} />
                    </View>
                    <View style={styles.flex}>
                      <Text variant="bodyStrong">Training reminders</Text>
                      <Text variant="caption" color={colors.textTertiary}>
                        {notificationsSupported
                          ? 'A local reminder on your training days. No spam, no guilt.'
                          : 'Local reminders are available in the iOS and Android app only.'}
                      </Text>
                    </View>
                    <Switch
                      value={remindersOn}
                      onValueChange={setRemindersOn}
                      disabled={!notificationsSupported}
                      trackColor={{ false: colors.surfaceRaised, true: colors.accent }}
                      thumbColor={remindersOn ? colors.accentInk : colors.textTertiary}
                    />
                  </View>
                </Card>
              </>
            ) : null}

            {step === 6 ? (
              <>
                <StepHeader
                  eyebrow="Review"
                  title="Ready to build your base."
                  subtitle="Your plan will be generated on-device from these answers. You can regenerate with AI later."
                />
                <Card style={styles.reviewCard}>
                  <ReviewRow icon={<Sparkles size={16} />} label="Name" value={`${name.trim() || '—'}, ${age}`} />
                  <ReviewRow icon={<Activity size={16} />} label="Experience" value={EXPERIENCE_LABEL[experience]} />
                  <ReviewRow icon={<Layers size={16} />} label="Environment" value={capitalise(environment)} />
                  <ReviewRow
                    icon={<Calendar size={16} />}
                    label="Schedule"
                    value={`${days.map((day) => WEEKDAY_LABEL[day]).join(', ')} · ${minutes} min`}
                  />
                  <ReviewRow
                    icon={<Dumbbell size={16} />}
                    label="Equipment"
                    value={equipment.map((item) => EQUIPMENT_LABEL[item]).join(', ')}
                  />
                  <ReviewRow
                    icon={<Bell size={16} />}
                    label="Reminder"
                    value={
                      notificationsSupported && remindersOn
                        ? `${formatTimeOfDay(reminderTime)} on training days`
                        : 'Off'
                    }
                  />
                  {avoid.length ? (
                    <ReviewRow
                      icon={<AlertTriangle size={16} />}
                      label="Skipping"
                      value={`${avoid.length} exercise${avoid.length === 1 ? '' : 's'}`}
                    />
                  ) : null}
                </Card>
                <Card variant="raised">
                  <Text variant="caption" color={colors.textSecondary}>
                    Forma provides general fitness guidance, not medical advice. Stop any activity that causes pain,
                    dizziness, or unusual shortness of breath, and seek appropriate professional help.
                  </Text>
                </Card>
              </>
            ) : null}
          </Animated.View>
        </ScrollView>

        <View
          style={[
            styles.footer,
            {
              backgroundColor: colors.background,
              borderTopColor: colors.border,
              paddingBottom: insets.bottom + spacing.md,
            },
          ]}
        >
          {helper ? (
            <Text variant="caption" color={colors.textTertiary} align="center">
              {helper}
            </Text>
          ) : null}
          {error ? <InlineError message={error} /> : null}
          <Button
            label={step === TOTAL_STEPS - 1 ? 'Build my plan' : 'Continue'}
            onPress={next}
            disabled={!canContinue || finishing}
            loading={finishing}
            fullWidth
            iconRight={
              step === TOTAL_STEPS - 1 ? (
                <Sparkles size={17} color={colors.accentInk} />
              ) : (
                <ArrowRight size={17} color={colors.accentInk} />
              )
            }
          />
        </View>
      </KeyboardAvoidingView>

      <AvoidExerciseSheet
        visible={avoidOpen}
        exercises={exercises}
        selected={avoid}
        onClose={() => setAvoidOpen(false)}
        onChange={setAvoid}
      />
    </View>
  );
}

function capitalise(value: string) {
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function StepHeader({ eyebrow, title, subtitle }: { eyebrow: string; title: string; subtitle: string }) {
  const { colors } = useTheme();
  return (
    <View style={styles.stepHeader}>
      <Text variant="overline" color={colors.accentText}>
        {eyebrow}
      </Text>
      <Text variant="title">{title}</Text>
      <Text variant="body" color={colors.textSecondary}>
        {subtitle}
      </Text>
    </View>
  );
}

function ReviewRow({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  const { colors } = useTheme();
  return (
    <View style={styles.reviewRow}>
      <View style={[styles.reviewIcon, { backgroundColor: colors.surfaceRaised }]}>{icon}</View>
      <View style={styles.flex}>
        <Text variant="caption" color={colors.textTertiary}>
          {label}
        </Text>
        <Text variant="bodyStrong" style={{ marginTop: 1 }}>
          {value}
        </Text>
      </View>
    </View>
  );
}

function PlanReady({ result }: { result: FinishResult }) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();
  const { plan, reminderMessage } = result;
  const trainingDays = plan.days.filter((day) => !day.isRestDay).length;
  const today = planForDate(plan, new Date());
  const nextDay = today && !today.isRestDay ? today : plan.days.find((day) => !day.isRestDay && day.weekday);
  const scale = useAnimatedValue(0.8);

  useEffect(() => {
    Animated.spring(scale, { toValue: 1, speed: 12, bounciness: 8, useNativeDriver: true }).start();
  }, [scale]);

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={[
          styles.readyContent,
          { paddingTop: insets.top + spacing.xxxl, paddingBottom: insets.bottom + spacing.xxxl },
        ]}
        showsVerticalScrollIndicator={false}
      >
        <Animated.View style={[styles.readyIconWrap, { transform: [{ scale }] }]}>
          <View style={[styles.readyIcon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
            <Check size={36} color={colors.accentText} strokeWidth={2.6} />
          </View>
        </Animated.View>

        <View style={styles.readyHeader}>
          <Text variant="overline" color={colors.accentText}>
            Plan ready
          </Text>
          <Text variant="display">Your base is built.</Text>
          <Text variant="body" color={colors.textSecondary}>
            {plan.name} is saved. Each session has a warm-up, structured sets, rest targets, and a cool-down.
          </Text>
        </View>

        <Card style={styles.readyCard}>
          <View style={styles.readyStats}>
            <ReadyStat label="Days / week" value={String(trainingDays)} />
            <View style={[styles.statDivider, { backgroundColor: colors.border }]} />
            <ReadyStat label="Per session" value={`${plan.sessionMinutes}m`} />
            <View style={[styles.statDivider, { backgroundColor: colors.border }]} />
            <ReadyStat label="Focus" value={GOAL_LABEL[plan.goal].split(' ')[0]} />
          </View>
          {nextDay ? (
            <View style={[styles.nextSession, { borderTopColor: colors.border }]}>
              <Text variant="overline" color={colors.textTertiary}>
                Next session
              </Text>
              <View style={styles.nextRow}>
                <Text variant="heading">{nextDay.title}</Text>
                <Text variant="caption" color={colors.textSecondary}>
                  {nextDay.exercises.length} exercises · {nextDay.estimatedMinutes} min
                </Text>
              </View>
            </View>
          ) : null}
        </Card>

        <Card variant="accent" style={styles.reminderCard}>
          <View style={styles.noteRow}>
            <Bell size={18} color={colors.accentText} />
            <Text variant="caption" style={styles.noteText}>
              {reminderMessage}
            </Text>
          </View>
        </Card>

        <Text variant="caption" color={colors.textTertiary} align="center">
          {isPreviewMode
            ? 'Preview build: everything is stored on this device. Connect Supabase to sync and enable the live AI coach.'
            : 'Generated on-device from your answers. Open Workouts to regenerate with the AI coach whenever you like.'}
        </Text>

        <Button label="Open my dashboard" onPress={() => router.replace('/(tabs)')} fullWidth />
        <Button
          label="Review my plan"
          variant="secondary"
          onPress={() => router.replace('/(tabs)/workouts')}
          fullWidth
        />
      </ScrollView>
    </View>
  );
}

function ReadyStat({ label, value }: { label: string; value: string }) {
  const { colors } = useTheme();
  return (
    <View style={styles.readyStat}>
      <Text variant="number" style={{ fontSize: 24, lineHeight: 27 }}>
        {value}
      </Text>
      <Text variant="caption" color={colors.textTertiary} style={{ fontSize: 10.5 }}>
        {label}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  header: {
    paddingHorizontal: layout.screenPadding,
    paddingBottom: spacing.md,
    gap: spacing.md,
  },
  headerRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  back: {
    width: 38,
    height: 38,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  progressTrack: { height: 3, borderRadius: 2, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: 2 },
  content: {
    paddingHorizontal: layout.screenPadding,
    paddingTop: spacing.xl,
    maxWidth: layout.maxContentWidth,
    width: '100%',
    alignSelf: 'center',
    gap: spacing.xl,
  },
  stepHeader: { gap: spacing.xs, marginBottom: spacing.xs },
  stack: { gap: spacing.sm },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  label: { marginBottom: 9 },
  daysRow: { flexDirection: 'row', gap: 6 },
  day: {
    flex: 1,
    height: 46,
    borderRadius: radii.md,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  dayLabel: { fontSize: 11.5 },
  stepperRow: { maxWidth: 220 },
  noteCard: { padding: spacing.md },
  noteRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  noteText: { flex: 1, lineHeight: 18 },
  section: { gap: spacing.md },
  pickerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.md,
    borderRadius: radii.lg,
    borderWidth: 1,
  },
  pickerIcon: {
    width: 36,
    height: 36,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toggleCard: { padding: spacing.md },
  reviewCard: { gap: spacing.md },
  reviewRow: { flexDirection: 'row', gap: spacing.md, alignItems: 'center' },
  reviewIcon: {
    width: 34,
    height: 34,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  footer: {
    paddingHorizontal: layout.screenPadding,
    paddingTop: spacing.md,
    borderTopWidth: StyleSheet.hairlineWidth,
    gap: spacing.sm,
  },
  readyContent: {
    paddingHorizontal: layout.screenPadding,
    maxWidth: layout.maxContentWidth,
    width: '100%',
    alignSelf: 'center',
    gap: spacing.lg,
  },
  readyIconWrap: { alignItems: 'center', marginBottom: spacing.sm },
  readyIcon: {
    width: 88,
    height: 88,
    borderRadius: 30,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
  },
  readyHeader: { alignItems: 'center', gap: spacing.sm, marginBottom: spacing.sm },
  readyCard: { gap: 0, padding: 0 },
  readyStats: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg },
  readyStat: { flex: 1, alignItems: 'center', gap: 2 },
  statDivider: { width: StyleSheet.hairlineWidth, height: 30 },
  nextSession: { borderTopWidth: StyleSheet.hairlineWidth, padding: spacing.lg, gap: 4 },
  nextRow: { gap: 2 },
  reminderCard: { padding: spacing.md },
  readyNote: { marginTop: 2 },
});
