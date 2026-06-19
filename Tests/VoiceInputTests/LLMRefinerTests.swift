import XCTest
@testable import VoiceInput

// MARK: - Mock URLProtocol

private final class MockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}

// MARK: - Tests

final class LLMRefinerTests: XCTestCase {

    private var refiner: LLMRefiner!
    private let validConfig = LLMRefiner.Config(
        baseURL: "https://api.example.com/v1",
        apiKey: "test-key",
        model: "test-model"
    )

    override func setUp() {
        refiner = LLMRefiner()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        refiner.session = URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        refiner = nil
    }

    // MARK: - Success path

    func testRefine_success() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let responseBody = """
            {"choices":[{"message":{"content":"corrected text"}}]}
            """.data(using: .utf8)!

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, responseBody)
        }

        let result = try await refiner.refine(text: "raw text", config: validConfig)
        XCTAssertEqual(result, "corrected text")
    }

    func testRefine_trimsWhitespace() async throws {
        MockURLProtocol.requestHandler = { _ in
            let body = """
            {"choices":[{"message":{"content":"  trimmed  "}}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: URL(string: "https://api.example.com/v1/chat/completions")!,
                                           statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        let result = try await refiner.refine(text: "raw", config: validConfig)
        XCTAssertEqual(result, "trimmed")
    }

    // MARK: - Error handling

    func testRefine_http401_invalidKey() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await refiner.refine(text: "test", config: validConfig)
            XCTFail("Expected error")
        } catch let error as LLMRefiner.RefineError {
            XCTAssertEqual(error.errorDescription, "Invalid API key")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefine_http429_rateLimited() async {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await refiner.refine(text: "test", config: validConfig)
            XCTFail("Expected error")
        } catch let error as LLMRefiner.RefineError {
            XCTAssertEqual(error.errorDescription, "Too many requests — wait a moment and try again")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefine_emptyChoices() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"choices":[]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        do {
            _ = try await refiner.refine(text: "test", config: validConfig)
            XCTFail("Expected error")
        } catch let error as LLMRefiner.RefineError {
            XCTAssertEqual(error.errorDescription, "API returned an empty response")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRefine_missingContent() async {
        MockURLProtocol.requestHandler = { request in
            let body = """
            {"choices":[{"message":{}}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        do {
            _ = try await refiner.refine(text: "test", config: validConfig)
            XCTFail("Expected error")
        } catch let error as LLMRefiner.RefineError {
            XCTAssertEqual(error.errorDescription, "API returned an empty response")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - URL construction

    func testRefine_stripsTrailingSlash() async throws {
        let config = LLMRefiner.Config(baseURL: "https://api.example.com/v1/", apiKey: "k", model: "m")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
            let body = """
            {"choices":[{"message":{"content":"ok"}}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        _ = try await refiner.refine(text: "test", config: config)
    }

    func testRefine_noVersionPath() async throws {
        let config = LLMRefiner.Config(baseURL: "https://custom.api.com", apiKey: "k", model: "m")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://custom.api.com/chat/completions")
            let body = """
            {"choices":[{"message":{"content":"ok"}}]}
            """.data(using: .utf8)!
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, body)
        }

        _ = try await refiner.refine(text: "test", config: config)
    }

    // MARK: - Error descriptions (no network)

    func testRefineError_invalidURL() {
        XCTAssertEqual(LLMRefiner.RefineError.invalidURL.errorDescription, "Invalid API URL")
    }

    func testRefineError_emptyResponse() {
        XCTAssertEqual(LLMRefiner.RefineError.emptyResponse.errorDescription, "API returned an empty response")
    }

    func testRefineError_tooManyRequests() {
        XCTAssertEqual(LLMRefiner.RefineError.tooManyRequests.errorDescription, "Too many requests — wait a moment and try again")
    }
}
