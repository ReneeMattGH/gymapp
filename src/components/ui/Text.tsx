import React from 'react';
import { Text as RNText, type TextProps as RNTextProps, type TextStyle } from 'react-native';

import { fonts } from '@/theme/tokens';
import { useTheme } from '@/theme/ThemeProvider';

export type TextVariant =
  | 'display'
  | 'title'
  | 'heading'
  | 'subheading'
  | 'body'
  | 'bodyStrong'
  | 'label'
  | 'caption'
  | 'overline'
  | 'number'
  | 'numberLarge';

type Props = RNTextProps & {
  variant?: TextVariant;
  color?: string;
  align?: TextStyle['textAlign'];
};

const base: Record<TextVariant, TextStyle> = {
  display: {
    fontFamily: fonts.display,
    fontSize: 36,
    lineHeight: 40,
    letterSpacing: -1.4,
  },
  title: {
    fontFamily: fonts.display,
    fontSize: 27,
    lineHeight: 32,
    letterSpacing: -0.8,
  },
  heading: {
    fontFamily: fonts.display,
    fontSize: 20,
    lineHeight: 26,
    letterSpacing: -0.4,
  },
  subheading: {
    fontFamily: fonts.bodyBold,
    fontSize: 16,
    lineHeight: 22,
    letterSpacing: -0.1,
  },
  body: {
    fontFamily: fonts.body,
    fontSize: 15,
    lineHeight: 23,
  },
  bodyStrong: {
    fontFamily: fonts.bodyBold,
    fontSize: 15,
    lineHeight: 23,
  },
  label: {
    fontFamily: fonts.bodyMedium,
    fontSize: 13,
    lineHeight: 18,
  },
  caption: {
    fontFamily: fonts.body,
    fontSize: 12.5,
    lineHeight: 18,
  },
  overline: {
    fontFamily: fonts.bodyBold,
    fontSize: 11,
    lineHeight: 15,
    letterSpacing: 1.4,
    textTransform: 'uppercase',
  },
  number: {
    fontFamily: fonts.display,
    fontSize: 26,
    lineHeight: 30,
    letterSpacing: -0.6,
    fontVariant: ['tabular-nums'],
  },
  numberLarge: {
    fontFamily: fonts.displayBold,
    fontSize: 52,
    lineHeight: 56,
    letterSpacing: -2,
    fontVariant: ['tabular-nums'],
  },
};

export function Text({ variant = 'body', color, align, style, ...rest }: Props) {
  const { colors } = useTheme();
  const defaultColor =
    variant === 'caption' || variant === 'label' || variant === 'overline'
      ? colors.textSecondary
      : colors.text;

  return (
    <RNText
      {...rest}
      style={[base[variant], { color: color ?? defaultColor }, align ? { textAlign: align } : null, style]}
    />
  );
}
