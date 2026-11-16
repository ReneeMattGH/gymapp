import { Eye, EyeOff } from 'lucide-react-native';
import React, { useState } from 'react';
import {
  Pressable,
  StyleSheet,
  TextInput,
  View,
  type TextInputProps,
  type StyleProp,
  type ViewStyle,
} from 'react-native';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';
import { fonts, radii, spacing } from '@/theme/tokens';

type Props = Omit<TextInputProps, 'style'> & {
  label?: string;
  error?: string | null;
  hint?: string;
  right?: React.ReactNode;
  containerStyle?: StyleProp<ViewStyle>;
};

export function Input({
  label,
  error,
  hint,
  right,
  secureTextEntry,
  containerStyle,
  onFocus,
  onBlur,
  multiline,
  ...rest
}: Props) {
  const { colors } = useTheme();
  const [focused, setFocused] = useState(false);
  const [revealed, setRevealed] = useState(false);
  const isSecure = !!secureTextEntry && !revealed;

  return (
    <View style={[styles.wrap, containerStyle]}>
      {label ? (
        <Text variant="label" color={colors.textSecondary} style={styles.label}>
          {label}
        </Text>
      ) : null}
      <View
        style={[
          styles.field,
          {
            backgroundColor: colors.input,
            borderColor: error ? colors.danger : focused ? colors.accentBorder : colors.border,
            minHeight: multiline ? 104 : 52,
            alignItems: multiline ? 'flex-start' : 'center',
          },
        ]}
      >
        <TextInput
          {...rest}
          multiline={multiline}
          secureTextEntry={isSecure}
          placeholderTextColor={colors.textTertiary}
          selectionColor={colors.accentText}
          onFocus={(event) => {
            setFocused(true);
            onFocus?.(event);
          }}
          onBlur={(event) => {
            setFocused(false);
            onBlur?.(event);
          }}
          style={[
            styles.input,
            {
              color: colors.text,
              height: multiline ? undefined : '100%',
              paddingTop: multiline ? 14 : 0,
              textAlignVertical: multiline ? 'top' : 'center',
            },
          ]}
        />
        {secureTextEntry ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={revealed ? 'Hide password' : 'Show password'}
            hitSlop={8}
            onPress={() => setRevealed((value) => !value)}
            style={styles.trailing}
          >
            {revealed ? (
              <EyeOff size={18} color={colors.textSecondary} />
            ) : (
              <Eye size={18} color={colors.textSecondary} />
            )}
          </Pressable>
        ) : (
          right
        )}
      </View>
      {error ? (
        <Text variant="caption" color={colors.danger} style={styles.helper}>
          {error}
        </Text>
      ) : hint ? (
        <Text variant="caption" color={colors.textTertiary} style={styles.helper}>
          {hint}
        </Text>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 6 },
  label: { marginLeft: 2 },
  field: {
    borderRadius: radii.md,
    borderWidth: 1,
    paddingHorizontal: spacing.lg,
    flexDirection: 'row',
    gap: spacing.sm,
    overflow: 'hidden',
  },
  input: {
    flex: 1,
    fontFamily: fonts.body,
    fontSize: 15,
    paddingVertical: 0,
  },
  trailing: { paddingVertical: 4 },
  helper: { marginLeft: 2 },
});
