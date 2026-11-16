import { Minus, Plus } from 'lucide-react-native';
import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';
import { radii } from '@/theme/tokens';

type Props = {
  value: number;
  onChange: (value: number) => void;
  min?: number;
  max?: number;
  step?: number;
  label?: string;
  suffix?: string;
  compact?: boolean;
};

export function Stepper({ value, onChange, min = 0, max = 999, step = 1, label, suffix, compact }: Props) {
  const { colors } = useTheme();
  const dec = () => onChange(Math.max(min, +(value - step).toFixed(2)));
  const inc = () => onChange(Math.min(max, +(value + step).toFixed(2)));

  return (
    <View style={styles.wrap}>
      {label ? (
        <Text variant="overline" color={colors.textSecondary}>
          {label}
        </Text>
      ) : null}
      <View
        style={[
          styles.control,
          { borderColor: colors.border, backgroundColor: colors.surface, height: compact ? 42 : 50 },
        ]}
      >
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Decrease ${label ?? 'value'}`}
          onPress={dec}
          disabled={value <= min}
          style={({ pressed }) => [styles.button, { opacity: value <= min ? 0.3 : pressed ? 0.6 : 1 }]}
          hitSlop={4}
        >
          <Minus size={compact ? 15 : 17} color={colors.text} strokeWidth={2.4} />
        </Pressable>
        <View style={styles.value}>
          <Text variant={compact ? 'bodyStrong' : 'subheading'}>
            {Number.isInteger(value) ? value : value.toFixed(1)}
            {suffix ? <Text variant="caption" color={colors.textTertiary}> {suffix}</Text> : null}
          </Text>
        </View>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel={`Increase ${label ?? 'value'}`}
          onPress={inc}
          disabled={value >= max}
          style={({ pressed }) => [styles.button, { opacity: value >= max ? 0.3 : pressed ? 0.6 : 1 }]}
          hitSlop={4}
        >
          <Plus size={compact ? 15 : 17} color={colors.text} strokeWidth={2.4} />
        </Pressable>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 6 },
  control: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    paddingHorizontal: 4,
  },
  button: {
    width: 40,
    height: '100%',
    alignItems: 'center',
    justifyContent: 'center',
  },
  value: { flex: 1, alignItems: 'center' },
});
