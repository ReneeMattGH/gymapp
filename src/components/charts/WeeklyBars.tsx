import React, { useEffect } from 'react';
import { Animated, StyleSheet, View } from 'react-native';

import { Text } from '@/components/ui/Text';
import { useAnimatedValue } from '@/lib/useAnimatedValue';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export type WeekBar = {
  label: string;
  value: number;
  target?: number;
  highlight?: boolean;
};

type Props = {
  data: WeekBar[];
  height?: number;
  suffix?: string;
  showValues?: boolean;
};

export function WeeklyBars({ data, height = 132, suffix, showValues = false }: Props) {
  const { colors } = useTheme();
  const max = Math.max(1, ...data.map((d) => Math.max(d.value, d.target ?? 0)));
  const barArea = height - 34;

  return (
    <View style={styles.row}>
      {data.map((entry, index) => {
        const isToday = entry.highlight;

        return (
          <View key={`${entry.label}-${index}`} style={styles.col}>
            {showValues && entry.value > 0 ? (
              <Text variant="caption" color={colors.textTertiary} style={styles.value}>
                {entry.value}
                {suffix}
              </Text>
            ) : null}
            <View style={[styles.track, { height: barArea }]}>
              {entry.target ? (
                <View
                  style={[
                    styles.target,
                    {
                      height: Math.max(3, (entry.target / max) * barArea),
                      backgroundColor: colors.surfaceRaised,
                    },
                  ]}
                />
              ) : null}
              <AnimatedBar
                ratio={Math.max(0.03, entry.value / max)}
                barArea={barArea}
                active={entry.value > 0}
                highlight={Boolean(isToday)}
              />
            </View>
            <Text
              variant="caption"
              color={isToday ? colors.accentText : colors.textTertiary}
              style={styles.label}
            >
              {entry.label}
            </Text>
          </View>
        );
      })}
    </View>
  );
}

function AnimatedBar({
  ratio,
  barArea,
  active,
  highlight,
}: {
  ratio: number;
  barArea: number;
  active: boolean;
  highlight: boolean;
}) {
  const { colors } = useTheme();
  const value = useAnimatedValue(0);

  useEffect(() => {
    const animation = Animated.spring(value, {
      toValue: ratio,
      speed: 14,
      bounciness: 3,
      useNativeDriver: false,
    });
    animation.start();
    return () => animation.stop();
  }, [ratio, value]);

  return (
    <Animated.View
      style={[
        styles.bar,
        {
          height: value.interpolate({ inputRange: [0, 1], outputRange: [3, barArea] }),
          backgroundColor: active ? (highlight ? colors.accent : colors.accent + 'CC') : colors.surfaceRaised,
          opacity: active ? 1 : 0.8,
        },
      ]}
    />
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-end' },
  col: { flex: 1, alignItems: 'center', gap: 6 },
  track: {
    width: '100%',
    justifyContent: 'flex-end',
    alignItems: 'center',
    position: 'relative',
  },
  bar: {
    width: '62%',
    minWidth: 12,
    borderTopLeftRadius: radii.sm,
    borderTopRightRadius: radii.sm,
    borderBottomLeftRadius: 3,
    borderBottomRightRadius: 3,
  },
  target: {
    position: 'absolute',
    bottom: 0,
    width: '62%',
    minWidth: 12,
    borderTopLeftRadius: radii.sm,
    borderTopRightRadius: radii.sm,
  },
  label: { fontSize: 11 },
  value: { fontSize: 10 },
});
