import { BlurView } from 'expo-blur';
import { useRouter } from 'expo-router';
import { ChevronLeft } from 'lucide-react-native';
import React from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
  type StyleProp,
  type ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

type ScreenProps = {
  children: React.ReactNode;
  scroll?: boolean;
  padded?: boolean;
  style?: StyleProp<ViewStyle>;
  contentContainerStyle?: StyleProp<ViewStyle>;
  edges?: 'top' | 'none';
  /** Extra bottom padding, useful above the tab bar. */
  bottomInset?: number;
  testID?: string;
};

export function Screen({
  children,
  scroll = false,
  padded = true,
  style,
  contentContainerStyle,
  edges = 'top',
  bottomInset,
  testID,
}: ScreenProps) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const paddingTop = edges === 'top' ? insets.top + spacing.sm : 0;
  const paddingBottom = Math.max(insets.bottom, spacing.md) + (bottomInset ?? spacing.xxl);

  if (scroll) {
    return (
      <ScrollView
        testID={testID}
        style={[styles.flex, { backgroundColor: colors.background }, style]}
        contentContainerStyle={[
          {
            paddingTop,
            paddingBottom,
            paddingHorizontal: padded ? layout.screenPadding : 0,
            gap: spacing.lg,
          },
          contentContainerStyle,
        ]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        {children}
      </ScrollView>
    );
  }

  return (
    <View
      testID={testID}
      style={[
        styles.flex,
        {
          backgroundColor: colors.background,
          paddingTop,
          paddingBottom,
          paddingHorizontal: padded ? layout.screenPadding : 0,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

type HeaderProps = {
  title?: string;
  subtitle?: string;
  back?: boolean;
  onBack?: () => void;
  right?: React.ReactNode;
  large?: boolean;
};

export function ScreenHeader({ title, subtitle, back, onBack, right, large }: HeaderProps) {
  const { colors } = useTheme();
  const router = useRouter();
  const insets = useSafeAreaInsets();

  return (
    <View style={[styles.header, { paddingTop: insets.top + spacing.sm }]}>
      <View style={styles.headerRow}>
        {back ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Go back"
            onPress={onBack ?? (() => router.back())}
            style={({ pressed }) => [
              styles.back,
              {
                backgroundColor: colors.surfaceRaised,
                borderColor: colors.border,
                opacity: pressed ? 0.7 : 1,
              },
            ]}
            hitSlop={8}
          >
            <ChevronLeft size={20} color={colors.text} strokeWidth={2.2} />
          </Pressable>
        ) : null}
        <View style={styles.flex}>
          {title ? (
            <Text variant={large ? 'title' : 'heading'} numberOfLines={1}>
              {title}
            </Text>
          ) : null}
          {subtitle ? (
            <Text variant="caption" style={{ marginTop: 2 }} numberOfLines={2}>
              {subtitle}
            </Text>
          ) : null}
        </View>
        {right}
      </View>
    </View>
  );
}

type GlassBarProps = {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
};

export function GlassBar({ children, style }: GlassBarProps) {
  const { colors, isDark } = useTheme();
  const content = (
    <View style={[styles.glassInner, { borderColor: colors.border }, style]}>{children}</View>
  );

  if (Platform.OS === 'ios') {
    return (
      <BlurView intensity={isDark ? 32 : 48} tint={isDark ? 'dark' : 'light'} style={styles.glassClip}>
        {content}
      </BlurView>
    );
  }

  return (
    <View style={[styles.glassClip, { backgroundColor: colors.surfaceOverlay }]}>{content}</View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: {
    paddingHorizontal: layout.screenPadding,
    paddingBottom: spacing.sm,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    minHeight: 44,
  },
  back: {
    width: 40,
    height: 40,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  glassClip: {
    overflow: 'hidden',
    borderRadius: radii.xxl,
  },
  glassInner: {
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.xxl,
  },
});
