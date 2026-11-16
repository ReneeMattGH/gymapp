import React from 'react';
import {
  ActivityIndicator,
  Animated,
  Pressable,
  StyleSheet,
  View,
  type PressableProps,
  type StyleProp,
  type ViewStyle,
} from 'react-native';

import { Text } from './Text';
import { useAnimatedValue } from '@/lib/useAnimatedValue';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export type ButtonVariant = 'primary' | 'secondary' | 'outline' | 'ghost' | 'danger';
export type ButtonSize = 'lg' | 'md' | 'sm';

type Props = Omit<PressableProps, 'children' | 'style'> & {
  label: string;
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: React.ReactNode;
  iconRight?: React.ReactNode;
  loading?: boolean;
  fullWidth?: boolean;
  style?: StyleProp<ViewStyle>;
};

const heights: Record<ButtonSize, number> = { lg: 54, md: 46, sm: 36 };
const fontVariant = { lg: 'subheading', md: 'bodyStrong', sm: 'label' } as const;

export function Button({
  label,
  variant = 'primary',
  size = 'lg',
  icon,
  iconRight,
  loading,
  fullWidth,
  disabled,
  style,
  onPressIn,
  onPressOut,
  ...rest
}: Props) {
  const { colors } = useTheme();
  const scale = useAnimatedValue(1);

  const palette = {
    primary: { bg: colors.accent, fg: colors.accentInk, border: 'transparent' },
    secondary: { bg: colors.surfaceRaised, fg: colors.text, border: colors.border },
    outline: { bg: 'transparent', fg: colors.text, border: colors.borderStrong },
    ghost: { bg: 'transparent', fg: colors.textSecondary, border: 'transparent' },
    danger: { bg: colors.dangerSoft, fg: colors.danger, border: 'transparent' },
  }[variant];

  const inactive = disabled || loading;

  return (
    <Animated.View style={[{ transform: [{ scale }] }, fullWidth ? styles.full : null, style]}>
      <Pressable
        accessibilityRole="button"
        accessibilityState={{ disabled: !!inactive, busy: !!loading }}
        disabled={inactive}
        onPressIn={(event) => {
          Animated.spring(scale, {
            toValue: 0.97,
            speed: 40,
            bounciness: 0,
            useNativeDriver: true,
          }).start();
          onPressIn?.(event);
        }}
        onPressOut={(event) => {
          Animated.spring(scale, {
            toValue: 1,
            speed: 30,
            bounciness: 6,
            useNativeDriver: true,
          }).start();
          onPressOut?.(event);
        }}
        style={[
          styles.base,
          {
            height: heights[size],
            paddingHorizontal: size === 'sm' ? spacing.md : spacing.xl,
            backgroundColor: palette.bg,
            borderColor: palette.border,
            opacity: inactive ? 0.55 : 1,
            shadowColor: variant === 'primary' ? colors.accent : colors.shadow,
            shadowOpacity: variant === 'primary' ? 0.18 : 0.06,
          },
        ]}
        {...rest}
      >
        {loading ? (
          <ActivityIndicator size="small" color={palette.fg} />
        ) : (
          <View style={styles.content}>
            {icon}
            <Text variant={fontVariant[size]} color={palette.fg} numberOfLines={1}>
              {label}
            </Text>
            {iconRight}
          </View>
        )}
      </Pressable>
    </Animated.View>
  );
}

const styles = StyleSheet.create({
  full: { width: '100%' },
  base: {
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
    shadowOffset: { width: 0, height: 8 },
    shadowRadius: 20,
    elevation: 2,
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
  },
});
