import React from 'react';
import { StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Stop } from 'react-native-svg';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';

type Props = {
  progress: number;
  size?: number;
  strokeWidth?: number;
  trackColor?: string;
  color?: string;
  label?: string;
  value?: string;
  children?: React.ReactNode;
};

export function ProgressRing({
  progress,
  size = 88,
  strokeWidth = 7,
  trackColor,
  color,
  label,
  value,
  children,
}: Props) {
  const { colors } = useTheme();
  const clamped = Math.max(0, Math.min(1, progress));
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * clamped;

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Svg width={size} height={size} style={StyleSheet.absoluteFill}>
        <Defs>
          <LinearGradient id="ring" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={color ?? colors.accent} stopOpacity={1} />
            <Stop offset="1" stopColor={color ?? colors.accent} stopOpacity={0.55} />
          </LinearGradient>
        </Defs>
        <Circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={trackColor ?? colors.surfaceRaised}
          strokeWidth={strokeWidth}
          fill="none"
        />
        {clamped > 0 ? (
          <Circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            stroke="url(#ring)"
            strokeWidth={strokeWidth}
            strokeLinecap="round"
            fill="none"
            strokeDasharray={`${dash} ${circumference}`}
            transform={`rotate(-90 ${size / 2} ${size / 2})`}
          />
        ) : null}
      </Svg>
      {children ??
        (value ? (
          <View style={styles.center}>
            <Text variant="number" style={{ fontSize: size * 0.24, lineHeight: size * 0.28 }}>
              {value}
            </Text>
            {label ? (
              <Text variant="overline" style={{ fontSize: 8, letterSpacing: 1 }}>
                {label}
              </Text>
            ) : null}
          </View>
        ) : null)}
    </View>
  );
}

const styles = StyleSheet.create({
  center: { alignItems: 'center', justifyContent: 'center' },
});
