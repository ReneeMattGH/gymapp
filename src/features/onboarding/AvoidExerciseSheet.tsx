import { Check } from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { Input } from '@/components/ui/Input';
import { Sheet } from '@/components/ui/Sheet';
import { Button } from '@/components/ui/Button';
import { Text } from '@/components/ui/Text';
import type { Exercise } from '@/data/types';
import { MUSCLE_LABEL } from '@/data/types';
import { useTheme } from '@/theme/ThemeProvider';
import { spacing } from '@/theme/tokens';

type Props = {
  visible: boolean;
  exercises: Exercise[];
  selected: string[];
  onClose: () => void;
  onChange: (ids: string[]) => void;
};

export function AvoidExerciseSheet({ visible, exercises, selected, onClose, onChange }: Props) {
  const { colors } = useTheme();
  const [query, setQuery] = useState('');

  const filtered = useMemo(() => {
    const text = query.trim().toLowerCase();
    if (!text) return exercises;
    return exercises.filter(
      (exercise) =>
        exercise.name.toLowerCase().includes(text) ||
        exercise.primaryMuscles.some((muscle) => MUSCLE_LABEL[muscle].toLowerCase().includes(text)),
    );
  }, [exercises, query]);

  const toggle = (id: string) => {
    onChange(selected.includes(id) ? selected.filter((item) => item !== id) : [...selected, id]);
  };

  return (
    <Sheet
      visible={visible}
      onClose={onClose}
      title="Exercises to skip"
      subtitle="Your plan will not include these. You can change this at any time."
    >
      <Input
        placeholder="Search exercises"
        value={query}
        onChangeText={setQuery}
        autoCapitalize="none"
        containerStyle={styles.search}
      />
      <ScrollView style={styles.list} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
        {filtered.map((exercise) => {
          const active = selected.includes(exercise.id);
          return (
            <Pressable
              key={exercise.id}
              accessibilityRole="checkbox"
              accessibilityState={{ checked: active }}
              onPress={() => toggle(exercise.id)}
              style={({ pressed }) => [
                styles.row,
                { borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <View
                style={[
                  styles.check,
                  {
                    borderColor: active ? colors.accent : colors.borderStrong,
                    backgroundColor: active ? colors.accent : 'transparent',
                  },
                ]}
              >
                {active ? <Check size={13} color={colors.accentInk} strokeWidth={3} /> : null}
              </View>
              <View style={styles.rowText}>
                <Text variant="bodyStrong">{exercise.name}</Text>
                <Text variant="caption" color={colors.textTertiary}>
                  {exercise.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')}
                </Text>
              </View>
            </Pressable>
          );
        })}
        {filtered.length === 0 ? (
          <Text variant="caption" color={colors.textTertiary} style={styles.empty}>
            No exercises match that search.
          </Text>
        ) : null}
      </ScrollView>
      <Button label={selected.length ? `Done · ${selected.length} selected` : 'Done'} onPress={onClose} fullWidth />
    </Sheet>
  );
}

const styles = StyleSheet.create({
  search: { marginBottom: spacing.xs },
  list: { maxHeight: 380 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    paddingVertical: 11,
    paddingHorizontal: 4,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  check: {
    width: 22,
    height: 22,
    borderRadius: 7,
    borderWidth: 1.4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rowText: { flex: 1 },
  empty: { paddingVertical: spacing.xl, textAlign: 'center' },
});
