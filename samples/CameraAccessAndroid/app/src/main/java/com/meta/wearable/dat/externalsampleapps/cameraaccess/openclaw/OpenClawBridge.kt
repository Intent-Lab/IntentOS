package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import android.util.Log
import com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini.GeminiConfig
import com.meta.wearable.dat.externalsampleapps.cameraaccess.settings.AgentBackend
import com.meta.wearable.dat.externalsampleapps.cameraaccess.settings.SettingsManager
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

class OpenClawBridge {
    companion object {
        private const val TAG = "AgentBridge"
        private const val SESSION_MAX_AGE_MS = 86_400_000L // 24 hours

        fun friendlyToolLabel(tool: String, input: Map<String, Any?>?): String {
            return when (tool) {
                "Bash" -> {
                    val cmd = input?.get("command")?.toString()
                    if (cmd != null) {
                        val short = cmd.lines().firstOrNull() ?: cmd
                        val trimmed = if (short.length > 60) short.take(60) + "..." else short
                        "Running: $trimmed"
                    } else "Running command..."
                }
                "Read" -> {
                    val path = input?.get("file_path")?.toString()
                    if (path != null) "Reading ${path.substringAfterLast('/')}"
                    else "Reading file..."
                }
                "Write" -> {
                    val path = input?.get("file_path")?.toString()
                    if (path != null) "Writing ${path.substringAfterLast('/')}"
                    else "Writing file..."
                }
                "Edit" -> {
                    val path = input?.get("file_path")?.toString()
                    if (path != null) "Editing ${path.substringAfterLast('/')}"
                    else "Editing file..."
                }
                "Glob" -> {
                    val pattern = input?.get("pattern")?.toString()
                    if (pattern != null) "Searching: $pattern"
                    else "Searching files..."
                }
                "Grep" -> {
                    val pattern = input?.get("pattern")?.toString()
                    if (pattern != null) {
                        val short = if (pattern.length > 40) pattern.take(40) + "..." else pattern
                        "Searching: $short"
                    } else "Searching code..."
                }
                "WebSearch" -> {
                    val query = input?.get("query")?.toString()
                    if (query != null) "Searching: $query"
                    else "Web search..."
                }
                "WebFetch" -> "Fetching web page..."
                "google_calendar_events" -> "Checking calendar..."
                "google_gmail_search" -> {
                    val query = input?.get("query")?.toString()
                    if (query != null) {
                        val short = if (query.length > 40) query.take(40) + "..." else query
                        "Searching email: $short"
                    } else "Searching email..."
                }
                "google_gmail_read" -> "Reading email..."
                "google_drive_search" -> {
                    val query = input?.get("query")?.toString()
                    if (query != null) {
                        val short = if (query.length > 40) query.take(40) + "..." else query
                        "Searching Drive: $short"
                    } else "Searching Drive..."
                }
                "google_drive_read" -> {
                    val name = input?.get("file_name")?.toString()
                    if (name != null) "Reading $name" else "Reading Drive file..."
                }
                "google_drive_create" -> {
                    val name = input?.get("name")?.toString()
                    if (name != null) "Creating $name" else "Creating Drive file..."
                }
                "google_drive_update" -> {
                    val name = input?.get("file_name")?.toString()
                    if (name != null) "Updating $name" else "Updating Drive file..."
                }
                "notion_search" -> {
                    val query = input?.get("query")?.toString()
                    if (query != null) {
                        val short = if (query.length > 40) query.take(40) + "..." else query
                        "Searching Notion: $short"
                    } else "Searching Notion..."
                }
                "notion_read_page" -> "Reading Notion page..."
                "notion_create_page" -> {
                    val title = input?.get("title")?.toString()
                    if (title != null) "Creating $title" else "Creating Notion page..."
                }
                "notion_update_page" -> "Updating Notion page..."
                "memory_read" -> "Recalling memories..."
                "memory_save" -> "Saving to memory..."
                "memory_delete" -> "Removing memory..."
                "memory_search" -> "Searching memories..."
                "memory_list" -> "Checking memory..."
                else -> "Running $tool..."
            }
        }
    }

