import { useRouter } from 'expo-router';
import { MailCheck } from 'lucide-react-native';
import React, { useState } from 'react';
import { View } from 'react-native';

import { AuthShell } from '@/components/layout/AuthShell';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import { authErrorMessage } from '@/lib/authErrors';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';

export default function ForgotPasswordScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { resetPassword } = useApp();
  const [email, setEmail] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const submit = async () => {
    setError(null);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
      setError('Enter the email you used to sign up.');
      return;
    }
    setBusy(true);
    try {
      await resetPassword(email.trim());
      setSent(true);
    } catch (caught) {
      setError(authErrorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  if (sent) {
    return (
      <AuthShell
        title="Reset link sent."
        subtitle={`If an account exists for ${email.trim()}, a reset link is on its way. Open it on this device to choose a new password.`}
        back={false}
      >
        <MailCheck size={34} color={colors.accentText} />
        <Text variant="caption" color={colors.textTertiary}>
          The link expires after a short time. You can request another one if needed.
        </Text>
        <Button label="Back to sign in" onPress={() => router.replace('/(auth)/sign-in')} fullWidth />
      </AuthShell>
    );
  }

  return (
    <AuthShell
      title="Reset your password."
      subtitle="Enter your account email and we will send a secure reset link."
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
        onSubmitEditing={submit}
      />
      {error ? <InlineError message={error} /> : null}
      <Button label="Send reset link" onPress={submit} loading={busy} disabled={busy} fullWidth />
      <View />
    </AuthShell>
  );
}
