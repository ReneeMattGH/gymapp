import { useRouter } from 'expo-router';
import { Bot, Info, Sparkles, Wand2, X } from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Button } from '@/components/ui/Button';
import { Chip } from '@/components/ui/Chip';
import { InlineError } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import {
  EQUIPMENT_LABEL,
  EXPERIENCE_LABEL,
  GOAL_LABEL,
  WEEKDAY_LABEL,
  type Equipment,
  type Experience,
  type Goal,
  type Preferences,
  type Profile,
} from '@/data/types';
import { aiConfigured, requestAiPlan } from '@/lib/ai';
import { generateLocalPlan, planFromAiPayload } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

const EXPERIENCES: Experience[] = ['beginner', 'intermediate', 'advanced'];
const GOALS: Goal[] = ['strength', 'endurance', 'mobility', 'general', 'consistency'];
const DAYS = [1, 2, 3, 4, 5, 6, 7];
const DURATIONS = [20, 30, 45, 60, 75];
const ALL_EQUIPMENT = Object.keys(EQUIPMENT_LABEL) as Equipment[];

export default function GeneratePlanScreen() {
  return (
    <RequireOnboarded>
      <GeneratePlanContent />
    </RequireOnboarded>
  );
}

function GeneratePlanContent() {
  const { colors } = useTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user, profile, preferences, saveProfile, savePreferences, savePlan } = useApp();

  const [experience, setExperience] = useState<Experience>(profile?.experience ?? 'beginner');
  const [goal, setGoal] = useState<Goal>(profile?.goals[0] ?? 'general');
  const [days, setDays] = useState<number[]>(
    preferences?.workoutDays.length ? preferences.workoutDays : [1, 3, 5],
  );
  const [minutes, setMinutes] = useState<number>(preferences?.sessionMinutes ?? 45);
  const [equipment, setEquipment] = useState<Equipment[]>(
    preferences?.equipment.length ? preferences.equipment : ['bodyweight'],
  );
  const [busy, setBusy] = useState<'ai' | 'local' | null>(null);
  const [error, setError] = useState<string | null>(null);

  const canGenerate = days.length > 0 && equipment.length > 0 && !busy;
  const sortedDays = useMemo(() => [...days].sort((a, b) => a - b), [days]);

  const toggleDay = (day: number) => {
    setDays((current) =>
      current.includes(day)
        ? current.length === 1
          ? current
          : current.filter((item) => item !== day)
        : [...current, day],
    );
  };

  const toggleEquipment = (item: Equipment) => {
    setEquipment((current) =>
      current.includes(item) ? current.filter((value) => value !== item) : [...current, item],
    );
  };

  const generate = async (mode: 'ai' | 'local') => {
    if (!user || !profile || !preferences || !canGenerate) return;
    setError(null);
    setBusy(mode);

    const nextProfile: Profile = { ...profile, experience, goals: [goal] };
    const nextPreferences: Preferences = {
      ...preferences,
      workoutDays: sortedDays,
      sessionMinutes: minutes,
      equipment,
    };

    try {
      if (mode === 'ai') {
        // The Edge Function reads the saved profile and preferences, so persist the
        // chosen options before asking the coach to generate.
        await saveProfile(nextProfile);
        await savePreferences(nextPreferences);
        const payload = await requestAiPlan();
        const built = planFromAiPayload(payload, {
          userId: user.id,
          profile: nextProfile,
          preferences: nextPreferences,
        });
        if (!built) {
          throw new Error(
            'The AI plan did not pass validation. Try again, or generate the on-device plan below.',
          );
        }
        await savePlan(built);
      } else {
        const built = generateLocalPlan({ userId: user.id, profile: nextProfile, preferences: nextPreferences });
        await savePreferences(nextPreferences);
        await saveProfile(nextProfile);
        await savePlan(built);
      }
      if (router.canGoBack()) router.back();
      else router.replace('/(tabs)/workouts');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not generate the plan.');
    } finally {
      setBusy(null);
    }
  };

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <ScrollView
        contentContainerStyle={[styles.content, { paddingTop: insets.top + spacing.md }]}
        showsVerticalScrollIndicator={false}
      >
        <View style={styles.header}>
          <View style={styles.flex}>
            <Text variant="overline" color={colors.textTertiary}>
              Plan builder
            </Text>
            <Text variant="title" style={{ marginTop: 2 }}>
              Build your week
            </Text>
          </View>
          <Pressable
            onPress={() => (router.canGoBack() ? router.back() : router.replace('/(tabs)/workouts'))}
            accessibilityRole="button"
            accessibilityLabel="Close"
            style={({ pressed }) => [
              styles.close,
              { backgroundColor: colors.surfaceRaised, borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
            ]}
          >
            <X size={18} color={colors.text} />
          </Pressable>
        </View>

        <Text variant="body" color={colors.textSecondary}>
          Choose how you want to train. Your preferences are saved and the new plan replaces the
          current one.
        </Text>

        <Section title="Experience" caption="Sets and exercise difficulty follow this.">
          <View style={styles.chipRow}>
            {EXPERIENCES.map((item) => (
              <Chip
                key={item}
                label={EXPERIENCE_LABEL[item]}
                selected={experience === item}
                onPress={() => setExperience(item)}
              />
            ))}
          </View>
        </Section>

        <Section title="Primary goal" caption="This shapes rep ranges and rest periods.">
          <View style={styles.chipRow}>
            {GOALS.map((item) => (
              <Chip key={item} label={GOAL_LABEL[item]} selected={goal === item} onPress={() => setGoal(item)} />
            ))}
          </View>
        </Section>

        <Section title="Training days" caption="At least one day. Keep rest days between hard sessions.">
          <View style={styles.chipRow}>
            {DAYS.map((day) => (
              <Chip
                key={day}
                label={WEEKDAY_LABEL[day]}
                selected={days.includes(day)}
                onPress={() => toggleDay(day)}
              />
            ))}
          </View>
        </Section>

        <Section title="Session length" caption="Includes warm-up and cool-down.">
          <View style={styles.chipRow}>
            {DURATIONS.map((item) => (
              <Chip
                key={item}
                label={`${item} min`}
                selected={minutes === item}
                onPress={() => setMinutes(item)}
              />
            ))}
          </View>
        </Section>

        <Section title="Equipment" caption="Only exercises that match your setup are used.">
          <View style={styles.chipRow}>
            {ALL_EQUIPMENT.map((item) => (
              <Chip
                key={item}
                label={EQUIPMENT_LABEL[item]}
                selected={equipment.includes(item)}
                onPress={() => toggleEquipment(item)}
              />
            ))}
          </View>
        </Section>

        {error ? <InlineError message={error} /> : null}

        {aiConfigured ? (
          <View style={[styles.aiNote, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
            <Sparkles size={16} color={colors.accentText} />
            <Text variant="caption" color={colors.textSecondary} style={styles.flex}>
              The AI coach will design the week around these settings, using safe, conservative
              volume for your experience level.
            </Text>
          </View>
        ) : (
          <View style={[styles.aiNote, { backgroundColor: colors.surface, borderColor: colors.border }]}>
            <Info size={16} color={colors.textTertiary} />
            <Text variant="caption" color={colors.textSecondary} style={styles.flex}>
              Live AI plan generation needs Supabase and OpenAI configured. Until then, the
              on-device generator builds a complete plan from the same exercise library.
            </Text>
          </View>
        )}

        <View style={styles.actions}>
          <Button
            label={aiConfigured ? 'Generate with AI coach' : 'AI coach not connected'}
            icon={<Bot size={17} color={aiConfigured ? colors.accentInk : colors.textTertiary} />}
            disabled={!aiConfigured || !canGenerate}
            loading={busy === 'ai'}
            onPress={() => generate('ai')}
            fullWidth
          />
          <Button
            label="Generate on this device"
            variant="secondary"
            icon={<Wand2 size={17} color={colors.text} />}
            disabled={!canGenerate}
            loading={busy === 'local'}
            onPress={() => generate('local')}
            fullWidth
          />
          <Text variant="caption" color={colors.textTertiary} align="center" style={styles.disclaimer}>
            Plans use conservative volume. If anything hurts, stop and seek professional advice.
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

function Section({
  title,
  caption,
  children,
}: {
  title: string;
  caption: string;
  children: React.ReactNode;
}) {
  const { colors } = useTheme();
  return (
    <View style={styles.section}>
      <View style={styles.sectionHeader}>
        <Text variant="subheading">{title}</Text>
        <Text variant="caption" color={colors.textTertiary}>
          {caption}
        </Text>
      </View>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: {
    paddingHorizontal: layout.screenPadding,
    paddingBottom: 40,
    gap: spacing.xl,
    maxWidth: layout.maxContentWidth + 40,
    width: '100%',
    alignSelf: 'center',
  },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  close: {
    width: 40,
    height: 40,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  section: { gap: spacing.sm },
  sectionHeader: { gap: 2 },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  aiNote: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.sm,
    padding: spacing.md,
    borderRadius: radii.lg,
    borderWidth: StyleSheet.hairlineWidth,
  },
  actions: { gap: spacing.md, marginTop: spacing.sm },
  disclaimer: { maxWidth: 320, alignSelf: 'center' },
});