    private val _lastToolCallStatus = MutableStateFlow<ToolCallStatus>(ToolCallStatus.Idle)
    val lastToolCallStatus: StateFlow<ToolCallStatus> = _lastToolCallStatus.asStateFlow()

    private val _connectionState = MutableStateFlow<OpenClawConnectionState>(OpenClawConnectionState.NotConfigured)
    val connectionState: StateFlow<OpenClawConnectionState> = _connectionState.asStateFlow()

    private val _streamingText = MutableStateFlow("")
    val streamingText: StateFlow<String> = _streamingText.asStateFlow()

    private val _agentSteps = MutableStateFlow<List<AgentStep>>(emptyList())
    val agentSteps: StateFlow<List<AgentStep>> = _agentSteps.asStateFlow()

    fun setToolCallStatus(status: ToolCallStatus) {
        _lastToolCallStatus.value = status
    }

    private val client = OkHttpClient.Builder()
        .readTimeout(120, TimeUnit.SECONDS)
        .connectTimeout(10, TimeUnit.SECONDS)
        .build()

    private val pingClient = OkHttpClient.Builder()
        .readTimeout(5, TimeUnit.SECONDS)
        .connectTimeout(5, TimeUnit.SECONDS)
        .build()

    private var sessionKey: String
    private val conversationHistory = mutableListOf<JSONObject>()

    // Direct E2B sandbox connection
    private var sandboxUrl: String? = null
    private var sandboxAuthToken: String? = null

    /** Track last-used backend to detect switches */
    private var lastUsedBackend: AgentBackend? = null

    /** Last OpenClaw response ID for session continuity via previous_response_id */
    private var lastOpenClawResponseId: String? = null

    /** Which backend this bridge is using (reads dynamically from settings) */
    val backend: AgentBackend
        get() = SettingsManager.agentBackend

    /** Max conversation history turns varies by backend */
    private val maxHistoryTurns: Int
        get() = if (backend == AgentBackend.OPENCLAW) 10 else 3

    init {
        // Reuse persisted session key if < 24 hours old
        val existingKey = SettingsManager.agentSessionKey
        val age = System.currentTimeMillis() - SettingsManager.agentSessionCreatedAt
        if (existingKey != null && age < SESSION_MAX_AGE_MS) {
            sessionKey = existingKey
            Log.d(TAG, "[${backend.label}] Resumed session: $existingKey")
        } else {
            sessionKey = newSessionKey()
            SettingsManager.agentSessionKey = sessionKey
            SettingsManager.agentSessionCreatedAt = System.currentTimeMillis()
            Log.d(TAG, "[${backend.label}] New session: $sessionKey")
        }
    }

    // -- Connection Check --

    suspend fun checkConnection() = withContext(Dispatchers.IO) {
        when (backend) {
            AgentBackend.E2B -> checkE2BConnection()
            AgentBackend.OPENCLAW -> checkOpenClawConnection()
        }
    }

    private fun checkE2BConnection() {
        if (!GeminiConfig.isE2BConfigured) {
            _connectionState.value = OpenClawConnectionState.NotConfigured
            return
        }
        _connectionState.value = OpenClawConnectionState.Checking

        val url = "${GeminiConfig.agentBaseURL}/api/agent/health"
        try {
            val request = Request.Builder()
                .url(url)
                .get()
                .addHeader("x-api-token", GeminiConfig.agentToken)
                .build()

            val response = pingClient.newCall(request).execute()
            val code = response.code
            response.close()

            if (code in 200..499) {
                _connectionState.value = OpenClawConnectionState.Connected
                Log.d(TAG, "[E2B] Gateway reachable (HTTP $code)")
            } else {
                _connectionState.value = OpenClawConnectionState.Unreachable("Unexpected response")
            }
        } catch (e: Exception) {
            _connectionState.value = OpenClawConnectionState.Unreachable(e.message ?: "Unknown error")
            Log.d(TAG, "[E2B] Gateway unreachable: ${e.message}")
        }
    }

