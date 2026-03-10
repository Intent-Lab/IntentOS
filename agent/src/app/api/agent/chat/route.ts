import { NextRequest, NextResponse } from "next/server";
import {
  getOrCreateSandbox,
  runAgent,
  updateAgentSession,
} from "@/lib/sandbox";
import { log } from "@/lib/logger";

export const dynamic = "force-dynamic";
export const maxDuration = 120;

interface ChatMessage {
  role: string;
  content: string;
}

export async function POST(request: NextRequest) {
  let sessionKey = "unknown";
  try {
    // Auth: simple shared token
    const apiToken = request.headers.get("x-api-token");
    if (process.env.AGENT_TOKEN && apiToken !== process.env.AGENT_TOKEN) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401 }
      );
    }

    const body = await request.json();

    if (!body.messages || !Array.isArray(body.messages)) {
      return NextResponse.json(
        { error: "Invalid request: messages array required" },
        { status: 400 }
      );
    }

    // Verify E2B is configured
    if (!process.env.E2B_API_KEY || !process.env.E2B_TEMPLATE_ID) {
      console.error("[Agent] E2B not configured");
      return NextResponse.json(
        { error: "Agent backend not configured" },
        { status: 503 }
      );
    }

    sessionKey =
      request.headers.get("x-agent-session-key") ||
      `anonymous:${Date.now()}`;

    console.log(`[Agent] E2B mode, session: ${sessionKey}`);

    // Extract the last user message as the prompt
    const lastUserMessage = [...body.messages]
      .reverse()
      .find((m: ChatMessage) => m.role === "user");

    if (!lastUserMessage?.content) {
      return NextResponse.json(
        { error: "No user message found" },
        { status: 400 }
      );
    }

    const prompt = lastUserMessage.content;

    await log("request", { prompt: prompt.slice(0, 500), messageCount: body.messages.length }, sessionKey);

    // Build system prompt from earlier system messages (if any)
    const systemMessages = body.messages
      .filter((m: ChatMessage) => m.role === "system")
      .map((m: ChatMessage) => m.content);
    const systemPrompt =
      systemMessages.length > 0 ? systemMessages.join("\n\n") : undefined;

    // Get or create sandbox, run agent
    const { sandbox, agentSessionId } = await getOrCreateSandbox(sessionKey);
    const result = await runAgent(
      sandbox,
      prompt,
      systemPrompt,
      agentSessionId
    );

    // Store agent session ID for multi-turn resume
    if (result.sessionId) {
      updateAgentSession(sessionKey, result.sessionId);
    }

    await log("response", {
      prompt: prompt.slice(0, 200),
      response: result.result.slice(0, 500),
      costUsd: result.costUsd,
      durationMs: result.durationMs,
      sessionId: result.sessionId,
    }, sessionKey);

    // Return OpenAI-compatible response format
    return NextResponse.json({
      id: `chatcmpl-${Date.now()}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: body.model || "claude-agent",
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: result.result,
          },
          finish_reason: "stop",
        },
      ],
      usage: {
        cost_usd: result.costUsd,
        duration_ms: result.durationMs,
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error("[Agent] Error:", message);
    await log("error", { error: message }, sessionKey);
    return NextResponse.json(
      { error: `Agent error: ${message}` },
      { status: 502 }
    );
  }
}
