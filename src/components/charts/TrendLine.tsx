import React from 'react';
import { StyleSheet, View } from 'react-native';
import Svg, { Circle, Defs, Line, LinearGradient, Path, Stop } from 'react-native-svg';

import { Text } from '@/components/ui/Text';
import { useTheme } from '@/theme/ThemeProvider';

type Point = { label: string; value: number };

type Props = {
  data: Point[];
  height?: number;
  suffix?: string;
};

const W = 300;

export function TrendLine({ data, height = 110, suffix = '' }: Props) {
  const { colors } = useTheme();
  const paddingY = 12;
  const chartW = W;
  const chartH = height;
  const max = Math.max(1, ...data.map((d) => d.value));
  const stepX = data.length > 1 ? chartW / (data.length - 1) : chartW;

  const points = data.map((point, index) => {
    const x = data.length > 1 ? index * stepX : chartW / 2;
    const y = chartH - paddingY - (point.value / max) * (chartH - paddingY * 2);
    return { ...point, x, y };
  });

  const path = points.map((point, index) => `${index === 0 ? 'M' : 'L'} ${point.x} ${point.y}`).join(' ');
  const area = points.length
    ? `${path} L ${points[points.length - 1].x} ${chartH} L ${points[0].x} ${chartH} Z`
    : '';

  return (
    <View style={styles.wrap}>
      <Svg width="100%" height={chartH} viewBox={`0 0 ${W} ${chartH}`} preserveAspectRatio="none">
        <Defs>
          <LinearGradient id="trend" x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={colors.accent} stopOpacity={0.24} />
            <Stop offset="1" stopColor={colors.accent} stopOpacity={0} />
          </LinearGradient>
        </Defs>
        {[0.33, 0.66].map((ratio) => (
          <Line
            key={ratio}
            x1="0"
            y1={chartH * ratio}
            x2={W}
            y2={chartH * ratio}
            stroke={colors.border}
            strokeWidth="1"
            strokeDasharray="3 5"
          />
        ))}
        {area ? <Path d={area} fill="url(#trend)" /> : null}
        {path ? <Path d={path} stroke={colors.accent} strokeWidth="2.4" fill="none" strokeLinejoin="round" strokeLinecap="round" /> : null}
        {points.map((point) => (
          <Circle key={`${point.label}-${point.x}`} cx={point.x} cy={point.y} r="3.2" fill={colors.accentInk} stroke={colors.accent} strokeWidth="2" />
        ))}
      </Svg>
      <View style={styles.labels}>
        {data.map((point, index) => (
          <Text
            key={`${point.label}-${index}`}
            variant="caption"
            color={colors.textTertiary}
            style={{ fontSize: 10 }}
          >
            {point.label}
          </Text>
        ))}
      </View>
      {data.length > 0 ? (
        <Text variant="caption" color={colors.textTertiary} style={styles.caption}>
          Peak {Math.round(max)}
          {suffix}
        </Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 6 },
  labels: { flexDirection: 'row', justifyContent: 'space-between' },
  caption: { position: 'absolute', right: 0, top: -18, fontSize: 10 },
});
