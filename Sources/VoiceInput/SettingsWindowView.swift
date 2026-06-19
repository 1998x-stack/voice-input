import SwiftUI

struct SettingsWindowView: View {
    @State private var baseURL: String
    @State private var apiKey: String
    @State private var model: String
    @State private var isTesting = false
    @State private var testResult: String?

    private let defaults = UserDefaults.standard

    init() {
        _baseURL = State(initialValue: UserDefaults.standard.string(forKey: "llmBaseURL") ?? "https://api.deepseek.com/v1")
        _apiKey = State(initialValue: ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? UserDefaults.standard.string(forKey: "llmApiKey") ?? "")
        _model = State(initialValue: UserDefaults.standard.string(forKey: "llmModel") ?? "deepseek-v4-flash")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("API Base URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://api.openai.com/v1", text: $baseURL)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("API Key")
                    .font(.caption)
                    .foregroundColor(.secondary)
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("deepseek-v4-flash", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            if let result = testResult {
                Text(result)
                    .font(.caption)
                    .foregroundColor(result.contains("Success") ? .green : .red)
            }

            HStack(spacing: 8) {
                Button(action: testConnection) {
                    if isTesting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .controlSize(.small)
                    }
                    Text("Test")
                }
                .disabled(isTesting)

                Button("Save") {
                    save()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let config = LLMRefiner.Config(baseURL: baseURL, apiKey: apiKey, model: model)
        let refiner = LLMRefiner()

        Task {
            defer { isTesting = false }
            do {
                let response = try await refiner.testConnection(config: config)
                await MainActor.run {
                    testResult = "Success: \(response)"
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }

    private func save() {
        defaults.set(baseURL, forKey: "llmBaseURL")
        defaults.set(apiKey, forKey: "llmApiKey")
        defaults.set(model, forKey: "llmModel")
        testResult = "Saved"

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1500)) {
            if testResult == "Saved" {
                testResult = nil
            }
        }
    }
}
