import Foundation

enum GeminiChatEvent {
  case textDelta(String)
  case toolCall(id: String, name: String, args: [String: Any])
  case done
}

@MainActor
class GeminiChatService {
  private var contents: [[String: Any]] = []
  private var currentTask: Task<Void, Never>?

  func sendMessage(_ text: String) -> AsyncThrowingStream<GeminiChatEvent, Error> {
    contents.append([
      "role": "user",
      "parts": [["text": text]]
    ])
    return streamRequest()
  }

  func sendToolResponse(callId: String, name: String, result: [String: Any]) -> AsyncThrowingStream<GeminiChatEvent, Error> {
    // Append the model's function call to history (already done when we received it)
    // Now append the function response
    contents.append([
      "role": "user",
      "parts": [[
        "functionResponse": [
          "name": name,
          "response": result
        ]
      ]]
    ])
    return streamRequest()
  }

  func resetConversation() {
    contents = []
    currentTask?.cancel()
    currentTask = nil
  }

  // MARK: - Private

  private func streamRequest() -> AsyncThrowingStream<GeminiChatEvent, Error> {
    guard let url = GeminiConfig.textChatURL() else {
      return AsyncThrowingStream { $0.finish(throwing: NSError(domain: "GeminiChat", code: -1, userInfo: [NSLocalizedDescriptionKey: "API key not configured"])) }
    }

    let body = buildRequestBody()
    let contentsRef = contents

    return AsyncThrowingStream { [weak self] continuation in
      let task = Task.detached {
        do {
          var request = URLRequest(url: url)
          request.httpMethod = "POST"
          request.setValue("application/json", forHTTPHeaderField: "Content-Type")
          request.httpBody = try JSONSerialization.data(withJSONObject: body)

          let (bytes, response) = try await URLSession.shared.bytes(for: request)

          if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            var errorBody = ""
            for try await line in bytes.lines {
              errorBody += line
              if errorBody.count > 500 { break }
            }
            continuation.finish(throwing: NSError(domain: "GeminiChat", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(errorBody)"]))
            return
          }

          var accumulatedText = ""
          var pendingFunctionCall: [String: Any]?

          for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst(6))
            guard !jsonStr.isEmpty else { continue }

            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            guard let candidates = json["candidates"] as? [[String: Any]],
                  let candidate = candidates.first,
                  let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }

            for part in parts {
              if let text = part["text"] as? String, !text.isEmpty {
                accumulatedText += text
                continuation.yield(.textDelta(text))
              }

              if let fc = part["functionCall"] as? [String: Any],
                 let name = fc["name"] as? String {
                let args = fc["args"] as? [String: Any] ?? [:]
                let callId = UUID().uuidString
                pendingFunctionCall = ["name": name, "args": args, "id": callId]

                // Append model's function call to history
                await MainActor.run {
                  self?.contents.append([
                    "role": "model",
                    "parts": [["functionCall": ["name": name, "args": args]]]
                  ])
                }

                continuation.yield(.toolCall(id: callId, name: name, args: args))
              }
            }
          }

          // If we accumulated text (no tool call), append model response to history
          if !accumulatedText.isEmpty && pendingFunctionCall == nil {
            await MainActor.run {
              self?.contents.append([
                "role": "model",
                "parts": [["text": accumulatedText]]
              ])
            }
          }

          continuation.yield(.done)
          continuation.finish()
        } catch {
          if !Task.isCancelled {
            continuation.finish(throwing: error)
          }
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private func buildRequestBody() -> [String: Any] {
    var body: [String: Any] = [
      "contents": contents,
      "generationConfig": [
        "temperature": 0.7
      ]
    ]

    // System instruction
    let systemPrompt = GeminiConfig.systemInstruction
    if !systemPrompt.isEmpty {
      body["systemInstruction"] = [
        "parts": [["text": systemPrompt]]
      ]
    }

    // Tool declarations
    let tools = ToolDeclarations.allDeclarations()
    if !tools.isEmpty {
      body["tools"] = [[
        "functionDeclarations": tools
      ]]
    }

    return body
  }
}
