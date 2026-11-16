import React from 'react';
import { StyleSheet, View } from 'react-native';

import { Text } from '@/components/ui/Text';
import { useTheme } from '@/theme/ThemeProvider';
import { spacing } from '@/theme/tokens';

function Inline({ text, color }: { text: string; color: string }) {
  const parts = text.split(/(\*\*[^*]+\*\*|`[^`]+`)/g).filter(Boolean);
  return (
    <Text variant="body" color={color} style={styles.inline}>
      {parts.map((part, index) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return (
            <Text key={index} style={styles.bold}>
              {part.slice(2, -2)}
            </Text>
          );
        }
        if (part.startsWith('`') && part.endsWith('`')) {
          return (
            <Text key={index} style={styles.mono}>
              {part.slice(1, -1)}
            </Text>
          );
        }
        return part;
      })}
    </Text>
  );
}

/** Lightweight markdown renderer for coach replies: bold, bullets, and numbered lines. */
export function RichText({ content, color }: { content: string; color?: string }) {
  const { colors } = useTheme();
  const bodyColor = color ?? colors.text;
  const lines = content.replace(/\r\n/g, '\n').split('\n');

  return (
    <View style={styles.wrap}>
      {lines.map((raw, index) => {
        const line = raw.trimEnd();
        if (!line.trim()) return <View key={`space-${index}`} style={styles.space} />;

        const heading = line.match(/^#{1,3}\s+(.*)$/);
        if (heading) {
          return (
            <Text key={index} variant="subheading" color={bodyColor} style={styles.heading}>
              {heading[1].replace(/\*\*/g, '')}
            </Text>
          );
        }

        const bullet = line.match(/^\s*[-•*]\s+(.*)$/);
        if (bullet) {
          return (
            <View key={index} style={styles.bulletRow}>
              <View style={[styles.dot, { backgroundColor: colors.accentText }]} />
              <View style={styles.flex}>
                <Inline text={bullet[1]} color={bodyColor} />
              </View>
            </View>
          );
        }

        const numbered = line.match(/^\s*(\d+)\.\s+(.*)$/);
        if (numbered) {
          return (
            <View key={index} style={styles.bulletRow}>
              <Text variant="caption" color={colors.accentText} style={styles.number}>
                {numbered[1]}
              </Text>
              <View style={styles.flex}>
                <Inline text={numbered[2]} color={bodyColor} />
              </View>
            </View>
          );
        }

        return <Inline key={index} text={line} color={bodyColor} />;
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { gap: 3 },
  flex: { flex: 1 },
  inline: { lineHeight: 21 },
  bold: { fontFamily: 'Inter_600SemiBold' },
  mono: { fontFamily: 'Inter_500Medium' },
  space: { height: 4 },
  heading: { marginTop: 4, marginBottom: 1 },
  bulletRow: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-start' },
  dot: { width: 4.5, height: 4.5, borderRadius: 3, marginTop: 8 },
  number: { width: 16, marginTop: 2, fontFamily: 'Inter_600SemiBold' },
});
