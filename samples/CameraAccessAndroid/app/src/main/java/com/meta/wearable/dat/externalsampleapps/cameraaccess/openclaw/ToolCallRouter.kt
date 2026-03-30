package com.meta.wearable.dat.externalsampleapps.cameraaccess.openclaw

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

class ToolCallRouter(
    private val bridge: OpenClawBridge,
    private val scope: CoroutineScope
) {
    companion object {
        private const val TAG = "ToolCallRouter"
        private const val MAX_CONSECUTIVE_FAILURES = 3
    }

    private val inFlightJobs = mutableMapOf<String, Job>()
    private var consecutiveFailures = 0

    fun handleToolCall(
        call: GeminiFunctionCall,
        sendResponse: (JSONObject) -> Unit
    ) {
        val callId = call.id
        val callName = call.name

        Log.d(TAG, "Received: $callName (id: $callId) args: ${call.args}")

        // Circuit breaker: reject if too many consecutive failures
        if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
            Log.d(TAG, "Circuit breaker open ($consecutiveFailures consecutive failures), rejecting $callName")
            val result = ToolResult.Failure("Agent gateway is currently unavailable. Please try again later.")
            val response = buildToolResponse(callId, callName, result)
            sendResponse(response)
            return
        }

        val job = scope.launch {
            val taskDesc = call.args["task"]?.toString() ?: call.args.toString()
            val result = bridge.delegateTask(task = taskDesc, toolName = callName)

            if (!coroutineContext[Job]!!.isCancelled) {
                // Track consecutive failures for circuit breaker
                when (result) {
                    is ToolResult.Success -> consecutiveFailures = 0
                    is ToolResult.Failure -> {
                        consecutiveFailures++
                        Log.d(TAG, "Consecutive failures: $consecutiveFailures/$MAX_CONSECUTIVE_FAILURES")
                    }
                }

                Log.d(TAG, "Result for $callName (id: $callId): $result")
                val response = buildToolResponse(callId, callName, result)
                sendResponse(response)
            } else {
                Log.d(TAG, "Task $callId was cancelled, skipping response")
            }

            inFlightJobs.remove(callId)
        }

        inFlightJobs[callId] = job
    }

    fun cancelToolCalls(ids: List<String>) {
        for (id in ids) {
            inFlightJobs[id]?.let { job ->
                Log.d(TAG, "Cancelling in-flight call: $id")
                job.cancel()
                inFlightJobs.remove(id)
            }
        }
        bridge.setToolCallStatus(ToolCallStatus.Cancelled(ids.firstOrNull() ?: "unknown"))
    }

    fun cancelAll() {
        for ((id, job) in inFlightJobs) {
            Log.d(TAG, "Cancelling in-flight call: $id")
            job.cancel()
        }
        inFlightJobs.clear()
    }

    fun resetCircuitBreaker() {
        consecutiveFailures = 0
    }

    private fun buildToolResponse(
        callId: String,
        name: String,
        result: ToolResult
    ): JSONObject {
        return JSONObject().apply {
            put("toolResponse", JSONObject().apply {
                put("functionResponses", JSONArray().put(JSONObject().apply {
                    put("id", callId)
                    put("name", name)
                    put("response", result.toJSON().apply {
                        put("scheduling", "INTERRUPT")
                    })
                }))
            })
        }
    }
}
