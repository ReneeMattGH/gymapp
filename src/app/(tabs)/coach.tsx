import { format, parseISO } from 'date-fns';
import {
  Clock,
  Info,
  MessageSquare,
  Plus,
  RefreshCw,
  Send,
  Sparkles,
  Square,
  Trash2,
} from 'lucide-react-native';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  TextInput,
  View,
  type ScrollViewInstance,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { RichText } from '@/components/coach/RichText';
import { TypingDots } from '@/components/coach/TypingDots';
import { Badge, InlineError } from '@/components/ui/Misc';
import { IconButton } from '@/components/ui/IconButton';
import { Sheet } from '@/components/ui/Sheet';
import { Text } from '@/components/ui/Text';
import { repository } from '@/data';
import type { CoachConversation, CoachMessage } from '@/data/types';
import { aiConfigured, streamCoachReply } from '@/lib/ai';
import { newId } from '@/lib/id';
import { localCoachReply } from '@/lib/localCoach';
import { exerciseName, planForDate } from '@/lib/plan';
import { useApp } from '@/state/AppProvider';
import { useTheme } from '@/theme/ThemeProvider';
import { fonts, radii, spacing } from '@/theme/tokens';

export default function CoachScreen() {
  const { colors } = useTheme();
  const insets = useSafeAreaInsets();
  const { user, profile, preferences, plan, sessions, exercises, previewMode } = useApp();

  const [conversations, setConversations] = useState<CoachConversation[]>([]);
  const [current, setCurrent] = useState<CoachConversation | null>(null);
  const [messages, setMessages] = useState<CoachMessage[]>([]);
  const [input, setInput] = useState('');
  const [busy, setBusy] = useState(false);
  const [loadingHistory, setLoadingHistory] = useState(true);
  const [loadingMessages, setLoadingMessages] = useState(false);
  const [streaming, setStreaming] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [historyVisible, setHistoryVisible] = useState(false);
  const [confirmDeleteId, setConfirmDeleteId] = useState<string | null>(null);
  const [lastUserText, setLastUserText] = useState<string | null>(null);

  const scrollRef = useRef<ScrollViewInstance>(null);
  const abortRef = useRef<AbortController | null>(null);

  const today = plan ? planForDate(plan, new Date()) : undefined;
  const firstExerciseId = today?.exercises[0]?.exerciseId;

  const suggestions = useMemo(
    () => [
      today && !today.isRestDay
        ? `What's in my ${today.title.toLowerCase()} today?`
        : 'How should I use a rest day?',
      firstExerciseId
        ? `How do I do a ${exerciseName(firstExerciseId)} with good form?`
        : 'How do I do a goblet squat with good form?',
      'I only have 15 minutes today',
      'What is a good warm-up and cool-down?',
    ],
    [firstExerciseId, today],
  );

  useEffect(() => {
    if (!user) return;
    let cancelled = false;

    const load = async () => {
      try {
        const list = await repository.listConversations(user.id);
        if (cancelled) return;
        setConversations(list);
        if (list.length === 0) return;
        const conversation = list[0];
        setCurrent(conversation);
        const loaded = await repository.listMessages(conversation.id);
        if (cancelled) return;
        setMessages(loaded);
        setLastUserText([...loaded].reverse().find((message) => message.role === 'user')?.content ?? null);
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load your coach history.');
      } finally {
        if (!cancelled) setLoadingHistory(false);
      }
    };

    void load();
    return () => {
      cancelled = true;
      abortRef.current?.abort();
    };
  }, [user]);

  const loadConversation = async (conversation: CoachConversation, closeSheet = true) => {
    abortRef.current?.abort();
    abortRef.current = null;
    setStreaming(null);
    setBusy(false);
    setError(null);
    setNotice(null);
    setConfirmDeleteId(null);
    setCurrent(conversation);
    if (closeSheet) setHistoryVisible(false);
    setLoadingMessages(true);
    try {
      const loaded = await repository.listMessages(conversation.id);
      setMessages(loaded);
      setLastUserText([...loaded].reverse().find((message) => message.role === 'user')?.content ?? null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not load this conversation.');
    } finally {
      setLoadingMessages(false);
    }
  };

  const startNew = () => {
    abortRef.current?.abort();
    abortRef.current = null;
    setStreaming(null);
    setBusy(false);
    setCurrent(null);
    setMessages([]);
    setInput('');
    setError(null);
    setNotice(null);
    setLastUserText(null);
    setHistoryVisible(false);
    setConfirmDeleteId(null);
  };

  const generateReply = async (conversation: CoachConversation, text: string) => {
    if (!profile || !preferences) throw new Error('Your profile is still loading.');

    if (!aiConfigured) {
      const reply = localCoachReply(text, { profile, preferences, plan, sessions, exercises });
      const assistant: CoachMessage = {
        id: newId('msg'),
        conversationId: conversation.id,
        userId: conversation.userId,
        role: 'assistant',
        content: reply,
        createdAt: new Date().toISOString(),
      };
      await repository.addMessage(assistant);
      setMessages((prev) => [...prev, assistant]);
    } else {
      const controller = new AbortController();
      abortRef.current = controller;
      setStreaming('');
      const full = await streamCoachReply({
        conversationId: conversation.id,
        message: text,
        signal: controller.signal,
        onDelta: (delta) => setStreaming((prev) => (prev ?? '') + delta),
      });
      if (controller.signal.aborted) return;
      const content = full.trim();
      if (!content) throw new Error('The coach returned an empty response. Please try again.');
      const assistant: CoachMessage = {
        id: newId('msg'),
        conversationId: conversation.id,
        userId: conversation.userId,
        role: 'assistant',
        content,
        createdAt: new Date().toISOString(),
      };
      await repository.addMessage(assistant);
      setMessages((prev) => [...prev, assistant]);
    }

    const updated: CoachConversation = { ...conversation, updatedAt: new Date().toISOString() };
    await repository.updateConversation(updated).catch(() => {});
    setCurrent(updated);
    setConversations((prev) => [updated, ...prev.filter((item) => item.id !== updated.id)]);
  };

  const send = async (raw?: string) => {
    if (!user || !profile || !preferences || busy) return;
    const text = (raw ?? input).trim();
    if (!text) return;

    setError(null);
    setNotice(null);
    setInput('');
    setLastUserText(text);
    setBusy(true);
    setStreaming(aiConfigured ? '' : null);

    let conversation = current;
    try {
      if (!conversation) {
        const now = new Date().toISOString();
        conversation = {
          id: newId('conv'),
          userId: user.id,
          title: text.length > 58 ? `${text.slice(0, 57)}…` : text,
          createdAt: now,
          updatedAt: now,
        };
        await repository.createConversation(conversation);
        setCurrent(conversation);
        setConversations((prev) => [conversation as CoachConversation, ...prev]);
      }

      const userMessage: CoachMessage = {
        id: newId('msg'),
        conversationId: conversation.id,
        userId: user.id,
        role: 'user',
        content: text,
        createdAt: new Date().toISOString(),
      };
      await repository.addMessage(userMessage);
      setMessages((prev) => [...prev, userMessage]);

      await generateReply(conversation, text);
    } catch (err) {
      if (abortRef.current?.signal.aborted || (err instanceof Error && err.name === 'AbortError')) {
        setNotice('Response stopped.');
      } else {
        setError(err instanceof Error ? err.message : 'The coach could not respond. Please try again.');
      }
    } finally {
      abortRef.current = null;
      setStreaming(null);
      setBusy(false);
    }
  };

  const retry = async () => {
    if (!current || !lastUserText || busy) return;
    setError(null);
    setBusy(true);
    setStreaming(aiConfigured ? '' : null);
    try {
      await generateReply(current, lastUserText);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'The coach could not respond. Please try again.');
    } finally {
      abortRef.current = null;
      setStreaming(null);
      setBusy(false);
    }
  };

  const stop = () => {
    abortRef.current?.abort();
    abortRef.current = null;
    setStreaming(null);
    setBusy(false);
    setNotice('Response stopped.');
  };

  const deleteConversation = async (conversationId: string) => {
    try {
      await repository.deleteConversation(conversationId);
      setConversations((prev) => prev.filter((item) => item.id !== conversationId));
      setConfirmDeleteId(null);
      if (current?.id === conversationId) startNew();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not delete the conversation.');
    }
  };

  const statusLabel = previewMode
    ? 'On-device preview coach'
    : aiConfigured
      ? 'Live AI coach · your plan and history'
      : 'AI setup required';

  const showEmpty = !loadingMessages && messages.length === 0 && streaming === null;

  return (
    <View style={[styles.root, { backgroundColor: colors.background }]}>
      <KeyboardAvoidingView
        style={styles.flex}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <View style={[styles.header, { paddingTop: insets.top + spacing.sm, borderBottomColor: colors.border }]}>
          <View style={styles.headerMain}>
            <View style={[styles.coachAvatar, { backgroundColor: colors.accentSoft, borderColor: colors.accentBorder }]}>
              <Sparkles size={19} color={colors.accentText} strokeWidth={2.1} />
            </View>
            <View style={styles.flex}>
              <Text variant="heading">Coach</Text>
              <Text variant="caption" numberOfLines={1} style={{ marginTop: 1 }}>
                {statusLabel}
              </Text>
            </View>
            <IconButton accessibilityLabel="Conversation history" onPress={() => setHistoryVisible(true)} size={38}>
              <Clock size={17} color={colors.text} />
            </IconButton>
            <IconButton accessibilityLabel="New conversation" onPress={startNew} size={38}>
              <Plus size={18} color={colors.text} />
            </IconButton>
          </View>
          {previewMode ? (
            <View style={styles.previewRow}>
              <Info size={12} color={colors.textTertiary} />
              <Text variant="caption" color={colors.textTertiary} style={styles.flex}>
                Answers use your saved plan and the exercise library on this device. Configure
                Supabase + OpenAI for live AI coaching.
              </Text>
            </View>
          ) : null}
        </View>

        <ScrollView
          ref={scrollRef}
          style={styles.flex}
          contentContainerStyle={[styles.messages, showEmpty ? styles.messagesEmpty : null]}
          keyboardShouldPersistTaps="handled"
          onContentSizeChange={() => scrollRef.current?.scrollToEnd({ animated: true })}
          showsVerticalScrollIndicator={false}
        >
          {loadingHistory || loadingMessages ? (
            <View style={styles.loading}>
              <ActivityIndicator size="small" color={colors.accent} />
              <Text variant="caption" color={colors.textTertiary}>
                Loading your coach…
              </Text>
            </View>
          ) : showEmpty ? (
            <View style={styles.intro}>
              <View style={[styles.introIcon, { backgroundColor: colors.surface, borderColor: colors.border }]}>
                <MessageSquare size={24} color={colors.accentText} />
              </View>
              <Text variant="title" align="center">
                What can we work on{profile?.name ? `, ${profile.name.split(/\s+/)[0]}` : ''}?
              </Text>
              <Text variant="body" color={colors.textSecondary} align="center" style={styles.introCopy}>
                Ask about form, today&apos;s session, substitutions, recovery, or how to make the
                plan fit your week.
              </Text>
              <View style={styles.suggestions}>
                {suggestions.map((suggestion) => (
                  <Pressable
                    key={suggestion}
                    accessibilityRole="button"
                    onPress={() => void send(suggestion)}
                    style={({ pressed }) => [
                      styles.suggestion,
                      { backgroundColor: colors.surface, borderColor: colors.border, opacity: pressed ? 0.7 : 1 },
                    ]}
                  >
                    <Text variant="body" color={colors.textSecondary} style={styles.flex}>
                      {suggestion}
                    </Text>
                    <Send size={14} color={colors.textTertiary} />
                  </Pressable>
                ))}
              </View>
              <Text variant="caption" color={colors.textTertiary} align="center" style={styles.disclaimer}>
                Coaching is educational and never a substitute for medical advice. Stop if you feel
                pain, dizziness, or unusual shortness of breath.
              </Text>
            </View>
          ) : (
            <>
              {messages.map((message) => (
                <MessageBubble key={message.id} message={message} />
              ))}
              {streaming !== null ? (
                <View style={[styles.row, styles.assistantRow]}>
                  <View style={[styles.bubble, { backgroundColor: colors.surface, borderColor: colors.border }]}>
                    {streaming === '' ? <TypingDots /> : <RichText content={streaming} />}
                    {streaming !== '' ? (
                      <Text variant="caption" color={colors.accentText} style={styles.cursor}>
                        ▍
                      </Text>
                    ) : null}
                  </View>
                </View>
              ) : null}
              {notice ? (
                <Text variant="caption" color={colors.textTertiary} align="center">
                  {notice}
                </Text>
              ) : null}
            </>
          )}
        </ScrollView>

        <View style={[styles.composerWrap, { borderTopColor: colors.border, backgroundColor: colors.background }]}>
          {error ? (
            <View style={styles.errorWrap}>
              <InlineError message={error} />
              {lastUserText ? (
                <Pressable onPress={() => void retry()} accessibilityRole="button" hitSlop={8}>
                  <View style={styles.retry}>
                    <RefreshCw size={12} color={colors.accentText} />
                    <Text variant="caption" color={colors.accentText}>
                      Retry
                    </Text>
                  </View>
                </Pressable>
              ) : null}
            </View>
          ) : null}
          <View style={styles.composer}>
            <TextInput
              value={input}
              onChangeText={setInput}
              placeholder="Ask your coach anything…"
              placeholderTextColor={colors.textTertiary}
              selectionColor={colors.accentText}
              multiline
              maxLength={1200}
              editable={!busy}
              style={[
                styles.input,
                {
                  backgroundColor: colors.input,
                  borderColor: colors.border,
                  color: colors.text,
                  maxHeight: 116,
                },
              ]}
              onSubmitEditing={() => void send()}
              blurOnSubmit={false}
            />
            <Pressable
              accessibilityRole="button"
              accessibilityLabel={busy ? 'Stop response' : 'Send message'}
              disabled={!busy && !input.trim()}
              onPress={() => (busy ? stop() : void send())}
              style={({ pressed }) => [
                styles.send,
                {
                  backgroundColor: busy || input.trim() ? colors.accent : colors.surfaceRaised,
                  opacity: pressed ? 0.75 : 1,
                },
              ]}
            >
              {busy && streaming === null ? (
                <ActivityIndicator size="small" color={colors.accentInk} />
              ) : busy ? (
                <Square size={14} color={colors.accentInk} fill={colors.accentInk} />
              ) : (
                <Send size={17} color={input.trim() ? colors.accentInk : colors.textTertiary} />
              )}
            </Pressable>
          </View>
          <Text variant="caption" color={colors.textTertiary} align="center" style={styles.inputHint}>
            {previewMode ? 'On-device preview · not a live AI model' : 'Coach may make mistakes — check your form safely.'}
          </Text>
        </View>
      </KeyboardAvoidingView>

      <Sheet
        visible={historyVisible}
        onClose={() => {
          setHistoryVisible(false);
          setConfirmDeleteId(null);
        }}
        title="Conversations"
        subtitle="Your coaching history is saved to your account."
      >
        <Pressable
          onPress={startNew}
          accessibilityRole="button"
          style={({ pressed }) => [
            styles.newChat,
            { borderColor: colors.accentBorder, backgroundColor: colors.accentSoft, opacity: pressed ? 0.75 : 1 },
          ]}
        >
          <Plus size={16} color={colors.accentText} />
          <Text variant="label" color={colors.accentText}>
            Start a new conversation
          </Text>
        </Pressable>

        <ScrollView contentContainerStyle={styles.historyList} showsVerticalScrollIndicator={false}>
          {conversations.length === 0 ? (
            <Text variant="body" color={colors.textSecondary} align="center" style={styles.historyEmpty}>
              No saved conversations yet. Your first question starts one.
            </Text>
          ) : (
            conversations.map((conversation) => {
              const selected = current?.id === conversation.id;
              const confirming = confirmDeleteId === conversation.id;
              return (
                <View
                  key={conversation.id}
                  style={[
                    styles.historyRow,
                    {
                      backgroundColor: selected ? colors.accentSoft : colors.surface,
                      borderColor: selected ? colors.accentBorder : colors.border,
                    },
                  ]}
                >
                  <Pressable
                    onPress={() => void loadConversation(conversation)}
                    accessibilityRole="button"
                    style={({ pressed }) => [styles.historyMain, { opacity: pressed ? 0.65 : 1 }]}
                  >
                    <View style={styles.flex}>
                      <Text variant="bodyStrong" numberOfLines={1}>
                        {conversation.title}
                      </Text>
                      <Text variant="caption">
                        {format(parseISO(conversation.updatedAt), 'd MMM · HH:mm')}
                      </Text>
                    </View>
                  </Pressable>
                  {confirming ? (
                    <View style={styles.confirmRow}>
                      <Pressable onPress={() => setConfirmDeleteId(null)} accessibilityRole="button" hitSlop={6}>
                        <Text variant="caption" color={colors.textSecondary}>
                          Cancel
                        </Text>
                      </Pressable>
                      <Pressable
                        onPress={() => void deleteConversation(conversation.id)}
                        accessibilityRole="button"
                        hitSlop={6}
                      >
                        <Text variant="caption" color={colors.danger}>
                          Delete
                        </Text>
                      </Pressable>
                    </View>
                  ) : (
                    <Pressable
                      onPress={() => setConfirmDeleteId(conversation.id)}
                      accessibilityRole="button"
                      accessibilityLabel={`Delete ${conversation.title}`}
                      hitSlop={8}
                      style={styles.trash}
                    >
                      <Trash2 size={15} color={colors.textTertiary} />
                    </Pressable>
                  )}
                </View>
              );
            })
          )}
        </ScrollView>
      </Sheet>
    </View>
  );
}

