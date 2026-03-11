import { NextRequest, NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/**
 * GET /api/notion/callback?code=<code>&state=<state>
 *
 * Notion redirects here after the user grants access.
 * Exchanges the authorization code for an access token,
 * then redirects to the iOS app via custom URL scheme.
 */
export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get("code");
  const state = request.nextUrl.searchParams.get("state") || "";
  const error = request.nextUrl.searchParams.get("error");

  if (error) {
    return new NextResponse(errorPage("Authorization was denied."), {
      status: 200,
      headers: { "Content-Type": "text/html" },
    });
  }

  if (!code) {
    return new NextResponse(errorPage("Missing authorization code."), {
      status: 400,
      headers: { "Content-Type": "text/html" },
    });
  }

  const clientId = process.env.NOTION_CLIENT_ID;
  const clientSecret = process.env.NOTION_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    return new NextResponse(errorPage("Notion integration not configured."), {
      status: 503,
      headers: { "Content-Type": "text/html" },
    });
  }

  // Build redirect URI (must match the one used in /auth)
  const host = request.headers.get("host") || "localhost:3000";
  const protocol = host.startsWith("localhost") ? "http" : "https";
  const redirectUri = `${protocol}://${host}/api/notion/callback`;

  try {
    // Exchange code for access token
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString(
      "base64"
    );

    const tokenRes = await fetch("https://api.notion.com/v1/oauth/token", {
      method: "POST",
      headers: {
        Authorization: `Basic ${credentials}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        grant_type: "authorization_code",
        code,
        redirect_uri: redirectUri,
      }),
    });

    if (!tokenRes.ok) {
      const body = await tokenRes.text();
      console.error("[Notion OAuth] Token exchange failed:", body);
      return new NextResponse(errorPage("Failed to connect to Notion."), {
        status: 200,
        headers: { "Content-Type": "text/html" },
      });
    }

    const data = await tokenRes.json();
    const accessToken = data.access_token;
    const workspaceName = data.workspace_name || "Notion";

    // Redirect back to iOS app via custom URL scheme
    const callbackUrl = new URL("matcha://notion-callback");
    callbackUrl.searchParams.set("token", accessToken);
    callbackUrl.searchParams.set("workspace", workspaceName);
    if (state) {
      callbackUrl.searchParams.set("state", state);
    }

    // Return an HTML page that redirects to the app scheme.
    // ASWebAuthenticationSession will intercept this redirect.
    const html = `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Connecting...</title></head>
<body>
<p>Connecting to Notion... If you are not redirected, <a href="${callbackUrl.toString()}">tap here</a>.</p>
<script>window.location.replace("${callbackUrl.toString()}");</script>
</body></html>`;

    return new NextResponse(html, {
      status: 200,
      headers: { "Content-Type": "text/html" },
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[Notion OAuth] Error:", message);
    return new NextResponse(errorPage("Something went wrong."), {
      status: 200,
      headers: { "Content-Type": "text/html" },
    });
  }
}

function errorPage(message: string): string {
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Error</title></head>
<body><p>${message}</p></body></html>`;
}
