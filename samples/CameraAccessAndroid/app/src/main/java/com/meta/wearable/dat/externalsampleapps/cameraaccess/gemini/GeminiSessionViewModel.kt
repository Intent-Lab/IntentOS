package com.meta.wearable.dat.externalsampleapps.cameraaccess.gemini

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.GeminiFunctionCall
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.OpenClawBridge
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.OpenClawConnectionState
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.ToolCallRouter
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.ToolCallStatus
import com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw.ToolResult
import com.meta.wearable.dat.externalsampleapps.cameraaccess.stream.StreamingMode
import java.io.File
import java.io.FileOutputStream
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

data class GeminiUiState(
    val isGeminiActive: Boolean = false,
    val connectionState: GeminiConnectionState = GeminiConnectionState.Disconnected,
    val isModelSpeaking: Boolean = false,
    val errorMessage: String? = null,
    val userTranscript: String = "",
    val aiTranscript: String = "",
    val toolCallStatus: ToolCallStatus = ToolCallStatus.Idle,
    val openClawConnectionState: OpenClawConnectionState = OpenClawConnectionState.NotConfigured,
)

class GeminiSessionViewModel : ViewModel() {
    companion object {
        private const val TAG = "GeminiSessionVM"
        private const val MAX_RECONNECT_ATTEMPTS = 3
    }

    private val _uiState = MutableStateFlow(GeminiUiState())
    val uiState: StateFlow<GeminiUiState> = _uiState.asStateFlow()

    private val geminiService = GeminiLiveService()
    private val openClawBridge = OpenClawBridge()
    private var toolCallRouter: ToolCallRouter? = null
    private val audioManager = AudioManager()
    private var lastVideoFrameTime: Long = 0
    private var stateObservationJob: Job? = null

    // Auto-reconnect state
    private var reconnectJob: Job? = null
    private var reconnectAttempts: Int = 0

    // Photo capture
    private var latestFrame: Bitmap? = null
    var appContext: Context? = null

    var streamingMode: StreamingMode = StreamingMode.GLASSES

    fun startSession() {
        if (_uiState.value.isGeminiActive) return

        if (!GeminiConfig.isConfigured) {
            _uiState.value = _uiState.value.copy(
                errorMessage = "Gemini API key not configured. Open Settings and add your key from https://aistudio.google.com/apikey"
            )
            return
        }

        _uiState.value = _uiState.value.copy(isGeminiActive = true)
        reconnectAttempts = 0

        // Wire audio callbacks
        audioManager.onAudioCaptured = lambda@{ data ->
            // Phone mode: mute mic while model speaks to prevent echo
            if (streamingMode == StreamingMode.PHONE && geminiService.isModelSpeaking.value) return@lambda
            geminiService.sendAudio(data)
        }

        wireServiceCallbacks()

        // Check agent connection and start session
        viewModelScope.launch {
            openClawBridge.checkConnection()
            openClawBridge.resetSession()

            // Wire tool call handling
            toolCallRouter = ToolCallRouter(openClawBridge, viewModelScope)

            geminiService.onToolCall = { toolCall ->
                for (call in toolCall.functionCalls) {
                    if (call.name == "capture_photo") {
                        handleCapturePhoto(call)
                    } else {
                        toolCallRouter?.handleToolCall(call) { response ->
                            geminiService.sendToolResponse(response)
                        }
                    }
                }
            }

            geminiService.onToolCallCancellation = { cancellation ->
                toolCallRouter?.cancelToolCalls(cancellation.ids)
            }

            // Start state observation
            startStateObservation()

            // Connect to Gemini
            connectGemini { success ->
                if (!success) {
                    handleConnectionFailure()
                }
            }
        }
    }

    private fun wireServiceCallbacks() {
        geminiService.onAudioReceived = { data ->
            audioManager.playAudio(data)
        }

        geminiService.onInterrupted = {
            audioManager.stopPlayback()
        }

        geminiService.onTurnComplete = {
            _uiState.value = _uiState.value.copy(userTranscript = "")
        }

        geminiService.onInputTranscription = { text ->
            _uiState.value = _uiState.value.copy(
                userTranscript = _uiState.value.userTranscript + text,
                aiTranscript = ""
            )
        }

        geminiService.onOutputTranscription = { text ->
            _uiState.value = _uiState.value.copy(
                aiTranscript = _uiState.value.aiTranscript + text
            )
        }

        geminiService.onDisconnected = { reason ->
            if (_uiState.value.isGeminiActive) {
                Log.d(TAG, "Disconnected: ${reason ?: "unknown"}")
                attemptReconnect(reason)
            }
        }
    }

    private fun connectGemini(onResult: (Boolean) -> Unit) {
        geminiService.connect { setupOk ->
            if (!setupOk) {
                onResult(false)
                return@connect
            }

            // Start mic capture
            try {
                audioManager.startCapture()
                onResult(true)
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(
                    errorMessage = "Mic capture failed: ${e.message}"
                )
                onResult(false)
            }
        }
    }

    private fun handleConnectionFailure() {
        val msg = when (val state = geminiService.connectionState.value) {
            is GeminiConnectionState.Error -> state.message
            else -> "Failed to connect to Gemini"
        }
        _uiState.value = _uiState.value.copy(errorMessage = msg)
        geminiService.disconnect()
        stateObservationJob?.cancel()
        _uiState.value = _uiState.value.copy(
            isGeminiActive = false,
            connectionState = GeminiConnectionState.Disconnected
        )
    }

