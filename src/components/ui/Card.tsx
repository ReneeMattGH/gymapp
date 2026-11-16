import React from 'react';
import { Pressable, StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';

import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

type Props = {
  children: React.ReactNode;
  onPress?: () => void;
  style?: StyleProp<ViewStyle>;
  padded?: boolean;
  variant?: 'default' | 'raised' | 'accent';
  disabled?: boolean;
  accessibilityLabel?: string;
};

export function Card({
  children,
  onPress,
  style,
  padded = true,
  variant = 'default',
  disabled,
  accessibilityLabel,
}: Props) {
  const { colors } = useTheme();
  const background =
    variant === 'accent' ? colors.accentSoft : variant === 'raised' ? colors.surfaceRaised : colors.surface;
  const borderColor = variant === 'accent' ? colors.accentBorder : colors.border;

  const content = (
    <View
      style={[
        styles.card,
        {
          backgroundColor: background,
          borderColor,
          padding: padded ? spacing.lg : 0,
        },
        style,
      ]}
    >
      {children}
    </View>
  );

  if (!onPress) return content;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => [{ opacity: pressed ? 0.82 : 1, transform: [{ scale: pressed ? 0.994 : 1 }] }]}
    >
      {content}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: radii.xl,
    borderWidth: StyleSheet.hairlineWidth,
    overflow: 'hidden',
  },
});
