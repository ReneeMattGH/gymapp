import { useRouter } from 'expo-router';
import { ChevronRight, Search, SlidersHorizontal, X } from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, ScrollView, StyleSheet, View } from 'react-native';

import { RequireOnboarded } from '@/components/auth/RequireOnboarded';
import { Chip } from '@/components/ui/Chip';
import { ExerciseArt } from '@/components/ui/ExerciseArt';
import { IconButton } from '@/components/ui/IconButton';
import { Input } from '@/components/ui/Input';
import { Badge, EmptyState } from '@/components/ui/Misc';
import { Screen } from '@/components/ui/Screen';
import { Sheet } from '@/components/ui/Sheet';
import { Text } from '@/components/ui/Text';
import {
  EQUIPMENT_LABEL,
  MUSCLE_LABEL,
  type Difficulty,
  type Equipment,
  type LibraryFilters,
  type MuscleGroup,
} from '@/data/types';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const CATEGORIES: { value: LibraryFilters['category']; label: string }[] = [
  { value: 'all', label: 'All' },
  { value: 'strength', label: 'Strength' },
  { value: 'conditioning', label: 'Conditioning' },
  { value: 'mobility', label: 'Mobility' },
];

const EMPTY_FILTERS: LibraryFilters = {
  query: '',
  category: 'all',
  muscle: 'all',
  equipment: 'all',
  difficulty: 'all',
};

const MUSCLES = Object.keys(MUSCLE_LABEL) as MuscleGroup[];
const EQUIPMENT = Object.keys(EQUIPMENT_LABEL) as Equipment[];
const DIFFICULTIES: Difficulty[] = ['beginner', 'intermediate', 'advanced'];

export default function ExerciseLibraryScreen() {
  return (
    <RequireOnboarded>
      <ExerciseLibrary />
    </RequireOnboarded>
  );
}

