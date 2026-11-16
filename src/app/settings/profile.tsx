import { useRouter } from 'expo-router';
import { ArrowLeft, CheckCircle2, Info, Save } from 'lucide-react-native';
import React, { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { IconButton } from '@/components/ui/IconButton';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import type { Environment, Experience, Goal } from '@/data/types';
import { EXPERIENCE_LABEL, GOAL_LABEL } from '@/data/types';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const EXPERIENCES: Experience[] = ['beginner', 'intermediate', 'advanced'];
const ENVIRONMENTS: { value: Environment; label: string }[] = [
  { value: 'home', label: 'Home' },
  { value: 'gym', label: 'Gym' },
  { value: 'both', label: 'Both' },
];
const GOALS: Goal[] = ['strength', 'endurance', 'mobility', 'general', 'consistency'];

export default function ProfileSettingsScreen() {
  return (
    <RequireOnboarded>
      <ProfileSettings />
    </RequireOnboarded>
  );
}

function ProfileSettings() {
  const { colors } = useTheme();
  const router = useRouter();
  const { profile, saveProfile, user } = useApp();

  const [name, setName] = useState(profile?.name ?? '');
  const [age, setAge] = useState(profile?.age ? String(profile.age) : '');
  const [experience, setExperience] = useState<Experience>(profile?.experience ?? 'beginner');
  const [environment, setEnvironment] = useState<Environment>(profile?.environment ?? 'both');
  const [goals, setGoals] = useState<Goal[]>(profile?.goals ?? []);
  const [limitations, setLimitations] = useState(profile?.limitations ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggleGoal = (goal: Goal) => {
    setSaved(false);
    setGoals((current) =>
      current.includes(goal) ? current.filter((item) => item !== goal) : [...current, goal],
    );
  };

  const save = async () => {
    if (!user) return;
    const trimmedName = name.trim();
    if (trimmedName.length < 2) {
      setError('Enter your name — at least two characters.');
      return;
    }
    const ageNumber = age.trim() ? Number(age.trim()) : null;
    if (ageNumber !== null && (!Number.isFinite(ageNumber) || ageNumber < 13 || ageNumber > 90)) {
      setError('Enter an age between 13 and 90, or leave it blank.');
      return;
    }
    if (goals.length === 0) {
      setError('Choose at least one goal.');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await saveProfile({
        id: user.id,
        name: trimmedName,
        age: ageNumber,
        experience,
        environment,
        goals,
        limitations: limitations.trim() ? limitations.trim() : null,
        onboardingCompleted: profile?.onboardingCompleted ?? true,
        createdAt: profile?.createdAt ?? new Date().toISOString(),
      });
      setSaved(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save your profile.');
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
            Settings
          </Text>
        </View>
      </View>

      <View>
        <Text variant="title">Your profile</Text>
        <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
          Used by the coach and your plan. Update it whenever your training changes.
        </Text>
      </View>

      <Card>
        <View style={styles.form}>
          <Input
            label="Name"
            value={name}
            onChangeText={(value) => {
              setName(value);
              setSaved(false);
            }}
            autoCapitalize="words"
            maxLength={60}
          />
          <Input
            label="Age (optional)"
            value={age}
            onChangeText={(value) => {
              setAge(value.replace(/[^0-9]/g, ''));
              setSaved(false);
            }}
            keyboardType="number-pad"
            maxLength={2}
            hint="Helps calibrate conservative training advice. Never shown publicly."
          />

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Experience
            </Text>
            <View style={styles.chipWrap}>
              {EXPERIENCES.map((value) => (
                <Chip
                  key={value}
                  label={EXPERIENCE_LABEL[value]}
                  selected={experience === value}
                  onPress={() => {
                    setExperience(value);
                    setSaved(false);
                  }}
                />
              ))}
            </View>
          </View>

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Where you train
            </Text>
            <View style={styles.chipWrap}>
              {ENVIRONMENTS.map((item) => (
                <Chip
                  key={item.value}
                  label={item.label}
                  selected={environment === item.value}
                  onPress={() => {
                    setEnvironment(item.value);
                    setSaved(false);
                  }}
                />
              ))}
            </View>
          </View>

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Goals
            </Text>
            <View style={styles.chipWrap}>
              {GOALS.map((goal) => (
                <Chip
                  key={goal}
                  label={GOAL_LABEL[goal]}
                  selected={goals.includes(goal)}
                  onPress={() => toggleGoal(goal)}
                />
              ))}
            </View>
          </View>

          <Input
            label="Limitations or injuries"
            value={limitations}
            onChangeText={(value) => {
              setLimitations(value);
              setSaved(false);
            }}
            multiline
            maxLength={400}
            placeholder="Anything the plan should work around"
            hint="Descriptive only. Forma cannot diagnose an injury; follow your clinician's guidance."
          />
        </View>
      </Card>

      {error ? <InlineError message={error} /> : null}

      <View style={styles.actions}>
        <Pressable
          accessibilityRole="button"
          onPress={save}
          disabled={saving}
          style={({ pressed }) => [
            styles.primary,
            {
              backgroundColor: colors.accent,
              opacity: saving ? 0.6 : pressed ? 0.85 : 1,
            },
          ]}
        >
          {saved ? (
            <CheckCircle2 size={16} color={colors.accentInk} />
          ) : (
            <Save size={16} color={colors.accentInk} />
          )}
          <Text variant="label" color={colors.accentInk}>
            {saving ? 'Saving…' : saved ? 'Saved' : 'Save profile'}
          </Text>
        </Pressable>
      </View>

      <View style={styles.note}>
        <Info size={14} color={colors.textTertiary} />
        <Text variant="caption" color={colors.textTertiary} style={styles.flex}>
          Your saved plan stays as it is. Regenerate it from Plan when you want these changes reflected in the
          weekly sessions.
        </Text>
      </View>
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { gap: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  form: { gap: spacing.lg },
  fieldGroup: { gap: spacing.sm },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  actions: { gap: spacing.sm },
  primary: {
    height: 52,
    borderRadius: radii.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  note: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
});
