import { Redirect, Stack } from 'expo-router';
import React from 'react';

import { BootSplash } from '@/components/ui/BootSplash';
import { useApp } from '@/state/AppProvider';

export default function AuthLayout() {
  const { ready, user, profile, setupRequired } = useApp();

  if (!ready) return <BootSplash />;
  if (setupRequired) return <Redirect href="/setup" />;
  if (user && profile?.onboardingCompleted) return <Redirect href="/(tabs)" />;
  if (user) return <Redirect href="/(onboarding)" />;

  return <Stack screenOptions={{ headerShown: false, animation: 'fade' }} />;
}
