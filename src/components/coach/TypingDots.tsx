import React, { useEffect, useState } from 'react';
import { Animated, StyleSheet, View } from 'react-native';

import { useTheme } from '@/theme/ThemeProvider';

/** Three-dot typing indicator used while the coach composes a reply. */
export function TypingDots() {
  const { colors } = useTheme();
  const [values] = useState(() => [new Animated.Value(0.3), new Animated.Value(0.3), new Animated.Value(0.3)]);

  useEffect(() => {
    const loops = values.map((value, index) =>
      Animated.loop(
        Animated.sequence([
          Animated.delay(index * 130),
          Animated.timing(value, { toValue: 1, duration: 340, useNativeDriver: true }),
          Animated.timing(value, { toValue: 0.3, duration: 340, useNativeDriver: true }),
          Animated.delay((2 - index) * 130),
        ]),
      ),
    );
    const animation = Animated.parallel(loops);
    animation.start();
    return () => animation.stop();
  }, [values]);

  return (
    <View style={styles.row}>
      {values.map((value, index) => (
        <Animated.View
          key={index}
          style={[styles.dot, { backgroundColor: colors.textTertiary, opacity: value }]}
        />
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingVertical: 4 },
  dot: { width: 6, height: 6, borderRadius: 3 },
});
