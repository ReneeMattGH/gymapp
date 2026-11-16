import { useState } from 'react';
import { Animated } from 'react-native';

// react-native exports useAnimatedValue, but react-native-web does not.
export function useAnimatedValue(initialValue: number) {
  const [value] = useState(() => new Animated.Value(initialValue));
  return value;
}
