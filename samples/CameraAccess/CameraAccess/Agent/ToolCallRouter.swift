import Foundation

@MainActor
class ToolCallRouter {
  private let bridge: AgentBridge
  private var inFlightTasks: [String: Task<Void, Never>] = [:]

  // Circuit breaker: stop tool calls after consecutive failures
  private var consecutiveFailures: Int = 0
  private let maxConsecutiveFailures = 3

  init(bridge: AgentBridge) {
    self.bridge = bridge
  }

  /// Route a tool call from Gemini to the agent. Calls sendResponse with the
  /// JSON dictionary to send back as a toolResponse message.
  func handleToolCall(
    _ call: GeminiFunctionCall,
    sendResponse: @escaping ([String: Any]) -> Void
  ) {
    let callId = call.id
    let callName = call.name

    NSLog("[ToolCall] Received: %@ (id: %@) args: %@",
          callName, callId, String(describing: call.args))

    // Circuit breaker: reject if too many consecutive failures
    if consecutiveFailures >= maxConsecutiveFailures {
      NSLog("[ToolCall] Circuit breaker open (%d consecutive failures), rejecting %@", consecutiveFailures, callName)
      let result = ToolResult.failure("Agent gateway is currently unavailable. Please try again later.")
      let response = buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)
      return
    }

    let task = Task { @MainActor in
      let taskDesc = call.args["task"] as? String ?? String(describing: call.args)
      let result = await bridge.delegateTask(task: taskDesc, toolName: callName)

      guard !Task.isCancelled else {
        NSLog("[ToolCall] Task %@ was cancelled, skipping response", callId)
        return
      }

      // Track consecutive failures for circuit breaker
      switch result {
      case .success:
        self.consecutiveFailures = 0
      case .failure:
        self.consecutiveFailures += 1
        NSLog("[ToolCall] Consecutive failures: %d/%d", self.consecutiveFailures, self.maxConsecutiveFailures)
      }

      NSLog("[ToolCall] Result for %@ (id: %@): %@",
            callName, callId, String(describing: result))

      let response = self.buildToolResponse(callId: callId, name: callName, result: result)
      sendResponse(response)

      self.inFlightTasks.removeValue(forKey: callId)
    }

    inFlightTasks[callId] = task
  }

  /// Cancel specific in-flight tool calls (from toolCallCancellation)
  func cancelToolCalls(ids: [String]) {
    for id in ids {
      if let task = inFlightTasks[id] {
        NSLog("[ToolCall] Cancelling in-flight call: %@", id)
        task.cancel()
        inFlightTasks.removeValue(forKey: id)
      }
    }
    bridge.lastToolCallStatus = .cancelled(ids.first ?? "unknown")
  }

  /// Cancel all in-flight tool calls (on session stop)
  func cancelAll() {
    for (id, task) in inFlightTasks {
      NSLog("[ToolCall] Cancelling in-flight call: %@", id)
      task.cancel()
    }
    inFlightTasks.removeAll()
  }

  /// Reset circuit breaker (e.g. after reconnecting)
  func resetCircuitBreaker() {
    consecutiveFailures = 0
  }

  // MARK: - Private

  private func buildToolResponse(
    callId: String,
    name: String,
    result: ToolResult
  ) -> [String: Any] {
    return [
      "toolResponse": [
        "functionResponses": [
          [
            "id": callId,
            "name": name,
            "response": result.responseValue.merging(["scheduling": "INTERRUPT"]) { _, new in new }
          ]
        ]
      ]
    ]
  }
}
