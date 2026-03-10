import { query } from "@anthropic-ai/claude-agent-sdk";

const prompt = process.env.AGENT_PROMPT;
if (!prompt) {
  console.error(JSON.stringify({ error: "AGENT_PROMPT env var is required" }));
  process.exit(1);
}

const systemPrompt = process.env.AGENT_SYSTEM_PROMPT || undefined;
const sessionId = process.env.AGENT_SESSION_ID || undefined;

let resultSessionId = null;
let resultContent = null;
let resultCost = null;
let resultDuration = null;

try {
  for await (const message of query({
    prompt,
    options: {
      model: "claude-sonnet-4-6-20250527",
      allowedTools: [
        "Read",
        "Write",
        "Edit",
        "Bash",
        "Glob",
        "Grep",
        "WebSearch",
        "WebFetch",
      ],
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      systemPrompt: systemPrompt,
      resume: sessionId,
      cwd: "/home/user/workspace",
    },
  })) {
    if (message.type === "system" && message.subtype === "init") {
      resultSessionId = message.session_id;
    }
    if (message.type === "result") {
      resultContent = message.result;
      resultCost = message.total_cost_usd;
      resultDuration = message.duration_ms;
    }
  }

  console.log(
    JSON.stringify({
      result: resultContent || "Agent completed with no response.",
      session_id: resultSessionId,
      cost_usd: resultCost,
      duration_ms: resultDuration,
    })
  );
} catch (error) {
  console.error(
    JSON.stringify({
      error: error instanceof Error ? error.message : String(error),
    })
  );
  process.exit(1);
}
