import { NextRequest, NextResponse } from "next/server";
import { getLogs, log } from "@/lib/logger";

export const dynamic = "force-dynamic";

// GET /api/agent/logs?count=50 — fetch recent logs
export async function GET(request: NextRequest) {
  const apiToken = request.headers.get("x-api-token");
  if (process.env.AGENT_TOKEN && apiToken !== process.env.AGENT_TOKEN) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const count = parseInt(request.nextUrl.searchParams.get("count") || "50");
  const logs = await getLogs(Math.min(count, 200));
  return NextResponse.json({ logs, count: logs.length });
}

// POST /api/agent/logs — iOS app can send client-side events
export async function POST(request: NextRequest) {
  const apiToken = request.headers.get("x-api-token");
  if (process.env.AGENT_TOKEN && apiToken !== process.env.AGENT_TOKEN) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  await log(
    body.type || "event",
    body.data || body,
    body.session || "ios-client"
  );
  return NextResponse.json({ ok: true });
}
