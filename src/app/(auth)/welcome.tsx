import { LinearGradient } from 'expo-linear-gradient';
import { useRouter } from 'expo-router';
import { Activity, Brain, ShieldCheck, Target } from 'lucide-react-native';
import React from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { Button } from '@/components/ui/Button';
import { ExerciseArt } from '@/components/ui/ExerciseArt';
import { Text } from '@/components/ui/Text';
import { Wordmark } from '@/components/ui/Brand';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, spacing } from '@/theme/tokens';

const features = [
  { icon: Brain, title: 'A coach with context', body: 'It knows your plan, equipment, and training history.' },
  { icon: Target, title: 'Plans that fit your week', body: 'Built around the days, time, and gear you actually have.' },
  { icon: Activity, title: 'Every set accounted for', body: 'Live workout tracking, rest timers, and honest progress.' },
];

export default function WelcomeScreen() {
  const { colors, isDark } = useTheme();
  const insets = useSafeAreaInsets();
  const router = useRouter();

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <LinearGradient
        colors={isDark ? ['#1A2410', '#0A0C08', '#070806'] : ['#E8F2D2', '#F3F4EC', '#F3F4EC']}
        locations={[0, 0.42, 1]}
        style={StyleSheet.absoluteFill}
      />
      <ScrollView
        contentContainerStyle={[
          styles.content,
          { paddingTop: insets.top + spacing.md, paddingBottom: insets.bottom + spacing.xl },
        ]}
        showsVerticalScrollIndicator={false}
      >
        <Wordmark />

        <View style={styles.hero}>
          <Text variant="overline" color={colors.accentText}>
            AI personal gym coach
          </Text>
          <Text variant="display" style={styles.headline}>
            Train with intent,
            {'\n'}
            not guesswork.
          </Text>
          <Text variant="body" color={colors.textSecondary} style={styles.sub}>
            Forma turns your goals, schedule, and equipment into a plan you can follow — with a coach that explains
            the why behind every movement.
          </Text>
        </View>

        <ExerciseArt id="welcome" muscle="full" category="strength" height={188} label="ADAPTIVE PLAN · LIVE COACHING" />

        <View style={styles.features}>
          {features.map((feature) => (
            <View key={feature.title} style={styles.feature}>
              <View style={[styles.featureIcon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
                <feature.icon size={17} color={colors.accentText} />
              </View>
              <View style={styles.featureText}>
                <Text variant="bodyStrong">{feature.title}</Text>
                <Text variant="caption" style={{ marginTop: 2 }}>
                  {feature.body}
                </Text>
              </View>
            </View>
          ))}
        </View>

        <View style={styles.actions}>
          <Button label="Create your plan" onPress={() => router.push('/(auth)/sign-up')} fullWidth />
          <Button
            label="I already have an account"
            variant="secondary"
            onPress={() => router.push('/(auth)/sign-in')}
            fullWidth
          />
        </View>

        <View style={styles.trust}>
          <ShieldCheck size={14} color={colors.textTertiary} />
          <Text variant="caption" color={colors.textTertiary} style={styles.trustText}>
            Coaching software, not medical care. Stop and seek professional advice if you experience pain or
            dizziness.
          </Text>
        </View>
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  content: {
    paddingHorizontal: layout.screenPadding,
    gap: spacing.xl,
    maxWidth: layout.maxContentWidth,
    width: '100%',
    alignSelf: 'center',
  },
  hero: { gap: spacing.md, marginTop: spacing.xl },
  headline: { fontSize: 42, lineHeight: 44, letterSpacing: -1.8 },
  sub: { maxWidth: 460 },
  features: { gap: spacing.lg },
  feature: { flexDirection: 'row', gap: spacing.md, alignItems: 'flex-start' },
  featureIcon: {
    width: 36,
    height: 36,
    borderRadius: 12,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  featureText: { flex: 1 },
  actions: { gap: spacing.sm, marginTop: spacing.xs },
  trust: { flexDirection: 'row', gap: 8, alignItems: 'flex-start', paddingTop: spacing.xs },
  trustText: { flex: 1, lineHeight: 17 },
});
