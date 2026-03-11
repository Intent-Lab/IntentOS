import { createServer } from "node:http";
import Anthropic from "@anthropic-ai/sdk";
import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from "node:fs";
import { execSync } from "node:child_process";
import { dirname, basename } from "node:path";

// --- Config ---
const PORT = 3000;
const AUTH_TOKEN = process.env.AUTH_TOKEN || "";
const WORKSPACE = "/home/user/workspace";
const MAX_TOOL_ITERATIONS = 20;
const MAX_TOKENS = 8192;
const MODEL = "claude-sonnet-4-6";

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// --- Conversation state (in-memory, one per sandbox) ---
let conversationMessages = [];
let systemBlocks = null; // cached system prompt blocks with cache_control

// --- Serialization queue ---
let processing = false;
const queue = [];

function enqueue(handler) {
  return new Promise((resolve, reject) => {
    queue.push({ handler, resolve, reject });
    processQueue();
  });
}

async function processQueue() {
  if (processing || queue.length === 0) return;
  processing = true;
  const { handler, resolve, reject } = queue.shift();
  try {
    resolve(await handler());
  } catch (e) {
    reject(e);
  } finally {
    processing = false;
    processQueue();
  }
}

// --- Tool definitions (Anthropic API format) ---
const TOOLS = [
  {
    name: "shell_exec",
    description: "Execute a shell command in the workspace. Returns stdout/stderr.",
    input_schema: {
      type: "object",
      properties: {
        command: { type: "string", description: "The shell command to execute" },
      },
      required: ["command"],
    },
  },
  {
    name: "file_read",
    description: "Read the contents of a file.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the file" },
      },
      required: ["path"],
    },
  },
  {
    name: "file_write",
    description: "Write content to a file. Creates parent directories if needed.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the file" },
        content: { type: "string", description: "Content to write" },
      },
      required: ["path", "content"],
    },
  },
  {
    name: "file_str_replace",
    description: "Replace a specific string in a file. Use for targeted edits.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the file" },
        old_str: { type: "string", description: "The exact string to find" },
        new_str: { type: "string", description: "The replacement string" },
      },
      required: ["path", "old_str", "new_str"],
    },
  },
  {
    name: "file_list",
    description: "List files and directories at a given path.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute path to the directory" },
      },
      required: ["path"],
    },
  },
  {
    name: "file_find_in_content",
    description: "Search for a regex pattern in file contents. Returns matching lines with paths and line numbers.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Directory or file to search in" },
        pattern: { type: "string", description: "Regex pattern to search for" },
      },
      required: ["path", "pattern"],
    },
  },
  {
    name: "file_find_by_name",
    description: "Find files matching a glob pattern in a directory tree.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Directory to search in" },
        glob: { type: "string", description: "Glob pattern (e.g. '*.js', 'test_*')" },
      },
      required: ["path", "glob"],
    },
  },
  { type: "web_search_20250305", name: "web_search" },
  {
    name: "google_calendar_events",
    description:
      "List upcoming events from the user's Google Calendar. Returns event title, time, location, and attendees. Only available if the user has connected their Google account.",
    input_schema: {
      type: "object",
      properties: {
        days_ahead: {
          type: "number",
          description: "Number of days ahead to look (default 1, max 14)",
        },
        max_results: {
          type: "number",
          description: "Maximum number of events to return (default 10, max 50)",
        },
      },
      required: [],
    },
  },
  {
    name: "google_gmail_search",
    description:
      "Search Gmail messages. Returns message ID, subject, from, date, and snippet. Only available if the user has connected their Google account.",
    input_schema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Gmail search query (same syntax as Gmail search box, e.g. 'from:alice subject:meeting is:unread')",
        },
        max_results: {
          type: "number",
          description: "Maximum number of messages to return (default 10, max 20)",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "google_gmail_read",
    description:
      "Read the full content of a specific Gmail message by ID (from google_gmail_search results). Returns subject, from, to, date, and body text.",
    input_schema: {
      type: "object",
      properties: {
        message_id: {
          type: "string",
          description: "The Gmail message ID to read",
        },
      },
      required: ["message_id"],
    },
  },
  {
    name: "google_drive_search",
    description:
      "Search for files in the user's Google Drive. Returns file ID, name, mimeType, and modifiedTime. Only available if the user has connected their Google account.",
    input_schema: {
      type: "object",
      properties: {
        query: {
          type: "string",
          description: "Search query (e.g. 'budget report', 'type:spreadsheet meeting notes'). Supports Google Drive search syntax.",
        },
        max_results: {
          type: "number",
          description: "Maximum number of files to return (default 10, max 50)",
        },
      },
      required: ["query"],
    },
  },
  {
    name: "google_drive_read",
    description:
      "Read the content of a Google Drive file by ID (from google_drive_search results). For Google Docs/Sheets/Slides, exports as plain text. For other files, downloads the raw content (up to 5MB).",
    input_schema: {
      type: "object",
      properties: {
        file_id: {
          type: "string",
          description: "The Google Drive file ID to read",
        },
        file_name: {
          type: "string",
          description: "File name (for display purposes only)",
        },
      },
      required: ["file_id"],
    },
  },
  {
    name: "google_drive_create",
    description:
      "Create a new file in Google Drive. Can create Google Docs, Sheets, or plain text files. Returns the new file's ID and web link.",
    input_schema: {
      type: "object",
      properties: {
        name: {
          type: "string",
          description: "File name (e.g. 'Meeting Notes.txt', 'Budget 2026')",
        },
        content: {
          type: "string",
          description: "Text content to write to the file",
        },
        mime_type: {
          type: "string",
          description: "MIME type: 'application/vnd.google-apps.document' for Google Doc, 'application/vnd.google-apps.spreadsheet' for Sheet, 'text/plain' for text file. Default: Google Doc.",
        },
        folder_id: {
          type: "string",
          description: "Optional parent folder ID. If omitted, creates in root.",
        },
      },
      required: ["name", "content"],
    },
  },
  {
    name: "google_drive_update",
    description:
      "Update the content of an existing Google Drive file by ID. For Google Docs, replaces the entire document content. For other files, overwrites the file content.",
    input_schema: {
      type: "object",
      properties: {
        file_id: {
          type: "string",
          description: "The Google Drive file ID to update",
        },
        content: {
          type: "string",
          description: "New text content for the file",
        },
        file_name: {
          type: "string",
          description: "File name (for display purposes only)",
        },
      },
      required: ["file_id", "content"],
    },
  },
];

