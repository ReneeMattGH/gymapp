export type ThemeMode = 'dark' | 'light';

export const fonts = {
  display: 'SpaceGrotesk_600SemiBold',
  displayMedium: 'SpaceGrotesk_500Medium',
  displayBold: 'SpaceGrotesk_700Bold',
  body: 'Inter_400Regular',
  bodyMedium: 'Inter_500Medium',
  bodyBold: 'Inter_600SemiBold',
} as const;

export type ThemeColors = {
  background: string;
  backgroundAlt: string;
  surface: string;
  surfaceRaised: string;
  surfaceOverlay: string;
  border: string;
  borderStrong: string;
  text: string;
  textSecondary: string;
  textTertiary: string;
  accent: string;
  accentInk: string;
  accentText: string;
  accentSoft: string;
  accentBorder: string;
  danger: string;
  dangerSoft: string;
  warning: string;
  warningSoft: string;
  info: string;
  success: string;
  overlay: string;
  tabBar: string;
  shadow: string;
  input: string;
};

const shared = {
  accent: '#C7FA4F',
  accentSoftDark: 'rgba(199,250,79,0.12)',
  accentSoftLight: 'rgba(96,132,10,0.10)',
  danger: '#FF7A6B',
  warning: '#F2C46B',
  info: '#8DCBFF',
};

export const darkColors: ThemeColors = {
  background: '#070806',
  backgroundAlt: '#0A0C09',
  surface: '#10130E',
  surfaceRaised: '#171B14',
  surfaceOverlay: 'rgba(16,19,14,0.94)',
  border: 'rgba(232,255,200,0.08)',
  borderStrong: 'rgba(232,255,200,0.16)',
  text: '#F3F6EE',
  textSecondary: '#A9B2A0',
  textTertiary: '#6F7869',
  accent: shared.accent,
  accentInk: '#0B0E06',
  accentText: shared.accent,
  accentSoft: shared.accentSoftDark,
  accentBorder: 'rgba(199,250,79,0.36)',
  danger: shared.danger,
  dangerSoft: 'rgba(255,122,107,0.12)',
  warning: shared.warning,
  warningSoft: 'rgba(242,196,107,0.12)',
  info: shared.info,
  success: shared.accent,
  overlay: 'rgba(4,5,3,0.72)',
  tabBar: 'rgba(11,14,9,0.97)',
  shadow: '#000000',
  input: '#12160F',
};

export const lightColors: ThemeColors = {
  background: '#F3F4EC',
  backgroundAlt: '#EAEDE0',
  surface: '#FFFFFF',
  surfaceRaised: '#F7F8F1',
  surfaceOverlay: 'rgba(255,255,255,0.96)',
  border: 'rgba(14,20,8,0.09)',
  borderStrong: 'rgba(14,20,8,0.18)',
  text: '#101408',
  textSecondary: '#575F4D',
  textTertiary: '#8A9280',
  accent: shared.accent,
  accentInk: '#101408',
  accentText: '#4F6E00',
  accentSoft: shared.accentSoftLight,
  accentBorder: 'rgba(79,110,0,0.32)',
  danger: '#BE4535',
  dangerSoft: 'rgba(190,69,53,0.10)',
  warning: '#946200',
  warningSoft: 'rgba(148,98,0,0.10)',
  info: '#276C99',
  success: '#4F6E00',
  overlay: 'rgba(12,16,8,0.42)',
  tabBar: 'rgba(255,255,255,0.97)',
  shadow: 'rgba(20,28,10,0.10)',
  input: '#F2F4EC',
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  xxxl: 32,
  huge: 48,
} as const;

export const radii = {
  sm: 10,
  md: 14,
  lg: 20,
  xl: 26,
  xxl: 32,
  pill: 999,
} as const;

export const layout = {
  screenPadding: 20,
  tabBarHeight: 68,
  maxContentWidth: 560,
} as const;
