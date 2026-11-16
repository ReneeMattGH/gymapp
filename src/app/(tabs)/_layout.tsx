import { Redirect } from 'expo-router';
import type { BottomTabBarProps } from 'expo-router/js-tabs';
import { Tabs } from 'expo-router/js-tabs';
import { ChartColumn, Dumbbell, House, Sparkles, UserRound } from 'lucide-react-native';
import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';

import { BootSplash } from '@/components/ui/BootSplash';
import { Text } from '@/components/ui/Text';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { layout, radii, spacing } from '@/theme/tokens';

const TABS = {
  index: { label: 'Home', icon: House },
  workouts: { label: 'Workouts', icon: Dumbbell },
  coach: { label: 'Coach', icon: Sparkles },
  progress: { label: 'Progress', icon: ChartColumn },
  profile: { label: 'Profile', icon: UserRound },
} as const;

function FormaTabBar({ state, navigateToTab, insets }: BottomTabBarProps) {
  const { colors } = useTheme();

  return (
    <View
      style={[
        styles.shell,
        {
          paddingBottom: Math.max(insets.bottom, 10),
          backgroundColor: colors.background,
          borderTopColor: colors.border,
        },
      ]}
    >
      <View
        style={[
          styles.bar,
          {
            backgroundColor: colors.tabBar,
            borderColor: colors.border,
            shadowColor: colors.shadow,
          },
        ]}
      >
        {state.routes.map((route, index) => {
          const meta = TABS[route.name as keyof typeof TABS];
          if (!meta) return null;
          const focused = state.index === index;
          const Icon = meta.icon;

          return (
            <Pressable
              key={route.key}
              accessibilityRole="tab"
              accessibilityState={{ selected: focused }}
              accessibilityLabel={meta.label}
              onPress={() => {
                if (!focused) navigateToTab(route.key);
              }}
              style={({ pressed }) => [styles.tab, { opacity: pressed ? 0.72 : 1 }]}
            >
              <View
                style={[
                  styles.iconWrap,
                  focused
                    ? { backgroundColor: colors.accent, shadowColor: colors.accent, shadowOpacity: 0.35 }
                    : null,
                ]}
              >
                <Icon
                  size={19}
                  color={focused ? colors.accentInk : colors.textTertiary}
                  strokeWidth={focused ? 2.5 : 2}
                />
              </View>
              <Text
                style={[
                  styles.label,
                  {
                    color: focused ? colors.accentText : colors.textTertiary,
                    fontFamily: focused ? 'Inter_600SemiBold' : 'Inter_500Medium',
                  },
                ]}
              >
                {meta.label}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}

export default function TabsLayout() {
  const { ready, user, profile, setupRequired } = useApp();

  if (!ready) return <BootSplash />;
  if (setupRequired) return <Redirect href="/setup" />;
  if (!user) return <Redirect href="/(auth)/welcome" />;
  if (!profile?.onboardingCompleted) return <Redirect href="/(onboarding)" />;

  return (
    <Tabs
      tabBar={(props) => <FormaTabBar {...props} />}
      screenOptions={{
        headerShown: false,
        lazy: true,
      }}
    >
      <Tabs.Screen name="index" options={{ title: 'Home' }} />
      <Tabs.Screen name="workouts" options={{ title: 'Workouts' }} />
      <Tabs.Screen name="coach" options={{ title: 'Coach' }} />
      <Tabs.Screen name="progress" options={{ title: 'Progress' }} />
      <Tabs.Screen name="profile" options={{ title: 'Profile' }} />
    </Tabs>
  );
}

const styles = StyleSheet.create({
  shell: {
    paddingTop: spacing.sm,
    paddingHorizontal: spacing.lg,
    borderTopWidth: StyleSheet.hairlineWidth,
  },
  bar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderRadius: radii.xxl,
    borderWidth: StyleSheet.hairlineWidth,
    paddingVertical: 9,
    paddingHorizontal: spacing.sm,
    shadowOffset: { width: 0, height: 10 },
    shadowRadius: 24,
    shadowOpacity: 0.28,
    elevation: 8,
    maxWidth: layout.maxContentWidth + 100,
    width: '100%',
    alignSelf: 'center',
  },
  tab: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
    paddingVertical: 2,
  },
  iconWrap: {
    width: 38,
    height: 32,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    shadowOffset: { width: 0, height: 4 },
    shadowRadius: 10,
    shadowOpacity: 0,
  },
  label: {
    fontSize: 10.5,
    lineHeight: 13,
    letterSpacing: 0.1,
  },
});
