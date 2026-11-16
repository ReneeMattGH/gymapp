import { useRouter } from 'expo-router';
import { ArrowUpRight, Database, KeyRound, Server, Terminal } from 'lucide-react-native';
import React from 'react';
import { Linking, StyleSheet, View } from 'react-native';

import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Screen } from '@/components/ui/Screen';
import { Text } from '@/components/ui/Text';
import { Wordmark } from '@/components/ui/Brand';
import { useTheme } from '@/theme/ThemeProvider';
import { radii, spacing } from '@/theme/tokens';

const steps = [
  {
    icon: Database,
    title: 'Create a Supabase project',
    body: 'Create a project, then open the SQL editor or use the Supabase CLI with the migrations in /supabase/migrations.',
  },
  {
    icon: Server,
    title: 'Deploy the AI functions',
    body: 'Deploy coach-chat, coach-plan, and delete-account. Set OPENAI_API_KEY as a function secret — never in the app.',
  },
  {
    icon: KeyRound,
    title: 'Add the public keys',
    body: 'Put your project URL and anon key in .env. The service-role key is never used by the app.',
  },
];

const envSnippet = `EXPO_PUBLIC_SUPABASE_URL=https://xxxx.supabase.co
EXPO_PUBLIC_SUPABASE_ANON_KEY=eyJhbGci...

# Optional, after Supabase is configured:
# supabase secrets set OPENAI_API_KEY=sk-...`;

export default function SetupScreen() {
  const { colors } = useTheme();
  const router = useRouter();

  return (
    <Screen scroll bottomInset={spacing.xxxl}>
      <View style={styles.brand}>
        <Wordmark />
      </View>

      <View style={styles.header}>
        <View style={[styles.badge, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
          <Text variant="overline" color={colors.accentText}>
            Setup required
          </Text>
        </View>
        <Text variant="display">Connect Forma to your backend.</Text>
        <Text variant="body" color={colors.textSecondary}>
          The interface is ready, but accounts, saved plans, and the AI coach need a Supabase project and an OpenAI
          key on the server. Nothing is faked while you connect them.
        </Text>
      </View>

      <Card style={styles.card}>
        {steps.map((step, index) => (
          <View key={step.title} style={styles.step}>
            <View style={[styles.stepIcon, { backgroundColor: colors.surfaceRaised, borderColor: colors.border }]}>
              <step.icon size={18} color={colors.accentText} />
            </View>
            <View style={styles.stepText}>
              <Text variant="subheading">
                {index + 1}. {step.title}
              </Text>
              <Text variant="caption" style={{ marginTop: 4 }}>
                {step.body}
              </Text>
            </View>
          </View>
        ))}
      </Card>

      <View style={styles.section}>
        <Text variant="overline" color={colors.textSecondary}>
          .env
        </Text>
        <View style={[styles.code, { backgroundColor: colors.surface, borderColor: colors.border }]}>
          <Terminal size={16} color={colors.accentText} style={styles.codeIcon} />
          <Text style={styles.codeText} color={colors.textSecondary}>
            {envSnippet}
          </Text>
        </View>
        <Text variant="caption" color={colors.textTertiary}>
          Restart the dev server after editing .env: npx expo start -c
        </Text>
      </View>

      <View style={styles.actions}>
        <Button label="Check configuration again" onPress={() => router.replace('/')} fullWidth />
        <Button
          label="Open Supabase dashboard"
          variant="outline"
          icon={<ArrowUpRight size={17} color={colors.text} />}
          onPress={() => Linking.openURL('https://supabase.com/dashboard')}
          fullWidth
        />
      </View>

      <Card variant="raised" style={styles.previewHint}>
        <Text variant="subheading" color={colors.textSecondary}>
          Local UI preview
        </Text>
        <Text variant="caption" style={{ marginTop: 4 }}>
          For development only, set EXPO_PUBLIC_DEV_PREVIEW=1 to explore the app with on-device storage. It is disabled
          in production builds and never pretends to be a backend.
        </Text>
      </Card>
    </Screen>
  );
}

const styles = StyleSheet.create({
  brand: { marginBottom: spacing.lg },
  header: { gap: spacing.sm, marginBottom: spacing.sm },
  badge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 5,
    borderRadius: radii.pill,
    borderWidth: StyleSheet.hairlineWidth,
  },
  card: { gap: spacing.xl },
  step: { flexDirection: 'row', gap: spacing.md },
  stepIcon: {
    width: 38,
    height: 38,
    borderRadius: radii.md,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
  },
  stepText: { flex: 1 },
  section: { gap: spacing.sm },
  code: {
    borderRadius: radii.md,
    borderWidth: StyleSheet.hairlineWidth,
    padding: spacing.md,
    flexDirection: 'row',
    gap: spacing.sm,
  },
  codeIcon: { marginTop: 2 },
  codeText: { fontFamily: 'Inter_400Regular', fontSize: 11.5, lineHeight: 18, flex: 1 },
  actions: { gap: spacing.sm, marginTop: spacing.xs },
  previewHint: { marginTop: spacing.xs },
});