function MessageBubble({ message }: { message: CoachMessage }) {
  const { colors } = useTheme();
  const isUser = message.role === 'user';

  return (
    <View style={[styles.row, isUser ? styles.userRow : styles.assistantRow]}>
      {!isUser ? <Badge label="" tone="accent" icon={<Sparkles size={11} color={colors.accentText} />} /> : null}
      <View
        style={[
          styles.bubble,
          isUser
            ? { backgroundColor: colors.accent, borderColor: colors.accent }
            : { backgroundColor: colors.surface, borderColor: colors.border },
          isUser ? styles.userBubble : null,
        ]}
      >
        {isUser ? (
          <Text variant="body" color={colors.accentInk}>
            {message.content}
          </Text>
        ) : (
          <RichText content={message.content} />
        )}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  flex: { flex: 1 },
  header: {
    gap: spacing.sm,
    paddingHorizontal: spacing.lg,
    paddingBottom: spacing.md,
    borderBottomWidth: StyleSheet.hairlineWidth,
  },
  headerMain: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  coachAvatar: {
    width: 42,
    height: 42,
    borderRadius: 15,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  previewRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 6,
    paddingRight: spacing.xl,
  },
  messages: {
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.lg,
    paddingBottom: spacing.md,
    gap: spacing.md,
  },
  messagesEmpty: { flexGrow: 1, justifyContent: 'center' },
  loading: { alignItems: 'center', gap: spacing.sm, paddingVertical: spacing.xxxl },
  intro: { alignItems: 'center', gap: spacing.md },
  introIcon: {
    width: 62,
    height: 62,
    borderRadius: 22,
    borderWidth: StyleSheet.hairlineWidth,
    alignItems: 'center',
    justifyContent: 'center',
  },
  introCopy: { maxWidth: 320 },
  suggestions: { width: '100%', gap: spacing.sm, marginTop: spacing.sm },
  suggestion: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.lg,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
  },
  disclaimer: { maxWidth: 320, marginTop: spacing.sm },
  row: { flexDirection: 'row', gap: spacing.sm, alignItems: 'flex-end' },
  userRow: { justifyContent: 'flex-end' },
  assistantRow: { justifyContent: 'flex-start' },
  bubble: {
    maxWidth: '86%',
    borderRadius: 20,
    borderWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm + 2,
    gap: 2,
  },
  userBubble: { borderBottomRightRadius: 7 },
  cursor: { marginTop: -2 },
  composerWrap: {
    borderTopWidth: StyleSheet.hairlineWidth,
    paddingHorizontal: spacing.lg,
    paddingTop: spacing.sm,
    paddingBottom: spacing.sm,
    gap: spacing.xs,
  },
  errorWrap: { gap: 6, marginBottom: 4 },
  retry: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-end' },
  composer: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.sm },
  input: {
    flex: 1,
    minHeight: 46,
    maxHeight: 116,
    borderWidth: 1,
    borderRadius: radii.xl,
    paddingHorizontal: spacing.lg,
    paddingTop: 13,
    paddingBottom: 12,
    fontFamily: fonts.body,
    fontSize: 15,
    lineHeight: 21,
  },
  send: {
    width: 46,
    height: 46,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  inputHint: { fontSize: 10.5, lineHeight: 14 },
  newChat: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: spacing.sm,
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    paddingVertical: spacing.md,
  },
  historyList: { gap: spacing.sm, paddingBottom: spacing.lg },
  historyEmpty: { paddingVertical: spacing.xl },
  historyRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: StyleSheet.hairlineWidth,
    borderRadius: radii.md,
    paddingLeft: spacing.md,
    paddingRight: spacing.sm,
    paddingVertical: spacing.sm,
    gap: spacing.sm,
  },
  historyMain: { flex: 1, paddingVertical: 2 },
  confirmRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
  trash: { padding: 4 },
});
