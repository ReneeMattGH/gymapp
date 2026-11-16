import { addDays, format, startOfWeek, subWeeks } from 'date-fns';
import React from 'react';
import { StyleSheet, View } from 'react-native';

import { Text } from '@/components/ui/Text';
import { useTheme } from '@/theme/ThemeProvider';

type Props = {
  /** Date keys (yyyy-MM-dd) of days with at least one completed session. */
  activeDays: Set<string>;
  weeks?: number;
};

export function ActivityHeatmap({ activeDays, weeks = 14 }: Props) {
  const { colors } = useTheme();
  const today = new Date();
  const start = startOfWeek(subWeeks(today, weeks - 1), { weekStartsOn: 1 });

  const columns = Array.from({ length: weeks }, (_, weekIndex) =>
    Array.from({ length: 7 }, (_, dayIndex) => {
      const date = addDays(start, weekIndex * 7 + dayIndex);
      const key = format(date, 'yyyy-MM-dd');
      const isFuture = date > today;
      return { key, active: activeDays.has(key), isFuture, date };
    }),
  );

  return (
    <View style={styles.wrap}>
      <View style={styles.grid}>
        {columns.map((column, index) => (
          <View key={index} style={styles.column}>
            {column.map((cell) => (
              <View
                key={cell.key}
                style={[
                  styles.cell,
                  {
                    backgroundColor: cell.isFuture
                      ? 'transparent'
                      : cell.active
                        ? colors.accent
                        : colors.surfaceRaised,
                    borderColor: cell.isFuture ? colors.border : 'transparent',
                    opacity: cell.isFuture ? 0.35 : cell.active ? 1 : 0.7,
                  },
                ]}
              />
            ))}
          </View>
        ))}
      </View>
      <View style={styles.legend}>
        <Text variant="caption" color={colors.textTertiary} style={{ fontSize: 10 }}>
          {format(start, 'd MMM')}
        </Text>
        <View style={styles.legendRight}>
          <Text variant="caption" color={colors.textTertiary} style={{ fontSize: 10 }}>
            Today
          </Text>
          <View style={[styles.cell, { backgroundColor: colors.accent }]} />
        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 8 },
  grid: { flexDirection: 'row', gap: 4 },
  column: { flex: 1, gap: 4 },
  cell: { width: '100%', aspectRatio: 1, borderRadius: 3, borderWidth: 1 },
  legend: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  legendRight: { flexDirection: 'row', alignItems: 'center', gap: 5 },
});