function ExerciseLibrary() {
  const { colors } = useTheme();
  const router = useRouter();
  const { exercises } = useApp();
  const [filters, setFilters] = useState<LibraryFilters>(EMPTY_FILTERS);
  const [filterVisible, setFilterVisible] = useState(false);

  const activeFilterCount = (filters.muscle !== 'all' ? 1 : 0) + (filters.equipment !== 'all' ? 1 : 0) + (filters.difficulty !== 'all' ? 1 : 0);

  const results = useMemo(() => {
    const query = filters.query.trim().toLowerCase();
    return exercises
      .filter((exercise) => {
        if (filters.category !== 'all' && exercise.category !== filters.category) return false;
        if (filters.muscle !== 'all' && !exercise.primaryMuscles.includes(filters.muscle)) return false;
        if (filters.equipment !== 'all' && !exercise.equipment.includes(filters.equipment)) return false;
        if (filters.difficulty !== 'all' && exercise.difficulty !== filters.difficulty) return false;
        if (!query) return true;
        const haystack = [
          exercise.name,
          exercise.category,
          exercise.difficulty,
          ...exercise.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]),
          ...exercise.secondaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]),
          ...exercise.equipment.map((item) => EQUIPMENT_LABEL[item]),
        ]
          .join(' ')
          .toLowerCase();
        return haystack.includes(query);
      })
      .sort((a, b) => a.name.localeCompare(b.name));
  }, [exercises, filters]);

  return (
    <>
      <Screen scroll contentContainerStyle={styles.content}>
        <View style={styles.header}>
          <View style={styles.flex}>
            <Text variant="title">Exercise library</Text>
            <Text variant="caption" style={{ marginTop: 2 }}>
              {exercises.length} movements with instructions, cues and swaps
            </Text>
          </View>
          <IconButton accessibilityLabel="Go back" onPress={() => router.back()} size={38}>
            <X size={17} color={colors.text} />
          </IconButton>
        </View>

        <Input
          value={filters.query}
          onChangeText={(query) => setFilters((current) => ({ ...current, query }))}
          placeholder="Search exercise, muscle or equipment"
          autoCapitalize="none"
          autoCorrect={false}
          returnKeyType="search"
          right={
            filters.query ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Clear search"
                hitSlop={8}
                onPress={() => setFilters((current) => ({ ...current, query: '' }))}
              >
                <X size={16} color={colors.textTertiary} />
              </Pressable>
            ) : (
              <Search size={17} color={colors.textTertiary} />
            )
          }
        />

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          contentContainerStyle={styles.categoryRow}
          style={styles.categoryScroll}
        >
          {CATEGORIES.map((category) => (
            <Chip
              key={category.value}
              label={category.label}
              selected={filters.category === category.value}
              onPress={() => setFilters((current) => ({ ...current, category: category.value }))}
            />
          ))}
          <Pressable
            onPress={() => setFilterVisible(true)}
            accessibilityRole="button"
            accessibilityLabel="Open filters"
            style={({ pressed }) => [
              styles.filterButton,
              {
                backgroundColor: activeFilterCount > 0 ? colors.accentSoft : colors.surface,
                borderColor: activeFilterCount > 0 ? colors.accentBorder : colors.border,
                opacity: pressed ? 0.7 : 1,
              },
            ]}
          >
            <SlidersHorizontal size={14} color={activeFilterCount > 0 ? colors.accentText : colors.textSecondary} />
            <Text variant="label" color={activeFilterCount > 0 ? colors.accentText : colors.textSecondary}>
              Filters{activeFilterCount > 0 ? ` · ${activeFilterCount}` : ''}
            </Text>
          </Pressable>
        </ScrollView>

        <View style={styles.resultRow}>
          <Text variant="caption" color={colors.textTertiary}>
            {results.length} result{results.length === 1 ? '' : 's'}
          </Text>
          {filters.muscle !== 'all' || filters.equipment !== 'all' || filters.difficulty !== 'all' ? (
            <Pressable
              onPress={() => setFilters((current) => ({ ...EMPTY_FILTERS, query: current.query, category: current.category }))}
              accessibilityRole="button"
              hitSlop={8}
            >
              <Text variant="caption" color={colors.accentText}>
                Clear filters
              </Text>
            </Pressable>
          ) : null}
        </View>

        {results.length === 0 ? (
          <EmptyState
            icon={<Search size={24} color={colors.accentText} />}
            title="No matching exercises"
            message="Try a broader search or remove a filter. Every movement in the plan comes from this library."
            action={
              <Pressable
                onPress={() => setFilters(EMPTY_FILTERS)}
                accessibilityRole="button"
                style={({ pressed }) => [
                  styles.clearButton,
                  { borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
                ]}
              >
                <Text variant="label" color={colors.accentText}>
                  Reset search & filters
                </Text>
              </Pressable>
            }
          />
        ) : (
          <View style={styles.list}>
            {results.map((exercise) => (
              <Pressable
                key={exercise.id}
                accessibilityRole="button"
                accessibilityLabel={`${exercise.name}, ${exercise.difficulty}`}
                onPress={() => router.push(`/exercise/${exercise.id}`)}
                style={({ pressed }) => [
                  styles.row,
                  { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.75 : 1 },
                ]}
              >
                <View style={styles.thumb}>
                  <ExerciseArt
                    id={exercise.id}
                    muscle={exercise.primaryMuscles[0]}
                    category={exercise.category}
                    height={74}
                    compact
                    label={exercise.category}
                    style={styles.thumbArt}
                  />
                </View>
                <View style={styles.flex}>
                  <Text variant="bodyStrong" numberOfLines={1} style={styles.name}>
                    {exercise.name}
                  </Text>
                  <Text variant="caption" numberOfLines={1}>
                    {exercise.primaryMuscles.map((muscle) => MUSCLE_LABEL[muscle]).join(' · ')}
                  </Text>
                  <Text variant="caption" color={colors.textTertiary} numberOfLines={1}>
                    {exercise.equipment.map((item) => EQUIPMENT_LABEL[item]).join(', ')}
                  </Text>
                </View>
                <ChevronRight size={16} color={colors.textTertiary} />
              </Pressable>
            ))}
          </View>
        )}
      </Screen>

      <Sheet
        visible={filterVisible}
        onClose={() => setFilterVisible(false)}
        title="Filters"
        subtitle="Narrow by muscle, equipment and difficulty."
      >
        <ScrollView contentContainerStyle={styles.filterSheet} showsVerticalScrollIndicator={false}>
          <View style={styles.filterGroup}>
            <Text variant="overline" color={colors.textTertiary}>
              Muscle group
            </Text>
            <View style={styles.chipWrap}>
              <Chip
                label="Any"
                selected={filters.muscle === 'all'}
                onPress={() => setFilters((current) => ({ ...current, muscle: 'all' }))}
              />
              {MUSCLES.map((muscle) => (
                <Chip
                  key={muscle}
                  label={MUSCLE_LABEL[muscle]}
                  selected={filters.muscle === muscle}
                  onPress={() => setFilters((current) => ({ ...current, muscle }))}
                />
              ))}
            </View>
          </View>

          <View style={styles.filterGroup}>
            <Text variant="overline" color={colors.textTertiary}>
              Equipment
            </Text>
            <View style={styles.chipWrap}>
              <Chip
                label="Any"
                selected={filters.equipment === 'all'}
                onPress={() => setFilters((current) => ({ ...current, equipment: 'all' }))}
              />
              {EQUIPMENT.map((equipment) => (
                <Chip
                  key={equipment}
                  label={EQUIPMENT_LABEL[equipment]}
                  selected={filters.equipment === equipment}
                  onPress={() => setFilters((current) => ({ ...current, equipment }))}
                />
              ))}
            </View>
          </View>

          <View style={styles.filterGroup}>
            <Text variant="overline" color={colors.textTertiary}>
              Difficulty
            </Text>
            <View style={styles.chipWrap}>
              <Chip
                label="Any"
                selected={filters.difficulty === 'all'}
                onPress={() => setFilters((current) => ({ ...current, difficulty: 'all' }))}
              />
              {DIFFICULTIES.map((difficulty) => (
                <Chip
                  key={difficulty}
                  label={difficulty.charAt(0).toUpperCase() + difficulty.slice(1)}
                  selected={filters.difficulty === difficulty}
                  onPress={() => setFilters((current) => ({ ...current, difficulty }))}
                />
              ))}
            </View>
          </View>

          <View style={styles.filterActions}>
            <Chip
              label="Clear all filters"
              onPress={() =>
                setFilters((current) => ({
                  ...EMPTY_FILTERS,
                  query: current.query,
                  category: current.category,
                }))
              }
            />
            <Pressable onPress={() => setFilterVisible(false)} accessibilityRole="button">
              <Badge label={`Show ${results.length} results`} tone="accent" />
            </Pressable>
          </View>
        </ScrollView>
      </Sheet>
    </>
  );
}

const styles = StyleSheet.create({
  content: { gap: spacing.md },
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'flex-start', gap: spacing.md },
  categoryScroll: { marginHorizontal: -spacing.xl },
  categoryRow: { gap: spacing.sm, paddingHorizontal: spacing.xl, alignItems: 'center' },
  filterButton: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    height: 38,
    paddingHorizontal: spacing.md + 2,
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
  },
  resultRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  list: { gap: spacing.sm },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.sm,
    borderRadius: radii.lg,
    borderWidth: StyleSheet.hairlineWidth,
  },
  thumb: { width: 74, height: 74, borderRadius: 15, overflow: 'hidden' },
  thumbArt: { width: 74, borderRadius: 15 },
  name: { marginBottom: 1 },
  clearButton: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.pill,
    paddingHorizontal: spacing.lg,
    paddingVertical: 9,
  },
  filterSheet: { gap: spacing.lg, paddingBottom: spacing.lg },
  filterGroup: { gap: spacing.sm },
  chipWrap: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  filterActions: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md },
});
