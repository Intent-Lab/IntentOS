const KV_URL = process.env.KV_REST_API_URL;
const KV_TOKEN = process.env.KV_REST_API_TOKEN;

const MAX_LOGS = 200; // keep last 200 entries
const LOG_KEY = "agent:logs";

interface LogEntry {
  ts: string;
  type: "request" | "response" | "error" | "event";
  session?: string;
  data: Record<string, unknown>;
}

async function redis(command: string[]): Promise<unknown> {
  if (!KV_URL || !KV_TOKEN) return null;
  const res = await fetch(`${KV_URL}`, {
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

export async function log(
  type: LogEntry["type"],
  data: Record<string, unknown>,
  session?: string
): Promise<void> {
  try {
    const entry: LogEntry = {
      ts: new Date().toISOString(),
      type,
      session,
      data,
    };
    await redis(["LPUSH", LOG_KEY, JSON.stringify(entry)]);
    await redis(["LTRIM", LOG_KEY, "0", String(MAX_LOGS - 1)]);
  } catch {
    // logging should never break the request
  }
}

export async function getLogs(count = 50): Promise<LogEntry[]> {
  const result = await redis(["LRANGE", LOG_KEY, "0", String(count - 1)]);
  if (!Array.isArray(result)) return [];
  return result.map((s: string) => JSON.parse(s));
}