    private fun checkOpenClawConnection() {
        val host = SettingsManager.openClawHost
        val token = SettingsManager.openClawGatewayToken
        if (host.isEmpty() || token.isEmpty()) {
            _connectionState.value = OpenClawConnectionState.NotConfigured
            return
        }
        _connectionState.value = OpenClawConnectionState.Checking

        val url = "$host:${SettingsManager.openClawPort}/v1/chat/completions"
        try {
            val request = Request.Builder()
                .url(url)
                .get()
                .addHeader("Authorization", "Bearer $token")
                .build()

            val response = pingClient.newCall(request).execute()
            val code = response.code
            response.close()

            if (code in 200..499) {
                _connectionState.value = OpenClawConnectionState.Connected
                Log.d(TAG, "[OpenClaw] Gateway reachable (HTTP $code)")
            } else {
                _connectionState.value = OpenClawConnectionState.Unreachable("Unexpected response")
            }
        } catch (e: Exception) {
            _connectionState.value = OpenClawConnectionState.Unreachable(e.message ?: "Unknown error")
            Log.d(TAG, "[OpenClaw] Gateway unreachable: ${e.message}")
        }
    }

    fun resetSession() {
        sessionKey = newSessionKey()
        conversationHistory.clear()
        sandboxUrl = null
        sandboxAuthToken = null
        lastOpenClawResponseId = null
        SettingsManager.agentSessionKey = sessionKey
        SettingsManager.agentSessionCreatedAt = System.currentTimeMillis()
        Log.d(TAG, "Reset session: $sessionKey")
    }

    // -- Context Injection --

    fun injectContext(messages: List<JSONObject>) {
        conversationHistory.addAll(0, messages)
        if (conversationHistory.size > maxHistoryTurns * 2) {
            val trimmed = conversationHistory.takeLast(maxHistoryTurns * 2)
            conversationHistory.clear()
            conversationHistory.addAll(trimmed)
        }
        Log.d(TAG, "[${backend.label}] Injected ${messages.size} context messages (total: ${conversationHistory.size})")

        // Also inject into E2B sandbox if active
        if (backend == AgentBackend.E2B && sandboxUrl != null && sandboxAuthToken != null) {
            try {
                injectContextToSandbox(messages)
            } catch (e: Exception) {
                Log.d(TAG, "Failed to inject context to sandbox: ${e.message}")
            }
        }
    }

    private fun injectContextToSandbox(messages: List<JSONObject>) {
        val sbUrl = sandboxUrl ?: return
        val authToken = sandboxAuthToken ?: return
        val url = "$sbUrl/context"

        val messagesArray = JSONArray()
        for (msg in messages) messagesArray.put(msg)

        val body = JSONObject().apply {
            put("messages", messagesArray)
            put("token", authToken)
        }

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Content-Type", "application/json")
            .build()

        val response = pingClient.newCall(request).execute()
        Log.d(TAG, "Context injected to sandbox: HTTP ${response.code}")
        response.close()
    }

    // -- Task Delegation --

