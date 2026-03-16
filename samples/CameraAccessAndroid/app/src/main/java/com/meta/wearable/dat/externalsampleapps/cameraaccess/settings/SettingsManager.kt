package com.meta.wearable.dat.externalsampleapps.cameraaccess.settings

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.meta.wearable.dat.externalsampleapps.cameraaccess.Secrets

enum class AgentBackend(val label: String) {
    E2B("E2B"),
    OPENCLAW("OpenClaw");

    companion object {
        fun fromLabel(label: String): AgentBackend =
            entries.find { it.label == label } ?: E2B
    }
}

object SettingsManager {
    private const val TAG = "SettingsManager"
    private const val PREFS_NAME = "visionclaw_settings"

    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        migrateSystemPromptIfNeeded()
    }

    /** One-time migration: replace old negative-framing system prompt with new positive default */
    private fun migrateSystemPromptIfNeeded() {
        val stored = prefs.getString("geminiSystemPrompt", null) ?: return
        if (stored.contains("You have NO memory, NO storage, and NO ability")) {
            prefs.edit().remove("geminiSystemPrompt").apply()
            Log.d(TAG, "Migrated system prompt to new default")
        }
    }

    // -- Gemini --

    var geminiAPIKey: String
        get() = prefs.getString("geminiAPIKey", null) ?: Secrets.geminiAPIKey
        set(value) = prefs.edit().putString("geminiAPIKey", value).apply()

    var geminiSystemPrompt: String
        get() = prefs.getString("geminiSystemPrompt", null) ?: DEFAULT_SYSTEM_PROMPT
        set(value) = prefs.edit().putString("geminiSystemPrompt", value).apply()

    // -- Agent Backend --

    var agentBackend: AgentBackend
        get() {
            val raw = prefs.getString("agentBackend", null) ?: return AgentBackend.E2B
            return AgentBackend.fromLabel(raw)
        }
        set(value) = prefs.edit().putString("agentBackend", value.label).apply()

    // -- E2B --

    var agentBaseURL: String
        get() = prefs.getString("agentBaseURL", null) ?: Secrets.agentBaseURL
        set(value) = prefs.edit().putString("agentBaseURL", value).apply()

    var agentToken: String
        get() = prefs.getString("agentToken", null) ?: Secrets.agentToken
        set(value) = prefs.edit().putString("agentToken", value).apply()

    // -- OpenClaw --

    var openClawHost: String
        get() = prefs.getString("openClawHost", null) ?: Secrets.openClawHost
        set(value) = prefs.edit().putString("openClawHost", value).apply()

    var openClawPort: Int
        get() {
            val stored = prefs.getInt("openClawPort", 0)
            return if (stored != 0) stored else Secrets.openClawPort
        }
        set(value) = prefs.edit().putInt("openClawPort", value).apply()

    var openClawHookToken: String
        get() = prefs.getString("openClawHookToken", null) ?: Secrets.openClawHookToken
        set(value) = prefs.edit().putString("openClawHookToken", value).apply()

    var openClawGatewayToken: String
        get() = prefs.getString("openClawGatewayToken", null) ?: Secrets.openClawGatewayToken
        set(value) = prefs.edit().putString("openClawGatewayToken", value).apply()

    // -- WebRTC --

    var webrtcSignalingURL: String
        get() = prefs.getString("webrtcSignalingURL", null) ?: Secrets.webrtcSignalingURL
        set(value) = prefs.edit().putString("webrtcSignalingURL", value).apply()

    // -- User Identity (permanent, survives reset) --

    val userId: String
        get() {
            val existing = prefs.getString("userId", null)
            if (existing != null) return existing
            val id = java.util.UUID.randomUUID().toString()
            prefs.edit().putString("userId", id).apply()
            return id
        }

    // -- Session Persistence --

    var agentSessionKey: String?
        get() = prefs.getString("agentSessionKey", null)
        set(value) = prefs.edit().putString("agentSessionKey", value).apply()

    var agentSessionCreatedAt: Long
        get() = prefs.getLong("agentSessionCreatedAt", 0L)
        set(value) = prefs.edit().putLong("agentSessionCreatedAt", value).apply()

    // -- Reset (preserves userId) --

    fun resetAll() {
        val keysToRemove = listOf(
            "geminiAPIKey", "geminiSystemPrompt", "agentBackend",
            "agentBaseURL", "agentToken",
            "openClawHost", "openClawPort", "openClawHookToken", "openClawGatewayToken",
            "webrtcSignalingURL",
            "agentSessionKey", "agentSessionCreatedAt"
        )
        val editor = prefs.edit()
        for (key in keysToRemove) {
            editor.remove(key)
        }
        editor.apply()
    }

    const val DEFAULT_SYSTEM_PROMPT = """You are an AI assistant for someone wearing Meta Ray-Ban smart glasses. You can see through their camera and have a voice conversation. Keep responses concise and natural.

You have powerful tools that let you take real actions in the world. Use them confidently whenever the user asks for help.

TOOLS:

1. execute -- Your main tool. It connects to a personal assistant that can do anything:
- Send messages (WhatsApp, Telegram, iMessage, Slack, email, etc.)
- Search the web, look up facts, news, local info
- Check and manage email, calendar, notes, reminders, todos
- Create, edit, or organize documents and files
- Research and analyze topics
- Remember information for later
- Control apps, devices, and services

2. capture_photo -- Capture and save the current camera frame as a photo. Use when the user asks to take a photo, capture what you see, save a picture, or snap a photo. You can optionally include a brief description. This works instantly.

RULES:

- When the user asks you to do something actionable, ALWAYS use execute. Pass a detailed task description with all relevant context (names, content, platforms, quantities, etc.).
- NEVER say you can't do something that execute can handle. If in doubt, try it.
- NEVER pretend to complete an action without actually calling the tool.
- Before calling execute, ALWAYS speak a brief acknowledgment first so the user knows you heard them. For example:
  - "Sure, let me check your email." then call execute.
  - "Got it, searching for that now." then call execute.
  - "On it, sending that message." then call execute.
- The tool may take several seconds, so the verbal acknowledgment is important.
- For messages, confirm recipient and content before sending unless clearly urgent."""
}
