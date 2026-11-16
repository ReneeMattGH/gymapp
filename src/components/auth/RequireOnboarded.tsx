import { Redirect } from 'expo-router';
import React, { type ReactNode } from 'react';

import { BootSplash } from '@/components/ui/BootSplash';
import { useApp } from '@/state/AppProvider';

/** Guards screens outside the tab navigator so they never render without a completed profile. */
export function RequireOnboarded({ children }: { children: ReactNode }) {
  const { ready, user, profile, setupRequired } = useApp();

  if (!ready) return <BootSplash />;
  if (setupRequired) return <Redirect href="/setup" />;
  if (!user) return <Redirect href="/(auth)/welcome" />;
  if (!profile?.onboardingCompleted) return <Redirect href="/(onboarding)" />;

  return <>{children}</>;
}
