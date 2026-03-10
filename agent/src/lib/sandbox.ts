import { Sandbox } from "e2b";
import {
  getSandboxMapping,
  saveSandboxMapping,
  deleteSandboxMapping,
  getMessages,
  formatMessagesAsContext,
} from "./session-store";

const SANDBOX_TIMEOUT_MS = 30 * 60 * 1000; // 30 minutes
const AGENT_TIMEOUT_MS = 90_000; // 90 seconds per agent run

interface SandboxHandle {
  sandbox: Sandbox;
  agentSessionId: string | null;
  lastActive: number;
  isNewSandbox: boolean; // true if freshly created (not resumed)
}

interface AgentResult {
  result: string;
  sessionId: string | null;
  costUsd: number | null;
  durationMs: number | null;
}

// In-memory hot cache (avoids Redis round-trip for consecutive requests).
// Redis is source of truth; this resets on cold start which is fine.
const sandboxCache = new Map<string, SandboxHandle>();

/**
 * Get or create an E2B sandbox for a given session key.
 * Tries: in-memory cache -> Redis mapping -> create new.
 * Returns isNewSandbox=true when a fresh sandbox was created for a session
 * that had prior messages (i.e. session recovery needed).
 */
export async function getOrCreateSandbox(
  sessionKey: string
): Promise<SandboxHandle> {
  // 1. Check in-memory cache
  const cached = sandboxCache.get(sessionKey);
  if (cached) {
    try {
      const sandbox = await Sandbox.connect(cached.sandbox.sandboxId);
      cached.sandbox = sandbox;
      cached.lastActive = Date.now();
      cached.isNewSandbox = false;
      return cached;
    } catch {
      sandboxCache.delete(sessionKey);
    }
  }

  // 2. Check Redis for persisted sandbox mapping
  const mapping = await getSandboxMapping(sessionKey);
  if (mapping) {
    try {
      console.log(
        `[Sandbox] Resuming sandbox ${mapping.sandboxId} for session ${sessionKey}`
      );
      const sandbox = await Sandbox.connect(mapping.sandboxId);
      const handle: SandboxHandle = {
        sandbox,
        agentSessionId: mapping.agentSessionId,
        lastActive: Date.now(),
        isNewSandbox: false,
      };
      sandboxCache.set(sessionKey, handle);

      // Update last active in Redis
      await saveSandboxMapping(
        sessionKey,
        sandbox.sandboxId,
        mapping.agentSessionId
      );

      return handle;
    } catch {
      console.log(
        `[Sandbox] Failed to resume ${mapping.sandboxId}, creating new`
      );
      await deleteSandboxMapping(sessionKey);
    }
  }

  // 3. Create new sandbox
  return createSandbox(sessionKey);
}

/**
 * Run the Claude Agent SDK inside the sandbox.
 * If this is a recovered session (new sandbox for existing conversation),
 * injects prior message history as system context.
 */
export async function runAgent(
  handle: SandboxHandle,
  prompt: string,
  systemPrompt?: string,
  agentSessionId?: string | null,
  sessionKey?: string
): Promise<AgentResult> {
  const envs: Record<string, string> = {
    AGENT_PROMPT: prompt,
  };

  // Build system prompt, potentially with recovery context
  let finalSystemPrompt = systemPrompt || "";

  if (handle.isNewSandbox && sessionKey) {
    // Session recovery: load prior messages from Redis and inject as context
    const priorMessages = await getMessages(sessionKey);
    if (priorMessages.length > 0) {
      const context = formatMessagesAsContext(priorMessages);
      const recoveryPrefix = `[Previous conversation history -- the user may refer to this]\n${context}`;
      finalSystemPrompt = finalSystemPrompt
        ? `${recoveryPrefix}\n\n${finalSystemPrompt}`
        : recoveryPrefix;
      console.log(
        `[Agent] Injected ${priorMessages.length} prior messages as recovery context`
      );
    }
  }

  if (finalSystemPrompt) {
    envs.AGENT_SYSTEM_PROMPT = finalSystemPrompt;
  }
  if (agentSessionId) {
    envs.AGENT_SESSION_ID = agentSessionId;
  }

  console.log(
    `[Agent] Running agent in sandbox ${handle.sandbox.sandboxId}, prompt: ${prompt.slice(0, 100)}...`
  );

  const result = await handle.sandbox.commands.run(
    "node /home/user/agent/run.mjs",
    { envs, timeoutMs: AGENT_TIMEOUT_MS }
  );

  if (result.exitCode !== 0) {
    const errorOutput = result.stderr || result.stdout;
    console.error(
      `[Agent] Script failed (exit ${result.exitCode}): ${errorOutput.slice(0, 500)}`
    );

    try {
      const parsed = JSON.parse(
        errorOutput.trim().split("\n").pop() || "{}"
      );
      throw new Error(
        parsed.error ||
          `Agent script failed with exit code ${result.exitCode}`
      );
    } catch (parseErr) {
      if (parseErr instanceof SyntaxError) {
        throw new Error(
          `Agent script failed (exit ${result.exitCode}): ${errorOutput.slice(0, 200)}`
        );
      }
      throw parseErr;
    }
  }

  // Parse the last line of stdout as JSON
  const lines = result.stdout.trim().split("\n");
  const lastLine = lines[lines.length - 1];

  try {
    const output = JSON.parse(lastLine);
    console.log(
      `[Agent] Completed. session=${output.session_id}, cost=$${output.cost_usd}, duration=${output.duration_ms}ms`
    );
    return {
      result: output.result || "Agent completed with no response.",
      sessionId: output.session_id || null,
      costUsd: output.cost_usd || null,
      durationMs: output.duration_ms || null,
    };
  } catch {
    console.error(
      `[Agent] Failed to parse output: ${lastLine.slice(0, 300)}`
    );
    return {
      result:
        result.stdout.trim() ||
        "Agent completed but output was not parsable.",
      sessionId: null,
      costUsd: null,
      durationMs: null,
    };
  }
}

/**
 * Update the agent session ID for multi-turn resume.
 * Persists to both in-memory cache and Redis.
 */
export async function updateAgentSession(
  sessionKey: string,
  agentSessionId: string
): Promise<void> {
  const handle = sandboxCache.get(sessionKey);
  if (handle) {
    handle.agentSessionId = agentSessionId;
    handle.lastActive = Date.now();

    // Persist to Redis
    await saveSandboxMapping(
      sessionKey,
      handle.sandbox.sandboxId,
      agentSessionId
    );
  }
}

async function createSandbox(sessionKey: string): Promise<SandboxHandle> {
  const templateId = process.env.E2B_TEMPLATE_ID;
  if (!templateId) {
    throw new Error("E2B_TEMPLATE_ID not configured");
  }

  console.log(`[Sandbox] Creating sandbox from template: ${templateId}`);

  const sandbox = await Sandbox.create(templateId, {
    timeoutMs: SANDBOX_TIMEOUT_MS,
    envs: {
      ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY || "",
    },
  });

  console.log(`[Sandbox] Created: ${sandbox.sandboxId}`);

  // Persist mapping to Redis
  await saveSandboxMapping(sessionKey, sandbox.sandboxId, null);

  const handle: SandboxHandle = {
    sandbox,
    agentSessionId: null,
    lastActive: Date.now(),
    isNewSandbox: true,
  };
  sandboxCache.set(sessionKey, handle);

  return handle;
}
