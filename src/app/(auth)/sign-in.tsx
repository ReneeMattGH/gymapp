import { useRouter } from 'expo-router';
import React, { useState } from 'react';
import { Pressable, StyleSheet } from 'react-native';

import { AuthShell } from '@/components/layout/AuthShell';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import { authErrorMessage } from '@/lib/authErrors';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';

export default function SignInScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { signIn } = useApp();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setError(null);
    if (!email.trim() || !password) {
      setError('Enter your email and password.');
      return;
    }
    setBusy(true);
    try {
      await signIn(email, password);
      router.replace('/');
    } catch (caught) {
      setError(authErrorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  return (
    <AuthShell
      title="Welcome back."
      subtitle="Sign in to pick up where you left off. Your plan and progress are waiting."
      footer={
        <Pressable accessibilityRole="button" onPress={() => router.push('/(auth)/sign-up')} hitSlop={8}>
          <Text variant="caption" color={colors.textSecondary}>
            New to Forma? <Text variant="label" color={colors.accentText}>Create an account</Text>
          </Text>
        </Pressable>
      }
    >
      <Input
        label="Email"
        value={email}
        onChangeText={setEmail}
        placeholder="you@example.com"
        keyboardType="email-address"
        autoCapitalize="none"
        autoComplete="email"
        textContentType="emailAddress"
        returnKeyType="next"
      />
      <Input
        label="Password"
        value={password}
        onChangeText={setPassword}
        placeholder="Your password"
        secureTextEntry
        autoComplete="password"
        textContentType="password"
        returnKeyType="go"
        onSubmitEditing={submit}
      />

      <Pressable
        accessibilityRole="button"
        onPress={() => router.push('/(auth)/forgot-password')}
        style={styles.forgot}
        hitSlop={8}
      >
        <Text variant="label" color={colors.accentText}>
          Forgot password?
        </Text>
      </Pressable>

      {error ? <InlineError message={error} /> : null}

      <Button label="Sign in" onPress={submit} loading={busy} disabled={busy} fullWidth />
    </AuthShell>
  );
}

const styles = StyleSheet.create({
  forgot: { alignSelf: 'flex-end', marginTop: -4 },
});
