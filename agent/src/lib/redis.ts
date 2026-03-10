const KV_URL = process.env.KV_REST_API_URL;
const KV_TOKEN = process.env.KV_REST_API_TOKEN;

/**
 * Execute a raw Redis command via Upstash REST API.
 * Returns null if Redis is not configured.
 */
export async function redis(command: string[]): Promise<unknown> {
  if (!KV_URL || !KV_TOKEN) return null;
  const res = await fetch(KV_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${KV_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(command),
  });
  const json = await res.json();
  return json.result;
}

/** Check if Redis is configured */
export function isRedisAvailable(): boolean {
  return Boolean(KV_URL && KV_TOKEN);
}

// --- Typed helpers ---

export async function redisGet(key: string): Promise<string | null> {
  const result = await redis(["GET", key]);
  return (result as string) ?? null;
}

export async function redisSet(
  key: string,
  value: string,
  ttlSeconds?: number
): Promise<void> {
  if (ttlSeconds) {
    await redis(["SET", key, value, "EX", String(ttlSeconds)]);
  } else {
    await redis(["SET", key, value]);
  }
}

export async function redisDel(key: string): Promise<void> {
  await redis(["DEL", key]);
}

export async function redisExpire(
  key: string,
  seconds: number
): Promise<void> {
  await redis(["EXPIRE", key, String(seconds)]);
}

export async function redisLPush(key: string, value: string): Promise<void> {
  await redis(["LPUSH", key, value]);
}

export async function redisLRange(
  key: string,
  start: number,
  stop: number
): Promise<string[]> {
  const result = await redis(["LRANGE", key, String(start), String(stop)]);
  return Array.isArray(result) ? result : [];
}

export async function redisLLen(key: string): Promise<number> {
  const result = await redis(["LLEN", key]);
  return typeof result === "number" ? result : 0;
}

export async function redisLTrim(
  key: string,
  start: number,
  stop: number
): Promise<void> {
  await redis(["LTRIM", key, String(start), String(stop)]);
}
