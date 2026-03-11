import Foundation

enum ChatMessageRole {
  case user
  case assistant
  case toolCall
}

enum ChatMessageStatus: Equatable {
  case sending
  case streaming
  case complete
  case error(String)
}

struct ChatMessage: Identifiable {
  let id: String
  let role: ChatMessageRole
  var text: String
  let timestamp: Date
  var status: ChatMessageStatus

  var toolCallName: String?
  var toolCallResult: String?

  /// When true, this assistant message is from the agent backend (not voice transcript)
  /// and should render as a card instead of a regular bubble
  var isAgentResult: Bool

  /// Agent steps associated with this message (for card display)
  var agentSteps: [AgentStep]

  init(
    id: String = UUID().uuidString,
    role: ChatMessageRole,
    text: String,
    timestamp: Date = Date(),
    status: ChatMessageStatus = .complete,
    toolCallName: String? = nil,
    toolCallResult: String? = nil,
    isAgentResult: Bool = false,
    agentSteps: [AgentStep] = []
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.timestamp = timestamp
    self.status = status
    self.toolCallName = toolCallName
    self.toolCallResult = toolCallResult
    self.isAgentResult = isAgentResult
    self.agentSteps = agentSteps
  }
}
