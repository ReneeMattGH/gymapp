import { useRouter } from 'expo-router';
import { ChevronLeft } from 'lucide-react-native';
import React from 'react';
import {
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { BrandMark } from '@/components/ui/Brand';
import { Text } from '@/components/ui/Text';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  back?: boolean;
  center?: boolean;
};

export function AuthShell({ title, subtitle, children, footer, back = true, center }: Props) {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();

  return (
    <KeyboardAvoidingView
      style={[styles.root, { backgroundColor: colors.background }]}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <ScrollView
        contentContainerStyle={[
          styles.content,
          {
            paddingTop: insets.top + spacing.md,
            paddingBottom: insets.bottom + spacing.xxxl,
          },
        ]}
        showsVerticalScrollIndicator={false}
        keyboardShouldPersistTaps="handled"
      >
        <View style={styles.column}>
          <View style={styles.topBar}>
            {back ? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Go back"
                onPress={() => (router.canGoBack() ? router.back() : router.replace('/(auth)/welcome'))}
                style={({ pressed }) => [
                  styles.back,
                  { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
                ]}
                hitSlop={8}
              >
                <ChevronLeft size={20} color={colors.text} strokeWidth={2.2} />
              </Pressable>
            ) : (
              <View style={styles.back} />
            )}
            <BrandMark size={34} />
          </View>

          <View style={[styles.header, center ? { alignItems: 'center' } : null]}>
            <Text variant="title" align={center ? 'center' : 'left'}>
              {title}
            </Text>
            {subtitle ? (
              <Text variant="body" color={colors.textSecondary} style={styles.subtitle} align={center ? 'center' : 'left'}>
                {subtitle}
              </Text>
            ) : null}
          </View>

          <View style={styles.body}>{children}</View>
          {footer ? <View style={styles.footer}>{footer}</View> : null}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: {
    flexGrow: 1,
    paddingHorizontal: layout.screenPadding,
    alignItems: 'center',
  },
  column: {
    width: '100%',
    maxWidth: layout.maxContentWidth,
    flex: 1,
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: spacing.xxxl,
  },
  back: {
    width: 40,
    height: 40,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  header: { gap: spacing.sm, marginBottom: spacing.xxl },
  subtitle: { lineHeight: 23 },
  body: { gap: spacing.lg },
  footer: { marginTop: spacing.xl, alignItems: 'center' },
});
