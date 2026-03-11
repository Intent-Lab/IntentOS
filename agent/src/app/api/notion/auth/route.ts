import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/**
 * GET /api/notion/auth?state=<nonce>
 *
 * Redirects the user to Notion's OAuth authorization page.
 * Called by iOS via ASWebAuthenticationSession.
 */
export async function GET(request: NextRequest) {
  const clientId = process.env.NOTION_CLIENT_ID;
  if (!clientId) {
    return NextResponse.json(
      { error: "Notion integration not configured" },
      { status: 503 }
    );
  }

  const state = request.nextUrl.searchParams.get("state") || "";

  // Build the redirect URI pointing to our callback endpoint
  const host = request.headers.get("host") || "localhost:3000";
  const protocol = host.startsWith("localhost") ? "http" : "https";
  const redirectUri = `${protocol}://${host}/api/notion/callback`;

  const authUrl = new URL("https://api.notion.com/v1/oauth/authorize");
  authUrl.searchParams.set("client_id", clientId);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("owner", "user");
  authUrl.searchParams.set("redirect_uri", redirectUri);
  if (state) {
    authUrl.searchParams.set("state", state);
  }

  return NextResponse.redirect(authUrl.toString());
}
