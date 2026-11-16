import React from 'react';
import { Pressable, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';

import { useTheme } from '@/theme/ThemeProvider';
import { radii } from '@/theme/tokens';

type Props = {
  children: React.ReactNode;
  onPress?: () => void;
  accessibilityLabel: string;
  variant?: 'surface' | 'accent' | 'ghost';
  size?: number;
  disabled?: boolean;
  style?: StyleProp<ViewStyle>;
};

export function IconButton({
  children,
  onPress,
  accessibilityLabel,
  variant = 'surface',
  size = 42,
  disabled,
  style,
}: Props) {
  const { colors } = useTheme();
  const background =
    variant === 'accent' ? colors.accent : variant === 'ghost' ? 'transparent' : colors.surfaceRaised;
  const border = variant === 'ghost' ? 'transparent' : variant === 'accent' ? colors.accent : colors.border;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled: !!disabled }}
      disabled={disabled}
      onPress={onPress}
      hitSlop={6}
      style={({ pressed }) => [
        styles.base,
        {
          width: size,
          height: size,
          borderRadius: size / 2.6,
          backgroundColor: background,
          borderColor: border,
          opacity: disabled ? 0.4 : pressed ? 0.7 : 1,
        },
        style,
      ]}
    >
      {children}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
  },
});
