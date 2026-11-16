import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { Text } from './Text';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

export function SectionHeader({
  title,
  caption,
  actionLabel,
  onAction,
  style,
}: {
  title: string;
  caption?: string;
  actionLabel?: string;
  onAction?: () => void;
  style?: object;
}) {
  const { colors } = useTheme();
  return (
    <View style={[styles.row, style]}>
      <View style={styles.flex}>
        <Text variant="heading">{title}</Text>
        {caption ? (
          <Text variant="caption" style={{ marginTop: 3 }}>
            {caption}
          </Text>
        ) : null}
      </View>
      {actionLabel && onAction ? (
        <Pressable onPress={onAction} hitSlop={10} accessibilityRole="button">
          <Text variant="label" color={colors.accentText} style={styles.action}>
            {actionLabel}
          </Text>
        </Pressable>
      ) : null}
    </View>
  );
}

export function Badge({
  label,
  tone = 'neutral',
  icon,
}: {
  label: string;
  tone?: 'neutral' | 'accent' | 'danger' | 'warning';
  icon?: React.ReactNode;
}) {
  const { colors } = useTheme();
  const palette = {
    neutral: { bg: colors.surfaceRaised, fg: colors.textSecondary, border: colors.border },
    accent: { bg: colors.accentSoft, fg: colors.accentText, border: colors.accentBorder },
    danger: { bg: colors.dangerSoft, fg: colors.danger, border: 'transparent' },
    warning: { bg: colors.warningSoft, fg: colors.warning, border: 'transparent' },
  }[tone];

  return (
    <View style={[styles.badge, { backgroundColor: palette.bg, borderColor: palette.border }]}>
      {icon}
      <Text variant="overline" color={palette.fg} style={styles.badgeLabel}>
        {label}
      </Text>
    </View>
  );
}

export function EmptyState({
  icon,
  title,
  message,
  action,
}: {
  icon?: React.ReactNode;
  title: string;
  message: string;
  action?: React.ReactNode;
}) {
  const { colors } = useTheme();
  return (
    <View style={styles.empty}>
      {icon ? (
        <View style={[styles.emptyIcon, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          {icon}
        </View>
      ) : null}
      <Text variant="subheading" align="center">
        {title}
      </Text>
      <Text variant="body" color={colors.textSecondary} align="center" style={styles.emptyText}>
        {message}
      </Text>
      {action ? <View style={styles.emptyAction}>{action}</View> : null}
    </View>
  );
}

export function Divider({ style }: { style?: object }) {
  const { colors } = useTheme();
  return <View style={[{ height: StyleSheet.hairlineWidth, backgroundColor: colors.border }, style]} />;
}

export function InlineError({ message }: { message: string }) {
  const { colors } = useTheme();
  return (
    <View style={[styles.inlineError, { backgroundColor: colors.dangerSoft }]}>
      <Text variant="caption" color={colors.danger}>
        {message}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.md },
  flex: { flex: 1 },
  action: { paddingBottom: 2 },
  badge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 5,
    paddingHorizontal: 9,
    paddingVertical: 5,
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
    alignSelf: 'flex-start',
  },
  badgeLabel: { fontSize: 9.5, letterSpacing: 1.1 },
  empty: {
    alignItems: 'center',
    paddingVertical: spacing.xxxl,
    paddingHorizontal: spacing.xl,
    gap: spacing.sm,
  },
  emptyIcon: {
    width: 58,
    height: 58,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: spacing.sm,
  },
  emptyText: { maxWidth: 320 },
  emptyAction: { marginTop: spacing.md },
  inlineError: {
    padding: spacing.md,
    borderRadius: radii.md,
  },
});
