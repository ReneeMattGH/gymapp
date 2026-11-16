import AsyncStorage from '@react-native-async-storage/async-storage';
import { useRouter } from 'expo-router';
import { RefreshCw, Sparkles } from 'lucide-react-native';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, View } from 'react-native';

import { Card } from '@/components/ui/Card';
import { Text } from '@/components/ui/Text';
import { dateKey } from '@/lib/date';
import { aiConfigured, requestDailyInsight } from '@/lib/ai';
import { localDailyInsight } from '@/lib/insight';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

type Source = 'ai' | 'local' | 'loading';

export function CoachNote() {
  const { user, profile, preferences, plan, sessions, previewMode } = useApp();
  const { colors } = useTheme();
  const router = useRouter();
  const [text, setText] = useState<string | null>(null);
  const [source, setSource] = useState<Source>('loading');
  const [hint, setHint] = useState<string | null>(null);
  const [attempt, setAttempt] = useState(0);

  const localText = useMemo(
    () =>
      profile && preferences
        ? localDailyInsight({ profile, preferences, plan, sessions })
        : '',
    [profile, preferences, plan, sessions],
  );

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      if (!user || !profile || !preferences) return;

      if (!aiConfigured) {
        setText(localText);
        setSource('local');
        setHint(
          previewMode
            ? 'On-device coach note built from your saved sessions. Connect Supabase and OpenAI for live AI coaching.'
            : 'Built from your saved training data.',
        );
        return;
      }

      const cacheKey = `forma.insight.${user.id}.${dateKey()}`;
      setSource('loading');
      setHint(null);
      try {
        const cached = await AsyncStorage.getItem(cacheKey);
        if (cancelled) return;
        if (cached) {
          setText(cached);
          setSource('ai');
          return;
        }
        const insight = await requestDailyInsight();
        if (cancelled) return;
        setText(insight);
        setSource('ai');
        await AsyncStorage.setItem(cacheKey, insight);
      } catch (error) {
        if (cancelled) return;
        setText(localText);
        setSource('local');
        setHint(
          `${error instanceof Error ? error.message : 'The AI coach is unavailable.'} Showing a note from your saved training data instead.`,
        );
      }
    };

    void load();
    return () => {
      cancelled = true;
    };
    // localText is intentionally excluded: it should not refetch when a session is saved.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, profile?.id, preferences?.userId, aiConfigured, attempt]);

  const retry = useCallback(() => setAttempt((value) => value + 1), []);

  return (
    <Card padded={false} style={styles.card}>
      <View style={styles.header}>
        <View style={[styles.icon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
          <Sparkles size={17} color={colors.accentText} strokeWidth={2.1} />
        </View>
        <View style={styles.flex}>
          <Text variant="overline" color={colors.textTertiary}>
            {source === 'ai' ? 'AI coach insight' : source === 'loading' ? 'Coach is reviewing your week' : 'Coach note'}
          </Text>
        </View>
        {source === 'local' && aiConfigured ? (
          <Pressable onPress={retry} accessibilityRole="button" accessibilityLabel="Retry AI insight" hitSlop={8}>
            <RefreshCw size={15} color={colors.textTertiary} />
          </Pressable>
        ) : null}
      </View>

      {source === 'loading' ? (
        <View style={styles.loading}>
          <ActivityIndicator size="small" color={colors.accent} />
          <Text variant="body" color={colors.textSecondary}>
            Putting together today&apos;s note…
          </Text>
        </View>
      ) : (
        <Text variant="body" color={colors.textSecondary} style={styles.body}>
          {text}
        </Text>
      )}

      {hint ? (
        <Text variant="caption" color={colors.textTertiary} style={styles.hint}>
          {hint}
        </Text>
      ) : null}

      <Pressable
        onPress={() => router.push('/(tabs)/coach')}
        accessibilityRole="button"
        style={({ pressed }) => [styles.action, { opacity: pressed ? 0.65 : 1 }]}
      >
        <Text variant="label" color={colors.accentText}>
          Ask your coach
        </Text>
        <Text variant="label" color={colors.accentText}>
          →
        </Text>
      </Pressable>
    </Card>
  );
}

const styles = StyleSheet.create({
  card: { padding: spacing.lg, gap: spacing.sm },
  header: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  flex: { flex: 1 },
  icon: {
    width: 32,
    height: 32,
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loading: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xs },
  body: { lineHeight: 22 },
  hint: { fontSize: 11.5, lineHeight: 16 },
  action: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    alignSelf: 'flex-start',
    paddingTop: spacing.xs,
  },
});
