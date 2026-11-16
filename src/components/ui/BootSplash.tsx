import { LinearGradient } from 'expo-linear-gradient';
import React, { useEffect } from 'react';
import { Animated, StyleSheet, View } from 'react-native';

import { BrandMark } from './Brand';
import { useAnimatedValue } from '@/lib/useAnimatedValue';
import { useTheme } from '@/theme/ThemeProvider';

export function BootSplash({ message = 'Preparing your plan' }: { message?: string }) {
  const { colors } = useTheme();
  const pulse = useAnimatedValue(0.5);

  useEffect(() => {
    const loop = Animated.loop(
      Animated.sequence([
        Animated.timing(pulse, { toValue: 1, duration: 1200, useNativeDriver: true }),
        Animated.timing(pulse, { toValue: 0.5, duration: 1200, useNativeDriver: true }),
      ]),
    );
    loop.start();
    return () => loop.stop();
  }, [pulse]);

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <Animated.View style={[styles.glow, { opacity: pulse }]}>
        <LinearGradient
          colors={['rgba(199,250,79,0.22)', 'rgba(199,250,79,0.02)', 'rgba(7,8,6,0)']}
          style={styles.glowFill}
        />
      </Animated.View>
      <View style={styles.center}>
        <BrandMark size={64} />
        <Animated.View style={{ opacity: pulse }}>
          <View style={[styles.dot, { backgroundColor: colors.accent }]} />
        </Animated.View>
      </View>
      <View style={styles.footer}>
        <View style={[styles.line, { backgroundColor: colors.border }]} />
        <View style={[styles.lineShort, { backgroundColor: colors.border }]} />
        <View accessibilityLabel={message} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  glow: { position: 'absolute', width: 520, height: 520, alignItems: 'center', justifyContent: 'center' },
  glowFill: { width: '100%', height: '100%', borderRadius: 260 },
  center: { alignItems: 'center', gap: 18 },
  dot: { width: 5, height: 5, borderRadius: 3, marginTop: 10 },
  footer: { position: 'absolute', bottom: 80, alignItems: 'center', gap: 8 },
  line: { width: 64, height: 2, borderRadius: 2, opacity: 0.7 },
  lineShort: { width: 28, height: 2, borderRadius: 2, opacity: 0.4 },
});
