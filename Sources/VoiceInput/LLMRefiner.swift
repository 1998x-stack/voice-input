import Foundation

final class LLMRefiner {
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        return URLSession(configuration: config)
    }()

    private let systemPrompt = """
    You are a conservative speech recognition post-processor. Your task is to fix ONLY obvious recognition errors in the user's dictated text. Specifically:

    1. Fix Chinese homophone errors (words that sound the same but are written differently)
    2. Restore English technical terms that were incorrectly converted to Chinese (e.g. 配森→Python, 杰森→JSON, 加瓦→Java)
    3. Fix obvious number/date formatting errors common in speech recognition

    DO NOT:
    - Rewrite, polish, or improve the text's style
    - Add, remove, or change any content that appears correct
    - Fix grammar unless it's clearly a recognition error
    - Add punctuation unless the original clearly intended it

    If the input looks correct, return it exactly as-is with no changes.

    Respond with ONLY the corrected text. No explanations, no prefixes, no markdown.
    """

    struct Config: Sendable {
        let baseURL: String
        let apiKey: String
        let model: String
    }

    func refine(text: String, config: Config) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": text]
        ]
        let content = try await performRequest(messages: messages, maxTokens: 2048, config: config)
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testConnection(config: Config) async throws -> String {
        let messages: [[String: String]] = [
            ["role": "user", "content": "Hello"]
        ]
        return try await performRequest(messages: messages, maxTokens: 10, config: config)
    }

    private func performRequest(messages: [[String: String]], maxTokens: Int, config: Config) async throws -> String {
        let base = config.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw RefineError.invalidURL
        }

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "temperature": 0,
            "max_tokens": maxTokens
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(statusCode) else {
            throw RefineError.apiError(statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw RefineError.emptyResponse
        }

        return content
    }

    enum RefineError: LocalizedError {
        case invalidURL
        case apiError(Int)
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Invalid API URL"
            case .apiError(let code): "API request failed (HTTP \(code)). Check your API key and base URL."
            case .emptyResponse: "API returned an empty response"
            }
        }
    }
}
