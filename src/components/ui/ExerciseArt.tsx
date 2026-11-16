import { Dumbbell, Footprints, Move, StretchHorizontal } from 'lucide-react-native';
import React from 'react';
import { StyleSheet, View, type StyleProp, type ViewStyle } from 'react-native';
import Svg, { Circle, Defs, LinearGradient, Path, Rect, Stop } from 'react-native-svg';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';
import { radii } from '@/theme/tokens';

const paletteByGroup: Record<string, [string, string]> = {
  chest: ['#1C2412', '#2E3A16'],
  back: ['#101D1A', '#183028'],
  shoulders: ['#1B1A24', '#2C2A3A'],
  quads: ['#211A10', '#3A2C14'],
  hamstrings: ['#171C22', '#26323D'],
  glutes: ['#1D1712', '#35271A'],
  core: ['#121A13', '#1F2E20'],
  arms: ['#1D1618', '#332227'],
  full: ['#15200F', '#263313'],
  calves: ['#181C1F', '#272F34'],
  hips: ['#1B1910', '#332F1A'],
  mobility: ['#141C1B', '#20302E'],
  conditioning: ['#1C1D10', '#323418'],
};

type Props = {
  id?: string;
  muscle?: string;
  category?: string;
  height?: number;
  compact?: boolean;
  style?: StyleProp<ViewStyle>;
  label?: string;
};

export function ExerciseArt({ id = '', muscle = 'full', category, height = 160, compact, style, label }: Props) {
  const { colors } = useTheme();
  const group = (muscle || 'full').toLowerCase();
  const [from, to] = paletteByGroup[group] ?? paletteByGroup.full;
  const seed = Array.from(id).reduce((acc, char) => acc + char.charCodeAt(0), 0);
  const offset = (seed % 5) * 6;
  const Icon =
    category === 'mobility'
      ? StretchHorizontal
      : category === 'conditioning'
        ? Footprints
        : group === 'core' || group === 'hips'
          ? Move
          : Dumbbell;

  return (
    <View style={[{ height, borderRadius: radii.lg, overflow: 'hidden' }, style]}>
      <Svg width="100%" height="100%" viewBox="0 0 320 180" preserveAspectRatio="xMidYMid slice">
        <Defs>
          <LinearGradient id={`bg-${seed}`} x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0" stopColor={from} />
            <Stop offset="1" stopColor={to} />
          </LinearGradient>
          <LinearGradient id={`line-${seed}`} x1="0" y1="0" x2="1" y2="0">
            <Stop offset="0" stopColor={colors.accent} stopOpacity={0.05} />
            <Stop offset="0.6" stopColor={colors.accent} stopOpacity={0.5} />
            <Stop offset="1" stopColor={colors.accent} stopOpacity={0} />
          </LinearGradient>
        </Defs>
        <Rect width="320" height="180" fill={`url(#bg-${seed})`} />
        <Circle cx={250 - offset} cy={30 + offset} r="92" stroke={colors.accent} strokeOpacity={0.12} fill="none" />
        <Circle cx={250 - offset} cy={30 + offset} r="132" stroke={colors.accent} strokeOpacity={0.07} fill="none" />
        <Circle cx={250 - offset} cy={30 + offset} r="60" stroke={colors.accent} strokeOpacity={0.16} fill="none" />
        <Path d={`M-20 ${140 + offset} L150 20`} stroke={`url(#line-${seed})`} strokeWidth="1.2" />
        <Path d={`M-30 ${168 + offset} L170 28`} stroke={colors.accent} strokeOpacity={0.1} strokeWidth="1" />
        <Path d="M0 92 H320" stroke={colors.text} strokeOpacity={0.04} />
        <Path d="M0 148 H320" stroke={colors.text} strokeOpacity={0.04} />
        <Circle cx={62 + offset} cy={128} r="26" stroke={colors.accent} strokeOpacity={0.2} fill="none" />
        <Circle cx={62 + offset} cy={128} r="4" fill={colors.accent} fillOpacity={0.5} />
      </Svg>
      <View style={styles.overlay}>
        <Icon size={compact ? 28 : 40} color={colors.accent} strokeWidth={1.2} style={{ opacity: 0.5 }} />
      </View>
      <View style={styles.footer}>
        <Text variant="overline" color={colors.accent} style={styles.tag}>
          {label ?? 'FORM GUIDE'}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  overlay: {
    position: 'absolute',
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
    alignItems: 'flex-end',
    justifyContent: 'center',
    paddingRight: 34,
  },
  footer: {
    position: 'absolute',
    left: 14,
    bottom: 11,
  },
  tag: { fontSize: 8.5, letterSpacing: 1.3, opacity: 0.85 },
});
