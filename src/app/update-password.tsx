import { useLocalSearchParams, useRouter } from 'expo-router';
import { CheckCircle2, KeyRound } from 'lucide-react-native';
import React, { useEffect, useState } from 'react';
import { View } from 'react-native';

import { AuthShell } from '@/components/layout/AuthShell';
import { Button } from '@/components/ui/Button';
import { Input } from '@/components/ui/Input';
import { InlineError } from '@/components/ui/Misc';
import { Text } from '@/components/ui/Text';
import { authErrorMessage } from '@/lib/authErrors';
import { supabaseConfig } from '@/lib/env';
import { requireSupabase } from '@/lib/supabase';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { spacing } from '@/theme/tokens';

export default function UpdatePasswordScreen() {
  const { colors } = useTheme();
  const router = useRouter();
  const { code, error_description: linkError } = useLocalSearchParams<{
    code?: string;
    error_description?: string;
  }>();
  const { updatePassword, user } = useApp();
  const [password, setPassword] = useState('');
  const [confirm, setConfirm] = useState('');
  const [error, setError] = useState<string | null>(linkError ?? null);
  const [exchanging, setExchanging] = useState(Boolean(code));
  const [ready, setReady] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);

  useEffect(() => {
    let mounted = true;
    const exchange = async () => {
      if (!code) {
        setReady(Boolean(user));
        setExchanging(false);
        return;
      }
      if (!supabaseConfig.isConfigured) {
        setError('Password resets require Supabase to be configured.');
        setExchanging(false);
        return;
      }
      try {
        const { error: exchangeError } = await requireSupabase().auth.exchangeCodeForSession(code);
        if (!mounted) return;
        if (exchangeError) setError(exchangeError.message);
        else setReady(true);
      } catch (caught) {
        if (mounted) setError(authErrorMessage(caught));
      } finally {
        if (mounted) setExchanging(false);
      }
    };
    void exchange();
    return () => {
      mounted = false;
    };
  }, [code, user]);

  const submit = async () => {
    setError(null);
    if (password.length < 8) {
      setError('Use at least 8 characters.');
      return;
    }
    if (password !== confirm) {
      setError('The two passwords do not match.');
      return;
    }
    setBusy(true);
    try {
      await updatePassword(password);
      setDone(true);
    } catch (caught) {
      setError(authErrorMessage(caught));
    } finally {
      setBusy(false);
    }
  };

  if (done) {
    return (
      <AuthShell title="Password updated." subtitle="You can use your new password from now on." back={false}>
        <CheckCircle2 size={38} color={colors.accentText} />
        <Button label="Continue to Forma" onPress={() => router.replace('/')} fullWidth />
      </AuthShell>
    );
  }

  if (exchanging) {
    return (
      <AuthShell title="Checking your link." subtitle="One moment while we verify the reset request." back={false}>
        <View />
      </AuthShell>
    );
  }

  if (!ready) {
    return (
      <AuthShell title="Open the reset link." subtitle="This screen needs a valid reset link from your email." back={false}>
        <KeyRound size={34} color={colors.textTertiary} />
        {error ? <InlineError message={error} /> : null}
        <Button label="Back to sign in" variant="secondary" onPress={() => router.replace('/(auth)/sign-in')} fullWidth />
      </AuthShell>
    );
  }

  return (
    <AuthShell title="Choose a new password." subtitle="Use at least 8 characters and something you do not reuse.">
      <Input
        label="New password"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
      />
      <Input
        label="Confirm new password"
        value={confirm}
        onChangeText={setConfirm}
        secureTextEntry
        autoComplete="new-password"
        textContentType="newPassword"
        onSubmitEditing={submit}
      />
      {error ? <InlineError message={error} /> : null}
      <Button label="Update password" onPress={submit} loading={busy} disabled={busy} fullWidth />
      <View style={{ height: spacing.xs }} />
      <Text variant="caption" color={colors.textTertiary} align="center">
        If you did not request this, close this screen and contact support.
      </Text>
    </AuthShell>
  );
}
