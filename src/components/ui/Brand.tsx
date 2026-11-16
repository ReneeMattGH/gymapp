import React from 'react';
import { StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';

export function BrandMark({ size = 40 }: { size?: number }) {
  const { colors } = useTheme();
  return (
    <Svg width={size} height={size} viewBox="0 0 48 48" fill="none">
      <Defs>
        <LinearGradient id="brand" x1="8" y1="6" x2="42" y2="44" gradientUnits="userSpaceOnUse">
          <Stop offset="0" stopColor={colors.accent} stopOpacity={1} />
          <Stop offset="1" stopColor={colors.accent} stopOpacity={0.45} />
        </LinearGradient>
      </Defs>
      <Rect x="1" y="1" width="46" height="46" rx="15" fill={colors.accent} fillOpacity={0.1} />
      <Path
        d="M30.5 14.5 A11.5 11.5 0 1 0 34 25"
        stroke="url(#brand)"
        strokeWidth="4.2"
        strokeLinecap="round"
        fill="none"
      />
      <Path d="M17 24h11" stroke={colors.accent} strokeWidth="4.2" strokeLinecap="round" />
      <Circle cx="35.5" cy="31.5" r="3.2" fill={colors.accent} />
    </Svg>
  );
}

export function Wordmark({ compact }: { compact?: boolean }) {
  const { colors } = useTheme();

  return (
    <View style={styles.row}>
      <BrandMark size={compact ? 30 : 38} />
      <View>
        <View style={styles.wordRow}>
          <Text
            style={{
              fontFamily: 'SpaceGrotesk_700Bold',
              fontSize: compact ? 16 : 20,
              lineHeight: compact ? 19 : 24,
              letterSpacing: 3.4,
              color: colors.text,
            }}
          >
            FORMA
          </Text>
          <View style={[styles.dot, { backgroundColor: colors.accent }]} />
        </View>
        {!compact ? (
          <Text
            style={{
              fontFamily: 'Inter_600SemiBold',
              fontSize: 9,
              lineHeight: 12,
              letterSpacing: 2.4,
              color: colors.textTertiary,
            }}
          >
            TRAIN WITH INTENT
          </Text>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  wordRow: { flexDirection: 'row', alignItems: 'flex-start' },
  dot: { width: 5, height: 5, borderRadius: 3, marginTop: 4, marginLeft: 3 },
});