    suspend fun delegateTask(
        task: String,
        toolName: String = "execute"
    ): ToolResult = withContext(Dispatchers.IO) {
        // Detect backend switch and reset connection state
        val currentBackend = backend
        if (lastUsedBackend != null && lastUsedBackend != currentBackend) {
            Log.d(TAG, "Backend switched from ${lastUsedBackend?.label} to ${currentBackend.label}, resetting")
            _connectionState.value = OpenClawConnectionState.NotConfigured
            sandboxUrl = null
            sandboxAuthToken = null
        }
        lastUsedBackend = currentBackend

        _lastToolCallStatus.value = ToolCallStatus.Executing(toolName)
        _streamingText.value = ""
        _agentSteps.value = listOf(AgentStep(type = AgentStep.StepType.Thinking, label = "Thinking..."))

        try {
            val content = when (currentBackend) {
                AgentBackend.E2B -> sendDirectOrFallback(task)
                AgentBackend.OPENCLAW -> sendViaOpenClaw(task)
            }
            Log.d(TAG, "[${currentBackend.label}] Result: ${content.take(200)}")
            markThinkingDone()
            _lastToolCallStatus.value = ToolCallStatus.Completed(toolName)
            return@withContext ToolResult.Success(content)
        } catch (e: Exception) {
            Log.e(TAG, "[${currentBackend.label}] Error: ${e.message}")
            _lastToolCallStatus.value = ToolCallStatus.Failed(toolName, e.message ?: "Unknown")
            return@withContext ToolResult.Failure("Agent error: ${e.message}")
        }
    }

    // -- E2B: Direct Sandbox + Vercel Fallback --

    private fun sendDirectOrFallback(prompt: String): String {
        // Initialize sandbox if needed
        if (sandboxUrl == null) {
            try {
                initSandbox()
            } catch (e: Exception) {
                Log.d(TAG, "Init failed, falling back to Vercel: ${e.message}")
                return sendViaVercel(prompt)
            }
        }

        // Try direct E2B streaming
        try {
            val result = sendToSandboxStreaming(prompt)
            // Persist to Vercel in background (sandbox path doesn't write to Redis)
            persistToVercel(prompt, result)
            return result
        } catch (e: Exception) {
            Log.d(TAG, "Direct E2B failed: ${e.message}, re-initializing...")
            // Sandbox may have expired -- re-init and retry once
            try {
                sandboxUrl = null
                sandboxAuthToken = null
                initSandbox()
                val result = sendToSandboxStreaming(prompt)
                persistToVercel(prompt, result)
                return result
            } catch (e2: Exception) {
                Log.d(TAG, "Retry failed, falling back to Vercel: ${e2.message}")
                return sendViaVercel(prompt)
            }
        }
    }

    /** Fire-and-forget: persist sandbox conversation turn to Redis via Vercel */
    private fun persistToVercel(userMessage: String, assistantMessage: String) {
        try {
            val baseURL = GeminiConfig.agentBaseURL
            val token = GeminiConfig.agentToken
            val url = "$baseURL/api/agent/persist"

            val body = JSONObject().apply {
                put("sessionKey", sessionKey)
                put("userId", SettingsManager.userId)
                put("userMessage", userMessage)
                put("assistantMessage", assistantMessage)
            }

            val request = Request.Builder()
                .url(url)
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .addHeader("Content-Type", "application/json")
                .addHeader("x-api-token", token)
                .build()

            // Fire-and-forget on a background thread
            Thread {
                try {
                    val response = pingClient.newCall(request).execute()
                    if (response.code == 200) {
                        Log.d(TAG, "Persisted conversation turn to Redis")
                    }
                    response.close()
                } catch (e: Exception) {
                    Log.d(TAG, "Persist failed (non-critical): ${e.message}")
                }
            }.start()
        } catch (e: Exception) {
            Log.d(TAG, "Persist setup failed (non-critical): ${e.message}")
        }
    }

    /** Ask the E2B sandbox to flush memory before session ends. Fire-and-forget. */
    fun flushMemory() {
        val sbUrl = sandboxUrl ?: return
        val authToken = sandboxAuthToken ?: return
        try {
            val body = JSONObject().apply {
                put("token", authToken)
                put("userId", SettingsManager.userId)
            }
            val request = Request.Builder()
                .url("$sbUrl/flush")
                .post(body.toString().toRequestBody("application/json".toMediaType()))
                .addHeader("Content-Type", "application/json")
                .build()
            Thread {
                try {
                    val response = pingClient.newCall(request).execute()
                    val responseBody = response.body?.string() ?: ""
                    response.close()
                    if (response.code == 200) {
                        val json = JSONObject(responseBody)
                        val flushed = json.optBoolean("flushed", false)
                        Log.d(TAG, "Memory flush: flushed=$flushed")
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "Memory flush failed (non-critical): ${e.message}")
                }
            }.start()
        } catch (e: Exception) {
            Log.d(TAG, "Memory flush setup failed (non-critical): ${e.message}")
        }
    }