    private fun startStateObservation() {
        stateObservationJob?.cancel()
        stateObservationJob = viewModelScope.launch {
            while (isActive) {
                delay(100)
                _uiState.value = _uiState.value.copy(
                    connectionState = geminiService.connectionState.value,
                    isModelSpeaking = geminiService.isModelSpeaking.value,
                    toolCallStatus = openClawBridge.lastToolCallStatus.value,
                    openClawConnectionState = openClawBridge.connectionState.value,
                )
            }
        }
    }

    // -- Auto-Reconnect --

    private fun attemptReconnect(reason: String?) {
        // Clean up current connection without full stop
        geminiService.disconnect()
        audioManager.stopCapture()
        stateObservationJob?.cancel()
        stateObservationJob = null
        _uiState.value = _uiState.value.copy(
            isModelSpeaking = false,
            userTranscript = "",
            aiTranscript = "",
            toolCallStatus = ToolCallStatus.Idle
        )

        reconnectAttempts++
        if (reconnectAttempts > MAX_RECONNECT_ATTEMPTS) {
            Log.d(TAG, "Max reconnect attempts reached, stopping")
            _uiState.value = _uiState.value.copy(
                isGeminiActive = false,
                connectionState = GeminiConnectionState.Disconnected,
                errorMessage = "Connection lost: ${reason ?: "Unknown error"}"
            )
            return
        }

        Log.d(TAG, "Reconnecting (attempt $reconnectAttempts/$MAX_RECONNECT_ATTEMPTS)...")
        _uiState.value = _uiState.value.copy(connectionState = GeminiConnectionState.Connecting)

        reconnectJob?.cancel()
        reconnectJob = viewModelScope.launch {
            delay(reconnectAttempts * 1000L) // exponential backoff: 1s, 2s, 3s
            if (!isActive || !_uiState.value.isGeminiActive) return@launch

            // Re-wire callbacks and reconnect
            wireServiceCallbacks()
            startStateObservation()

            connectGemini { success ->
                if (success) {
                    Log.d(TAG, "Reconnected successfully")
                    reconnectAttempts = 0
                } else {
                    Log.d(TAG, "Reconnect failed, will retry")
                    if (_uiState.value.isGeminiActive && reconnectAttempts <= MAX_RECONNECT_ATTEMPTS) {
                        attemptReconnect("Reconnect failed")
                    } else {
                        _uiState.value = _uiState.value.copy(
                            isGeminiActive = false,
                            connectionState = GeminiConnectionState.Disconnected,
                            errorMessage = "Connection lost after $MAX_RECONNECT_ATTEMPTS attempts"
                        )
                    }
                }
            }
        }
    }

    // -- Photo Capture --

    private fun handleCapturePhoto(call: GeminiFunctionCall) {
        val description = call.args["description"]?.toString()
        val frame = latestFrame
        val ctx = appContext

        val resultText: String
        if (frame != null && ctx != null) {
            try {
                val filename = "photo_${System.currentTimeMillis()}.jpg"
                val photosDir = File(ctx.filesDir, "photos")
                photosDir.mkdirs()
                val file = File(photosDir, filename)
                FileOutputStream(file).use { out ->
                    frame.compress(Bitmap.CompressFormat.JPEG, 90, out)
                }
                resultText = "Photo captured and saved: $filename"
                Log.d(TAG, "[Capture] Saved frame: $filename${if (description != null) " ($description)" else ""}")
            } catch (e: Exception) {
                resultText = "Failed to save photo: ${e.message}"
            }
        } else if (frame == null) {
            resultText = "No camera frame available to capture"
        } else {
            resultText = "App context not available for saving photo"
        }

        val result = if (resultText.startsWith("Photo captured"))
            ToolResult.Success(resultText) else ToolResult.Failure(resultText)

        val response = JSONObject().apply {
            put("toolResponse", JSONObject().apply {
                put("functionResponses", JSONArray().put(JSONObject().apply {
                    put("id", call.id)
                    put("name", "capture_photo")
                    put("response", result.toJSON())
                }))
            })
        }
        geminiService.sendToolResponse(response)
    }

    // -- Public API --

    fun stopSession() {
        reconnectJob?.cancel()
        reconnectJob = null
        reconnectAttempts = 0
        toolCallRouter?.cancelAll()
        toolCallRouter = null
        audioManager.stopCapture()
        geminiService.disconnect()
        stateObservationJob?.cancel()
        stateObservationJob = null
        _uiState.value = GeminiUiState()
    }

    fun sendVideoFrameIfThrottled(bitmap: Bitmap) {
        if (!_uiState.value.isGeminiActive) return
        if (_uiState.value.connectionState != GeminiConnectionState.Ready) return
        latestFrame = bitmap
        val now = System.currentTimeMillis()
        if (now - lastVideoFrameTime < GeminiConfig.VIDEO_FRAME_INTERVAL_MS) return
        lastVideoFrameTime = now
        geminiService.sendVideoFrame(bitmap)
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    override fun onCleared() {
        super.onCleared()
        stopSession()
    }
}
