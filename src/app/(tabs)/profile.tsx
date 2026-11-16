import { format, parseISO } from 'date-fns';
import { useRouter } from 'expo-router';
import {
  BellRing,
  CalendarDays,
  ChevronRight,
  Dumbbell,
  LogOut,
  Mail,
  Moon,
  Palette,
  ShieldCheck,
  Sparkles,
  Sun,
  Trash2,
  UserRound,
} from 'lucide-react-native';
import React, { useMemo, useState } from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { Badge, Divider, InlineError } from '@/components/ui/Misc';
import { Button } from '@/components/ui/Button';
import { Card } from '@/components/ui/Card';
import { Chip } from '@/components/ui/Chip';
import { Input } from '@/components/ui/Input';
import { Screen } from '@/components/ui/Screen';
import { Sheet } from '@/components/ui/Sheet';
import { Text } from '@/components/ui/Text';
import { EQUIPMENT_LABEL, GOAL_LABEL } from '@/data/types';
import { aiConfigured } from '@/lib/ai';
import { cancelAllReminders, reminderSummary } from '@/lib/notifications';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, spacing } from '@/theme/tokens';

export default function ProfileScreen() {
  const { colors, mode, setMode } = useTheme();
  const router = useRouter();
  const {
    user,
    profile,
    preferences,
    plan,
    reminders,
    previewMode,
    saveReminders,
    signOut,
    deleteAccount,
    dataError,
  } = useApp();

  const [signOutOpen, setSignOutOpen] = useState(false);
  const [deleteOpen, setDeleteOpen] = useState(false);
  const [deleteConfirm, setDeleteConfirm] = useState('');
  const [busy, setBusy] = useState<'signout' | 'delete' | null>(null);
  const [error, setError] = useState<string | null>(null);

  const initials = useMemo(() => {
    const name = profile?.name?.trim() || user?.email?.split('@')[0] || 'You';
    return name
      .split(/\s+/)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase() ?? '')
      .join('');
  }, [profile?.name, user?.email]);

  const memberSince = profile?.createdAt ? format(parseISO(profile.createdAt), 'MMMM yyyy') : null;

  const handleSignOut = async () => {
    setBusy('signout');
    setError(null);
    try {
      await cancelAllReminders();
      if (reminders) await saveReminders({ ...reminders, scheduledIds: [] }).catch(() => {});
      await signOut();
      setSignOutOpen(false);
      router.replace('/(auth)/welcome');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not sign out.');
    } finally {
      setBusy(null);
    }
  };

  const handleDelete = async () => {
    if (deleteConfirm.trim().toUpperCase() !== 'DELETE') {
      setError('Type DELETE to confirm.');
      return;
    }
    setBusy('delete');
    setError(null);
    try {
      await cancelAllReminders();
      await deleteAccount();
      setDeleteOpen(false);
      router.replace('/(auth)/welcome');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not delete your account.');
    } finally {
      setBusy(null);
    }
  };

  return (
    <Screen scroll bottomInset={layout.tabBarHeight + 28}>
      <View style={styles.header}>
        <View>
          <Text variant="overline" color={colors.accentText}>
            Profile
          </Text>
          <Text variant="title" style={{ marginTop: 2 }}>
            Your setup.
          </Text>
        </View>
      </View>

      <Card variant="raised">
        <View style={styles.identity}>
          <View
            style={[
              styles.avatar,
              { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder },
            ]}
          >
            <Text variant="heading" color={colors.accentText}>
              {initials || 'Y'}
            </Text>
          </View>
          <View style={styles.flex}>
            <Text variant="heading" numberOfLines={1}>
              {profile?.name ?? 'Athlete'}
            </Text>
            {user?.email ? (
              <View style={styles.emailRow}>
                <Mail size={12} color={colors.textTertiary} />
                <Text variant="caption" numberOfLines={1}>
                  {user.email}
                </Text>
              </View>
            ) : null}
            <View style={styles.badgeRow}>
              {previewMode ? <Badge label="Preview data" tone="warning" /> : null}
              {!previewMode && !aiConfigured ? <Badge label="AI setup required" tone="warning" /> : null}
              {!previewMode && aiConfigured ? <Badge label="AI connected" tone="accent" /> : null}
              {memberSince ? <Badge label={`Since ${memberSince}`} /> : null}
            </View>
          </View>
        </View>
        {preferences ? (
          <View style={styles.identityMeta}>
            <Text variant="caption" color={colors.textTertiary}>
              {preferences.workoutDays.length} training days · {preferences.sessionMinutes} min ·{' '}
              {preferences.equipment.length} equipment option{preferences.equipment.length === 1 ? '' : 's'}
            </Text>
            {profile?.goals.length ? (
              <Text variant="caption" color={colors.textTertiary} style={{ marginTop: 3 }}>
                Focus: {profile.goals.map((goal) => GOAL_LABEL[goal]).join(' · ')}
              </Text>
            ) : null}
          </View>
        ) : null}
      </Card>

      {dataError ? <InlineError message={dataError} /> : null}

      <View style={styles.section}>
        <Text variant="heading">Your plan</Text>
        <Card onPress={() => router.push('/(tabs)/workouts')} accessibilityLabel="Open your plan">
          <View style={styles.rowBetween}>
            <View style={styles.flex}>
              <Text variant="bodyStrong" numberOfLines={1}>
                {plan?.name ?? 'No active plan'}
              </Text>
              <Text variant="caption" style={{ marginTop: 3 }}>
                {plan
                  ? `${plan.daysPerWeek} days/week · ${plan.sessionMinutes} min · ${
                      plan.source === 'ai' ? 'AI generated' : 'On-device'
                    }`
                  : 'Generate a plan from your preferences.'}
              </Text>
            </View>
            <ChevronRight size={17} color={colors.textTertiary} />
          </View>
          {preferences ? (
            <Text variant="caption" color={colors.textTertiary} style={{ marginTop: spacing.sm }}>
              Equipment: {preferences.equipment.map((item) => EQUIPMENT_LABEL[item]).join(', ') || 'none'}
            </Text>
          ) : null}
        </Card>
        <Text variant="caption" color={colors.textTertiary}>
          Changing preferences does not rewrite an existing plan. Regenerate it when you are ready.
        </Text>
      </View>

      <View style={styles.section}>
        <Text variant="heading">Training</Text>
        <Card padded={false}>
          <SettingsRow
            icon={<UserRound size={17} color={colors.accentText} />}
            title="Edit profile"
            subtitle="Name, experience, goals, limitations"
            onPress={() => router.push('/settings/profile')}
          />
          <SettingsRow
            icon={<Dumbbell size={17} color={colors.accentText} />}
            title="Training preferences"
            subtitle="Days, session length, equipment, units"
            onPress={() => router.push('/settings/preferences')}
          />
          <SettingsRow
            icon={<CalendarDays size={17} color={colors.accentText} />}
            title="Plan"
            subtitle={plan ? `${plan.daysPerWeek} days per week` : 'Not generated'}
            onPress={() => router.push('/plan/generate')}
          />
          <SettingsRow
            last
            icon={<Sparkles size={17} color={colors.accentText} />}
            title="AI coach"
            subtitle={previewMode ? 'On-device preview replies' : aiConfigured ? 'Streaming replies enabled' : 'Add OpenAI key in Supabase'}
            onPress={() => router.push('/(tabs)/coach')}
          />
        </Card>
      </View>

      <View style={styles.section}>
        <Text variant="heading">Reminders & appearance</Text>
        <Card padded={false}>
          <SettingsRow
            icon={<BellRing size={17} color={colors.accentText} />}
            title="Notifications"
            subtitle={reminderSummary(reminders)}
            onPress={() => router.push('/settings/reminders')}
          />
          <View style={[styles.themeRow, { borderTopColor: colors.border }]}>
            <View style={[styles.rowIcon, { backgroundColor: colors.surfaceRaised }]}>
              <Palette size={17} color={colors.accentText} />
            </View>
            <View style={styles.flex}>
              <Text variant="bodyStrong">Appearance</Text>
              <Text variant="caption" style={{ marginTop: 2 }}>
                Dark is the default. Your choice stays on this device.
              </Text>
            </View>
          </View>
          <View style={[styles.themeChips, { borderTopColor: colors.border }]}>
            <Chip
              label="Dark"
              selected={mode === 'dark'}
              onPress={() => setMode('dark')}
              icon={<Moon size={14} color={mode === 'dark' ? colors.accentInk : colors.textSecondary} />}
            />
            <Chip
              label="Light"
              selected={mode === 'light'}
              onPress={() => setMode('light')}
              icon={<Sun size={14} color={mode === 'light' ? colors.accentInk : colors.textSecondary} />}
            />
          </View>
        </Card>
      </View>

      <View style={styles.section}>
        <View style={styles.privacyHead}>
          <ShieldCheck size={16} color={colors.accentText} />
          <Text variant="heading">Privacy</Text>
        </View>
        <Card>
          <Text variant="caption" color={colors.textSecondary} style={styles.privacyText}>
            {previewMode
              ? 'Preview mode stores everything in this browser or device only. Nothing is sent to Supabase or an AI provider. This build must not be used for real training records.'
              : 'Your profile, plan, workouts, check-ins, and coach messages are stored in your own Supabase account with row-level security. The AI coach sends your message plus your training context to the configured provider so it can reply. API keys stay server-side in Supabase Edge Functions.'}
          </Text>
          <Divider style={{ marginVertical: spacing.md }} />
          <Text variant="caption" color={colors.textSecondary}>
            Forma does not diagnose injuries or medical conditions. Stop training and seek professional advice
            for sharp, sudden, or worsening pain, dizziness, chest pain, or shortness of breath.
          </Text>
        </Card>
      </View>

      <View style={styles.section}>
        <Text variant="heading">Account</Text>
        {previewMode ? (
          <Card>
            <Text variant="caption" color={colors.textSecondary}>
              Preview mode has no real account. Sign-out and account deletion become available when Supabase is
              configured. Preview data stays on this device and can be cleared with your browser or app storage.
            </Text>
          </Card>
        ) : (
          <Card padded={false}>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                setError(null);
                setSignOutOpen(true);
              }}
              style={({ pressed }) => [styles.accountRow, { opacity: pressed ? 0.7 : 1 }]}
            >
              <LogOut size={17} color={colors.text} />
              <Text variant="bodyStrong" style={styles.flex}>
                Sign out
              </Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              onPress={() => {
                setError(null);
                setDeleteConfirm('');
                setDeleteOpen(true);
              }}
              style={({ pressed }) => [
                styles.accountRow,
                { borderTopWidth: StyleSheet.hairlineWidth, borderTopColor: colors.border, opacity: pressed ? 0.7 : 1 },
              ]}
            >
              <Trash2 size={17} color={colors.danger} />
              <View style={styles.flex}>
                <Text variant="bodyStrong" color={colors.danger}>
                  Delete account
                </Text>
                <Text variant="caption" style={{ marginTop: 2 }}>
                  Permanently removes your profile, plans, sessions, and coach history.
                </Text>
              </View>
            </Pressable>
          </Card>
        )}
      </View>

      <Text variant="caption" color={colors.textTertiary} style={styles.footerNote}>
        Forma · a training tool, not a medical service.
      </Text>

      <Sheet
        visible={signOutOpen}
        onClose={() => {
          if (!busy) setSignOutOpen(false);
        }}
        title="Sign out?"
        subtitle="Local reminders on this device will be cancelled. Your training data stays in your account."
      >
        {error ? <InlineError message={error} /> : null}
        <Button label="Sign out" variant="secondary" onPress={handleSignOut} loading={busy === 'signout'} fullWidth />
        <Button
          label="Stay signed in"
          variant="ghost"
          onPress={() => setSignOutOpen(false)}
          disabled={busy === 'signout'}
          fullWidth
        />
      </Sheet>

      <Sheet
        visible={deleteOpen}
        onClose={() => {
          if (!busy) setDeleteOpen(false);
        }}
        title="Delete your account"
        subtitle="This cannot be undone. Your profile, plans, workout history, check-ins, and coach conversations are deleted."
      >
        <Input
          label="Type DELETE to confirm"
          value={deleteConfirm}
          onChangeText={setDeleteConfirm}
          autoCapitalize="characters"
          autoCorrect={false}
          placeholder="DELETE"
        />
        {error ? <InlineError message={error} /> : null}
        <Button
          label="Delete everything"
          variant="danger"
          onPress={handleDelete}
          loading={busy === 'delete'}
          disabled={deleteConfirm.trim().toUpperCase() !== 'DELETE'}
          fullWidth
        />
        <Button
          label="Keep my account"
          variant="ghost"
          onPress={() => setDeleteOpen(false)}
          disabled={busy === 'delete'}
          fullWidth
        />
      </Sheet>
    </Screen>
  );
}