    private fun initSandbox() {
        val baseURL = GeminiConfig.agentBaseURL
        val token = GeminiConfig.agentToken
        val url = "$baseURL/api/agent/init"

        val request = Request.Builder()
            .url(url)
            .post("{}".toRequestBody("application/json".toMediaType()))
            .addHeader("Content-Type", "application/json")
            .addHeader("x-api-token", token)
            .addHeader("x-agent-session-key", sessionKey)
            .addHeader("x-agent-user-id", SettingsManager.userId)
            .build()

        Log.d(TAG, "Initializing sandbox for session: $sessionKey")

        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: ""
        val statusCode = response.code
        response.close()

        if (statusCode !in 200..299) {
            val errorMsg = try {
                JSONObject(responseBody).optString("error", "Sandbox init HTTP $statusCode")
            } catch (_: Exception) { "Sandbox init HTTP $statusCode" }
            throw RuntimeException(errorMsg)
        }

        val json = JSONObject(responseBody)
        sandboxUrl = json.getString("sandboxUrl")
        sandboxAuthToken = json.getString("authToken")
        Log.d(TAG, "Sandbox initialized: $sandboxUrl")
    }

    private fun sendToSandboxStreaming(prompt: String): String {
        val sbUrl = sandboxUrl ?: throw RuntimeException("Sandbox not initialized")
        val authToken = sandboxAuthToken ?: throw RuntimeException("Sandbox not initialized")
        val url = "$sbUrl/stream"

        val body = JSONObject().apply {
            put("prompt", prompt)
            put("token", authToken)
            put("userId", SettingsManager.userId)
            // TODO: Add googleAccessToken and notionAccessToken when Google/Notion OAuth
            // is implemented on Android. See iOS GoogleAuthManager.swift and NotionAuthManager.swift.
        }

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Content-Type", "application/json")
            .build()

        _streamingText.value = ""

        val response = client.newCall(request).execute()
        if (response.code !in 200..299) {
            val code = response.code
            val errorBody = response.body?.string() ?: ""
            response.close()
            val errorMsg = try {
                JSONObject(errorBody).optString("error", "Sandbox stream HTTP $code")
            } catch (_: Exception) { "Sandbox stream HTTP $code" }
            throw RuntimeException(errorMsg)
        }

        val source = response.body?.source() ?: throw RuntimeException("Empty response body")
        var finalResult: String? = null
        var currentEvent = ""

        try {
            while (!source.exhausted()) {
                val line = source.readUtf8Line() ?: break

                if (line.startsWith("event: ")) {
                    currentEvent = line.removePrefix("event: ")
                } else if (line.startsWith("data: ")) {
                    val dataStr = line.removePrefix("data: ")
                    when (currentEvent) {
                        "token" -> {
                            val json = JSONObject(dataStr)
                            val text = json.optString("text", "")
                            if (text.isNotEmpty()) {
                                if (_streamingText.value.isEmpty()) {
                                    markThinkingDone()
                                }
                                _streamingText.value += text
                            }
                        }
                        "tool_start" -> {
                            val json = JSONObject(dataStr)
                            val tool = json.optString("tool", "")
                            val inputObj = json.optJSONObject("input")
                            val inputMap = if (inputObj != null) {
                                val map = mutableMapOf<String, Any?>()
                                for (key in inputObj.keys()) map[key] = inputObj.opt(key)
                                map
                            } else null
                            val label = friendlyToolLabel(tool, inputMap)
                            val steps = _agentSteps.value.toMutableList()
                            steps.add(AgentStep(type = AgentStep.StepType.Tool(tool), label = label))
                            _agentSteps.value = steps
                            Log.d(TAG, "Tool: $tool")
                        }
                        "tool_done" -> {
                            val json = JSONObject(dataStr)
                            val tool = json.optString("tool", "")
                            val success = json.optBoolean("success", true)
                            val steps = _agentSteps.value.toMutableList()
                            val idx = steps.indexOfLast {
                                it.type is AgentStep.StepType.Tool &&
                                (it.type as AgentStep.StepType.Tool).name == tool && !it.isDone
                            }
                            if (idx >= 0) {
                                steps[idx] = steps[idx].copy(isDone = true, success = success)
                                _agentSteps.value = steps
                            }
                        }
                        "done" -> {
                            val json = JSONObject(dataStr)
                            finalResult = json.optString("result", "")
                            Log.d(TAG, "Done. cost: ${json.opt("cost_usd")}, duration: ${json.opt("duration_ms")}ms")
                        }
                        "error" -> {
                            val json = JSONObject(dataStr)
                            val error = json.optString("error", "Unknown error")
                            throw RuntimeException("Server error: $error")
                        }
                    }
                    currentEvent = ""
                }
            }
        } finally {
            response.close()
        }

        return finalResult ?: _streamingText.value
    }

