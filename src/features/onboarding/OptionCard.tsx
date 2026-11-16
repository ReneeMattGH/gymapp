import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { Check } from 'lucide-react-native';

import { Text } from '@/components/ui/Text';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

type Props = {
  title: string;
  body: string;
  icon?: React.ReactNode;
  selected: boolean;
  onPress: () => void;
};

export function OptionCard({ title, body, icon, selected, onPress }: Props) {
  const { colors } = useTheme();

  return (
    <Pressable
      accessibilityRole="radio"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => [
        styles.card,
        {
          backgroundColor: selected ? colors.accentSoft : colors.surface,
          borderColor: selected ? colors.accentBorder : colors.border,
          opacity: pressed ? 0.85 : 1,
        },
      ]}
    >
      {icon ? (
        <View
          style={[
            styles.icon,
            {
              backgroundColor: selected ? colors.accent : colors.surfaceRaised,
              borderColor: selected ? colors.accent : colors.border,
            },
          ]}
        >
          {React.isValidElement(icon)
            ? React.cloneElement(icon as React.ReactElement<{ color?: string }>, {
                color: selected ? colors.accentInk : colors.textSecondary,
              })
            : icon}
        </View>
      ) : null}
      <View style={styles.text}>
        <Text variant="subheading">{title}</Text>
        <Text variant="caption" style={{ marginTop: 3 }}>
          {body}
        </Text>
      </View>
      <View
        style={[
          styles.radio,
          {
            borderColor: selected ? colors.accent : colors.borderStrong,
            backgroundColor: selected ? colors.accent : 'transparent',
          },
        ]}
      >
        {selected ? <Check size={12} color={colors.accentInk} strokeWidth={3} /> : null}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  card: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: spacing.md,
    padding: spacing.lg,
    borderRadius: radii.lg,
    borderWidth: 1,
  },
  icon: {
    width: 42,
    height: 42,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
  },
  text: { flex: 1 },
  radio: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 1.5,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 2,
  },
});