// --- Per-request Google OAuth token (set before each agent run) ---
let currentGoogleAccessToken = null;

// --- Tool execution ---
async function executeTool(name, input) {
  switch (name) {
    case "shell_exec": {
      try {
        const output = execSync(input.command, {
          cwd: WORKSPACE,
          timeout: 60_000,
          encoding: "utf-8",
          maxBuffer: 1024 * 1024,
        });
        return output || "(no output)";
      } catch (err) {
        return `Exit code ${err.status || 1}: ${err.stderr || err.message}`;
      }
    }
    case "file_read": {
      try {
        return readFileSync(input.path, "utf-8");
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "file_write": {
      try {
        mkdirSync(dirname(input.path), { recursive: true });
        writeFileSync(input.path, input.content, "utf-8");
        return `File written: ${input.path} (${input.content.length} bytes)`;
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "file_str_replace": {
      try {
        const content = readFileSync(input.path, "utf-8");
        if (!content.includes(input.old_str)) {
          return `Error: old_str not found in ${input.path}`;
        }
        const newContent = content.replace(input.old_str, input.new_str);
        writeFileSync(input.path, newContent, "utf-8");
        return `Replaced in ${input.path}`;
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "file_list": {
      try {
        const entries = readdirSync(input.path, { withFileTypes: true });
        return entries
          .map((e) => `${e.isDirectory() ? "[dir]" : "[file]"} ${e.name}`)
          .join("\n") || "(empty directory)";
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "file_find_in_content": {
      try {
        const output = execSync(
          `grep -rn --include='*' -E ${JSON.stringify(input.pattern)} ${JSON.stringify(input.path)}`,
          { cwd: WORKSPACE, timeout: 30_000, encoding: "utf-8", maxBuffer: 1024 * 1024 }
        );
        return output || "(no matches)";
      } catch (err) {
        if (err.status === 1) return "(no matches)";
        return `Error: ${err.stderr || err.message}`;
      }
    }
    case "file_find_by_name": {
      try {
        const output = execSync(
          `find ${JSON.stringify(input.path)} -name ${JSON.stringify(input.glob)} -type f 2>/dev/null | head -200`,
          { cwd: WORKSPACE, timeout: 30_000, encoding: "utf-8", maxBuffer: 1024 * 1024 }
        );
        return output || "(no matches)";
      } catch (err) {
        return `Error: ${err.stderr || err.message}`;
      }
    }
    case "google_calendar_events": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        const daysAhead = Math.min(input.days_ahead || 1, 14);
        const maxResults = Math.min(input.max_results || 10, 50);
        const timeMin = new Date().toISOString();
        const timeMax = new Date(Date.now() + daysAhead * 86400000).toISOString();
        const url = `https://www.googleapis.com/calendar/v3/calendars/primary/events?timeMin=${timeMin}&timeMax=${timeMax}&maxResults=${maxResults}&singleEvents=true&orderBy=startTime`;
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${currentGoogleAccessToken}` },
        });
        if (!res.ok) {
          const err = await res.text();
          return `Google Calendar API error (${res.status}): ${err.slice(0, 500)}`;
        }
        const data = await res.json();
        const events = (data.items || []).map((e) => ({
          title: e.summary || "(no title)",
          start: e.start?.dateTime || e.start?.date || "unknown",
          end: e.end?.dateTime || e.end?.date || "",
          location: e.location || "",
          attendees: (e.attendees || []).map((a) => a.email).join(", "),
        }));
        return events.length > 0
          ? JSON.stringify(events, null, 2)
          : "No events found in the specified time range.";
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_gmail_search": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        const maxResults = Math.min(input.max_results || 10, 20);
        const listUrl = `https://www.googleapis.com/gmail/v1/users/me/messages?q=${encodeURIComponent(input.query)}&maxResults=${maxResults}`;
        const listRes = await fetch(listUrl, {
          headers: { Authorization: `Bearer ${currentGoogleAccessToken}` },
        });
        if (!listRes.ok) {
          const err = await listRes.text();
          return `Gmail API error (${listRes.status}): ${err.slice(0, 500)}`;
        }
        const listData = await listRes.json();
        const messageIds = (listData.messages || []).map((m) => m.id);
        if (messageIds.length === 0) return "No messages found matching the query.";
        const messages = [];
        for (const id of messageIds) {
          const msgRes = await fetch(
            `https://www.googleapis.com/gmail/v1/users/me/messages/${id}?format=metadata&metadataHeaders=Subject&metadataHeaders=From&metadataHeaders=Date`,
            { headers: { Authorization: `Bearer ${currentGoogleAccessToken}` } }
          );
          if (msgRes.ok) {
            const msg = await msgRes.json();
            const headers = Object.fromEntries(
              (msg.payload?.headers || []).map((h) => [h.name, h.value])
            );
            messages.push({
              id: msg.id,
              subject: headers.Subject || "(no subject)",
              from: headers.From || "",
              date: headers.Date || "",
              snippet: msg.snippet || "",
            });
          }
        }
        return JSON.stringify(messages, null, 2);
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_gmail_read": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        const msgRes = await fetch(
          `https://www.googleapis.com/gmail/v1/users/me/messages/${input.message_id}?format=full`,
          { headers: { Authorization: `Bearer ${currentGoogleAccessToken}` } }
        );
        if (!msgRes.ok) {
          const err = await msgRes.text();
          return `Gmail API error (${msgRes.status}): ${err.slice(0, 500)}`;
        }
        const msg = await msgRes.json();
        const headers = Object.fromEntries(
          (msg.payload?.headers || []).map((h) => [h.name, h.value])
        );
        let body = "";
        function extractText(part) {
          if (part.mimeType === "text/plain" && part.body?.data) {
            body += Buffer.from(part.body.data, "base64url").toString("utf-8");
          } else if (part.parts) {
            part.parts.forEach(extractText);
          }
        }
        extractText(msg.payload);
        if (!body && msg.snippet) body = msg.snippet;
        if (body.length > 5000) body = body.slice(0, 5000) + "\n... [truncated]";
        return JSON.stringify({
          id: msg.id,
          subject: headers.Subject || "(no subject)",
          from: headers.From || "",
          to: headers.To || "",
          date: headers.Date || "",
          body,
        }, null, 2);
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_drive_search": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        const maxResults = Math.min(input.max_results || 10, 50);
        // Convert simple query to Drive API query format
        const q = `fullText contains '${input.query.replace(/'/g, "\\'")}'` +
          " and trashed = false";
        const url = `https://www.googleapis.com/drive/v3/files?q=${encodeURIComponent(q)}&pageSize=${maxResults}&fields=files(id,name,mimeType,modifiedTime,size,webViewLink)&orderBy=modifiedTime desc`;
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${currentGoogleAccessToken}` },
        });
        if (!res.ok) {
          const err = await res.text();
          return `Google Drive API error (${res.status}): ${err.slice(0, 500)}`;
        }
        const data = await res.json();
        const files = (data.files || []).map((f) => ({
          id: f.id,
          name: f.name,
          mimeType: f.mimeType,
          modifiedTime: f.modifiedTime,
          size: f.size || null,
          link: f.webViewLink || "",
        }));
        return files.length > 0
          ? JSON.stringify(files, null, 2)
          : "No files found matching the query.";
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_drive_read": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        // First get file metadata to determine type
        const metaRes = await fetch(
          `https://www.googleapis.com/drive/v3/files/${input.file_id}?fields=id,name,mimeType,size`,
          { headers: { Authorization: `Bearer ${currentGoogleAccessToken}` } }
        );
        if (!metaRes.ok) {
          const err = await metaRes.text();
          return `Google Drive API error (${metaRes.status}): ${err.slice(0, 500)}`;
        }
        const meta = await metaRes.json();

        let content;
        // Google Workspace files need export
        const googleTypes = {
          "application/vnd.google-apps.document": "text/plain",
          "application/vnd.google-apps.spreadsheet": "text/csv",
          "application/vnd.google-apps.presentation": "text/plain",
        };
        if (googleTypes[meta.mimeType]) {
          const exportUrl = `https://www.googleapis.com/drive/v3/files/${input.file_id}/export?mimeType=${encodeURIComponent(googleTypes[meta.mimeType])}`;
          const expRes = await fetch(exportUrl, {
            headers: { Authorization: `Bearer ${currentGoogleAccessToken}` },
          });
          if (!expRes.ok) {
            const err = await expRes.text();
            return `Export error (${expRes.status}): ${err.slice(0, 500)}`;
          }
          content = await expRes.text();
        } else {
          // Binary/text files -- download directly
          const dlRes = await fetch(
            `https://www.googleapis.com/drive/v3/files/${input.file_id}?alt=media`,
            { headers: { Authorization: `Bearer ${currentGoogleAccessToken}` } }
          );
          if (!dlRes.ok) {
            const err = await dlRes.text();
            return `Download error (${dlRes.status}): ${err.slice(0, 500)}`;
          }
          content = await dlRes.text();
        }

        if (content.length > 50000) content = content.slice(0, 50000) + "\n... [truncated]";
        return JSON.stringify({
          id: meta.id,
          name: meta.name,
          mimeType: meta.mimeType,
          content,
        }, null, 2);
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_drive_create": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        const mimeType = input.mime_type || "application/vnd.google-apps.document";
        const isGoogleDoc = mimeType === "application/vnd.google-apps.document";

        // For Google Docs, upload as text/plain and convert
        const metadata = { name: input.name, mimeType };
        if (input.folder_id) {
          metadata.parents = [input.folder_id];
        }

        const boundary = "----DriveUpload" + Date.now();
        const uploadMimeType = isGoogleDoc ? "text/plain" : (mimeType.startsWith("application/vnd.google-apps.") ? "text/plain" : mimeType);

        const body =
          `--${boundary}\r\n` +
          `Content-Type: application/json; charset=UTF-8\r\n\r\n` +
          JSON.stringify(metadata) + `\r\n` +
          `--${boundary}\r\n` +
          `Content-Type: ${uploadMimeType}\r\n\r\n` +
          input.content + `\r\n` +
          `--${boundary}--`;

        const res = await fetch(
          "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name,webViewLink",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${currentGoogleAccessToken}`,
              "Content-Type": `multipart/related; boundary=${boundary}`,
            },
            body,
          }
        );
        if (!res.ok) {
          const err = await res.text();
          return `Google Drive API error (${res.status}): ${err.slice(0, 500)}`;
        }
        const file = await res.json();
        return JSON.stringify({
          id: file.id,
          name: file.name,
          link: file.webViewLink || "",
          message: `File "${file.name}" created successfully.`,
        }, null, 2);
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    case "google_drive_update": {
      if (!currentGoogleAccessToken) return "Error: Google account not connected. Ask the user to sign in to Google in the app Settings.";
      try {
        // Get current file metadata to determine type
        const metaRes = await fetch(
          `https://www.googleapis.com/drive/v3/files/${input.file_id}?fields=id,name,mimeType`,
          { headers: { Authorization: `Bearer ${currentGoogleAccessToken}` } }
        );
        if (!metaRes.ok) {
          const err = await metaRes.text();
          return `Google Drive API error (${metaRes.status}): ${err.slice(0, 500)}`;
        }
        const meta = await metaRes.json();

        const uploadMimeType = meta.mimeType.startsWith("application/vnd.google-apps.") ? "text/plain" : meta.mimeType;

        const res = await fetch(
          `https://www.googleapis.com/upload/drive/v3/files/${input.file_id}?uploadType=media&fields=id,name,modifiedTime,webViewLink`,
          {
            method: "PATCH",
            headers: {
              Authorization: `Bearer ${currentGoogleAccessToken}`,
              "Content-Type": uploadMimeType,
            },
            body: input.content,
          }
        );
        if (!res.ok) {
          const err = await res.text();
          return `Google Drive API error (${res.status}): ${err.slice(0, 500)}`;
        }
        const file = await res.json();
        return JSON.stringify({
          id: file.id,
          name: file.name,
          modifiedTime: file.modifiedTime,
          link: file.webViewLink || "",
          message: `File "${file.name}" updated successfully.`,
        }, null, 2);
      } catch (err) {
        return `Error: ${err.message}`;
      }
    }
    default:
      return `Unknown tool: ${name}`;
  }
}

// --- SSE helpers ---
function sendSSE(res, event, data) {
  if (res.writableEnded) return;
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

// --- System prompt setup ---
function getSystemBlocks(customSystemPrompt, hasGoogleToken) {
  let base = customSystemPrompt || "You are a helpful coding assistant. You have access to a workspace at /home/user/workspace. Use the tools available to help the user with their tasks.";
  if (hasGoogleToken) {
    base += "\n\nThe user has connected their Google account. You can use google_calendar_events, google_gmail_search, and google_gmail_read tools to access their calendar and email. You can also use google_drive_search, google_drive_read, google_drive_create, and google_drive_update to search, read, create, and update files in their Google Drive. Use these when the user asks about their schedule, meetings, emails, or files.";
  }
  // cache_control on system prompt so it's cached across turns
  return [{ type: "text", text: base, cache_control: { type: "ephemeral" } }];
}

// --- Core agent loop ---
async function runAgent(prompt, customSystemPrompt, stream, googleAccessToken) {
  const startTime = Date.now();
  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  let cacheReadTokens = 0;
  let cacheCreationTokens = 0;

  // Set per-request Google token for tool execution
  currentGoogleAccessToken = googleAccessToken || null;

  // Initialize system blocks on first call, if custom prompt provided, or if Google token status changed
  const hasGoogle = !!googleAccessToken;
  const needsRefresh = !systemBlocks || customSystemPrompt ||
    (hasGoogle && !systemBlocks[0]?.text?.includes("google_drive_search")) ||
    (!hasGoogle && systemBlocks[0]?.text?.includes("google_drive_search"));
  if (needsRefresh) {
    systemBlocks = getSystemBlocks(customSystemPrompt, hasGoogle);
  }

  // Add user message
  conversationMessages.push({ role: "user", content: prompt });

  // Add cache_control to the last user message before the new one (conversation prefix caching)
  if (conversationMessages.length >= 3) {
    const prevMsg = conversationMessages[conversationMessages.length - 2];
    if (typeof prevMsg.content === "string") {
      prevMsg.content = [
        { type: "text", text: prevMsg.content, cache_control: { type: "ephemeral" } },
      ];
    } else if (Array.isArray(prevMsg.content)) {
      // Mark last block with cache_control
      const lastBlock = prevMsg.content[prevMsg.content.length - 1];
      if (lastBlock && !lastBlock.cache_control) {
        lastBlock.cache_control = { type: "ephemeral" };
      }
    }
  }

  let fullTextContent = "";

  for (let iteration = 0; iteration < MAX_TOOL_ITERATIONS; iteration++) {
    const messageStream = anthropic.messages.stream({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      system: systemBlocks,
      messages: conversationMessages,
      tools: TOOLS,
    });

    // Stream text deltas if streaming response
    if (stream) {
      messageStream.on("text", (text) => {
        fullTextContent += text;
        sendSSE(stream, "token", { text });
      });
    }

    const finalMsg = await messageStream.finalMessage();

    // Track token usage
    totalInputTokens += finalMsg.usage?.input_tokens || 0;
    totalOutputTokens += finalMsg.usage?.output_tokens || 0;
    cacheReadTokens += finalMsg.usage?.cache_read_input_tokens || 0;
    cacheCreationTokens += finalMsg.usage?.cache_creation_input_tokens || 0;

    // Append assistant message to conversation
    conversationMessages.push({ role: "assistant", content: finalMsg.content });

    // If not streaming, collect text from the response
    if (!stream) {
      for (const block of finalMsg.content) {
        if (block.type === "text") {
          fullTextContent += block.text;
        }
      }
    }

    // Check stop reason
    if (finalMsg.stop_reason !== "tool_use") {
      // end_turn or max_tokens -- done
      break;
    }

    // Execute tools
    const toolUseBlocks = finalMsg.content.filter((b) => b.type === "tool_use");
    const toolResults = [];

    for (const block of toolUseBlocks) {
      if (stream) {
        sendSSE(stream, "tool_start", { tool: block.name, input: summarizeInput(block.input) });
      }

      try {
        const result = await executeTool(block.name, block.input);
        const truncated = typeof result === "string" && result.length > 10000
          ? result.slice(0, 10000) + "\n... [truncated]"
          : result;

        toolResults.push({
          type: "tool_result",
          tool_use_id: block.id,
          content: typeof truncated === "string" ? truncated : JSON.stringify(truncated),
        });

        if (stream) {
          sendSSE(stream, "tool_done", { tool: block.name, success: true });
        }
      } catch (err) {
        const errorMsg = err instanceof Error ? err.message : String(err);
        toolResults.push({
          type: "tool_result",
          tool_use_id: block.id,
          content: `Error: ${errorMsg}`,
          is_error: true,
        });

        if (stream) {
          sendSSE(stream, "tool_done", { tool: block.name, success: false, error: errorMsg });
        }
      }
    }

    // Append tool results as user message
    conversationMessages.push({ role: "user", content: toolResults });
  }

  const durationMs = Date.now() - startTime;
  const costUsd =
    (totalInputTokens * 3) / 1_000_000 +
    (totalOutputTokens * 15) / 1_000_000;

  console.log(
    `[Agent] Done. tokens: ${totalInputTokens}in/${totalOutputTokens}out, cache: ${cacheReadTokens}read/${cacheCreationTokens}write, cost: $${costUsd.toFixed(4)}, duration: ${durationMs}ms`
  );

  return {
    result: fullTextContent || "Agent completed with no response.",
    cost_usd: costUsd,
    duration_ms: durationMs,
    input_tokens: totalInputTokens,
    output_tokens: totalOutputTokens,
    cache_read_tokens: cacheReadTokens,
    cache_creation_tokens: cacheCreationTokens,
  };
}

/** Summarize tool input for SSE events (avoid sending huge payloads) */
function summarizeInput(input) {
  if (!input) return {};
  const summary = {};
  for (const [k, v] of Object.entries(input)) {
    if (typeof v === "string" && v.length > 200) {
      summary[k] = v.slice(0, 200) + "...";
    } else {
      summary[k] = v;
    }
  }
  return summary;
}

// --- HTTP server ---
const server = createServer(async (req, res) => {
  // Health check
  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      status: "ok",
      messageCount: conversationMessages.length,
    }));
    return;
  }

  // Parse body for POST endpoints
  if (req.method === "POST" && (req.url === "/message" || req.url === "/stream" || req.url === "/context")) {
    let body = "";
    for await (const chunk of req) body += chunk;

    let parsed;
    try {
      parsed = JSON.parse(body);
    } catch {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Invalid JSON" }));
      return;
    }

    // Auth check
    if (AUTH_TOKEN && parsed.token !== AUTH_TOKEN) {
      res.writeHead(401, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "Unauthorized" }));
      return;
    }

    // --- POST /context (inject voice session context into system prompt) ---
    if (req.url === "/context") {
      const { messages } = parsed;
      if (!Array.isArray(messages)) {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "messages array is required" }));
        return;
      }

      // Format voice transcripts as system-level context (not fake conversation)
      const contextLines = messages
        .filter((m) => m.role && m.content)
        .map((m) => `${m.role === "user" ? "User" : "Assistant"}: ${m.content}`)
        .join("\n");

      if (contextLines) {
        // Rebuild system blocks with voice context appended
        const basePrompt = systemBlocks?.[0]?.text || getSystemBlocks().text;
        const updatedPrompt = basePrompt +
          "\n\n[Voice conversation that just happened -- the user may refer to this. " +
          "You were the assistant in this conversation and performed any actions mentioned.]\n" +
          contextLines;
        systemBlocks = [{ type: "text", text: updatedPrompt, cache_control: { type: "ephemeral" } }];
      }

      console.log(`[Server] Injected ${messages.length} voice context messages into system prompt`);
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ ok: true, contextLines: messages.length }));
      return;
    }

    const { prompt, systemPrompt, googleAccessToken } = parsed;
    if (!prompt) {
      res.writeHead(400, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: "prompt is required" }));
      return;
    }

    // --- POST /message (non-streaming, backward compatible) ---
    if (req.url === "/message") {
      try {
        const result = await enqueue(() => runAgent(prompt, systemPrompt, null, googleAccessToken));
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(JSON.stringify(result));
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error("[Server] Agent error:", msg);
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: msg }));
      }
      return;
    }

    // --- POST /stream (SSE streaming) ---
    if (req.url === "/stream") {
      res.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "Access-Control-Allow-Origin": "*",
      });

      try {
        const result = await enqueue(() => runAgent(prompt, systemPrompt, res, googleAccessToken));
        sendSSE(res, "done", {
          result: result.result,
          cost_usd: result.cost_usd,
          duration_ms: result.duration_ms,
          cache_read_tokens: result.cache_read_tokens,
        });
      } catch (error) {
        const msg = error instanceof Error ? error.message : String(error);
        console.error("[Server] Agent error:", msg);
        sendSSE(res, "error", { error: msg });
      }
      res.end();
      return;
    }
  }

  // CORS preflight
  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    });
    res.end();
    return;
  }

  res.writeHead(404, { "Content-Type": "application/json" });
  res.end(JSON.stringify({ error: "Not found" }));
});

server.listen(PORT, () => {
  console.log(`Agent server listening on port ${PORT}`);
});
