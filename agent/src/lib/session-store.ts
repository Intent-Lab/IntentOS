import {
  isRedisAvailable,
  redisGet,
  redisSet,
  redisDel,
  redisExpire,
  redisLPush,
  redisLRange,
  redisLLen,
  redis,
} from "./redis";

const SESSION_TTL = 7 * 24 * 60 * 60; // 7 days in seconds

// --- Sandbox mapping ---

interface SandboxMapping {
  sandboxId: string;
  agentSessionId: string | null;
  lastActiveAt: string;
}

export async function saveSandboxMapping(
  sessionKey: string,
  sandboxId: string,
  agentSessionId: string | null
): Promise<void> {
  if (!isRedisAvailable()) return;
  const data: SandboxMapping = {
    sandboxId,
    agentSessionId,
    lastActiveAt: new Date().toISOString(),
  };
  await redisSet(`sb:${sessionKey}`, JSON.stringify(data), SESSION_TTL);
}

export async function getSandboxMapping(
  sessionKey: string
): Promise<SandboxMapping | null> {
  if (!isRedisAvailable()) return null;
  const raw = await redisGet(`sb:${sessionKey}`);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as SandboxMapping;
  } catch {
    return null;
  }
}

export async function deleteSandboxMapping(
  sessionKey: string
): Promise<void> {
  if (!isRedisAvailable()) return;
  await redisDel(`sb:${sessionKey}`);
}

// --- Chat messages ---

interface StoredMessage {
  role: string;
  content: string;
  ts: string;
  costUsd?: number;
  durationMs?: number;
}

export async function appendMessage(
  sessionKey: string,
  message: {
    role: string;
    content: string;
    costUsd?: number;
    durationMs?: number;
  }
): Promise<void> {
  if (!isRedisAvailable()) return;
  const key = `msgs:${sessionKey}`;
  const entry: StoredMessage = {
    ...message,
    ts: new Date().toISOString(),
  };
  // RPUSH to maintain chronological order (oldest first)
  await redis(["RPUSH", key, JSON.stringify(entry)]);
  await redisExpire(key, SESSION_TTL);
}

export async function getMessages(
  sessionKey: string,
  limit?: number
): Promise<StoredMessage[]> {
  if (!isRedisAvailable()) return [];
  const key = `msgs:${sessionKey}`;
  const len = await redisLLen(key);
  if (len === 0) return [];

  const start = limit ? Math.max(0, len - limit) : 0;
  const raw = await redisLRange(key, start, len - 1);
  return raw.map((s) => {
    try {
      return JSON.parse(s) as StoredMessage;
    } catch {
      return { role: "system", content: s, ts: "" };
    }
  });
}

export async function getMessageCount(
  sessionKey: string
): Promise<number> {
  if (!isRedisAvailable()) return 0;
  return await redisLLen(`msgs:${sessionKey}`);
}

/**
 * Replace all messages with a compacted summary + recent messages.
 * Called when message count exceeds threshold.
 */
export async function compactMessages(
  sessionKey: string,
  summaryContent: string,
  recentMessages: StoredMessage[]
): Promise<void> {
  if (!isRedisAvailable()) return;
  const key = `msgs:${sessionKey}`;

  // Delete old list
  await redisDel(key);

  // Push summary as first message
  const summary: StoredMessage = {
    role: "system",
    content: `[Conversation summary]\n${summaryContent}`,
    ts: new Date().toISOString(),
  };
  await redis(["RPUSH", key, JSON.stringify(summary)]);

  // Push recent messages
  for (const msg of recentMessages) {
    await redis(["RPUSH", key, JSON.stringify(msg)]);
  }

  await redisExpire(key, SESSION_TTL);
}

/**
 * Format stored messages as context string for system prompt injection.
 * Used when a sandbox dies and needs to be recreated with prior context.
 */
export function formatMessagesAsContext(
  messages: StoredMessage[]
): string {
  return messages
    .map((m) => {
      if (m.role === "system") return m.content;
      const label = m.role === "user" ? "User" : "Assistant";
      return `${label}: ${m.content}`;
    })
    .join("\n\n");
}
