import Foundation

// MARK: - Agent Task

struct AgentTask {
  let id: String
  let name: String
  let description: String
  let createdAt: Date

  init(id: String, name: String, description: String, createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.description = description
    self.createdAt = createdAt
  }
}

// MARK: - Agent Result

struct AgentResult {
  let taskId: String
  let toolName: String
  let result: ToolResult
  let responsePayload: [String: Any]

  /// Build the toolResponse JSON payload from a tool call result
  static func from(taskId: String, toolName: String, result: ToolResult) -> AgentResult {
    let payload: [String: Any] = [
      "toolResponse": [
        "functionResponses": [
          [
            "id": taskId,
            "name": toolName,
            "response": result.responseValue.merging(["scheduling": "INTERRUPT"]) { _, new in new }
          ]
        ]
      ]
    ]
    return AgentResult(
      taskId: taskId,
      toolName: toolName,
      result: result,
      responsePayload: payload
    )
  }
}
