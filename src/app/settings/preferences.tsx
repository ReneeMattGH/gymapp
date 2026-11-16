import { useRouter } from 'expo-router';
import { ArrowLeft, CheckCircle2, Info, Save } from 'lucide-react-native';
import React, { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { IconButton } from '@/components/ui/IconButton';
import { InlineError } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { AvoidExerciseSheet } from '@/features/onboarding/AvoidExerciseSheet';
import { EQUIPMENT_LABEL, WEEKDAY_LABEL, type Equipment } from '@/data/types';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const EQUIPMENT: Equipment[] = [
  'bodyweight',
  'dumbbells',
  'barbell',
  'kettlebell',
  'resistance-band',
  'cable',
  'machine',
  'bench',
  'pull-up-bar',
  'jump-rope',
];
const MINUTES = [20, 30, 45, 60, 75, 90];
const DAYS = [1, 2, 3, 4, 5, 6, 7];

export default function PreferencesScreen() {
  return (
    <RequireOnboarded>
      <PreferencesContent />
    </RequireOnboarded>
  );
}

function PreferencesContent() {
  const { colors } = useTheme();
  const router = useRouter();
  const { preferences, exercises, savePreferences, user } = useApp();

  const [days, setDays] = useState<number[]>(preferences?.workoutDays ?? [1, 3, 5]);
  const [minutes, setMinutes] = useState(preferences?.sessionMinutes ?? 45);
  const [equipment, setEquipment] = useState<Equipment[]>(
    preferences?.equipment ?? ['bodyweight', 'dumbbells', 'bench'],
  );
  const [avoid, setAvoid] = useState<string[]>(preferences?.avoidExercises ?? []);
  const [units, setUnits] = useState<'kg' | 'lb'>(preferences?.units ?? 'kg');
  const [avoidOpen, setAvoidOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const toggle = <T,>(list: T[], value: T, max?: number): T[] => {
    if (list.includes(value)) return list.filter((item) => item !== value);
    if (max && list.length >= max) return list;
    return [...list, value];
  };

  const toggleDay = (day: number) => {
    setSaved(false);
    if (days.includes(day)) {
      if (days.length === 1) return;
      setDays(days.filter((item) => item !== day));
      return;
    }
    if (days.length >= 6) return;
    setDays([...days, day].sort((a, b) => a - b));
  };

  const save = async () => {
    if (!user) return;
    if (days.length < 1 || days.length > 6) {
      setError('Choose between one and six training days.');
      return;
    }
    if (equipment.length === 0) {
      setError('Choose at least one equipment option, including bodyweight.');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await savePreferences({
        userId: user.id,
        workoutDays: [...days].sort((a, b) => a - b),
        sessionMinutes: minutes,
        equipment,
        avoidExercises: avoid,
        reminderTime: preferences?.reminderTime ?? '18:00',
        units,
      });
      setSaved(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not save your preferences.');
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
        <Text variant="title">Training preferences</Text>
        <Text variant="body" color={colors.textSecondary} style={{ marginTop: 4 }}>
          These shape your next generated plan and the coach&apos;s recommendations.
        </Text>
      </View>

      <Card>
        <View style={styles.form}>
          <View style={styles.fieldGroup}>
            <View style={styles.labelRow}>
              <Text variant="label" color={colors.textSecondary}>
                Training days
              </Text>
              <Text variant="caption" color={colors.textTertiary}>
                {days.length} of 7
              </Text>
            </View>
            <View style={styles.chipWrap}>
              {DAYS.map((day) => (
                <Chip
                  key={day}
                  label={WEEKDAY_LABEL[day]}
                  selected={days.includes(day)}
                  onPress={() => toggleDay(day)}
                />
              ))}
            </View>
            <Text variant="caption" color={colors.textTertiary}>
              Choose one to six days. Rest days fill the rest of the week.
            </Text>
          </View>

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Session length
            </Text>
            <View style={styles.chipWrap}>
              {MINUTES.map((value) => (
                <Chip
                  key={value}
                  label={`${value} min`}
                  selected={minutes === value}
                  onPress={() => {
                    setMinutes(value);
                    setSaved(false);
                  }}
                />
              ))}
            </View>
          </View>

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Equipment available
            </Text>
            <View style={styles.chipWrap}>
              {EQUIPMENT.map((item) => (
                <Chip
                  key={item}
                  label={EQUIPMENT_LABEL[item]}
                  selected={equipment.includes(item)}
                  onPress={() => {
                    setEquipment((current) => toggle(current, item));
                    setSaved(false);
                  }}
                />
              ))}
            </View>
          </View>

          <View style={styles.fieldGroup}>
            <Text variant="label" color={colors.textSecondary}>
              Weight units
            </Text>
            <View style={styles.chipWrap}>
              <Chip
                label="Kilograms"
                selected={units === 'kg'}
                onPress={() => {
                  setUnits('kg');
                  setSaved(false);
                }}
              />
              <Chip
                label="Pounds"
                selected={units === 'lb'}
                onPress={() => {
                  setUnits('lb');
                  setSaved(false);
                }}
              />
            </View>
            <Text variant="caption" color={colors.textTertiary}>
              Stored in kilograms. Displayed in your chosen unit throughout the app.
            </Text>
          </View>

          <Pressable
            accessibilityRole="button"
            onPress={() => setAvoidOpen(true)}
            style={({ pressed }) => [
              styles.avoidRow,
              { borderColor: colors.border, backgroundColor: colors.surfaceRaised, opacity: pressed ? 0.8 : 1 },
            ]}
          >
            <View style={styles.flex}>
              <Text variant="bodyStrong">Exercises to skip</Text>
              <Text variant="caption" style={{ marginTop: 2 }}>
                {avoid.length === 0
                  ? 'None selected'
                  : `${avoid.length} exercise${avoid.length === 1 ? '' : 's'} excluded`}
              </Text>
            </View>
            <Text variant="label" color={colors.accentText}>
              Choose
            </Text>
          </Pressable>
        </View>
      </Card>

      {error ? <InlineError message={error} /> : null}

      <Pressable
        accessibilityRole="button"
        onPress={save}
        disabled={saving}
        style={({ pressed }) => [
          styles.primary,
          { backgroundColor: colors.accent, opacity: saving ? 0.6 : pressed ? 0.85 : 1 },
        ]}
      >
        {saved ? (
          <CheckCircle2 size={16} color={colors.accentInk} />
        ) : (
          <Save size={16} color={colors.accentInk} />
        )}
        <Text variant="label" color={colors.accentInk}>
          {saving ? 'Saving…' : saved ? 'Saved' : 'Save preferences'}
        </Text>
      </Pressable>

      <View style={styles.note}>
        <Info size={14} color={colors.textTertiary} />
        <Text variant="caption" color={colors.textTertiary} style={styles.flex}>
          Your current plan is unchanged until you regenerate it. New sessions follow the new preferences.
        </Text>
      </View>

      <Pressable
        accessibilityRole="button"
        onPress={() => router.push('/plan/generate')}
        style={({ pressed }) => [
          styles.secondary,
          { borderColor: colors.accentBorder, opacity: pressed ? 0.8 : 1 },
        ]}
      >
        <Text variant="label" color={colors.accentText}>
          Regenerate my plan
        </Text>
      </Pressable>

      <AvoidExerciseSheet
        visible={avoidOpen}
        exercises={exercises}
        selected={avoid}
        onClose={() => setAvoidOpen(false)}
        onChange={(ids) => {
          setAvoid(ids);
          setSaved(false);
        }}
      />
    </Screen>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  content: { gap: spacing.lg },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  form: { gap: spacing.lg },
  fieldGroup: { gap: spacing.sm },
  labelRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  avoidRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    padding: spacing.md,
  },
  primary: {
    height: 52,
    borderRadius: radii.md,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
  },
  note: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  secondary: {
    height: 48,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
