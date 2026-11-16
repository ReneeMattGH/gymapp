import { Redirect } from 'expo-router';
import React from 'react';

import { BootSplash } from '@/components/ui/BootSplash';
import { useApp } from '@/state/AppProvider';

export default function Index() {
  const { ready, dataLoading, user, profile, setupRequired } = useApp();

  if (!ready || (user && dataLoading)) {
    return <BootSplash />;
  }

  if (setupRequired) return <Redirect href="/setup" />;
  if (!user) return <Redirect href="/(auth)/welcome" />;
  if (!profile?.onboardingCompleted) return <Redirect href="/(onboarding)" />;

  return <Redirect href="/(tabs)" />;
}
