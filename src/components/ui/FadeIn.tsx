import React, { useEffect } from 'react';
import { Animated, type StyleProp, type ViewStyle } from 'react-native';

import { useAnimatedValue } from '@/lib/useAnimatedValue';

type Props = {
  children: React.ReactNode;
  delay?: number;
  offset?: number;
  style?: StyleProp<ViewStyle>;
};

/** Small entrance animation for dashboard sections. */
export function FadeIn({ children, delay = 0, offset = 14, style }: Props) {
  const value = useAnimatedValue(0);

  useEffect(() => {
    const animation = Animated.timing(value, {
      toValue: 1,
      duration: 460,
      delay,
      useNativeDriver: true,
    });
    animation.start();
    return () => animation.stop();
  }, [delay, value]);

  return (
    <Animated.View
      style={[
        style,
        {
          opacity: value,
          transform: [
            {
              translateY: value.interpolate({ inputRange: [0, 1], outputRange: [offset, 0] }),
            },
          ],
        },
      ]}
    >
      {children}
    </Animated.View>
  );
}