    // -- E2B: Vercel Fallback --

    private fun sendViaVercel(prompt: String): String {
        val baseURL = GeminiConfig.agentBaseURL
        val token = GeminiConfig.agentToken
        val url = "$baseURL/api/agent/chat"

        conversationHistory.add(JSONObject().apply {
            put("role", "user")
            put("content", prompt)
        })
        trimHistory()

        Log.d(TAG, "[E2B:Vercel] Sending ${conversationHistory.size} messages in conversation")

        val messagesArray = JSONArray()
        for (msg in conversationHistory) {
            messagesArray.put(msg)
        }

        val body = JSONObject().apply {
            put("model", "claude-agent")
            put("messages", messagesArray)
            put("stream", false)
        }

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Content-Type", "application/json")
            .addHeader("x-api-token", token)
            .addHeader("x-agent-session-key", sessionKey)
            .addHeader("x-agent-user-id", SettingsManager.userId)
            .build()

        val response = client.newCall(request).execute()
        val responseBody = response.body?.string() ?: ""
        val statusCode = response.code
        response.close()

        if (statusCode !in 200..299) {
            Log.d(TAG, "[E2B:Vercel] Chat failed: HTTP $statusCode - ${responseBody.take(200)}")
            val errorMsg = try {
                JSONObject(responseBody).optString("error", "HTTP $statusCode")
            } catch (_: Exception) { "HTTP $statusCode" }
            throw RuntimeException(errorMsg)
        }

        val json = JSONObject(responseBody)
        val choices = json.optJSONArray("choices")
        val content = choices?.optJSONObject(0)
            ?.optJSONObject("message")
            ?.optString("content", "")

        val result = if (!content.isNullOrEmpty()) content else responseBody
        conversationHistory.add(JSONObject().apply {
            put("role", "assistant")
            put("content", result)
        })
        Log.d(TAG, "[E2B:Vercel] Agent result: ${result.take(200)}")
        return result
    }

    // -- OpenClaw Backend --

