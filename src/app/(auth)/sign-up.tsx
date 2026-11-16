import { useRouter } from 'expo-router';
import { CheckCircle2, MailCheck } from 'lucide-react-native';
import React, { useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { AuthShell } from '@/components/layout/AuthShell';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import { authErrorMessage } from '@/lib/authErrors';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { spacing } from '@/theme/tokens';

export default function SignUpScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { signUp } = useApp();
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [sentTo, setSentTo] = useState<string | null>(null);

  const submit = async () => {
    setError(null);
    if (name.trim().length < 2) {
      setError('Tell us what you would like to be called.');
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError('Enter a valid email address.');
      return;
    }
    if (password.length < 8) {
      setError('Use at least 8 characters for your password.');
      return;
    }
    if (password !== confirm) {
      setError('The two passwords do not match.');
      return;
    }

    setBusy(true);
    try {
      const result = await signUp(name.trim(), email.trim(), password);
      if (result.needsEmailConfirmation) {
        setSentTo(email.trim());
      } else {
        router.replace('/');
      }
    } catch (caught) {
      setError(authErrorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  if (sentTo) {
    return (
      <AuthShell
        title="Check your inbox."
        subtitle={`We sent a confirmation link to ${sentTo}. Open it, then come back and sign in.`}
        back={false}
      >
        <View style={[styles.successIcon, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
          <MailCheck size={30} color={colors.accentText} />
        </View>
        <Text variant="body" color={colors.textSecondary}>
          The link may take a minute to arrive. Check your spam folder if you do not see it.
        </Text>
        <Button label="Back to sign in" onPress={() => router.replace('/(auth)/sign-in')} fullWidth />
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="Start with a plan."
      subtitle="A few details now means the training actually fits your life. You can change everything later."
      footer={
        <Pressable accessibilityRole="button" onPress={() => router.replace('/(auth)/sign-in')} hitSlop={8}>
          <Text variant="caption" color={colors.textSecondary}>
            Already training with Forma? <Text variant="label" color={colors.accentText}>Sign in</Text>
          </Text>
        </Pressable>
      }
    >
      <Input
        label="Your name"
        value={name}
        onChangeText={setName}
        placeholder="What should the coach call you?"
        autoCapitalize="words"
        autoComplete="name"
        textContentType="name"
      />
      <Input
        label="Email"
        value={email}
        onChangeText={setEmail}
        placeholder="you@example.com"
        keyboardType="email-address"
        autoCapitalize="none"
        autoComplete="email"
        textContentType="emailAddress"
      />
      <Input
        label="Password"
        value={password}
        onChangeText={setPassword}
        placeholder="At least 8 characters"
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
        hint="Use a password you do not reuse elsewhere."
      />
      <Input
        label="Confirm password"
        value={confirm}
        onChangeText={setConfirm}
        placeholder="Repeat your password"
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
        onSubmitEditing={submit}
      />

      {error ? <InlineError message={error} /> : null}

      <View style={styles.terms}>
        {['Real plans from real preferences', 'Your data stays yours', 'You can delete your account any time'].map(
          (item) => (
            <View key={item} style={styles.termRow}>
              <CheckCircle2 size={15} color={colors.accentText} />
              <Text variant="caption" color={colors.textSecondary} style={styles.termText}>
                {item}
              </Text>
            </View>
          ),
        )}
      </View>

      <Button label="Create account" onPress={submit} loading={busy} disabled={busy} fullWidth />
      <Text variant="caption" color={colors.textTertiary} align="center">
        Forma is coaching software, not medical care. Consult a qualified professional for injuries or health
        concerns.
      </Text>
    </AuthShell>
  );
}

const styles = StyleSheet.create({
  successIcon: {
    width: 64,
    height: 64,
    borderRadius: 22,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    marginBottom: spacing.sm,
  },
  terms: { gap: 8, marginTop: -4 },
  termRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  termText: { flex: 1 },
});