function SettingsRow({
  icon,
  title,
  subtitle,
  onPress,
  last,
}: {
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  onPress: () => void;
  last?: boolean;
}) {
  const { colors } = useTheme();
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => [
        styles.settingsRow,
        !last && { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: colors.border },
        { opacity: pressed ? 0.7 : 1 },
      ]}
    >
      <View style={[styles.rowIcon, { backgroundColor: colors.surfaceRaised }]}>{icon}</View>
      <View style={styles.flex}>
        <Text variant="bodyStrong">{title}</Text>
        <Text variant="caption" style={{ marginTop: 2 }} numberOfLines={2}>
          {subtitle}
        </Text>
      </View>
      <ChevronRight size={17} color={colors.textTertiary} />
    </Pressable>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  identity: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  avatar: {
    width: 58,
    height: 58,
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  emailRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 3 },
  badgeRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6, marginTop: spacing.sm },
  identityMeta: { marginTop: spacing.lg },
  section: { gap: spacing.sm },
  rowBetween: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  settingsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
  },
  rowIcon: {
    width: 36,
    height: 36,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  themeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  themeChips: {
    flexDirection: 'row',
    gap: spacing.sm,
    borderTopWidth: StyleSheet.hairlineWidth,
    padding: spacing.lg,
    paddingTop: spacing.md,
  },
  privacyHead: { flexDirection: 'row', alignItems: 'center', gap: 7 },
  privacyText: { lineHeight: 19 },
  accountRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    padding: spacing.lg,
  },
  footerNote: { textAlign: 'center', marginTop: spacing.sm },
});