    private fun sendViaOpenClaw(task: String): String {
        val host = SettingsManager.openClawHost
        val port = SettingsManager.openClawPort
        val gatewayToken = SettingsManager.openClawGatewayToken
        val url = "$host:$port/v1/responses"

        val body = JSONObject().apply {
            put("model", "openclaw")
            put("input", task)
            put("stream", true)
            lastOpenClawResponseId?.let { put("previous_response_id", it) }
        }

        Log.d(TAG, "[OpenClaw] Sending via /v1/responses (streaming, prevId: $lastOpenClawResponseId)")

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Authorization", "Bearer $gatewayToken")
            .addHeader("Content-Type", "application/json")
            .addHeader("x-openclaw-session-key", sessionKey)
            .build()

        _streamingText.value = ""

        val response = client.newCall(request).execute()
        if (response.code !in 200..299) {
            val code = response.code
            val errorBody = response.body?.string() ?: ""
            response.close()
            Log.d(TAG, "[OpenClaw] Request failed: HTTP $code - ${errorBody.take(200)}")
            throw RuntimeException("HTTP $code")
        }

        val source = response.body?.source() ?: throw RuntimeException("Empty response body")
        var accumulated = ""

        try {
            while (!source.exhausted()) {
                val line = source.readUtf8Line() ?: break

                // OpenResponses SSE format: "data: {...}" or "data: [DONE]"
                if (!line.startsWith("data: ")) continue
                val dataStr = line.removePrefix("data: ")

                if (dataStr == "[DONE]") break

                try {
                    val json = JSONObject(dataStr)
                    val type = json.optString("type", "")

                    when (type) {
                        "response.in_progress" -> {
                            // Server confirmed it's processing - show immediate feedback
                            val steps = _agentSteps.value.toMutableList()
                            steps.add(AgentStep(
                                type = AgentStep.StepType.Tool("openclaw"),
                                label = "OpenClaw processing..."
                            ))
                            _agentSteps.value = steps
                            Log.d(TAG, "[OpenClaw] Server is processing")
                        }

                        "response.output_text.delta" -> {
                            val delta = json.optString("delta", "")
                            if (delta.isNotEmpty()) {
                                // Mark thinking + processing as done on first token
                                if (accumulated.isEmpty()) {
                                    markAllStepsDone()
                                }
                                accumulated += delta
                                _streamingText.value = accumulated
                            }
                        }

                        "response.completed" -> {
                            // Extract response ID for session continuity
                            val resp = json.optJSONObject("response")
                            val respId = resp?.optString("id", null)
                            if (respId != null) {
                                lastOpenClawResponseId = respId
                                Log.d(TAG, "[OpenClaw] Response completed, id: $respId")
                            }
                        }

                        "response.failed" -> {
                            val resp = json.optJSONObject("response")
                            val error = resp?.optJSONObject("error")
                            val message = error?.optString("message", "OpenClaw request failed")
                                ?: "OpenClaw request failed"
                            throw RuntimeException(message)
                        }
                    }
                } catch (e: RuntimeException) {
                    throw e
                } catch (_: Exception) {
                    // Skip malformed JSON chunks
                }
            }
        } finally {
            response.close()
        }

        val result = accumulated.ifEmpty { "OK" }
        Log.d(TAG, "[OpenClaw] Agent result: ${result.take(200)}")
        return result
    }

    // -- Helpers --

    private fun trimHistory() {
        if (conversationHistory.size > maxHistoryTurns * 2) {
            val trimmed = conversationHistory.takeLast(maxHistoryTurns * 2)
            conversationHistory.clear()
            conversationHistory.addAll(trimmed)
        }
    }

    private fun markThinkingDone() {
        val steps = _agentSteps.value.toMutableList()
        val idx = steps.indexOfFirst { it.type is AgentStep.StepType.Thinking && !it.isDone }
        if (idx >= 0) {
            steps[idx] = steps[idx].copy(isDone = true)
            _agentSteps.value = steps
        }
    }

    private fun markAllStepsDone() {
        val steps = _agentSteps.value.toMutableList()
        var changed = false
        for (i in steps.indices) {
            if (!steps[i].isDone) {
                steps[i] = steps[i].copy(isDone = true)
                changed = true
            }
        }
        if (changed) _agentSteps.value = steps
    }

    private fun newSessionKey(): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
        formatter.timeZone = TimeZone.getTimeZone("UTC")
        val ts = formatter.format(Date())
        return "agent:main:glass:$ts"
    }
}
